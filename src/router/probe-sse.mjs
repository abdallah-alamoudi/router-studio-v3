// Incremental UTF-8 SSE framing. Caller owns byte/time bounds and event semantics.
export class ProbeSse {
 constructor(onEvent){this.onEvent=onEvent;this.decoder=new TextDecoder('utf-8',{fatal:true});this.pending='';this.data=[];this.sawCR=false;}
 push(bytes){this.consume(this.decoder.decode(bytes,{stream:true}));}
 consume(text){for(const character of text){if(this.sawCR){this.sawCR=false;if(character==='\n')continue;}if(character==='\r'||character==='\n'){this.line(this.pending);this.pending='';this.sawCR=character==='\r';}else this.pending+=character;}}
 line(line){if(!line){if(this.data.length){const value=this.data.join('\n');this.data=[];if(value!=='[DONE]')this.onEvent(JSON.parse(value));}return;}if(line.startsWith('data:'))this.data.push(line.slice(5).replace(/^ /,''));}
 end(){this.consume(this.decoder.decode());if(this.pending||this.data.length)throw Error('Unterminated SSE frame');}
}
