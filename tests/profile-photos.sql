-- All users and Storage metadata below are rollback-only fixtures. No files are uploaded.
begin;
do $$ declare u uuid; kind text; fid uuid; photo uuid; begin
  foreach kind in array array['owner','other','business','inactive'] loop
    u:=gen_random_uuid();
    insert into auth.users(id,email,aud,role,raw_user_meta_data,raw_app_meta_data,email_confirmed_at)
      values(u,'photo-test-'||u||'@example.invalid','authenticated','authenticated','{}','{}',now());
    update public.profiles set active=kind<>'inactive',role='freelancer',profile_type=case when kind='business' then 'company' else 'freelancer' end,onboarding_completed=true where id=u;
    perform set_config('test.photo_'||kind,u::text,true);
    if kind='owner' then
      insert into public.freelancers(profile_id,full_name,active) values(u,'Photo validation',true) returning id into fid;
      perform set_config('test.photo_freelancer',fid::text,true);
    end if;
  end loop;
  for i in 0..13 loop
    photo:=gen_random_uuid();
    perform set_config('test.photo_id_'||i,photo::text,true);
    insert into storage.objects(bucket_id,name,owner_id,metadata) values('eventcore-profile-photos',current_setting('test.photo_owner')||'/'||photo||'.webp',current_setting('test.photo_owner'),'{"size":1024,"mimetype":"image/webp"}');
    insert into public.profile_photo_cleanup(object_path,profile_id,not_before) values(current_setting('test.photo_owner')||'/'||photo||'.webp',current_setting('test.photo_owner')::uuid,now()+interval '15 minutes');
  end loop;
