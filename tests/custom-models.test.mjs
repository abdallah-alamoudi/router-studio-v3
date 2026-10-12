import {test} from 'node:test';
import assert from 'node:assert/strict';
import {
  normalizeCatalogResponse,
  addCredential,
  addCustomModel,
  removeCredential,
  buildCodexCatalog
} from '../src/router/custom-models.mjs';

const base={credentials:[],customModels:[],aliases:{},modelRoutes:{}};
const catalog={credentialId:'cred-1',...normalizeCatalogResponse({data:[
  {id:'gpt-6.1-sol',display_name:'GPT 6.1 Sol',supported_reasoning_levels:[{effort:'medium'},{effort:'xhigh'}],opaque:{keep:true}},
  {id:'gpt-6-astra'}
]})};

test('credentials are independent records with stable ids and labels',()=>{
  const a=addCredential(base,{id:'cred-1',label:'Cheap',keyEnv:'SAFE_8STOKEN_CHEAP'});
  const b=addCredential(a,{id:'cred-1',label:'Renamed',keyEnv:'SAFE_8STOKEN_CHEAP'});
  assert.equal(b.credentials[0].label,'Renamed');
  assert.throws(()=>addCredential(b,{id:'cred-2',label:'Renamed',keyEnv:'SAFE_8STOKEN_OTHER'}),/label/i);
});

test('custom model binds credential id and original model without binding effort',()=>{
  const withKey=addCredential(base,{id:'cred-1',label:'Cheap',keyEnv:'SAFE_8STOKEN_CHEAP'});
  const result=addCustomModel(withKey,catalog,{id:'sol-cheap',credentialId:'cred-1',originalModel:'gpt-6.1-sol',displayLabel:'6.1 cheap'});
  assert.deepEqual(result.customModels[0],{id:'sol-cheap',credentialId:'cred-1',originalModel:'gpt-6.1-sol',displayLabel:'6.1 cheap',metadata:{supported_reasoning_levels:[{effort:'medium'},{effort:'xhigh'}]}});
  assert.throws(()=>addCustomModel(result,catalog,{id:'other',credentialId:'cred-1',originalModel:'gpt-6.1-sol',displayLabel:'6.1 cheap'}),/label/i);
  assert.throws(()=>addCustomModel(result,catalog,{id:'gpt-6.1-sol',credentialId:'cred-1',originalModel:'gpt-6.1-sol',displayLabel:'other'}),/conflict/i);
});

test('deleting a credential used by a custom model is rejected',()=>{
  const withKey=addCredential(base,{id:'cred-1',label:'Cheap',keyEnv:'SAFE_8STOKEN_CHEAP'});
  const withModel=addCustomModel(withKey,catalog,{id:'sol-cheap',credentialId:'cred-1',originalModel:'gpt-6.1-sol',displayLabel:'6.1 cheap'});
  assert.throws(()=>removeCredential(withModel,'cred-1'),/custom model/i);
});

test('catalog exposes custom display labels and only trusted source metadata',()=>{
  const withKey=addCredential(base,{id:'cred-1',label:'Cheap',keyEnv:'SAFE_8STOKEN_CHEAP'});
  const withModel=addCustomModel(withKey,catalog,{id:'sol-cheap',credentialId:'cred-1',originalModel:'gpt-6.1-sol',displayLabel:'6.1 cheap'});
  const generated=buildCodexCatalog(catalog,withModel);
  assert.equal(generated.models.find(x=>x.slug==='sol-cheap').display_name,'6.1 cheap');
  assert.deepEqual(generated.models.find(x=>x.slug==='sol-cheap').supported_reasoning_levels,[{effort:'medium'},{effort:'xhigh'}]);
  assert.equal(generated.models.find(x=>x.slug==='sol-cheap').default_reasoning_level,undefined);
});

test('operations are pure, credential environments are immutable and cannot be shared',()=>{
  const empty={aliases:{}};const before=structuredClone(empty);
  const one=addCredential(empty,{id:'cred-1',label:'Cheap',keyEnv:'SAFE_8STOKEN_CHEAP'});
  assert.deepEqual(empty,before);
  assert.throws(()=>addCredential(one,{id:'cred-1',label:'New label',keyEnv:'SAFE_8STOKEN_OTHER'}),/immutable/i);
  assert.throws(()=>addCredential(one,{id:'cred-2',label:'Other',keyEnv:'SAFE_8STOKEN_CHEAP'}),/environment/i);
  for(const label of [' ','bad\nlabel',' trailing '])assert.throws(()=>addCredential(empty,{id:'cred-1',label,keyEnv:'SAFE_8STOKEN_CHEAP'}),/label/i);
});

