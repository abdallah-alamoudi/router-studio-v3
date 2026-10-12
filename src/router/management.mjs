// Public metadata transformation only. The PowerShell worker owns secrets and commit/recovery.
import {createHash} from 'node:crypto';
import fs from 'node:fs';
import {pathToFileURL} from 'node:url';
import {addCredential,findCredential,removeCredential,setCredentialCatalog,invalidateCredentialCatalog,addCustomModel,updateCustomModel,removeCustomModel,buildCodexCatalog,validateRegistry,migrateCredentials} from './custom-models.mjs';
export function applyManagement(input,catalog,request,fetchedCatalog,savedEnvironments=[]){
 let config=migrateCredentials(input,savedEnvironments);config.credentials??=[];config.customModels??=[];
 const previousCustomModels=structuredClone(config.customModels);
 let credential=findCredential(config,request.credentialId),keyEnv=credential?.keyEnv;
 if(request.action==='save-credential'){
  if(credential)throw Error('Credential already exists.');
  // Identity, never a mutable display label, determines the protected storage slot.
  keyEnv='SAFE_8STOKEN_EXTRA_C'+createHash('sha256').update(request.credentialId).digest('hex').slice(0,32).toUpperCase();
  config=addCredential(config,{id:request.credentialId,label:request.label,keyEnv});
 }else if(request.action==='delete-custom-model')config=removeCustomModel(config,request.customModelId);
 else {
  if(!credential)throw Error('Credential does not exist.');
  switch(request.action){
   case 'rename-credential':config=addCredential(config,{id:credential.id,label:request.label,keyEnv});break;
   case 'rotate-credential':config=invalidateCredentialCatalog(config,credential.id);break;
   case 'delete-credential':config=removeCredential(config,credential.id);break;
   case 'fetch-credential-catalog':config=setCredentialCatalog(config,credential.id,fetchedCatalog,new Date().toISOString());break;
   case 'save-custom-model':{
    const definition={id:request.customModelId,credentialId:credential.id,originalModel:request.originalModel,displayLabel:request.displayLabel};
    const source={credentialId:credential.id,models:credential.catalog?.models??[]};
    config=config.customModels.some(m=>m.id===definition.id)?updateCustomModel(config,source,definition):addCustomModel(config,source,definition);break;
   }
   default:throw Error('Unsupported management action.');
  }
 }
 validateRegistry(config);
 return {config,catalog:buildCodexCatalog(catalog,config,{previousCustomModels}),keyEnv};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 try{
  const [configFile,catalogFile,requestFile,outputFile]=process.argv.slice(2);
  const input=JSON.parse(fs.readFileSync(requestFile,'utf8'));
  if(process.argv[6]==='--registry'){fs.writeFileSync(outputFile,JSON.stringify(migrateCredentials(JSON.parse(fs.readFileSync(configFile,'utf8')),input.savedEnvironments??[])));process.exit(0);}
  const result=applyManagement(JSON.parse(fs.readFileSync(configFile,'utf8')),JSON.parse(fs.readFileSync(catalogFile,'utf8')),input.request,input.catalog,input.savedEnvironments);
  fs.writeFileSync(outputFile,JSON.stringify(result));
 }catch{process.exitCode=1;}
}