end $$;
set local role authenticated;
do $$ declare denied boolean; p uuid; result jsonb; rows jsonb; old_path text; begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('test.photo_owner'),'role','authenticated')::text,true);
  p:=current_setting('test.photo_id_0')::uuid;
  denied:=false;
  begin perform public.save_profile_photo(p,'portfolio',null,false);
  exception when raise_exception then if sqlerrm='real_photo_declaration_required' then denied:=true;else raise;end if;end;
  if not denied then raise exception 'declaration_not_required';end if;
  denied:=false;
  begin perform public.save_profile_photo(gen_random_uuid(),'portfolio',null,true);
  exception when raise_exception then if sqlerrm='invalid_photo_object' then denied:=true;else raise;end if;end;
  if not denied then raise exception 'missing_storage_object_accepted';end if;
  denied:=false;
  begin insert into public.profile_photos(id,profile_id,kind,slot,object_path,byte_size,real_declared) values(p,current_setting('test.photo_owner')::uuid,'portfolio',1,'bypass',1024,true);
  exception when insufficient_privilege then denied:=true;end;
  if not denied then raise exception 'direct_photo_insert_allowed';end if;
  denied:=false;
  begin insert into storage.objects(bucket_id,name) values('eventcore-profile-photos','bypass.webp');
  exception when insufficient_privilege then denied:=true;end;
  if not denied then raise exception 'direct_storage_upload_allowed';end if;
  for i in 1..10 loop
    perform public.save_profile_photo(current_setting('test.photo_id_'||i)::uuid,'portfolio','Real work declaration',true);
  end loop;
  rows:=public.get_profile_photo_collection();
  if jsonb_array_length(rows)<>10 then raise exception 'gallery_count_wrong';end if;
  denied:=false;
  begin perform public.save_profile_photo(p,'portfolio',null,true);
  exception when raise_exception then if sqlerrm='portfolio_full' then denied:=true;else raise;end if;end;
  if not denied then raise exception 'eleventh_photo_allowed';end if;
  perform public.save_profile_photo(p,'avatar',null,true);
  old_path:=current_setting('test.photo_owner')||'/'||p||'.webp';
  result:=public.save_profile_photo(current_setting('test.photo_id_11')::uuid,'avatar',null,true);
  if result->>'previous_object_path'<>old_path then raise exception 'avatar_cleanup_path_wrong';end if;
  if (select count(*) from public.profile_photos where kind='avatar')<>1 then raise exception 'multiple_avatars';end if;
  perform public.delete_profile_photo(current_setting('test.photo_id_1')::uuid);
  perform public.delete_profile_photo(current_setting('test.photo_id_1')::uuid);
  denied:=false;
  begin perform public.save_profile_photo(current_setting('test.photo_id_1')::uuid,'portfolio',null,true);
  exception when raise_exception then if sqlerrm='invalid_photo_object' then denied:=true;else raise;end if;end;
  if not denied then raise exception 'queued_object_resurrected_during_cleanup';end if;
  perform public.save_profile_photo(current_setting('test.photo_id_12')::uuid,'portfolio',null,true);
  if (select count(*) from public.profile_photos where kind='portfolio')<>10 then raise exception 'freed_slot_not_reusable';end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('test.photo_other'),'role','authenticated')::text,true);
  if (select count(*) from public.profile_photos)<>0 then raise exception 'other_professional_reads_gallery';end if;
  denied:=false;
  begin perform public.get_profile_photo_collection(current_setting('test.photo_freelancer')::uuid);
  exception when raise_exception then if sqlerrm='forbidden' then denied:=true;else raise;end if;end;
  if not denied then raise exception 'unauthorized_directory_read';end if;
  denied:=false;
  begin perform public.delete_profile_photo(current_setting('test.photo_id_2')::uuid);
  exception when raise_exception then if sqlerrm='forbidden' then denied:=true;else raise;end if;end;
  if not denied then raise exception 'other_user_deleted_photo';end if;
  denied:=false;
  begin perform public.save_profile_photo(current_setting('test.photo_id_13')::uuid,'portfolio',null,true);
  exception when raise_exception then if sqlerrm='invalid_photo_object' then denied:=true;else raise;end if;end;
  if not denied then raise exception 'another_owners_staged_object_used';end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('test.photo_business'),'role','authenticated')::text,true);
  rows:=public.get_profile_photo_collection(current_setting('test.photo_freelancer')::uuid);
  if jsonb_array_length(rows)<>11 then raise exception 'contractor_cannot_see_profile';end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('test.photo_inactive'),'role','authenticated')::text,true);
  denied:=false;
  begin perform public.get_profile_photo_collection();
  exception when raise_exception then if sqlerrm='forbidden' then denied:=true;else raise;end if;end;
  if not denied then raise exception 'inactive_profile_access';end if;
end $$;
reset role;
do $$ begin
  if has_function_privilege('anon','public.get_profile_photo_collection(uuid)','execute') then raise exception 'anonymous_gallery_rpc';end if;
  if exists(select 1 from storage.buckets where id='eventcore-profile-photos' and (public or file_size_limit<>3000000 or allowed_mime_types<>array['image/webp'])) then raise exception 'bucket_configuration_wrong';end if;
  if has_table_privilege('authenticated','public.profile_photo_cleanup','select') or has_table_privilege('authenticated','public.profile_photo_cleanup','insert') then raise exception 'cleanup_queue_exposed';end if;
  if not exists(select 1 from public.profile_photo_cleanup where object_path=current_setting('test.photo_owner')||'/'||current_setting('test.photo_id_0')||'.webp' and not_before<=now()) then raise exception 'avatar_cleanup_not_durable';end if;
  if not exists(select 1 from public.profile_photo_cleanup where object_path=current_setting('test.photo_owner')||'/'||current_setting('test.photo_id_1')||'.webp' and not_before<=now()) then raise exception 'direct_rpc_delete_not_queued';end if;
  if exists(select 1 from public.profile_photo_cleanup q join public.profile_photos p on p.object_path=q.object_path) then raise exception 'committed_photo_still_staged';end if;
end $$;
select 'PASS: declaration, 10-photo quota, owner/contractor/anon authorization, private storage, durable avatar/direct-RPC cleanup, staging completion and rejection of queued path resurrection; fixtures rolled back' as validation;
rollback;
