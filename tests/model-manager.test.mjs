import {test} from 'node:test';
import assert from 'node:assert/strict';
import {updateRoutes} from '../src/router/model-manager.mjs';
const config={defaultKeyEnv:'SAFE_8STOKEN_PLUS',aliases:{},modelRoutes:{old:'SAFE_8STOKEN_EXTRA_OLD'}};
const catalog={models:[{slug:'gpt-6.1-sol',context_window:1000000,supported_reasoning_levels:[{effort:'medium'},{effort:'xhigh'}]},{slug:'gpt-6-astra',supported_reasoning_levels:[{effort:'xhigh'}]},{slug:'deepseek-v4.1-flash',opaque:{keep:true}}]};
test('exact raw model routes use the selected group without changing raw metadata',()=>{const r=updateRoutes(config,catalog,'CHINESE',['deepseek-v4.1-flash']);assert.equal(r.config.modelRoutes['deepseek-v4.1-flash'],'SAFE_8STOKEN_EXTRA_CHINESE');assert.deepEqual(r.catalog,catalog);assert.equal(r.config.modelRoutes.old,'SAFE_8STOKEN_EXTRA_OLD');assert.equal(config.modelRoutes['deepseek-v4.1-flash'],undefined);});
test('Pro key enables supported Heavy and Extreme aliases',()=>{const r=updateRoutes(config,catalog,'PRO',[]);assert.equal(r.config.aliases['8s-heavy'].keyEnv,'SAFE_8STOKEN_PRO');assert.equal(r.config.aliases['8s-extreme'].model,'gpt-6-astra');assert.deepEqual(r.catalog.models.find(m=>m.slug==='8s-heavy').supported_reasoning_levels,[{effort:'xhigh'}]);});
test('missing effort metadata rejects a preset without changing input',()=>{const bad={models:[{slug:'gpt-6.1-sol',supported_reasoning_levels:[]}]};assert.throws(()=>updateRoutes(config,bad,'PRO',[]),/metadata|effort/i);assert.deepEqual(config.aliases,{});});
test('invalid labels, empty extra routes, aliases and unknown model IDs are rejected',()=>{for(const [label,ids]of [['A B',['deepseek-v4.1-flash']],['CHINESE',[]],['CHINESE',['8s-heavy']],['CHINESE',['unknown']]])assert.throws(()=>updateRoutes(config,catalog,label,ids));});
test('updating existing Pro credentials does not duplicate aliases',()=>{const a=updateRoutes(config,catalog,'PRO',[]);const b=updateRoutes(a.config,a.catalog,'PRO',[]);assert.equal(b.catalog.models.filter(m=>m.slug==='8s-heavy').length,1);assert.deepEqual(b.catalog,a.catalog);});

test('raw route management cannot overwrite a custom binding',()=>{
 const cfg={...config,credentials:[{id:'key',label:'Key',keyEnv:'SAFE_8STOKEN_EXTRA_KEY'}],customModels:[{id:'rs-custom',credentialId:'key',originalModel:'gpt-6.1-sol',displayLabel:'Custom'}]};
 assert.throws(()=>updateRoutes(cfg,{models:[...catalog.models,{slug:'rs-custom'}]},'CHINESE',['rs-custom']),/custom|raw/i);
});
test('legacy replacement invalidates registered credential catalog and dependent custom models',()=>{
 const registered={defaultKeyEnv:'SAFE_8STOKEN_PLUS',aliases:{},credentials:[{id:'cred-1',label:'Key',keyEnv:'SAFE_8STOKEN_EXTRA_WORK',catalog:{models:[{id:'raw'}]}}],customModels:[{id:'custom-1',credentialId:'cred-1',originalModel:'raw',displayLabel:'Custom',availability:'available',metadata:{}}]};
 const changed=updateRoutes(registered,{models:[{slug:'raw'},{slug:'custom-1'}]},'WORK',['raw']);
 assert.equal(changed.config.credentials[0].catalog,undefined);assert.equal(changed.config.customModels[0].availability,'unavailable');assert.equal(changed.catalog.models.some(m=>m.slug==='custom-1'),false);
});