import http from 'node:http';
import https from 'node:https';
import fs from 'node:fs';
import {timingSafeEqual} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {selectRoute} from './route-policy.mjs';
import {validateRegistry} from './custom-models.mjs';

// Walk JSON syntax to obtain text spans. Values are never reserialized.
function spans(text){
  JSON.parse(text); // Validate full JSON grammar first.
  let i=0;
  const ws=()=>{while(/\s/.test(text[i]||'!'))i++;};
  function value(){
    ws();const start=i;let members;
    if(text[i]==='{'){
      members=new Map();i++;ws();
      while(text[i]!=='}'){
        const k=value();if(text[k.start]!== '"')throw Error('Invalid JSON key');
        const name=JSON.parse(text.slice(k.start,k.end));
        if(members.has(name))throw Error('Duplicate JSON key');
        ws();i++;const v=value();members.set(name,v);ws();
        if(text[i]===','){i++;ws();}else break;
      }i++;
    }else if(text[i]==='['){i++;ws();while(text[i]!==']'){value();ws();if(text[i]===','){i++;ws();}else break;}i++;}
    else if(text[i]==='"'){i++;while(i<text.length){if(text[i]==='\\'){i+=2;continue;}if(text[i++]==='"')break;}}
    else {while(i<text.length&&!/[\s,\]}]/.test(text[i]))i++;}
    return {start,end:i,members};
  }
  return value();
}
export function rewrite(body,aliases,modelRoutes={},registry={}){
  if(!body.length)return {body};
  const text=new TextDecoder('utf-8',{fatal:true}).decode(body);const root=spans(text);
  const model=root.members?.get('model');if(!model)return {body};
  const name=JSON.parse(text.slice(model.start,model.end));
  const selection=selectRoute({...registry,aliases,modelRoutes},name);
  const preset=selection.kind==='Custom model'?{model:selection.resolvedModel}:Object.hasOwn(aliases,name)?aliases[name]:undefined;if(!preset)return {body,keyEnv:selection.keyEnv};
  const edits=[[model.start,model.end,JSON.stringify(preset.model)]];
  if(preset.effort){
    const reasoning=root.members.get('reasoning');
    if(reasoning){
      if(!reasoning.members)throw Error('Preset requires reasoning object');
      const effort=reasoning.members.get('effort');
      if(effort)edits.push([effort.start,effort.end,JSON.stringify(preset.effort)]);
      else edits.push([reasoning.end-1,reasoning.end-1,`${reasoning.members.size?',':''}"effort":${JSON.stringify(preset.effort)}`]);
    }else edits.push([root.end-1,root.end-1,`,"reasoning":{"effort":${JSON.stringify(preset.effort)}}`]);
  }
  let output=text;for(const [a,b,v]of edits.sort((x,y)=>y[0]-x[0]))output=output.slice(0,a)+v+output.slice(b);
  return {body:Buffer.from(output),keyEnv:selection.keyEnv};
}
const HOP=new Set(['connection','keep-alive','proxy-authenticate','proxy-authorization','te','trailer','transfer-encoding','upgrade']);
function clean(headers){const deny=new Set([...HOP,...String(headers.connection||'').toLowerCase().split(',').map(s=>s.trim())]);return Object.fromEntries(Object.entries(headers).filter(([k])=>!deny.has(k)));}
function secretEqual(a,b){const x=Buffer.from(a),y=Buffer.from(b);return x.length===y.length&&timingSafeEqual(x,y);}
export function createRouter(config,env=process.env){
  if(Array.isArray(config.credentials)||Array.isArray(config.customModels))validateRegistry(config);
  const target=new URL(config.upstream);
  if((target.protocol!=='https:'&&!(config.allowHttpForTests&&target.protocol==='http:'&&target.hostname==='127.0.0.1'))||target.username||target.password||target.pathname!=='/'||target.search||target.hash)throw Error('Upstream must be a fixed HTTPS origin');
  const token=env[config.localTokenEnv];if(!token||token.length<8)throw Error('Missing local authentication token');
  const max=config.maxRequestBytes??64*1024*1024;
  const server=http.createServer(async(req,res)=>{
    let outgoing;
    const fail=(status,message)=>{if(res.headersSent){res.destroy();return;}res.writeHead(status,{'content-type':'application/json','connection':'close'});res.end(JSON.stringify({error:{message,type:'local_router_error'}}));};
    // No browser CORS exposure; desktop/CLI clients do not send Origin.
    if(req.headers.origin!==undefined||req.headers['sec-fetch-site']!==undefined)return fail(403,'Browser-origin requests are not accepted');
    if(!secretEqual(req.headers.authorization||'',`Bearer ${token}`))return fail(401,'Invalid local token');
    if(!req.url.startsWith('/')||req.url.startsWith('//')||/[\\\r\n]/.test(req.url))return fail(400,'Only origin-form request paths are accepted');
    if(req.url==='/__router/health'){res.setHeader('content-type','application/json');return res.end(JSON.stringify({ok:true,version:'1.0.0',transport:'HTTP/SSE',automaticReplay:false}));}
    if(req.headers['content-encoding']&&req.headers['content-encoding']!=='identity')return fail(415,'Encoded request bodies are not supported');
    try{
      let size=0,chunks=[];
      for await(const chunk of req){size+=chunk.length;if(size>max)return fail(413,'Request exceeds configured body limit');chunks.push(chunk);}
      let body=Buffer.concat(chunks);let keyEnv=config.defaultKeyEnv;
      if(body.length&&(/application\/(?:[\w.-]+\+)?json/i.test(req.headers['content-type']||'')||/^\/v1\/responses(?:[/?]|$)/.test(req.url))){const changed=rewrite(body,config.aliases??{},config.modelRoutes??{},config);body=changed.body;keyEnv=changed.keyEnv??keyEnv;}
      const key=env[keyEnv];if(!key)return fail(503,'Selected route credential has not been configured');
      const headers=clean(req.headers);delete headers.host;delete headers['content-length'];delete headers.expect;
      headers.authorization=`Bearer ${key}`;
      if(body.length||req.headers['content-length']!==undefined)headers['content-length']=String(body.length);
      const transport=target.protocol==='https:'?https:http;
      outgoing=transport.request({protocol:target.protocol,hostname:target.hostname,port:target.port||undefined,path:req.url,method:req.method,headers},up=>{
        res.writeHead(up.statusCode,up.statusMessage,clean(up.headers));res.flushHeaders();
        up.on('error',()=>res.destroy());up.on('aborted',()=>res.destroy());
        up.pipe(res); // No decompression, JSON/SSE interpretation, buffering or retries.
      });
      outgoing.setTimeout(config.idleTimeoutMs??300000,()=>outgoing.destroy(Error('timeout')));
      outgoing.on('error',()=>fail(502,'Upstream transport failed; request was not replayed'));
      res.on('close',()=>{if(!res.writableFinished)outgoing.destroy();});
      outgoing.end(body);
    }catch(error){if(outgoing)outgoing.destroy();if(['credential_missing','unsupported_capability'].includes(error.code))fail(503,'Selected custom model is unavailable or its credential is missing');else fail(400,'Invalid or unsupported request body');}
  });
  server.requestTimeout=300000;server.headersTimeout=30000;
  server.on('upgrade',(req,socket)=>socket.end('HTTP/1.1 501 Not Implemented\r\nConnection: close\r\nContent-Length: 0\r\n\r\n'));
  return server;
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
  try{
    const config=JSON.parse(fs.readFileSync(process.argv[2]||new URL('./router-config.json',import.meta.url),'utf8'));
    if(config.allowHttpForTests)throw Error('Test-only HTTP upstream is not allowed by the launcher');
    const server=createRouter(config);server.on('error',()=>{console.error('Router could not bind its local port.');process.exit(1);});
    server.listen(config.port??18761,'127.0.0.1',()=>console.log('Safe router listening on loopback; no automatic replay.'));
    for(const sig of ['SIGINT','SIGTERM'])process.on(sig,()=>{server.closeAllConnections();server.close(()=>process.exit(0));});
  }catch(e){console.error(e.message);process.exit(1);}
}
