import https from 'node:https';
import {validateProbePlan} from './route-policy.mjs';import {ProbeSse} from './probe-sse.mjs';
function classifyResponse(body,tool=false){
 if(!body||typeof body!=='object')return ['failed','protocol_mismatch'];
 if(body.error||body.status==='failed')return ['failed','upstream_error'];
 if(body.status==='incomplete')return ['incomplete',body.incomplete_details?.reason==='max_output_tokens'?'output_limit':null];
 if(body.status==='cancelled')return ['cancelled',null];
 if(body.status!=='completed'||!Array.isArray(body.output))return ['failed','protocol_mismatch'];
 if(tool){const calls=body.output.filter(item=>item?.type==='function_call');
  if(calls.length!==1||calls[0].name!=='router_studio_echo'||typeof calls[0].call_id!=='string'||typeof calls[0].arguments!=='string')return ['failed','protocol_mismatch'];
  try{const args=JSON.parse(calls[0].arguments);if(!args||Object.keys(args).length!==1||typeof args.text!=='string'||args.text.length>64||args.text!=='OK')throw Error();}catch{return ['failed','protocol_mismatch'];}
 }else if(!body.output.some(item=>item?.type==='message'&&item.content?.some(part=>part.type==='output_text'&&typeof part.text==='string'&&part.text.trim())))return ['failed','protocol_mismatch'];
 return ['passed',null];
}
export async function runProbe(plan,key,options={}){
 validateProbePlan(plan);const started=performance.now();let firstEventMs=null;
 const result=(outcome,errorCode=null,httpStatus=null)=>({kind:plan.kind,modelId:plan.modelId??null,credentialLabel:plan.credentialLabel??null,endpointName:plan.endpointName,outcome,errorCode,httpStatus,elapsedMs:performance.now()-started,firstEventMs,completedAtUtc:new Date().toISOString(),snapshotDigest:plan.snapshotDigest});
 if(['local','official_config'].includes(plan.kind))return result('not_verified');
 if(typeof key!=='string'||!key||key.length>8192||/[\r\n\0]/.test(key))return result('failed','auth_rejected');
 const generation=plan.kind!=='catalog',stream=plan.kind==='stream';
 const body=generation?{model:plan.resolvedModel,input:'Reply with OK.',max_output_tokens:plan.outputTokenLimit,store:false,...(plan.effort?{reasoning:{effort:plan.effort}}:{}),...(stream?{stream:true}:{}),...(plan.kind==='tool'?{tools:[{type:'function',name:'router_studio_echo',description:'Return the text OK without executing any action.',strict:true,parameters:{type:'object',properties:{text:{type:'string',enum:['OK']}},required:['text'],additionalProperties:false}}],tool_choice:{type:'function',name:'router_studio_echo'},parallel_tool_calls:false}:{})}:null;
 const payload=body?JSON.stringify(body):undefined;
 const timeoutMs=Math.min(30000,Math.max(1,options.timeoutMs??30000)),maximumBytes=Math.min(1024*1024,Math.max(1,options.maximumBytes??1024*1024));
 return new Promise(resolve=>{
  let req,res,settled=false,status=null;const signal=options.signal;
  const finish=(outcome,errorCode)=>{if(settled)return;settled=true;(options.clearTimer??clearTimeout)(timer);signal?.removeEventListener('abort',cancel);resolve(result(outcome,errorCode,status));res?.destroy();req?.destroy();};
  const cancel=()=>finish('cancelled');const timer=(options.setTimer??setTimeout)(()=>finish('timed_out','network_error'),timeoutMs);
  if(signal?.aborted){finish('cancelled');return;}signal?.addEventListener('abort',cancel,{once:true});
  try{
   req=(options.request??https.request)({protocol:'https:',hostname:'8stoken.com',port:443,path:generation?'/v1/responses':'/v1/models',method:generation?'POST':'GET',agent:false,headers:{authorization:`Bearer ${key}`,accept:stream?'text/event-stream':'application/json','accept-encoding':'identity',...(generation?{'content-type':'application/json','content-length':Buffer.byteLength(payload)}:{})}},up=>{
    res=up;if(settled){up.destroy();return;}status=up.statusCode;
    up.on('error',()=>finish('failed','network_error'));up.on('aborted',()=>finish('failed','network_error'));
    if(status!==200){finish('failed',status===401||status===403?'auth_rejected':status===429?'rate_limited':status>=300&&status<400?'protocol_mismatch':'upstream_error');return;}
    if(!(stream?/^text\/event-stream(?:;|$)/i:/^application\/(?:[\w.-]+\+)?json(?:;|$)/i).test(up.headers['content-type']??'')||up.headers['content-encoding']&&up.headers['content-encoding']!=='identity'){finish('failed','protocol_mismatch');return;}
    let bytes=0,terminal=null;const chunks=[];
    const sse=stream?new ProbeSse(event=>{
     if(!event||typeof event.type!=='string')throw Error();firstEventMs??=performance.now()-started;
     if(event.type==='error'||event.type==='response.failed'){terminal=['failed','upstream_error'];return;}
     if(terminal)throw Error('Event after terminal');
     if(event.type==='response.completed'){if(event.response?.status!=='completed')throw Error();terminal=classifyResponse(event.response);}
     if(event.type==='response.incomplete')terminal=classifyResponse(event.response);
    }):null;
    up.on('data',chunk=>{if(settled)return;bytes+=chunk.length;if(bytes>maximumBytes){finish('failed','response_limit');return;}try{if(sse)sse.push(chunk);else chunks.push(chunk);}catch{finish('failed','protocol_mismatch');}});
    up.on('end',()=>{if(settled)return;try{
     if(sse){sse.end();if(!terminal)throw Error();finish(...terminal);return;}
     const value=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(Buffer.concat(chunks)));
     if(generation){finish(...classifyResponse(value,plan.kind==='tool'));return;}
     if(!value||!Array.isArray(value.data)||value.data.length>10000||value.data.some(m=>!m||typeof m.id!=='string'||!m.id||m.id.length>160))throw Error();finish('passed');
    }catch{finish('failed','protocol_mismatch');}});
    up.on('close',()=>{if(!up.readableEnded)finish('failed','network_error');});
   });req.on('error',()=>finish('failed','network_error'));req.end(payload);
  }catch{finish('failed','network_error');}
 });
}
