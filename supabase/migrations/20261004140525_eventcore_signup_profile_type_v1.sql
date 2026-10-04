create or replace function private.handle_new_user()
    returns trigger
    language plpgsql
    security definer
    set search_path=''
    as $$
    declare
      initial_role text := 'freelancer';
      requested_profile_type text;
    begin
      if lower(coalesce(new.email,''))=lower('douglascesaroficial@gmail.com') then
        initial_role:='admin';
        update auth.users
          set raw_app_meta_data=coalesce(raw_app_meta_data,'{}'::jsonb)||jsonb_build_object('role','admin')
          where id=new.id;
      end if;

      requested_profile_type:=nullif(new.raw_user_meta_data->>'profile_type','');
      if requested_profile_type not in ('freelancer','team_lead','company','agency') then
        requested_profile_type:=null;
      end if;

      insert into public.profiles(id,full_name,phone,role,profile_type,onboarding_completed)
      values (
        new.id,
        coalesce(
          nullif(new.raw_user_meta_data->>'full_name',''),
          nullif(split_part(coalesce(new.email,''),'@',1),''),
          'Usuário'
        ),
        nullif(new.raw_user_meta_data->>'phone',''),
        initial_role,
        case when initial_role='admin' then null else requested_profile_type end,
        initial_role='admin'
      );

      return new;
    end;
    $$;
