const labelPattern=/^[A-Za-z][A-Za-z0-9_]{0,39}$/;
const modelPattern=/^[A-Za-z0-9][A-Za-z0-9_./:-]{0,159}$/;
function invalid(code='invalid_request'){throw Object.assign(new Error('Invalid probe plan'),{code});}
export function credentialEnvironment(label){
 if(typeof label!=='string'||!labelPattern.test(label))invalid();
 label=label.toUpperCase();return ['PLUS','PRO','FULL'].includes(label)?`SAFE_8STOKEN_${label}`:`SAFE_8STOKEN_EXTRA_${label}`;
}
export function selectRoute(config,modelId){
 const custom=config.customModels?.find(m=>m.id===modelId);
 if(custom){
  const credential=config.credentials?.find(c=>c.id===custom.credentialId);
  if(!credential)throw Object.assign(Error('Custom model credential is missing'),{code:'credential_missing'});
  if(custom.availability==='unavailable')throw Object.assign(Error('Custom model is unavailable'),{code:'unsupported_capability'});
  return {modelId,resolvedModel:custom.originalModel,effort:undefined,keyEnv:credential.keyEnv,credentialId:credential.id,credentialLabel:credential.label,kind:'Custom model'};
 }
 if(config.retiredCustomModelIds?.includes(modelId))throw Object.assign(Error('Custom model is retired and unavailable'),{code:'unsupported_capability'});
 const preset=Object.hasOwn(config.aliases??{},modelId)?config.aliases[modelId]:undefined;
 return {modelId,resolvedModel:preset?.model??modelId,effort:preset?.effort,keyEnv:preset?preset.keyEnv:Object.hasOwn(config.modelRoutes??{},modelId)?config.modelRoutes[modelId]:config.defaultKeyEnv,kind:preset?'Preset':'Raw model'};
}
export function resolveRoute(config,catalog,modelId){
 if(typeof modelId!=='string'||!modelPattern.test(modelId)||!catalog.models?.some(m=>m.slug===modelId))invalid('unsupported_capability');
 const route=selectRoute(config,modelId);
 if(route.kind==='Custom model'){
  if(!/^SAFE_8STOKEN_(?:EXTRA_)?[A-Z][A-Z0-9_]{0,39}$/.test(route.keyEnv??'')||!modelPattern.test(route.resolvedModel))invalid();
  return route;
 }
 const credentialLabel=route.keyEnv?.replace(/^SAFE_8STOKEN_(?:EXTRA_)?/,'');
 if(!credentialLabel || credentialEnvironment(credentialLabel)!==route.keyEnv || !modelPattern.test(route.resolvedModel))invalid();
 return {...route,credentialLabel};
}
export function planProbe(config,catalog,request,snapshotDigest,{preview=false}={}){
 if(!request||typeof request!=='object'||Array.isArray(request)||Object.keys(request).some(k=>!['kind','modelId','credentialId','credentialLabel','outputTokenLimit','expectedSnapshotDigest','acknowledgement'].includes(k)))invalid();
 if(config.upstream && config.upstream!=='https://8stoken.com' && config.upstream!=='https://8stoken.com/')invalid();
 if(!['catalog','local','official_config','responses','stream','tool'].includes(request.kind))invalid('unsupported_capability');
 if(request.outputTokenLimit!==undefined && (!Number.isInteger(request.outputTokenLimit)||request.outputTokenLimit<256||request.outputTokenLimit>2048))invalid();
 if(request.expectedSnapshotDigest!==undefined && request.expectedSnapshotDigest!==snapshotDigest)invalid('config_changed');
 if(request.acknowledgement!==undefined && typeof request.acknowledgement!=='boolean')invalid();
 if(['responses','stream','tool'].includes(request.kind)){
  if(request.credentialLabel!=null||request.credentialId!=null)invalid();
  if(!preview && request.acknowledgement!==true)invalid('acknowledgement_required');
  if(request.expectedSnapshotDigest!==snapshotDigest)invalid('config_changed');
  const route=resolveRoute(config,catalog,request.modelId);
  return validateProbePlan({kind:request.kind,modelId:request.modelId,resolvedModel:route.resolvedModel,...(route.effort?{effort:route.effort}:{}),outputTokenLimit:request.outputTokenLimit??256,...(route.credentialId?{credentialId:route.credentialId}:{}),credentialLabel:route.credentialLabel,keyEnv:route.keyEnv,endpointName:'8stoken',snapshotDigest});
 }
 if(request.modelId!=null)invalid();
 if(request.kind==='catalog'){
  if(!preview && request.acknowledgement!==true)invalid('acknowledgement_required');
  if(request.credentialId!=null){
   if(request.credentialLabel!=null)invalid();
   const credential=config.credentials?.find(c=>c.id===request.credentialId);if(!credential)invalid('credential_missing');
   return validateProbePlan({kind:'catalog',credentialId:credential.id,credentialLabel:credential.label,keyEnv:credential.keyEnv,endpointName:'8stoken',snapshotDigest});
  }
  return validateProbePlan({kind:'catalog',credentialLabel:request.credentialLabel?.toUpperCase(),keyEnv:credentialEnvironment(request.credentialLabel),endpointName:'8stoken',snapshotDigest});
 }
 if(request.credentialLabel!=null||request.credentialId!=null)invalid();
 return validateProbePlan({kind:request.kind,endpointName:request.kind==='local'?'Local router':'Official ChatGPT',snapshotDigest});
}
export function validateProbePlan(plan){
 if(!plan||typeof plan!=='object'||Array.isArray(plan)||Object.keys(plan).some(k=>!['kind','modelId','resolvedModel','effort','outputTokenLimit','credentialId','credentialLabel','keyEnv','endpointName','snapshotDigest'].includes(k))||!/^[a-f0-9]{64}$/.test(plan.snapshotDigest??''))invalid();
 const generation=['responses','stream','tool'].includes(plan.kind);
 const endpoint=generation?'8stoken':{catalog:'8stoken',local:'Local router',official_config:'Official ChatGPT'}[plan.kind];
 if(!endpoint || plan.endpointName!==endpoint)invalid();
 if(generation){
  if(typeof plan.modelId!=='string'||!modelPattern.test(plan.modelId)||typeof plan.resolvedModel!=='string'||!modelPattern.test(plan.resolvedModel)||!Number.isInteger(plan.outputTokenLimit)||plan.outputTokenLimit<256||plan.outputTokenLimit>2048||plan.effort!==undefined && !/^[a-z][a-z0-9_]{0,31}$/.test(plan.effort))invalid();
 }else if(['modelId','resolvedModel','effort','outputTokenLimit'].some(k=>Object.hasOwn(plan,k)))invalid();
 if(plan.kind==='catalog'||generation){
  if(plan.credentialId!==undefined){
   if(typeof plan.credentialId!=='string'||!/^[A-Za-z][A-Za-z0-9._:-]{0,79}$/.test(plan.credentialId)||typeof plan.credentialLabel!=='string'||!plan.credentialLabel.trim()||plan.credentialLabel.length>80||/[\u0000-\u001f\u007f]/u.test(plan.credentialLabel)||!/^SAFE_8STOKEN_(?:EXTRA_)?[A-Z][A-Z0-9_]{0,39}$/.test(plan.keyEnv??'')||plan.keyEnv==='SAFE_8STOKEN_LOCAL_TOKEN')invalid();
  }else if(plan.keyEnv!==credentialEnvironment(plan.credentialLabel))invalid();
 }else if(plan.keyEnv!==undefined || plan.credentialLabel!==undefined || plan.credentialId!==undefined)invalid();
 return plan;
}
