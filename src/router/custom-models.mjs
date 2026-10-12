// Public configuration only. Secrets stay in the worker's encrypted store.
const idPattern=/^[A-Za-z][A-Za-z0-9._:-]{0,79}$/;
const modelPattern=/^[A-Za-z0-9][A-Za-z0-9_./:-]{0,159}$/;
const envPattern=/^SAFE_8STOKEN_(?:EXTRA_)?[A-Z][A-Z0-9_]{0,39}$/;
const effortPattern=/^[a-z][a-z0-9_]{0,31}$/;
function fail(message){throw new Error(message);}
function object(value){return value!==null&&typeof value==='object'&&!Array.isArray(value);}
function label(value){return typeof value==='string'&&value.length>0&&value.length<=80&&value===value.trim()&&!/[\u0000-\u001f\u007f]/u.test(value);}
function configCopy(input){
  if(!object(input))fail('Configuration is required.');
  const config=structuredClone(input);config.credentials??=[];config.customModels??=[];
  if(!Array.isArray(config.credentials)||!Array.isArray(config.customModels))fail('Credentials and custom models must be arrays.');
  return config;
}
function assertId(id){if(typeof id!=='string'||!idPattern.test(id))fail('Invalid identifier.');}
function assertLabel(value){if(!label(value))fail('Invalid display label.');}
function uniqueLabel(records,value,ignoreId){
  const key=value.toLowerCase();
  if(records.some(x=>x.id!==ignoreId&&(x.label??x.displayLabel).toLowerCase()===key))fail('Display label already exists.');
}

