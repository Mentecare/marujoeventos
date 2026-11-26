import {createHash} from 'node:crypto';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {pathToFileURL} from 'node:url';

// A private staging archive, never an operational restore or a claim of RPC parity.
const excludedTables=new Set(['google_oauth_connections','profile_private_identity','integrations']);
const quote=value=>"'"+String(value).replaceAll("'","''")+"'";
export function prepareRecovery(raw){
 const source=JSON.parse(raw);
 if(!source||!Array.isArray(source.rows)||typeof source.captured_at_utc!=='string'||!Number.isFinite(Date.parse(source.captured_at_utc)))throw new Error('invalid_recovery_snapshot');
 const hash=createHash('sha256').update(raw).digest('hex');
 const project=typeof source.project==='string'?source.project:JSON.stringify(source.project??null);
 const statements=[`INSERT INTO migration_sources(source_sha256,captured_at,source_project) VALUES(${quote(hash)},${quote(source.captured_at_utc)},${quote(project)});`];
 const inventory=[],seenTables=new Set();
 for(const table of source.rows){
  if(!/^[a-z][a-z0-9_]*$/.test(table.table_name)||seenTables.has(table.table_name)||!Number.isSafeInteger(table.row_count)||table.row_count<0)throw new Error('invalid_recovery_table');
  seenTables.add(table.table_name);
  const excluded=excludedTables.has(table.table_name);
  if(!excluded&&(!Array.isArray(table.rows)||table.row_count!==table.rows.length))throw new Error('incomplete_recovery_table: '+table.table_name);
  const rows=excluded?[]:table.rows;
  const keys=new Set();
  for(let index=0;index<rows.length;index++){
   const row=rows[index];if(!row||typeof row!=='object'||Array.isArray(row))throw new Error('invalid_recovery_row');
   if(Object.keys(row).some(k=>/password|secret|token|ciphertext|private_key/i.test(k)))throw new Error('secret_field_in_recovery: '+table.table_name);
   const key=row.id==null?`row:${index}`:String(row.id);
   if(keys.has(key))throw new Error('duplicate_recovery_row: '+table.table_name);keys.add(key);
   statements.push(`INSERT INTO migration_recovery_rows(source_sha256,table_name,record_key,payload) VALUES(${quote(hash)},${quote(table.table_name)},${quote(key)},${quote(JSON.stringify(row))});`);
  }
  statements.push(`INSERT INTO migration_table_inventory(source_sha256,table_name,expected_count,archived_count,excluded) VALUES(${quote(hash)},${quote(table.table_name)},${table.row_count},${rows.length},${excluded?1:0});`);
  inventory.push({table:table.table_name,expected:table.row_count,archived:rows.length,excluded});
 }
 return {hash,capturedAt:source.captured_at_utc,inventory,sql:statements.join('\n')+'\n'};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
 const [input,output]=process.argv.slice(2);if(!input||!output)throw new Error('Usage: node scripts/cloudflare-recovery.mjs snapshot.json cloudflare/private/archive.sql');
 const target=resolve(output),allowed=resolve('cloudflare/private')+'/';
 if(!target.startsWith(allowed))throw new Error('Recovery output must stay in git-ignored cloudflare/private/');
 const result=prepareRecovery(readFileSync(input,'utf8'));
 mkdirSync(dirname(target),{recursive:true,mode:0o700});
 writeFileSync(target,result.sql,{mode:0o600,flag:'wx'});
 writeFileSync(target+'.inventory.json',JSON.stringify({hash:result.hash,capturedAt:result.capturedAt,inventory:result.inventory},null,2)+'\n',{mode:0o600,flag:'wx'});
 console.log(JSON.stringify({sha256:result.hash,capturedAt:result.capturedAt,tables:result.inventory.length,archivedRows:result.inventory.reduce((s,x)=>s+x.archived,0),excludedTables:result.inventory.filter(x=>x.excluded).map(x=>x.table),state:'unreconciled'}));
}
