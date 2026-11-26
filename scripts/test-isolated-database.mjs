// Isolated PostgreSQL regression tests. Auth/Storage below are test stubs, not hosted Supabase.
import {PGlite} from '@electric-sql/pglite';
import {pgcrypto} from '@electric-sql/pglite/contrib/pgcrypto';
import {readFileSync,readdirSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../',import.meta.url));
const db=new PGlite({extensions:{pgcrypto}});
await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create schema storage;
create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}',email_confirmed_at timestamptz,created_at timestamptz default now());
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb $$;
create function auth.role() returns text language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claim.role',true),''),current_user) $$;
grant usage on schema public,auth,storage to anon,authenticated,service_role;
create table storage.buckets(id text primary key,name text,public boolean default false,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text,owner uuid,owner_id text,metadata jsonb,created_at timestamptz default now());
create function storage.foldername(text) returns text[] language sql immutable as $$ select string_to_array($1,'/') $$;
alter table storage.objects enable row level security;grant all on storage.objects to authenticated,service_role;
`);
for(const file of readdirSync(root+'/supabase/migrations').sort()){
 let sql=readFileSync(root+'/supabase/migrations/'+file,'utf8');

 try{await db.exec(sql);console.log('OK',file)}catch(e){console.error('FAIL',file,e.message,e.detail||'');await db.close();process.exit(1)}
}
console.log('MIGRATIONS PASS');
for(const file of ['tests/operations-payroll.sql','tests/workflows-security.sql','tests/interface-finance-security.sql','tests/commercial-security.sql']){
 try{await db.exec(readFileSync(root+'/'+file,'utf8'));console.log('TEST PASS',file)}catch(e){console.error('TEST FAIL',file,e.message);await db.exec('rollback').catch(()=>{});process.exitCode=1;}
}

await db.close();
