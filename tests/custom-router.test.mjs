import {test} from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import {createRouter,rewrite} from '../src/router/router.mjs';
const registry={credentials:[{id:'key-1',label:'cheap',keyEnv:'SAFE_8STOKEN_EXTRA_CHEAP'}],customModels:[{id:'rs-sol-cheap',credentialId:'key-1',originalModel:'gpt-6.1-sol',displayLabel:'6.1 cheap',metadata:{}}]};
const env={LOCAL:'local-test-secret',DEFAULT:'default-test-secret',SAFE_8STOKEN_EXTRA_CHEAP:'cheap-test-secret'};
async function listen(server){await new Promise(r=>server.listen(0,'127.0.0.1',r));return server.address().port;}
async function fixture(t,overrides={}){
 const seen=[];const upstream=http.createServer(async(q,s)=>{let body='';for await(const part of q)body+=part;seen.push({authorization:q.headers.authorization,body});s.end('{}');});
 const port=await listen(upstream);
 const proxy=createRouter({...registry,...overrides,upstream:`http://127.0.0.1:${port}`,allowHttpForTests:true,localTokenEnv:'LOCAL',defaultKeyEnv:'DEFAULT'},overrides.env??env);
 const proxyPort=await listen(proxy);
 t.after(()=>{proxy.closeAllConnections();upstream.closeAllConnections();proxy.close();upstream.close();});
 return {seen,url:`http://127.0.0.1:${proxyPort}/v1/responses`};
}
async function post(url,body){return fetch(url,{method:'POST',headers:{authorization:'Bearer local-test-secret','content-type':'application/json'},body});}
test('custom rewrite changes only the model span, retaining selected effort and exact opaque bytes',()=>{
 const body=Buffer.from('{ "model":"rs-sol-cheap", "reasoning":{"effort":"medium","summary":"auto"}, "opaque":9007199254740993999 }');
 const result=rewrite(body,{}, {},registry);
 assert.equal(result.body.toString(),body.toString().replace('rs-sol-cheap','gpt-6.1-sol'));
 assert.equal(result.keyEnv,'SAFE_8STOKEN_EXTRA_CHEAP');
 const noEffort=rewrite(Buffer.from('{"model":"rs-sol-cheap"}'),{},{},registry);
 assert.equal(noEffort.body.toString(),'{"model":"gpt-6.1-sol"}');
});
test('custom requests use the bound credential; legacy raw still uses the default',async t=>{
 const {url,seen}=await fixture(t);
 assert.equal((await post(url,'{"model":"rs-sol-cheap","reasoning":{"effort":"high"}}')).status,200);
 assert.equal(seen[0].authorization,'Bearer cheap-test-secret');
 assert.equal(JSON.parse(seen[0].body).reasoning.effort,'high');
 assert.equal(JSON.parse(seen[0].body).model,'gpt-6.1-sol');
 assert.equal((await post(url,'{"model":"raw"}')).status,200);
 assert.equal(seen[1].authorization,'Bearer default-test-secret');
});
test('missing custom credential, missing secret and unavailable model fail without upstream or fallback',async t=>{
 for(const overrides of [{credentials:[]},{env:{LOCAL:env.LOCAL,DEFAULT:env.DEFAULT}},{customModels:[{...registry.customModels[0],availability:'unavailable'}]}]){
  const {url,seen}=await fixture(t,overrides);
  assert.equal((await post(url,'{"model":"rs-sol-cheap"}')).status,503);
  assert.equal(seen.length,0);
 }
});

test('ambiguous or malformed persisted registry is rejected before serving requests',()=>{
 for(const overrides of [{credentials:[registry.credentials[0],registry.credentials[0]]},{aliases:{'rs-sol-cheap':{model:'wrong',keyEnv:'DEFAULT'}}},{credentials:[{...registry.credentials[0],keyEnv:'LOCAL'}]}]){
  assert.throws(()=>createRouter({...registry,...overrides,upstream:'https://8stoken.com',localTokenEnv:'LOCAL'},env));
 }
});