test('normalization drops unknown provider fields and does not invent reasoning capabilities',()=>{
  const result=normalizeCatalogResponse({data:[{id:'raw',api_key:'private-canary',owner:'private-canary',reasoning_effort:['high'],supported_reasoning_levels:[{effort:'high',description:'supported',secret:'private-canary'}],context_window:12345},{id:'plain',default_reasoning_level:'high'}]});
  assert.deepEqual(result,{models:[{slug:'raw',context_window:12345,supported_reasoning_levels:[{effort:'high',description:'supported'}]},{slug:'plain'}]});
  assert.doesNotMatch(JSON.stringify(result),/private-canary/);
  for(const payload of [{data:[{id:'bad model'}]},{data:[{id:'raw'},{id:'raw'}]},{data:[{id:'raw',supported_reasoning_levels:[{effort:'high'},{effort:'high'}]}]}])assert.throws(()=>normalizeCatalogResponse(payload),/catalog|reasoning/i);
});

test('custom model creation requires a catalog explicitly associated with that credential',()=>{
  const config=addCredential(base,{id:'cred-1',label:'Cheap',keyEnv:'SAFE_8STOKEN_CHEAP'});
  assert.throws(()=>addCustomModel(config,{...catalog,credentialId:'cred-other'},{id:'sol-cheap',credentialId:'cred-1',originalModel:'gpt-6.1-sol',displayLabel:'6.1 cheap'}),/catalog.*credential/i);
});

test('catalog generation is idempotent and never borrows raw reasoning metadata for custom models',()=>{
  const config={...base,credentials:[{id:'cred-1',label:'Cheap',keyEnv:'SAFE_8STOKEN_CHEAP'}],customModels:[{id:'sol-cheap',credentialId:'cred-1',originalModel:'gpt-6.1-sol',displayLabel:'6.1 cheap',metadata:{}}]};
  const generated=buildCodexCatalog(catalog,config);
  const entry=generated.models.find(x=>x.slug==='sol-cheap');
  assert.equal(entry.supported_reasoning_levels,undefined);
  assert.deepEqual(buildCodexCatalog(generated,config),generated);
  assert.deepEqual(buildCodexCatalog({models:[]},config).models,[entry]);
  assert.equal(buildCodexCatalog(catalog,{...config,credentials:[]}).models.some(x=>x.slug==='sol-cheap'),false);
});

test('legacy default, raw and alias credential references prevent unsafe deletion',()=>{
  const config=addCredential({...base,defaultKeyEnv:'SAFE_8STOKEN_CHEAP'},{id:'cred-1',label:'Cheap',keyEnv:'SAFE_8STOKEN_CHEAP'});
  assert.throws(()=>removeCredential(config,'cred-1'),/route/i);
});