// Accept only fields with a known shape. Unknown provider fields and speculative
// capabilities (including reasoning_effort) are deliberately not persisted.
export function normalizeModelMetadata(entry){
  if(!object(entry))fail('Model catalog entry is invalid.');
  const metadata={};
  for(const name of ['context_window','max_output_tokens']){
    if(entry[name]!==undefined){if(!Number.isSafeInteger(entry[name])||entry[name]<=0)fail('Model catalog metadata is invalid.');metadata[name]=entry[name];}
  }
  if(entry.supported_reasoning_levels!==undefined){
    if(!Array.isArray(entry.supported_reasoning_levels)||entry.supported_reasoning_levels.length>32)fail('Model reasoning metadata is invalid.');
    const seen=new Set();
    metadata.supported_reasoning_levels=entry.supported_reasoning_levels.map(level=>{
      if(!object(level)||typeof level.effort!=='string'||!effortPattern.test(level.effort)||seen.has(level.effort))fail('Model reasoning metadata is invalid.');
      seen.add(level.effort);const result={effort:level.effort};
      if(typeof level.description==='string'&&level.description.length<=512&&!/[\u0000-\u001f\u007f]/u.test(level.description))result.description=level.description;
      return result;
    });
    if(typeof entry.default_reasoning_level==='string'&&seen.has(entry.default_reasoning_level))metadata.default_reasoning_level=entry.default_reasoning_level;
  }
  return metadata;
}
export function normalizeCatalogResponse(payload){
  if(!object(payload)||!Array.isArray(payload.data)||payload.data.length>10000)fail('Model catalog response is invalid.');
  const seen=new Set();
  const models=payload.data.map(entry=>{
    if(!object(entry)||typeof entry.id!=='string'||!modelPattern.test(entry.id)||seen.has(entry.id))fail('Model catalog entry is invalid or duplicated.');
    seen.add(entry.id);return {slug:entry.id,...normalizeModelMetadata(entry)};
  });
  return {models};
}
export function addCredential(input,{id,label:displayLabel,keyEnv}){
  const config=configCopy(input);assertId(id);assertLabel(displayLabel);
  if(typeof keyEnv!=='string'||!envPattern.test(keyEnv)||keyEnv==='SAFE_8STOKEN_LOCAL_TOKEN')fail('Invalid credential environment.');
  uniqueLabel(config.credentials,displayLabel,id);
  if(config.credentials.some(x=>x.id!==id&&x.keyEnv===keyEnv))fail('Credential environment already exists.');
  const record=config.credentials.find(x=>x.id===id);
  if(record){
    if(record.keyEnv!==keyEnv)fail('Credential environment is immutable.');
    record.label=displayLabel;
  }else config.credentials.push({id,label:displayLabel,keyEnv});
  return config;
}
export function addCustomModel(input,catalog,{id,credentialId,originalModel,displayLabel}){
  const config=configCopy(input);assertId(id);assertLabel(displayLabel);
  if(!findCredential(config,credentialId))fail('Credential does not exist.');
  if(catalog?.credentialId!==credentialId)fail('Model catalog is not associated with the selected credential.');
  const source=catalog.models?.find(x=>x.slug===originalModel);
  if(!source)fail('Original model is not present in the catalog.');
  if(config.retiredCustomModelIds?.includes(id))fail('Custom model identifier is retired.');
  if(config.customModels.some(x=>x.id===id))fail('Custom model identifier already exists.');
  uniqueLabel(config.customModels,displayLabel);
  if(catalog.models.some(x=>x.slug===displayLabel||x.display_name===displayLabel)||Object.entries(config.aliases??{}).some(([slug,x])=>slug===displayLabel||x.display===displayLabel))fail('Display label conflicts with an existing model or alias.');
  if(Object.hasOwn(config.aliases??{},id)||Object.hasOwn(config.modelRoutes??{},id)||catalog.models.some(x=>x.slug===id))fail('Custom model identifier conflicts with an existing model or route.');
  config.customModels.push({id,credentialId,originalModel,displayLabel,metadata:normalizeModelMetadata(source)});
  return config;
}
export function removeCredential(input,credentialId){
  const config=configCopy(input);const credential=findCredential(config,credentialId);
  if(!credential)fail('Credential does not exist.');
  if(config.customModels.some(x=>x.credentialId===credentialId))fail('Credential is used by a custom model.');
  if(config.defaultKeyEnv===credential.keyEnv||Object.values(config.modelRoutes??{}).includes(credential.keyEnv)||Object.values(config.aliases??{}).some(x=>x.keyEnv===credential.keyEnv))fail('Credential is used by an existing route.');
  config.credentials=config.credentials.filter(x=>x.id!==credentialId);return config;
}
export function buildCodexCatalog(catalog,input,{previousCustomModels=[]}={}){
  const config=configCopy(input);const result=structuredClone(catalog);
  if(!Array.isArray(result.models))fail('Model catalog metadata is missing.');
  // Replace our generated entries, retaining existing raw/legacy entries.
  const customIds=new Set([...config.customModels,...previousCustomModels].map(x=>x.id).concat(config.retiredCustomModelIds??[]));
  result.models=result.models.filter(x=>!customIds.has(x.slug));
  for(const custom of config.customModels){
    if(!findCredential(config,custom.credentialId)||custom.availability==='unavailable')continue;
    const entry={...normalizeModelMetadata(custom.metadata??{}),slug:custom.id,display_name:custom.displayLabel,visibility:'list',supported_in_api:true};
    result.models.push(entry);
  }
  return result;
}
export function findCredential(config,credentialId){return config.credentials?.find(x=>x.id===credentialId);}

