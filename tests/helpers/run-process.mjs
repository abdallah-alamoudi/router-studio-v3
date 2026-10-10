import {spawn,spawnSync} from 'node:child_process';

// Test-only runner: timeout kills its own process tree, then waits for process exit.
export function runProcess(command,args,{env=process.env,timeoutMs=20000}={}){
  return new Promise((resolve,reject)=>{
    const child=spawn(command,args,{env,windowsHide:true,detached:process.platform!=='win32'});
    let stdout='',stderr='',timedOut=false;
    child.stdout.on('data',x=>stdout+=x);child.stderr.on('data',x=>stderr+=x);
    const timer=setTimeout(()=>{
      timedOut=true;
      if(child.exitCode!==null||child.signalCode!==null)return;
      if(process.platform==='win32'){
        const killed=spawnSync('taskkill.exe',['/PID',String(child.pid),'/T','/F'],{windowsHide:true,stdio:'ignore'});
        if(killed.status!==0&&child.exitCode===null){child.kill();child.stdout.destroy();child.stderr.destroy();reject(Error('Could not terminate the owned test process tree; Windows process-tree permissions are required'));return;}
      }else{
        try{process.kill(-child.pid,'SIGKILL');}catch(error){if(error.code!=='ESRCH')reject(error);}
      }
    },timeoutMs);
    child.on('error',e=>{clearTimeout(timer);reject(e);});
    child.on('close',status=>{clearTimeout(timer);resolve({status,stdout,stderr,timedOut});});
  });
}
