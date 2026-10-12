import {test} from 'node:test';import assert from 'node:assert/strict';
import {resolveRoute,selectRoute,planProbe} from '../src/router/route-policy.mjs';
const config={defaultKeyEnv:'SAFE_8STOKEN_PLUS',modelRoutes:{raw:'SAFE_8STOKEN_EXTRA_RAW','8s-heavy':'SAFE_8STOKEN_EXTRA_WRONG'},aliases:{'8s-heavy':{model:'raw',effort:'xhigh',keyEnv:'SAFE_8STOKEN_PRO'}},credentials:[{id:'cred-1',label:'Cheap',keyEnv:'SAFE_8STOKEN_CHEAP'}],customModels:[{id:'sol-cheap',credentialId:'cred-1',originalModel:'gpt-6.1-sol',displayLabel:'6.1 cheap',metadata:{supported_reasoning_levels:[{effort:'medium'}]}}]};
const catalog={models:[{slug:'raw'},{slug:'fallback'},{slug:'8s-heavy'},{slug:'sol-cheap'},{slug:'gpt-6.1-sol'}]};
test('preset_beats_exact',()=>{assert.deepEqual(resolveRoute(config,catalog,'8s-heavy'),{modelId:'8s-heavy',resolvedModel:'raw',effort:'xhigh',keyEnv:'SAFE_8STOKEN_PRO',credentialLabel:'PRO',kind:'Preset'});});
test('exact_beats_default',()=>{assert.equal(resolveRoute(config,catalog,'raw').keyEnv,'SAFE_8STOKEN_EXTRA_RAW');assert.equal(resolveRoute(config,catalog,'fallback').keyEnv,'SAFE_8STOKEN_PLUS');});
test('unknown_model_rejected_for_probe; proxy raw models retain default route',()=>{assert.throws(()=>resolveRoute(config,catalog,'unknown'));assert.equal(selectRoute(config,'unknown').keyEnv,'SAFE_8STOKEN_PLUS');});
test('catalog_uses_selected_label and requires explicit acknowledgement',()=>{const plan=planProbe(config,catalog,{kind:'catalog',credentialLabel:'RAW',acknowledgement:true},'a'.repeat(64));assert.equal(plan.keyEnv,'SAFE_8STOKEN_EXTRA_RAW');assert.equal(plan.credentialLabel,'RAW');assert.equal(plan.endpointName,'8stoken');assert.throws(()=>planProbe(config,catalog,{kind:'catalog',credentialLabel:'RAW'},'a'.repeat(64)));});
test('production_target_fixed and request cannot override assigned key',()=>{for(const request of [{kind:'catalog',credentialLabel:'PLUS',acknowledgement:true,endpoint:'https://evil.example'},{kind:'local',keyEnv:'SAFE_8STOKEN_PRO'}])assert.throws(()=>planProbe(config,catalog,request,'a'.repeat(64)));});
test('typed request defaults accepted while malformed output bounds are refused',()=>{assert.equal(planProbe(config,catalog,{kind:'local',outputTokenLimit:256,acknowledgement:false},'a'.repeat(64)).kind,'local');for(const outputTokenLimit of [0,2049,256.5,'256'])assert.throws(()=>planProbe(config,catalog,{kind:'local',outputTokenLimit},'a'.repeat(64)));});
test('custom model resolves original model and its credential without forcing effort',()=>{assert.deepEqual(resolveRoute(config,catalog,'sol-cheap'),{modelId:'sol-cheap',resolvedModel:'gpt-6.1-sol',effort:undefined,keyEnv:'SAFE_8STOKEN_CHEAP',credentialId:'cred-1',credentialLabel:'Cheap',kind:'Custom model'});});
test('custom model never silently falls back when its credential is missing',()=>{assert.throws(()=>resolveRoute({...config,credentials:[]},catalog,'sol-cheap'),/credential/i);assert.throws(()=>selectRoute({...config,credentials:[]},'sol-cheap'),/credential/i);});

test('custom catalog fetch plans use stable credential ids, not labels or default keys',()=>{
 const c={...config,credentials:[{...config.credentials[0],label:'My cheap key'}]};
 const plan=planProbe(c,catalog,{kind:'catalog',credentialId:'cred-1',acknowledgement:true},'a'.repeat(64));
 assert.equal(plan.keyEnv,'SAFE_8STOKEN_CHEAP');assert.equal(plan.credentialId,'cred-1');assert.equal(plan.credentialLabel,'My cheap key');
 assert.throws(()=>planProbe(c,catalog,{kind:'catalog',credentialId:'missing',acknowledgement:true},'a'.repeat(64)));
 assert.throws(()=>planProbe(c,catalog,{kind:'catalog',credentialId:'cred-1',credentialLabel:'PLUS',acknowledgement:true},'a'.repeat(64)));
 assert.throws(()=>planProbe(c,catalog,{kind:'catalog',credentialId:'cred-1'},'a'.repeat(64)));
});
test('custom generation probes resolve their credential without synthesizing effort',()=>{
 const plan=planProbe({...config,credentials:[{...config.credentials[0],label:'My cheap key'}]},catalog,{kind:'responses',modelId:'sol-cheap',acknowledgement:true,expectedSnapshotDigest:'a'.repeat(64)},'a'.repeat(64));
 assert.equal(plan.credentialId,'cred-1');assert.equal(plan.keyEnv,'SAFE_8STOKEN_CHEAP');assert.equal(plan.effort,undefined);
});

test('retired custom IDs cannot silently become raw default routes',()=>{
 assert.throws(()=>selectRoute({...config,customModels:[],retiredCustomModelIds:['sol-cheap']},'sol-cheap'),/unavailable|retired/i);
});