export function setCredentialCatalog(input,credentialId,catalog,fetchedAtUtc){
  const config=configCopy(input);const credential=findCredential(config,credentialId);
  if(!credential)fail('Credential does not exist.');
  if(typeof fetchedAtUtc!=='string'||!Number.isFinite(Date.parse(fetchedAtUtc)))fail('Model catalog timestamp is invalid.');
  if(!Array.isArray(catalog?.models))fail('Model catalog metadata is missing.');
  const normalized=normalizeCatalogResponse({data:catalog.models.map(m=>({...m,id:m.slug}))});
  credential.catalog={source:'8stoken:/v1/models',fetchedAtUtc,models:normalized.models};
  for(const custom of config.customModels.filter(x=>x.credentialId===credentialId)){
    const source=normalized.models.find(x=>x.slug===custom.originalModel);
    custom.availability=source?'available':'unavailable';
    custom.metadata=source?normalizeModelMetadata(source):{};
  }
  return config;
}
export function invalidateCredentialCatalog(input,credentialId){
  const config=configCopy(input);const credential=findCredential(config,credentialId);
  if(!credential)fail('Credential does not exist.');
  delete credential.catalog;
  for(const custom of config.customModels.filter(x=>x.credentialId===credentialId)){
    custom.availability='unavailable';custom.metadata={};
  }
  return config;
}
export function updateCustomModel(input,catalog,definition){
  const config=configCopy(input);
  if(!config.customModels.some(x=>x.id===definition.id))fail('Custom model does not exist.');
  config.customModels=config.customModels.filter(x=>x.id!==definition.id);
  return addCustomModel(config,catalog,definition);
}
export function removeCustomModel(input,id){
  const config=configCopy(input);
  if(!config.customModels.some(x=>x.id===id))fail('Custom model does not exist.');
  config.customModels=config.customModels.filter(x=>x.id!==id);config.retiredCustomModelIds=[...new Set([...(config.retiredCustomModelIds??[]),id])];return config;
}
export function validateRegistry(input){
  const config=configCopy(input);const ids=new Set(),labels=new Set(),environments=new Set();
  for(const credential of config.credentials){
    if(!object(credential))fail('Invalid credential.');
    assertId(credential.id);assertLabel(credential.label);
    if(!envPattern.test(credential.keyEnv??'')||credential.keyEnv==='SAFE_8STOKEN_LOCAL_TOKEN')fail('Invalid credential environment.');
    if(ids.has(credential.id)||labels.has(credential.label.toLowerCase())||environments.has(credential.keyEnv))fail('Duplicate credential.');
    ids.add(credential.id);labels.add(credential.label.toLowerCase());environments.add(credential.keyEnv);
  }
  if(config.retiredCustomModelIds!==undefined){
    if(!Array.isArray(config.retiredCustomModelIds)||new Set(config.retiredCustomModelIds).size!==config.retiredCustomModelIds.length)fail('Invalid retired model identifiers.');
    for(const id of config.retiredCustomModelIds){assertId(id);if(config.customModels.some(m=>m.id===id)||Object.hasOwn(config.aliases??{},id)||Object.hasOwn(config.modelRoutes??{},id))fail('Retired model identifier conflicts with an active route.');}
  }
  ids.clear();labels.clear();
  for(const custom of config.customModels){
    if(!object(custom))fail('Invalid custom model.');
    assertId(custom.id);assertId(custom.credentialId);assertLabel(custom.displayLabel);
    if(!modelPattern.test(custom.originalModel??''))fail('Invalid original model.');
    if(ids.has(custom.id)||labels.has(custom.displayLabel.toLowerCase()))fail('Duplicate custom model.');
    if(Object.hasOwn(config.aliases??{},custom.id)||Object.hasOwn(config.modelRoutes??{},custom.id)||config.customModels.some(m=>m.id===custom.originalModel))fail('Custom model identifier conflicts with a model or route.');
    if(custom.availability!==undefined&&!['available','unavailable'].includes(custom.availability))fail('Invalid model availability.');
    normalizeModelMetadata(custom.metadata??{});
    ids.add(custom.id);labels.add(custom.displayLabel.toLowerCase());
  }
  return config;
}
export function migrateCredentials(input,environments){
  let config=configCopy(input);
  for(const keyEnv of [...new Set(environments)].sort()){
    if(typeof keyEnv!=='string'||!envPattern.test(keyEnv)||keyEnv==='SAFE_8STOKEN_LOCAL_TOKEN'||config.credentials.some(x=>x.keyEnv===keyEnv))continue;
    const label=keyEnv.replace(/^SAFE_8STOKEN_(?:EXTRA_)?/,'');
    const id='legacy-'+keyEnv.replace(/^SAFE_8STOKEN_/,'').toLowerCase().replaceAll('_','-');
    config=addCredential(config,{id,label,keyEnv});
  }
  return validateRegistry(config);
}
