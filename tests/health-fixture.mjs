// Local test-only health service. No upstream requests or real credentials.
import http from 'node:http';
import fs from 'node:fs';
const args=process.argv.slice(2);
function option(name,fallback){const i=args.indexOf(name);return i<0?fallback:args[i+1];}
const port=Number(option('--port','18761'));
const readyFile=option('--ready-file',undefined);
if(!Number.isInteger(port)||port<0||port>65535)throw Error('Invalid fixture port');
const server=http.createServer((req,res)=>{
  if(req.url!=='/__router/health'||req.headers.authorization!=='Bearer fake-local-token'){
    res.writeHead(403);return res.end();
  }
  res.setHeader('content-type','application/json');
  res.end('{"ok":true,"version":"test"}');
});
server.on('error',error=>{console.error(`Health fixture bind failed: ${error.code}`);process.exit(1);});
server.listen(port,'127.0.0.1',()=>{
  if(readyFile)fs.writeFileSync(readyFile,JSON.stringify({port:server.address().port,pid:process.pid}));
});