import * as registry from '../src/router/custom-models.mjs';
test('catalog refresh updates credential-specific metadata and disables disappeared models',()=>{
  const withKey=addCredential(base,{id:'cred-1',label:'Cheap',keyEnv:'SAFE_8STOKEN_CHEAP'});
  const withModel=addCustomModel(withKey,catalog,{id:'sol-cheap',credentialId:'cred-1',originalModel:'gpt-6.1-sol',displayLabel:'6.1 cheap'});
  const before=structuredClone(withModel);
  const refreshed=registry.setCredentialCatalog(withModel,'cred-1',{models:[{slug:'gpt-6.1-sol',supported_reasoning_levels:[{effort:'low'}]}]},'2026-10-12T10:00:00.000Z');
  assert.deepEqual(refreshed.customModels[0].metadata.supported_reasoning_levels,[{effort:'low'}]);
  assert.equal(refreshed.credentials[0].catalog.source,'8stoken:/v1/models');
  assert.equal(refreshed.credentials[0].catalog.fetchedAtUtc,'2026-10-12T10:00:00.000Z');
  const missing=registry.setCredentialCatalog(refreshed,'cred-1',{models:[]},'2026-10-12T11:00:00.000Z');
  assert.equal(missing.customModels[0].availability,'unavailable');
  assert.equal(buildCodexCatalog(catalog,missing).models.some(x=>x.slug==='sol-cheap'),false);
  const restored=registry.setCredentialCatalog(missing,'cred-1',catalog,'2026-10-12T12:00:00.000Z');
  assert.equal(restored.customModels[0].availability,'available');
  assert.deepEqual(withModel,before);
});
test('secret replacement invalidates the key catalog and bound models until explicit refresh',()=>{
  const withKey=addCredential(base,{id:'cred-1',label:'Cheap',keyEnv:'SAFE_8STOKEN_CHEAP'});
  const withCatalog=registry.setCredentialCatalog(withKey,'cred-1',catalog,'2026-10-12T10:00:00.000Z');
  const withModel=addCustomModel(withCatalog,catalog,{id:'sol-cheap',credentialId:'cred-1',originalModel:'gpt-6.1-sol',displayLabel:'6.1 cheap'});
  const changed=registry.invalidateCredentialCatalog(withModel,'cred-1');
  assert.equal(changed.credentials[0].catalog,undefined);
  assert.equal(changed.customModels[0].availability,'unavailable');
});
test('custom model update keeps its id and deletion removes it from the generated catalog',()=>{
  const withKey=addCredential(base,{id:'cred-1',label:'Cheap',keyEnv:'SAFE_8STOKEN_CHEAP'});
  const withModel=addCustomModel(withKey,catalog,{id:'sol-cheap',credentialId:'cred-1',originalModel:'gpt-6.1-sol',displayLabel:'6.1 cheap'});
  const updated=registry.updateCustomModel(withModel,catalog,{id:'sol-cheap',credentialId:'cred-1',originalModel:'gpt-6-astra',displayLabel:'Astra cheap'});
  assert.equal(updated.customModels[0].id,'sol-cheap');assert.equal(updated.customModels[0].originalModel,'gpt-6-astra');
  const removed=registry.removeCustomModel(updated,'sol-cheap');
  const generated=buildCodexCatalog(catalog,updated);
  assert.equal(buildCodexCatalog(generated,removed,{previousCustomModels:updated.customModels}).models.some(x=>x.slug==='sol-cheap'),false);
});
test('invalid registry state, local auth environment and conflicting names are rejected',()=>{
  assert.throws(()=>addCredential(base,{id:'cred-1',label:'Bad',keyEnv:'SAFE_8STOKEN_LOCAL_TOKEN'}),/environment/i);
  const one=addCredential(base,{id:'cred-1',label:'Cheap',keyEnv:'SAFE_8STOKEN_CHEAP'});
  assert.throws(()=>registry.validateRegistry({...one,credentials:[one.credentials[0],one.credentials[0]]}),/duplicate/i);
  assert.throws(()=>addCustomModel({...one,aliases:{heavy:{display:'Sol Heavy'}}},catalog,{id:'custom',credentialId:'cred-1',originalModel:'gpt-6.1-sol',displayLabel:'Sol Heavy'}),/conflict/i);
});
test('legacy credentials migrate deterministically without changing existing routing or catalog',()=>{
  const input={defaultKeyEnv:'SAFE_8STOKEN_PLUS',aliases:{heavy:{model:'raw',keyEnv:'SAFE_8STOKEN_PRO'}},modelRoutes:{raw:'SAFE_8STOKEN_EXTRA_CHINESE'}};
  const migrated=registry.migrateCredentials(input,['SAFE_8STOKEN_LOCAL_TOKEN','SAFE_8STOKEN_PLUS','SAFE_8STOKEN_PRO','SAFE_8STOKEN_EXTRA_CHINESE']);
  assert.deepEqual(migrated.aliases,input.aliases);assert.deepEqual(migrated.modelRoutes,input.modelRoutes);
  assert.equal(migrated.credentials.length,3);
  assert.equal(migrated.credentials.find(x=>x.keyEnv==='SAFE_8STOKEN_PLUS').id,'legacy-plus');
  assert.deepEqual(registry.migrateCredentials(migrated,['SAFE_8STOKEN_PLUS']),migrated);
  assert.deepEqual(input,{defaultKeyEnv:'SAFE_8STOKEN_PLUS',aliases:{heavy:{model:'raw',keyEnv:'SAFE_8STOKEN_PRO'}},modelRoutes:{raw:'SAFE_8STOKEN_EXTRA_CHINESE'}});
});

test('deletion permanently retires custom IDs and strips stale catalog entries',()=>{
 const keyed=addCredential(base,{id:'cred-1',label:'Cheap',keyEnv:'SAFE_8STOKEN_CHEAP'});
 const defined=addCustomModel(keyed,catalog,{id:'sol-cheap',credentialId:'cred-1',originalModel:'gpt-6.1-sol',displayLabel:'Cheap sol'});
 const removed=registry.removeCustomModel(defined,'sol-cheap');
 assert.deepEqual(removed.retiredCustomModelIds,['sol-cheap']);
 assert.equal(buildCodexCatalog(buildCodexCatalog(catalog,defined),removed).models.some(m=>m.slug==='sol-cheap'),false);
 assert.throws(()=>addCustomModel(removed,catalog,{id:'sol-cheap',credentialId:'cred-1',originalModel:'gpt-6.1-sol',displayLabel:'Reused'}),/retired/i);
 assert.throws(()=>registry.validateRegistry({...defined,retiredCustomModelIds:['sol-cheap']}),/retired/i);
});
