import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {pathToFileURL} from 'node:url';
function sections(text){
  if(/"""|'''/.test(text))throw Error('Multiline TOML needs manual configuration');
  if(/^\s*["'](?:model_provider|model_catalog_json|base_url|env_key|requires_openai_auth|wire_api)["']\s*=/m.test(text))throw Error('Unsupported quoted managed TOML key');
  const rows=text.split(/\r?\n/),map=new Map([['',[]]]);let current='';
  for(let i=0;i<rows.length;i++){
    const array=rows[i].match(/^\s*\[\[([^\]]+)\]\]\s*(?:#.*)?$/);
    if(array){current=`@@array-${i}`;map.set(current,[]);continue;}
    const h=rows[i].match(/^\s*\[([^\]]+)\]\s*(?:#.*)?$/);
    if(h){current=h[1];if(map.has(current))throw Error('Duplicate TOML section');map.set(current,[]);}
    else map.get(current).push(i);
  }return {rows,map};
}
function field(s,section,name){const matches=(s.map.get(section)||[]).filter(i=>new RegExp(`^\\s*${name}\\s*=`).test(s.rows[i]));if(matches.length>1)throw Error('Duplicate TOML field');return matches[0];}
function read(s,section,name){const i=field(s,section,name);if(i===undefined)return undefined;const raw=s.rows[i].replace(/^\s*\w+\s*=\s*/,'');const m=raw.match(/^("(?:\\.|[^"\\])*"|'[^']*')\s*(?:#.*)?$/);if(!m)throw Error(`Unsupported TOML ${name}`);return m[1][0]==="'"?m[1].slice(1,-1):JSON.parse(m[1]);}
function set(s,section,name,value){const i=field(s,section,name);const line=`${name} = ${typeof value==='boolean'?value:JSON.stringify(value)}`;if(i!==undefined)s.rows[i]=line;else{const indices=s.map.get(section);if(!indices)throw Error('Missing custom provider section');const at=indices.length?indices.at(-1)+1:s.rows.findIndex(r=>r.trim()===`[${section}]`)+1;s.rows.splice(at,0,line);const rebuilt=sections(s.rows.join('\n'));s.rows=rebuilt.rows;s.map=rebuilt.map;}}
export function adapt(config,catalog,aliases,catalogPath,port){
  const s=sections(config),provider=read(s,'','model_provider');
  if(!provider||provider==='openai'||!/^[\w-]+$/.test(provider))throw Error('Existing custom provider required');
  const section=`model_providers.${provider}`;
  if(field(s,section,'experimental_bearer_token')!==undefined||field(s,section,'api_key')!==undefined)throw Error('Hard-coded provider auth needs manual configuration');
  for(const [name,indices]of s.map){
    if(name===section||name.startsWith(section+'.')){
      if(indices.some(i=>/^\s*["']?authorization["']?\s*=/i.test(s.rows[i])||/^\s*(?:http_headers|env_http_headers)\s*=.*authorization/i.test(s.rows[i])))throw Error('Provider Authorization override needs manual configuration');
    }
  }
  if(read(s,section,'wire_api')!=='responses')throw Error('Existing Responses wire_api required');
  const base=read(s,section,'base_url');if(!base||!/^https:\/\/8stoken\.com\/v1\/?$/.test(base))throw Error('Existing direct 8stoken provider required');
  if(!Array.isArray(catalog.models))throw Error('Unsupported catalog: models array required');
  const result=structuredClone(catalog),slugs=new Set(catalog.models.map(m=>m.slug));
  if(slugs.size!==catalog.models.length)throw Error('Duplicate catalog models');
  for(const [slug,preset]of Object.entries(aliases)){
    if(slugs.has(slug))throw Error('Alias already exists in catalog');
    const source=catalog.models.find(m=>m.slug===preset.model);if(!source)throw Error(`Source model ${preset.model} missing from catalog`);
    const clone=structuredClone(source);
    if(preset.effort){const level=clone.supported_reasoning_levels?.find(x=>x.effort===preset.effort);if(!level)throw Error(`Unsupported preset effort for ${preset.model}`);clone.supported_reasoning_levels=[level];clone.default_reasoning_level=preset.effort;}
    clone.slug=slug;clone.display_name=preset.display;clone.visibility='list';clone.supported_in_api=true;
    delete clone.upgrade;result.models.push(clone);
  }
  set(s,'','model_catalog_json',catalogPath.replaceAll('\\','/'));
  set(s,section,'base_url',`http://127.0.0.1:${port}/v1`);set(s,section,'env_key','SAFE_8STOKEN_LOCAL_TOKEN');set(s,section,'requires_openai_auth',false);
  return {config:s.rows.join(config.includes('\r\n')?'\r\n':'\n'),catalog:result};
}
const hash=s=>crypto.createHash('sha256').update(s).digest('hex');
function installationSource(config,configPath){
  const s=sections(config),provider=read(s,'','model_provider')||'openai';
  const ref=read(s,'','model_catalog_json')||'8stoken-model-catalog.json';
  const catalogPath=path.isAbsolute(ref)?ref:path.join(path.dirname(configPath),ref);
  if(!fs.existsSync(catalogPath))throw Error('Model metadata missing: expected 8stoken-model-catalog.json beside config.toml, or an existing model_catalog_json. No settings changed.');
  const catalog=JSON.parse(fs.readFileSync(catalogPath,'utf8').replace(/^\uFEFF/,''));
  for(const [name,indices]of s.map){
    if(name.startsWith('profiles.')&&indices.some(i=>/^\s*(model|model_provider|model_catalog_json|model_reasoning_effort|forced_login_method)\s*=/.test(s.rows[i])))throw Error('Profile override requires manual setup');
  }
  if(provider!=='openai')return {config,catalog};
  if(s.map.has('model_providers.openai'))throw Error('OpenAI provider override requires manual setup');
  if(s.map.has('model_providers.safe_8stoken'))throw Error('safe_8stoken provider already exists; review configuration manually');
  set(s,'','model_provider','safe_8stoken');
  set(s,'','model','gpt-6.1-sol');
  // Auth forcing belongs to official mode; local router authenticates via its env_key.
  const remove=new Set(['forced_login_method','preferred_auth_method','model_reasoning_effort']);
  const root=new Set(s.map.get(''));
  s.rows=s.rows.filter((line,i)=>!(root.has(i)&&[...remove].some(k=>new RegExp(`^\\s*${k}\\s*=`).test(line))));
  const text=s.rows.join(config.includes('\r\n')?'\r\n':'\n')+'\n[model_providers.safe_8stoken]\nname = "Safe 8stoken Router"\nbase_url = "https://8stoken.com/v1"\nwire_api = "responses"\nenv_key = "EIGHTSTOKEN_API_KEY"\n';
  return {config:text,catalog};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
  try{
    const [operation,configPath,installDir]=process.argv.slice(2);
    const config=fs.readFileSync(configPath,'utf8').replace(/^\uFEFF/,'');const statePath=path.join(installDir,'rollback.json');
    if(operation==='enable-extreme'){
      const source=installationSource(config,configPath),catalog=source.catalog;
      const routerPath=path.join(installDir,'router-config.json');const router=JSON.parse(fs.readFileSync(routerPath,'utf8'));
      const astra=catalog.models?.find(m=>m.slug==='gpt-6-astra');
      const hasPro=Object.values(router.aliases).some(a=>a.keyEnv==='SAFE_8STOKEN_PRO');
      if(hasPro&&astra?.supported_reasoning_levels?.some(x=>x.effort==='xhigh'))router.aliases['8s-extreme']={model:'gpt-6-astra',effort:'xhigh',keyEnv:'SAFE_8STOKEN_PRO',display:'6 Astra - Extreme (Pro)'};
      const generated=path.join(installDir,'codex-router-catalog.json');
      const prepared=adapt(source.config,catalog,router.aliases,generated,router.port);
      fs.writeFileSync(generated,JSON.stringify(prepared.catalog,null,2));
      fs.writeFileSync(routerPath,JSON.stringify(router,null,2));console.log('Existing model catalog validated.');
    }else if(operation==='restore'){
      const recoveryState=fs.existsSync(statePath)?statePath:statePath+'.tmp';
      const state=JSON.parse(fs.readFileSync(recoveryState,'utf8'));
      const original=fs.readFileSync(path.join(installDir,'config-before-router.toml'),'utf8').replace(/^\uFEFF/,'');
      if(hash(config)!==state.installedHash&&hash(config)!==hash(original))throw Error('Codex config changed since setup. Restore manually from config-before-router.toml; current config was left untouched.');
      fs.copyFileSync(path.join(installDir,'config-before-router.toml'),configPath);console.log('Original Codex config restored.');
    }else if(operation==='install'){
      if(fs.existsSync(statePath)||fs.existsSync(statePath+'.tmp'))throw Error('Existing or incomplete installation: rollback before reinstalling');
      const source=installationSource(config,configPath);const router=JSON.parse(fs.readFileSync(path.join(installDir,'router-config.json'),'utf8').replace(/^\uFEFF/,''));
      const generated=path.join(installDir,'codex-router-catalog.json');const r=adapt(source.config,source.catalog,router.aliases,generated,router.port);
      fs.copyFileSync(configPath,path.join(installDir,'config-before-router.toml'));
      fs.writeFileSync(generated,JSON.stringify(r.catalog,null,2));
      const temporary=configPath+'.safe-router.tmp';const pending=statePath+'.tmp';let committed=false;
      try{
        fs.writeFileSync(temporary,r.config);fs.writeFileSync(pending,JSON.stringify({configPath,installedHash:hash(r.config)},null,2));
        fs.renameSync(temporary,configPath);committed=true;fs.renameSync(pending,statePath);
      }catch(e){
        if(committed)fs.copyFileSync(path.join(installDir,'config-before-router.toml'),configPath);
        for(const file of [temporary,pending]){try{if(fs.statSync(file).isFile())fs.unlinkSync(file);}catch{}}
        throw e;
      }
      console.log('Codex connected. Raw models preserved; presets added.');
    }else throw Error('Expected install, enable-extreme or restore');
  }catch(e){console.error(e.message);process.exit(1);}
}
