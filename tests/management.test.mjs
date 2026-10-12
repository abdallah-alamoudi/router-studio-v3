import test from 'node:test';
import assert from 'node:assert/strict';
import {applyManagement} from '../src/router/management.mjs';
const config={defaultKeyEnv:'SAFE_8STOKEN_PLUS',aliases:{},credentials:[],customModels:[]};
const catalog={models:[{slug:'original',supported_reasoning_levels:[{effort:'medium'}]}]};
const request=(action,payload)=>({action,...payload});
test('independent credential identity uses an opaque environment and immutable create',()=>{
 const saved=applyManagement(config,catalog,request('save-credential',{credentialId:'cred-1',label:'مفتاح'}));
 assert.match(saved.keyEnv,/^SAFE_8STOKEN_EXTRA_[A-Z0-9_]+$/);assert.equal(saved.config.credentials[0].id,'cred-1');
 const renamed=applyManagement(saved.config,catalog,request('rename-credential',{credentialId:'cred-1',label:'Renamed'}));
 assert.equal(renamed.config.credentials[0].keyEnv,saved.keyEnv);
 assert.throws(()=>applyManagement(saved.config,catalog,request('save-credential',{credentialId:'cred-1',label:'Overwrite'})));
});
test('custom CRUD binds stored credential catalog and never introduces an effort override',()=>{
 let s=applyManagement(config,catalog,request('save-credential',{credentialId:'cred-1',label:'Key'}));
 s=applyManagement(s.config,s.catalog,request('fetch-credential-catalog',{credentialId:'cred-1'}),catalog);
 s=applyManagement(s.config,s.catalog,request('save-custom-model',{customModelId:'custom-1',credentialId:'cred-1',originalModel:'original',displayLabel:'Custom'}));
 assert.equal(s.config.customModels[0].credentialId,'cred-1');assert.equal(s.catalog.models.find(m=>m.slug==='custom-1').display_name,'Custom');
 assert.equal(s.config.customModels[0].effort,undefined);
 assert.throws(()=>applyManagement(s.config,s.catalog,request('delete-credential',{credentialId:'cred-1'})));
 s=applyManagement(s.config,s.catalog,request('save-custom-model',{customModelId:'custom-1',credentialId:'cred-1',originalModel:'original',displayLabel:'New label'}));
 assert.equal(s.config.customModels[0].displayLabel,'New label');
 s=applyManagement(s.config,s.catalog,request('delete-custom-model',{customModelId:'custom-1'}));
 assert.deepEqual(s.config.retiredCustomModelIds,['custom-1']);assert.equal(s.catalog.models.length,1);
 s=applyManagement(s.config,s.catalog,request('delete-credential',{credentialId:'cred-1'}));assert.equal(s.config.credentials.length,0);
});
test('rotation invalidates catalog and removes unavailable custom models from visible catalog',()=>{
 let s=applyManagement(config,catalog,request('save-credential',{credentialId:'cred-1',label:'Key'}));
 s=applyManagement(s.config,s.catalog,request('fetch-credential-catalog',{credentialId:'cred-1'}),catalog);
 s=applyManagement(s.config,s.catalog,request('save-custom-model',{customModelId:'custom-1',credentialId:'cred-1',originalModel:'original',displayLabel:'Custom'}));
 s=applyManagement(s.config,s.catalog,request('rotate-credential',{credentialId:'cred-1'}));
 assert.equal(s.config.customModels[0].availability,'unavailable');assert.equal(s.config.credentials[0].catalog,undefined);assert.equal(s.catalog.models.length,1);
});
test('management conservatively adopts saved legacy slots without changing routes or duplicating slots',()=>{
 const old={defaultKeyEnv:'SAFE_8STOKEN_PLUS',aliases:{},modelRoutes:{original:'SAFE_8STOKEN_EXTRA_WORK'}};
 const s=applyManagement(old,catalog,request('rename-credential',{credentialId:'legacy-plus',label:'My old key'}),undefined,['SAFE_8STOKEN_PLUS','SAFE_8STOKEN_EXTRA_WORK','SAFE_8STOKEN_LOCAL_TOKEN']);
 assert.equal(s.config.credentials.find(c=>c.id==='legacy-plus').keyEnv,'SAFE_8STOKEN_PLUS');
 assert.equal(s.config.credentials.length,2);assert.deepEqual(s.config.modelRoutes,old.modelRoutes);
 const next=applyManagement(s.config,s.catalog,request('rename-credential',{credentialId:'legacy-plus',label:'Again'}),undefined,['SAFE_8STOKEN_PLUS','SAFE_8STOKEN_EXTRA_WORK']);assert.equal(next.config.credentials.length,2);
});
