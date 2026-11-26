import test from 'node:test';
import assert from 'node:assert/strict';
import {prepareRecovery} from '../scripts/cloudflare-recovery.mjs';
const source=rows=>JSON.stringify({captured_at_utc:'2026-10-08T22:49:04.566Z',project:'test-only',rows});
test('Cloudflare recovery preserves exact payload and refuses incomplete snapshots',()=>{
 const raw=source([{table_name:'payments',row_count:1,rows:[{id:'pay-1',amount:'100.01',note:"D'água",status:'paid'}]}]);
 const result=prepareRecovery(raw);assert.match(result.sql,/100\.01/);assert.match(result.sql,/D''água/);assert.equal(result.inventory[0].archived,1);assert.equal(result.hash,prepareRecovery(raw).hash);
 assert.throws(()=>prepareRecovery(source([{table_name:'payments',row_count:2,rows:[{id:'pay-1'}]}])),/incomplete_recovery_table/);
});
test('Cloudflare recovery explicitly excludes credentials and rejects unexpected secret columns',()=>{
 const result=prepareRecovery(source([{table_name:'google_oauth_connections',row_count:1,rows:null},{table_name:'profile_private_identity',row_count:1,rows:[{private_key:'do-not-copy'}]}]));
 assert.equal(result.inventory.filter(x=>x.excluded).length,2);assert.doesNotMatch(result.sql,/do-not-copy/);
 assert.throws(()=>prepareRecovery(source([{table_name:'profiles',row_count:1,rows:[{id:'x',access_token:'do-not-copy'}]}])),/secret_field/);
});
test('Cloudflare recovery refuses duplicate rows and SQL identifiers from untrusted backup metadata',()=>{
 assert.throws(()=>prepareRecovery(source([{table_name:'payments',row_count:2,rows:[{id:'x'},{id:'x'}]}])),/duplicate_recovery_row/);
 assert.throws(()=>prepareRecovery(source([{table_name:"payments; DROP TABLE profiles",row_count:0,rows:[]}])),/invalid_recovery_table/);
});
test('Cloudflare archive schema stores the original evidence and prevents rewriting it',async()=>{
 const {DatabaseSync}=await import('node:sqlite');
 const {readFileSync}=await import('node:fs');
 const db=new DatabaseSync(':memory:');
 try{
  db.exec(readFileSync(new URL('../cloudflare/migrations/0001_recovery_archive.sql',import.meta.url),'utf8'));
  const {sql}=prepareRecovery(source([{table_name:'payments',row_count:1,rows:[{id:'pay-1',amount:'100.01',status:'paid'}]}]));
  db.exec(sql);
  const row=db.prepare('select payload from migration_recovery_rows').get();assert.deepEqual(JSON.parse(row.payload),{id:'pay-1',amount:'100.01',status:'paid'});
  assert.equal(db.prepare('select state from migration_sources').get().state,'unreconciled');
  assert.throws(()=>db.exec("update migration_recovery_rows set payload='{}'"),/immutable_recovery_archive/);
  assert.throws(()=>db.exec('delete from migration_recovery_rows'),/immutable_recovery_archive/);
  assert.throws(()=>db.exec(sql),/UNIQUE constraint/);
 }finally{db.close()}
});
