import {test} from 'node:test';import assert from 'node:assert/strict';
import {EventEmitter} from 'node:events';import {Readable} from 'node:stream';
import {runProbe} from '../src/router/probe-engine.mjs';
const plan={kind:'catalog',credentialLabel:'PLUS',keyEnv:'SAFE_8STOKEN_PLUS',endpointName:'8stoken',snapshotDigest:'a'.repeat(64)};
function fixture(status,body,headers={'content-type':'application/json'}){const calls=[];return {calls,request(options,callback){calls.push(options);const req=new EventEmitter();req.end=()=>queueMicrotask(()=>{const res=Readable.from([Buffer.from(body)]);res.statusCode=status;res.headers=headers;callback(res);});req.destroy=()=>{};return req;}};}
test('catalog validates bounded schema with one GET to fixed production target',async()=>{const f=fixture(200,'{"data":[{"id":"raw"}]}');const result=await runProbe(plan,'fake-provider-key',f);assert.equal(result.outcome,'passed');assert.equal(f.calls.length,1);assert.equal(f.calls[0].hostname,'8stoken.com');assert.equal(f.calls[0].path,'/v1/models');assert.equal(f.calls[0].method,'GET');assert.equal(f.calls[0].headers.authorization,'Bearer fake-provider-key');assert.doesNotMatch(JSON.stringify(result),/fake-provider-key|"raw"/);});
test('redirect_never_followed and upstream errors not replayed or echoed',async()=>{for(const status of [302,401,429,500]){const f=fixture(status,'fake-provider-key upstream private body',{location:'https://evil.example','content-type':'application/json'});const result=await runProbe(plan,'fake-provider-key',f);assert.equal(result.outcome,'failed');assert.equal(result.httpStatus,status);assert.equal(f.calls.length,1);assert.doesNotMatch(JSON.stringify(result),/private body|fake-provider-key|evil/);}});
test('malformed catalog and response limit cannot pass',async()=>{for(const body of ['{"data":{}}','{"data":[{"id":42}]}','not JSON','x'.repeat(1024*1024+1)]){const f=fixture(200,body);assert.equal((await runProbe(plan,'fake-provider-key',f)).outcome,'failed');}});
test('local and official_auth_not_verified send zero upstream requests',async()=>{const f=fixture(200,'{}');for(const kind of ['local','official_config']){const result=await runProbe({kind,endpointName:kind==='local'?'Local router':'Official ChatGPT',snapshotDigest:'a'.repeat(64)},null,f);assert.equal(result.outcome,'not_verified');}assert.equal(f.calls.length,0);});
test('absolute timeout bounds stalled headers and cancellation aborts transport',async()=>{let destroyed=0;const stalled={request(){const req=new EventEmitter();req.end=()=>{};req.destroy=()=>destroyed++;return req;},timeoutMs:10};assert.equal((await runProbe(plan,'fake-provider-key',stalled)).outcome,'timed_out');const cancel=new AbortController();const pending=runProbe(plan,'fake-provider-key',{...stalled,timeoutMs:30000,signal:cancel.signal});cancel.abort();assert.equal((await pending).outcome,'cancelled');assert.equal(destroyed,2);});

test('explicit catalog collection returns normalized entries, while diagnostic probes stay metadata-free',async()=>{
 const f=fixture(200,JSON.stringify({data:[{id:'gpt-6.1-sol',supported_reasoning_levels:[{effort:'medium'}],owner:'private-provider-field'}]}));
 const result=await runProbe(plan,'fake-provider-key',{...f,includeCatalog:true});
 assert.equal(result.outcome,'passed');
 assert.deepEqual(result.catalog,{models:[{slug:'gpt-6.1-sol',supported_reasoning_levels:[{effort:'medium'}]}]});
 assert.doesNotMatch(JSON.stringify(result),/private-provider-field|fake-provider-key/);
 const ordinary=await runProbe(plan,'fake-provider-key',f);
 assert.equal(ordinary.catalog,undefined);
});
test('catalog collector fails closed on duplicate ids, malformed effort metadata or reflected secret',async()=>{
 for(const data of [[{id:'raw'},{id:'raw'}],[{id:'raw',supported_reasoning_levels:['high']}],[{id:'fake-provider-key'}]]){
  const f=fixture(200,JSON.stringify({data}));
  const result=await runProbe(plan,'fake-provider-key',{...f,includeCatalog:true});
  assert.equal(result.outcome,'failed');assert.equal(result.errorCode,'protocol_mismatch');assert.equal(result.catalog,undefined);
 }
});
