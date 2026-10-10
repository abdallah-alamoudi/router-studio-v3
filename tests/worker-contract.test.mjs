import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {runProcess} from './helpers/run-process.mjs';

const pwsh=process.platform==='win32'?'pwsh.exe':'pwsh';
const check=spawnSync(pwsh,['-NoProfile','-Command','$PSVersionTable.PSVersion.Major'],{encoding:'utf8'});
const skip=process.platform!=='win32'||check.status!==0||Number(check.stdout.trim())<7;

test('versioned management contract and legacy callers pass isolated checks',{skip},async()=>{
  const sandbox=fs.mkdtempSync(path.join(os.tmpdir(),'studio contract sandbox Ω '));
  try{
    const env={...process.env,TEMP:sandbox,TMP:sandbox};
    delete env.NODE_TEST_CONTEXT;
    const script=fileURLToPath(new URL('./worker-contract.ps1',import.meta.url));
    const result=await runProcess(pwsh,['-NoProfile','-ExecutionPolicy','Bypass','-File',script,'-Node',process.execPath],{env,timeoutMs:90000});
    const output=result.stdout+'\n'+result.stderr;
    assert.equal(result.status,0,output);
    assert.equal(result.timedOut,false,output);
    const completed=/CONTRACT: (\d+) checks; 0 failures\./.exec(output);
    assert.ok(completed&&Number(completed[1])>=26,output);
    assert.doesNotMatch(output,/contract-private-canary|fake-local-token/);
    assert.equal(fs.readdirSync(sandbox).length,0,'Contract fixture left temporary credential data behind');
  }finally{fs.rmSync(sandbox,{recursive:true,force:true});}
});
