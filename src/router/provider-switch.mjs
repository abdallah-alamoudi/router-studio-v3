import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {pathToFileURL} from 'node:url';
const managed=['model_provider','model','model_catalog_json','model_reasoning_effort','preferred_auth_method','forced_login_method'];
const digest=x=>crypto.createHash('sha256').update(x).digest('hex');
// Compare values rather than formatting. Quoted content is kept intact.
function canonical(line){
  let out='',quote='',escape=false;
  for(const ch of line.trim()){
    if(quote){out+=ch;if(escape){escape=false;continue;}if(ch==='\\'&&quote==='"'){escape=true;continue;}if(ch===quote)quote='';}
    else if(ch==='"'||ch==="'"){quote=ch;out+=ch;}
    else if(ch==='#')break;
    else if(!/\s/.test(ch))out+=ch;
  }
  return out;
}
function knownLocalRoute(s){
  const allowed=new Set(['name','base_url','wire_api','env_key','requires_openai_auth','supports_websockets']);
  const fields=new Map();
  for(const row of s.providerRows){const c=canonical(row);if(!c)continue;if(c.startsWith('[')){if(c!==`[model_providers.${s.provider}]`)return false;continue;}const at=c.indexOf('=');if(at<0)return false;const key=c.slice(0,at);if(!allowed.has(key)||fields.has(key))return false;let v=c.slice(at+1);try{if(v.startsWith('"'))v=JSON.parse(v);else if(v.startsWith("'")&&v.endsWith("'"))v=v.slice(1,-1);}catch{return false;}fields.set(key,v);}
  return fields.get('base_url')==='http://127.0.0.1:18761/v1'&&fields.get('wire_api')==='responses'&&fields.get('env_key')==='SAFE_8STOKEN_LOCAL_TOKEN'&&(!fields.has('requires_openai_auth')||fields.get('requires_openai_auth')==='false')&&(!fields.has('supports_websockets')||fields.get('supports_websockets')==='false');
}
function inspect(text){
  if (/"""|'''/.test(text)) throw Error('Multiline TOML requires manual configuration');
  const lines=text.split(/\r?\n/);let section='',root=[],settings=[],providerRows=[];
  const seen=new Set();let provider;
  for (const line of lines){
    if (/^\s*\[/.test(line)) {section=line.trim().replace(/\s*#.*$/,'').trim();if(section.includes('"')||section.includes("'")){if(/model_providers|profiles/.test(section))throw Error('Quoted provider/profile section override requires manual configuration');}continue;}
    if (/^\s*["'](?:model_provider|model|model_catalog_json|model_reasoning_effort|preferred_auth_method|forced_login_method)["']\s*=/.test(line)) throw Error('Quoted managed keys require manual configuration');
    const match=line.match(/^\s*([\w]+)\s*=/);
    if(!section&&/^\s*["']?openai_base_url["']?\s*=/.test(line))throw Error('OpenAI base URL override requires manual configuration');
    if(section.startsWith('[profiles.')&&match&&managed.includes(match[1]))throw Error('Profile override requires manual configuration');
    if(section==='[model_providers.openai]'&&line.trim()&&!line.trim().startsWith('#'))throw Error('OpenAI provider override requires manual configuration');
    if(!section){
      if(match&&managed.includes(match[1])){
        if(seen.has(match[1]))throw Error('Duplicate managed configuration key');seen.add(match[1]);settings.push(line);
        if(match[1]==='model_provider'){const m=line.match(/^\s*model_provider\s*=\s*("(?:\\.|[^"\\])*"|'[^']*')\s*(?:#.*)?$/);if(!m)throw Error('Unsupported model_provider');provider=m[1][0]==="'"?m[1].slice(1,-1):JSON.parse(m[1]);}
      }else root.push(line);
    }
  }
  // Include nested header tables in the route signature, so header/auth edits are detected.
  section='';for(const line of lines){if(/^\s*\[/.test(line))section=line.trim().replace(/\s*#.*$/,'').trim();if(section===`[model_providers.${provider}]`||section.startsWith(`[model_providers.${provider}.`))providerRows.push(line);}
  const boundary=lines.findIndex(line=>/^\s*\[/.test(line));
  let context='';const semantic=[],routeFields=new Set();
  for(const row of providerRows){const c=canonical(row);if(!c)continue;if(c.startsWith('['))context=c;else{const field=context+'|'+c.split('=')[0];if(routeFields.has(field))throw Error('Duplicate router connection field. Current configuration was kept.');routeFields.add(field);semantic.push([context,c]);}}semantic.sort((a,b)=>JSON.stringify(a).localeCompare(JSON.stringify(b)));
  return {provider,settings,root,providerRows,tail:boundary<0?[]:lines.slice(boundary),signature:digest(providerRows.join('\n')),semanticSignature:digest(JSON.stringify(semantic)),newline:text.includes('\r\n')?'\r\n':'\n'};
}
function readConfig(cp){return fs.readFileSync(cp,'utf8').replace(/^\uFEFF/,'');}
const statePath=dir=>path.join(dir,'provider-state.json');
function recover(cp,dir){const pending=statePath(dir)+'.pending';if(!fs.existsSync(pending))return;const p=JSON.parse(fs.readFileSync(pending,'utf8'));const h=digest(readConfig(cp));if(h===p.nextHash){fs.writeFileSync(statePath(dir)+'.tmp',JSON.stringify(p.state,null,2));fs.renameSync(statePath(dir)+'.tmp',statePath(dir));}else if(h!==p.previousHash)throw Error('Interrupted switch and external config edits: recover from switch-config-before.toml manually');fs.unlinkSync(pending);}
export function initializeSwitch(cp,dir){
  recover(cp,dir);if(fs.existsSync(statePath(dir)))return;
  const text=readConfig(cp),s=inspect(text);
  if(!s.provider||s.provider==='openai')throw Error('Initialize from installed router configuration');
  const section=s.tail.join('\n');
  if(!section.includes('SAFE_8STOKEN_LOCAL_TOKEN')||!section.includes('http://127.0.0.1:18761/v1'))throw Error('Installed local router configuration required');
  let official=['model_provider = "openai"','forced_login_method = "chatgpt"'];
  const backup=path.join(dir,'config-before-router.toml');
  if(fs.existsSync(backup)){
    const original=inspect(readConfig(backup));
    if(!original.provider||original.provider==='openai'){
      official=original.settings.filter(line=>!/^\s*(model_provider|model_catalog_json|preferred_auth_method|forced_login_method)\s*=/.test(line));
      official.unshift('model_provider = "openai"','forced_login_method = "chatgpt"');
    }
  }
  const state={version:3,active:'router',routerProvider:s.provider,routerSignature:s.signature,routerSemanticSignature:s.semanticSignature,router:s.settings,official};
  fs.writeFileSync(statePath(dir)+'.tmp',JSON.stringify(state,null,2));fs.renameSync(statePath(dir)+'.tmp',statePath(dir));
}
export function switchProvider(cp,dir,target){
  if(!['official','router'].includes(target))throw Error('Choose official or router');
  initializeSwitch(cp,dir);
  const state=JSON.parse(fs.readFileSync(statePath(dir),'utf8')),before=readConfig(cp),s=inspect(before);
  if(s.provider!==(state.active==='official'?'openai':state.routerProvider))throw Error('Active provider changed outside the menu; no edits made');
  // Check the stored router provider even when official access is active.
  const routeText=before.replace(/^\s*model_provider\s*=.*$/m,`model_provider = ${JSON.stringify(state.routerProvider)}`);
  const route=inspect(routeText);
  if(state.routerSemanticSignature){if(route.semanticSignature!==state.routerSemanticSignature)throw Error('Router connection values changed. Open Diagnostics and review the connection before adopting it. No Codex settings changed.');}
  else if(route.signature!==state.routerSignature&&!knownLocalRoute(route))throw Error('Router connection changed and could not be verified as the local router. No settings changed.');
  state.version=3;state.routerSignature=route.signature;state.routerSemanticSignature=route.semanticSignature;
  if(state.active===target){fs.writeFileSync(statePath(dir)+'.tmp',JSON.stringify(state,null,2));fs.renameSync(statePath(dir)+'.tmp',statePath(dir));return;}
  state[state.active]=s.settings;
  state.active=target;
  const after=[...state[target],...s.root,...s.tail].join(s.newline);
  const pending=statePath(dir)+'.pending',tmp=cp+'.provider-switch.tmp';
  fs.copyFileSync(cp,path.join(dir,'switch-config-before.toml'));
  const backups=path.join(dir,'backups');fs.mkdirSync(backups,{recursive:true});fs.copyFileSync(cp,path.join(backups,`${Date.now()}-${crypto.randomBytes(3).toString('hex')}.toml`));
  try{
    fs.writeFileSync(tmp,after,{flag:'wx'});
    fs.writeFileSync(pending,JSON.stringify({previousHash:digest(before),nextHash:digest(after),state},null,2),{flag:'wx'});
    fs.renameSync(tmp,cp);
    recover(cp,dir);
  }catch(e){try{if(fs.statSync(tmp).isFile())fs.unlinkSync(tmp);}catch{}throw e;}
}
function getField(s,key){let primary=false;for(const row of s.providerRows){const c=canonical(row);if(c.startsWith('[')){primary=c===`[model_providers.${s.provider}]`;continue;}if(primary&&new RegExp(`^${key}=`).test(c)){const v=c.slice(c.indexOf('=')+1);try{return JSON.parse(v);}catch{return v.startsWith("'")?v.slice(1,-1):v;}}}return null;}
export function connectionStatus(cp,dir){
  const text=readConfig(cp),s=inspect(text);const state=fs.existsSync(statePath(dir))?JSON.parse(fs.readFileSync(statePath(dir),'utf8')):null;
  const rp=state?.routerProvider||s.provider;const route=inspect(text.replace(/^\s*model_provider\s*=.*$/m,`model_provider = ${JSON.stringify(rp)}`));
  const mismatch=!!state&&((state.active==='official'?'openai':rp)!==s.provider||(state.routerSemanticSignature?state.routerSemanticSignature!==route.semanticSignature:state.routerSignature!==route.signature));
  const endpoint=getField(s,'base_url'),localEndpoint=getField(route,'base_url')==='http://127.0.0.1:18761/v1',localCredential=getField(route,'env_key')==='SAFE_8STOKEN_LOCAL_TOKEN',responses=getField(route,'wire_api')==='responses';
  const model=(s.settings.find(r=>/^\s*model\s*=/.test(r))||'').replace(/^.*?=\s*/,'').replace(/^"|"$/g,'');
  return {provider:s.provider||'openai',selected:s.provider==='openai'?'official':s.provider===rp?'router':'other',localRoute:localEndpoint&&localCredential&&responses,localEndpoint,localCredential,responses,reviewNeeded:mismatch,canAdopt:knownLocalRoute(route),stateVersion:state?.version||null,model:/^[\w./:-]{1,160}$/.test(model)&&!model.startsWith('sk-')?model:'Custom / unspecified',endpoint:s.provider==='openai'?'Official ChatGPT sign-in':['http://127.0.0.1:18761/v1','https://8stoken.com/v1'].includes(endpoint)?endpoint:'Another endpoint (hidden from diagnostics)'};
}
export function repairState(cp,dir){
  recover(cp,dir);initializeSwitch(cp,dir);const state=JSON.parse(fs.readFileSync(statePath(dir),'utf8')),text=readConfig(cp),s=inspect(text);
  if(![state.routerProvider,'openai'].includes(s.provider))throw Error('Active provider is different. Select the intended provider manually before recovery.');
  const route=inspect(text.replace(/^\s*model_provider\s*=.*$/m,`model_provider = ${JSON.stringify(state.routerProvider)}`));
  if(!knownLocalRoute(route))throw Error('Recovery refused: endpoint, credentials, or extra headers do not match the verified local router. Current settings were kept.');
  fs.copyFileSync(statePath(dir),path.join(dir,'provider-state.before-repair.json'));
  state.active=s.provider==='openai'?'official':'router';state[state.active]=s.settings;state.version=3;state.routerSignature=route.signature;state.routerSemanticSignature=route.semanticSignature;
  fs.writeFileSync(statePath(dir)+'.tmp',JSON.stringify(state,null,2));fs.renameSync(statePath(dir)+'.tmp',statePath(dir));
}
export function listBackups(dir){const p=path.join(dir,'backups');if(!fs.existsSync(p))return [];return fs.readdirSync(p).filter(x=>/^\d+-[a-f0-9]{6}\.toml$/.test(x)).sort().reverse().map(id=>({id,date:new Date(Number(id.split('-')[0])).toISOString(),bytes:fs.statSync(path.join(p,id)).size}));}
function validateBackup(cp,dir,id){
  if(!/^\d+-[a-f0-9]{6}\.toml$/.test(id||'') || !listBackups(dir).some(b=>b.id===id))throw Error('Choose a backup from the list.');
  const file=path.join(dir,'backups',id);const after=readConfig(file),s=inspect(after),state=JSON.parse(fs.readFileSync(statePath(dir),'utf8'));
  if(!['openai',state.routerProvider].includes(s.provider))throw Error('Backup does not contain a recognized connection.');
  const route=inspect(after.replace(/^\s*model_provider\s*=.*$/m,`model_provider = ${JSON.stringify(state.routerProvider)}`));if(!knownLocalRoute(route))throw Error('Backup does not contain the verified local router.');
  return {after,s,state,route,before:readConfig(cp)};
}
export function previewBackup(cp,dir,id){
 if(fs.existsSync(statePath(dir)+'.pending'))throw Error('Recovery required before preview.');
 const {before,after}=validateBackup(cp,dir,id),current=inspect(before),saved=inspect(after);
 const field=(s,key)=>s.settings.find(line=>new RegExp(`^\\s*${key}\\s*=`).test(line));
 const changes=managed.filter(key=>canonical(field(current,key)||'')!==canonical(field(saved,key)||'')).map(key=>({field:key,before:field(current,key)?'Configured':'Absent',after:field(saved,key)?'Configured':'Absent'}));
 if([...current.root,...current.tail].join('\n')!==[...saved.root,...saved.tail].join('\n'))changes.push({field:'Other configuration',before:'Current settings',after:'Backup settings (values hidden)'});
 return {id,configDigest:digest(before),backupDigest:digest(after),changes};
}
export function restoreBackup(cp,dir,id,expected){
  if(expected && (digest(readConfig(cp))!==expected.configDigest || digest(readConfig(path.join(dir,'backups',id)))!==expected.backupDigest))throw Error('Configuration or backup changed after preview.');
  recover(cp,dir);
  const {before,after,s,state,route}=validateBackup(cp,dir,id);
  if(expected && (digest(before)!==expected.configDigest || digest(after)!==expected.backupDigest))throw Error('Configuration or backup changed after preview.');
  fs.copyFileSync(cp,path.join(dir,'backups',`${Date.now()}-${crypto.randomBytes(3).toString('hex')}.toml`));
  state.active=s.provider==='openai'?'official':'router';state[state.active]=s.settings;state.version=3;state.routerSignature=route.signature;state.routerSemanticSignature=route.semanticSignature;
  const tmp=cp+'.provider-switch.tmp',pending=statePath(dir)+'.pending';fs.writeFileSync(tmp,after,{flag:'wx'});
  try{fs.writeFileSync(pending,JSON.stringify({previousHash:digest(before),nextHash:digest(after),state}),{flag:'wx'});fs.renameSync(tmp,cp);recover(cp,dir);}catch(e){try{fs.unlinkSync(tmp);}catch{}throw e;}
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){try{const [target,cp,dir,id,configDigest,backupDigest]=process.argv.slice(2);
  if(target==='status')console.log(JSON.stringify(connectionStatus(cp,dir)));
  else if(target==='backups')console.log(JSON.stringify(listBackups(dir)));
  else if(target==='preview-backup')console.log(JSON.stringify(previewBackup(cp,dir,id)));
  else if(target==='repair'){repairState(cp,dir);console.log('Verified local connection adopted. Codex settings were kept.');}
  else if(target==='restore-backup'){restoreBackup(cp,dir,id,configDigest?{configDigest,backupDigest}:undefined);console.log('Backup restored. Reopen Codex and start a new session.');}
  else{if(target==='init')initializeSwitch(cp,dir);else switchProvider(cp,dir,target);console.log(target==='init'?'Provider menu initialized.':`Selected ${target}. Reopen Codex and start a new session.`);}
}catch(e){console.error(e.message);process.exitCode=1;}}
