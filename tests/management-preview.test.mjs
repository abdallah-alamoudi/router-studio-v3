import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';import os from 'node:os';import path from 'node:path';
import * as models from '../src/router/model-manager.mjs';
import * as providers from '../src/router/provider-switch.mjs';
const config={defaultKeyEnv:'SAFE_8STOKEN_PLUS',aliases:{},modelRoutes:{old:'SAFE_8STOKEN_EXTRA_OLD'}};
const catalog={models:[{slug:'raw-one'},{slug:'8s-heavy'}]};
const source='model_provider="custom"\nmodel="raw-one"\n[model_providers.custom]\nbase_url="http://127.0.0.1:18761/v1"\nwire_api="responses"\nenv_key="SAFE_8STOKEN_LOCAL_TOKEN"\n';
function fixture(t){const dir=fs.mkdtempSync(path.join(os.tmpdir(),'preview Ω '));t.after(()=>fs.rmSync(dir,{recursive:true,force:true}));const cp=path.join(dir,'config.toml');fs.writeFileSync(cp,source);providers.initializeSwitch(cp,dir);providers.switchProvider(cp,dir,'official');const id=providers.listBackups(dir)[0].id;return {cp,dir,id};}
test('preview_does_not_write and unselected_routes_preserved',()=>{
 assert.equal(typeof models.previewRoutes,'function');const before=JSON.stringify({config,catalog});
 const result=models.previewRoutes(config,catalog,'CHINESE',['raw-one']);
 assert.deepEqual(result.changes,[{modelId:'raw-one',kind:'Raw model',beforeCredential:'PLUS',afterCredential:'CHINESE'}]);
 assert.equal(JSON.stringify({config,catalog}),before);assert.equal(models.updateRoutes(config,catalog,'CHINESE',['raw-one']).config.modelRoutes.old,'SAFE_8STOKEN_EXTRA_OLD');
});
test('preset_cannot_be_raw_remapped in preview',()=>{assert.equal(typeof models.previewRoutes,'function');assert.throws(()=>models.previewRoutes(config,catalog,'CHINESE',['8s-heavy']));});
test('backup_preview_hides_header_values and does not write',t=>{
 const {cp,dir,id}=fixture(t);fs.appendFileSync(cp,'\n[model_providers.custom.http_headers]\nX-Private="fake-secret-header"\n');
 assert.equal(typeof providers.previewBackup,'function');const files=fs.readdirSync(dir);const before=fs.readFileSync(cp,'utf8');
 const preview=providers.previewBackup(cp,dir,id);assert.ok(preview.changes.some(x=>x.field==='model_provider'));
 assert.doesNotMatch(JSON.stringify(preview),/fake-secret-header|SAFE_8STOKEN_LOCAL_TOKEN|base_url/);assert.equal(fs.readFileSync(cp,'utf8'),before);assert.deepEqual(fs.readdirSync(dir),files);
});
test('preview_detects_external_change before backup restore',t=>{
 const {cp,dir,id}=fixture(t);assert.equal(typeof providers.previewBackup,'function');const preview=providers.previewBackup(cp,dir,id);
 fs.appendFileSync(cp,'\n# newer edit\n');const current=fs.readFileSync(cp,'utf8');
 assert.throws(()=>providers.restoreBackup(cp,dir,id,preview),/changed/i);assert.equal(fs.readFileSync(cp,'utf8'),current);
});
test('changed backup content invalidates preview',t=>{
 const {cp,dir,id}=fixture(t);assert.equal(typeof providers.previewBackup,'function');const preview=providers.previewBackup(cp,dir,id);
 fs.appendFileSync(path.join(dir,'backups',id),'\n# changed backup\n');assert.throws(()=>providers.restoreBackup(cp,dir,id,preview),/changed/i);
});
