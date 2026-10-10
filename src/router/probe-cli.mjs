import {pathToFileURL} from 'node:url';
import {planProbe,validateProbePlan} from './route-policy.mjs';
import {runProbe} from './probe-engine.mjs';
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 let key=process.env.ROUTER_STUDIO_PROBE_KEY;delete process.env.ROUTER_STUDIO_PROBE_KEY;
 try{
  const args=process.argv.slice(2);if(args.length && (args.length!==1||!['--plan','--preview'].includes(args[0])))throw Error();
  let bytes=0;const chunks=[];for await(const chunk of process.stdin){bytes+=chunk.length;if(bytes>1024*1024)throw Error();chunks.push(chunk);}
  const input=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(Buffer.concat(chunks)));
  const data=args.length?planProbe(input.config??{},input.catalog??{},input.request,input.snapshotDigest,{preview:args[0]==='--preview'}):await runProbe(validateProbePlan(input),key);
  process.stdout.write(JSON.stringify({schemaVersion:1,ok:true,data}));
 }catch(error){
  const code=['invalid_request','unsupported_capability','acknowledgement_required','config_changed'].includes(error.code)?error.code:'invalid_request';
  process.stdout.write(JSON.stringify({schemaVersion:1,ok:false,error:{code,message:'The provider check could not run. Review the target and refresh local status.'}}));process.exitCode=1;
 }finally{key=null;}
}
