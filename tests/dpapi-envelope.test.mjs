import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {runProcess} from './helpers/run-process.mjs';
const pwsh=process.platform==='win32'?'pwsh.exe':'pwsh';
const available=spawnSync(pwsh,['-NoProfile','-Command','$PSVersionTable.PSVersion.Major'],{encoding:'utf8'});
const skip=process.platform!=='win32'||available.status!==0||Number(available.stdout.trim())<7;
test('DPAPI input and recovery cancellation guards pass isolated checks',{skip},async()=>{
 const sandbox=fs.mkdtempSync(path.join(os.tmpdir(),'studio DPAPI sandbox Ω '));
 try{
  const env={...process.env,TEMP:sandbox,TMP:sandbox};delete env.NODE_TEST_CONTEXT;
  const script=fileURLToPath(new URL('./dpapi-envelope.ps1',import.meta.url));
  const result=await runProcess(pwsh,['-NoProfile','-ExecutionPolicy','Bypass','-File',script],{env,timeoutMs:30000});
  const output=result.stdout+'\n'+result.stderr;
  assert.equal(result.status,0,output);assert.equal(result.timedOut,false,output);
  assert.match(output,/DPAPI: PASS - 21 checks/);
  assert.doesNotMatch(output,/fake-BRIDGE-canary-key|fake-plus-DPAPI-key|fake-local-DPAPI-token/);
  assert.equal(fs.readdirSync(sandbox).length,0,'DPAPI fixture left temporary data behind');
 }finally{fs.rmSync(sandbox,{recursive:true,force:true});}
});
