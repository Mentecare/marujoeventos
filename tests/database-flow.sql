-- Real database integration test. Every fixture and change rolls back.
begin;
do $$ declare u uuid; k text; begin
  foreach k in array array['freelancer','team_lead','company','agency','other'] loop
    u:=gen_random_uuid(); perform set_config('test.ec_'||k,u::text,true);
    insert into auth.users(id,email,aud,role,raw_user_meta_data,raw_app_meta_data,email_confirmed_at)
    values(u,'eventcore-check-'||u::text||'@example.invalid','authenticated','authenticated',jsonb_build_object('full_name','EventCore validation '||k,'profile_type',case when k='other' then 'freelancer' else k end),'{}',now());
  end loop;
end $$;
set local role authenticated;
do $$ declare k text; doc text; typ text; spec uuid; result jsonb; begin
 select id into spec from public.specialties where slug='loader'; perform set_config('test.ec_specialty',spec::text,true);
 foreach k in array array['freelancer','team_lead','company','agency','other'] loop
   perform set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('test.ec_'||k),'role','authenticated')::text,true);
   doc:=case k when 'freelancer' then '52998224725' when 'team_lead' then '12345678909' when 'company' then '11222333000181' when 'agency' then '12ABC34501DE35' else '11144477735' end;
   typ:=case when k in ('company','agency') then 'cnpj' else 'cpf' end;
   result:=public.complete_profile(jsonb_build_object('profile_type',case when k='other' then 'freelancer' else k end,'full_name','EventCore validation '||k,'document_type',typ,'document_number',doc,'specialty_ids',jsonb_build_array(spec),'organization_name','Validation '||k,'business_type','Produção'));
   if (result->>'completed')::boolean is not true then raise exception 'profile_completion_failed_%',k; end if;
   if k='company' then perform set_config('test.ec_org',result->>'organization_id',true); end if;
   if k='agency' then perform set_config('test.ec_other_org',result->>'organization_id',true); end if;
 end loop;
end $$;

-- Organization isolation, public catalog, capacity and coherent hire/application/payment.
do $$ declare client uuid; ev uuid; service uuid; begin
 perform set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('test.ec_company'),'role','authenticated')::text,true);
 insert into public.clients(trade_name,organization_id) values('Validation client',current_setting('test.ec_org')::uuid) returning id into client;
 insert into public.events(client_id,name,venue,start_at,end_at,status,coordinator_id,created_by_profile_id,organization_id,notes)
 values(client,'Validation event','Validation venue',now()-interval '5 minutes',now()+interval '1 hour','confirmed',auth.uid(),auth.uid(),current_setting('test.ec_org')::uuid,'PRIVATE INTERNAL NOTE') returning id into ev;
 insert into public.event_services(event_id,service_type,label,specialty_id,quantity_needed,visibility,application_enabled,freelancer_unit_cost)
 values(ev,'loader','Carregador',current_setting('test.ec_specialty')::uuid,1,'open',true,150) returning id into service;
 update public.event_services set requirements='Closed shoes' where id=service;
 perform set_config('test.ec_event',ev::text,true);perform set_config('test.ec_service',service::text,true);perform set_config('test.ec_client',client::text,true);
 if (select count(*) from public.events where id=ev)<>1 then raise exception 'manager_event_read_failed'; end if;
end $$;
do $$ declare o record; app uuid; denied boolean; updated int; begin
 perform set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('test.ec_freelancer'),'role','authenticated')::text,true);
 if exists(select 1 from public.clients where id=current_setting('test.ec_client')::uuid) then raise exception 'freelancer_client_data_leaked'; end if;
 if exists(select 1 from public.events where id=current_setting('test.ec_event')::uuid) then raise exception 'raw_opportunity_event_leaked'; end if;
 select * into o from public.get_event_opportunities() where service_id=current_setting('test.ec_service')::uuid;
 if o.event_name<>'Validation event' or o.vacancies<>1 or o.amount<>150 or not o.compatible then raise exception 'sanitized_opportunity_read_failed'; end if;
 app:=public.apply_for_opportunity(current_setting('test.ec_service')::uuid,'Validation interest');perform set_config('test.ec_app',app::text,true);
 if public.apply_for_opportunity(current_setting('test.ec_service')::uuid,null)<>app then raise exception 'application_not_idempotent'; end if;
 denied:=false;begin update public.profiles set onboarding_completed=true,profile_type='company' where id=auth.uid(); exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'direct_onboarding_forgery_allowed'; end if;
 update public.freelancers set rating=5,completed_jobs=999 where profile_id=auth.uid();get diagnostics updated=row_count;
 if updated<>0 then raise exception 'reputation_forgery_allowed'; end if;
 denied:=false;begin insert into public.job_applications(event_service_id,freelancer_id,status) select current_setting('test.ec_service')::uuid,id,'accepted' from public.freelancers where profile_id=auth.uid();exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'accepted_application_forgery_allowed'; end if;
