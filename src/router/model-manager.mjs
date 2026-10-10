import fs from 'node:fs';import {pathToFileURL} from 'node:url';
export function updateRoutes(input,metadata,label,ids){
  if(!/^[A-Za-z][A-Za-z0-9_]{0,39}$/.test(label||''))throw Error('Use letters, numbers, and underscore for the credential label.');
  label=label.toUpperCase();const standard=['PLUS','PRO','FULL'].includes(label);ids=[...new Set(ids.map(x=>x.trim()).filter(Boolean))];
  if(!standard&&!ids.length)throw Error('Select at least one raw model for this group key.');
  if(!Array.isArray(metadata.models))throw Error('Model catalog metadata is missing.');
  const config=structuredClone(input),catalog=structuredClone(metadata);config.modelRoutes??={};config.aliases??={};
  const envName=standard?`SAFE_8STOKEN_${label}`:`SAFE_8STOKEN_EXTRA_${label}`;
  for(const id of ids){if(!/^[A-Za-z0-9][A-Za-z0-9_./:-]{0,159}$/.test(id)||id.startsWith('8s-')||!catalog.models.some(m=>m.slug===id))throw Error('Select exact raw model IDs from the catalog. Presets cannot be remapped.');config.modelRoutes[id]=envName;}
  const presets=label==='PLUS'?[['8s-balanced','gpt-6.1-sol','medium','6.1 Sol - Balanced (Plus)']]:label==='PRO'?[['8s-heavy','gpt-6.1-sol','xhigh','6.1 Sol - Heavy (Pro)']]:label==='FULL'?[['8s-critical','gpt-6.1-sol','xhigh','6.1 Sol - Critical (Full)']]:[];
  if(label==='PRO'&&catalog.models.find(m=>m.slug==='gpt-6-astra')?.supported_reasoning_levels?.some(x=>x.effort==='xhigh'))presets.push(['8s-extreme','gpt-6-astra','xhigh','6 Astra - Extreme (Pro)']);
  for(const [slug,model,effort,display]of presets){const source=catalog.models.find(m=>m.slug===model),level=source?.supported_reasoning_levels?.find(x=>x.effort===effort);if(!level)throw Error('Source model effort metadata is missing. Refresh the catalog before enabling this preset.');
    config.aliases[slug]={model,effort,keyEnv:envName,display};catalog.models=catalog.models.filter(m=>m.slug!==slug);const clone=structuredClone(source);Object.assign(clone,{slug,display_name:display,supported_reasoning_levels:[level],default_reasoning_level:effort,visibility:'list',supported_in_api:true});delete clone.upgrade;catalog.models.push(clone);
  }
  return {config,catalog,envName};
}
const credentialLabel=env=>/^SAFE_8STOKEN_(?:EXTRA_)?[A-Z][A-Z0-9_]{0,39}$/.test(env||'')?env.replace(/^SAFE_8STOKEN_(?:EXTRA_)?/,''):'Custom / hidden';
export function previewRoutes(input,metadata,label,ids){
 const updated=updateRoutes(input,metadata,label,ids);
 const touched=new Set(ids.map(x=>x.trim()).filter(Boolean));
 for(const [id,preset]of Object.entries(updated.config.aliases))if(preset.keyEnv===updated.envName)touched.add(id);
 return {label:label.toUpperCase(),changes:[...touched].map(modelId=>({modelId,kind:updated.config.aliases[modelId]?'Preset':'Raw model',beforeCredential:credentialLabel(input.aliases?.[modelId]?.keyEnv??input.modelRoutes?.[modelId]??input.defaultKeyEnv),afterCredential:credentialLabel(updated.envName)}))};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){try{const [conf,cat,request,output,mode]=process.argv.slice(2),r=JSON.parse(fs.readFileSync(request));const result=(mode==='--preview'?previewRoutes:updateRoutes)(JSON.parse(fs.readFileSync(conf)),JSON.parse(fs.readFileSync(cat)),r.label,r.ids);fs.writeFileSync(output,JSON.stringify(result));}catch(e){console.error(e.message);process.exitCode=1;}}