end $$;
do $$ declare a uuid; denied boolean; begin
 perform set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('test.ec_company'),'role','authenticated')::text,true);
 a:=public.hire_application(current_setting('test.ec_app')::uuid);perform set_config('test.ec_assignment',a::text,true);
 if public.hire_application(current_setting('test.ec_app')::uuid)<>a then raise exception 'hire_not_idempotent'; end if;
 if not exists(select 1 from public.job_applications where id=current_setting('test.ec_app')::uuid and status='accepted') or not exists(select 1 from public.payments where assignment_id=a and amount=150 and status='pending') then raise exception 'hire_not_atomic'; end if;
 denied:=false;begin perform public.submit_assignment_rating(a,5,'Too early');exception when raise_exception then if sqlerrm='completed_validated_event_required' then denied:=true;else raise;end if;end;
 if not denied then raise exception 'early_review_allowed'; end if;
end $$;
do $$ declare denied boolean; n int; begin
 perform set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('test.ec_other'),'role','authenticated')::text,true);
 denied:=false;begin perform public.apply_for_opportunity(current_setting('test.ec_service')::uuid,null);exception when raise_exception then if sqlerrm='vacancies_filled' then denied:=true;else raise;end if;end;
 if not denied then raise exception 'overbooking_allowed'; end if;
 if exists(select 1 from public.assignments where id=current_setting('test.ec_assignment')::uuid) then raise exception 'other_freelancer_assignment_leaked'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('test.ec_agency'),'role','authenticated')::text,true);
 if exists(select 1 from public.clients where id=current_setting('test.ec_client')::uuid) or exists(select 1 from public.events where id=current_setting('test.ec_event')::uuid) then raise exception 'cross_organization_read_allowed'; end if;
 denied:=false;begin insert into public.events(client_id,name,venue,start_at,end_at,status,coordinator_id,created_by_profile_id,organization_id) values(current_setting('test.ec_client')::uuid,'Foreign client','Validation venue',now(),now()+interval '1 hour','planning',auth.uid(),auth.uid(),current_setting('test.ec_other_org')::uuid);exception when insufficient_privilege or raise_exception then denied:=true;end;
 if not denied then raise exception 'foreign_client_link_allowed'; end if;
 denied:=false;begin perform public.hire_application(current_setting('test.ec_app')::uuid);exception when raise_exception then if sqlerrm='forbidden' then denied:=true;else raise;end if;end;
 if not denied then raise exception 'foreign_hiring_allowed'; end if;
end $$;

-- Professional attendance, contractor validation/completion, one actual review, payment.
do $$ declare denied boolean; a uuid:=current_setting('test.ec_assignment')::uuid; begin
 perform set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('test.ec_freelancer'),'role','authenticated')::text,true);
 update public.assignments set status='confirmed' where id=a;
 denied:=false;begin update public.assignments set status='checked_in' where id=a;exception when raise_exception then if sqlerrm='attendance_required' then denied:=true;else raise;end if;end;
 if not denied then raise exception 'unrecorded_presence_allowed'; end if;
 perform public.record_assignment_attendance(a,'in',-22.90,-43.20);
 perform public.record_assignment_attendance(a,'out',-22.90,-43.20);
 if not exists(select 1 from public.assignments where id=a and status='checked_out') then raise exception 'attendance_state_not_atomic'; end if;
end $$;
do $$ declare r uuid; denied boolean; a uuid:=current_setting('test.ec_assignment')::uuid; begin
 perform set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('test.ec_company'),'role','authenticated')::text,true);
 perform public.validate_assignment_attendance(a);
 update public.events set end_at=now()-interval '1 second',status='completed' where id=current_setting('test.ec_event')::uuid;
 r:=public.submit_assignment_rating(a,4,'Validation completed');
 denied:=false;begin perform public.submit_assignment_rating(a,5,'Duplicate');exception when raise_exception then if sqlerrm='assignment_already_rated' then denied:=true;else raise;end if;end;
 if not denied then raise exception 'duplicate_review_allowed'; end if;
 perform public.mark_assignment_paid(a,'pix');
 if not exists(select 1 from public.payments where assignment_id=a and status='paid' and amount=150) then raise exception 'payment_failed'; end if;
 if not exists(select 1 from public.get_professional_directory() where profile_id=current_setting('test.ec_freelancer')::uuid and rating=4 and review_count=1 and completed_jobs=1) then raise exception 'real_reputation_aggregation_failed'; end if;
end $$;
select 'PASS: five profiles; private identity; safe opportunities; atomic hiring/attendance; capacity; tenant isolation; duplicate review denial; actual reputation; payments; fixtures rolled back' as validation;
rollback;
