alter table public.profiles
      add column if not exists profile_type text,
      add column if not exists onboarding_completed boolean not null default false,
      add column if not exists professional_status text not null default 'available',
      add column if not exists bio text;

    do $$ begin
      if not exists (select 1 from pg_constraint where conname='profiles_profile_type_check') then
        alter table public.profiles add constraint profiles_profile_type_check
          check (profile_type is null or profile_type in ('freelancer','team_lead','company','agency'));
      end if;
      if not exists (select 1 from pg_constraint where conname='profiles_professional_status_check') then
        alter table public.profiles add constraint profiles_professional_status_check
          check (professional_status in ('available','busy','unavailable'));
      end if;
    end $$;

    update public.profiles
    set onboarding_completed=true
    where role in ('admin','coordinator') and onboarding_completed=false;

    grant select (profile_type,onboarding_completed,professional_status,bio) on public.profiles to authenticated;
    grant update (profile_type,onboarding_completed,professional_status,bio) on public.profiles to authenticated;

    create table if not exists public.specialties (
      id uuid primary key default gen_random_uuid(),
      slug text not null unique,
      name text not null,
      category text not null default 'operational',
      active boolean not null default true,
      sort_order integer not null default 100,
      created_at timestamptz not null default now()
    );

    insert into public.specialties(slug,name,sort_order) values
     ('loader','Carregador',10),
     ('electrician','Eletricista',20),
     ('carpenter','Marceneiro',30),
     ('producer','Produtor',40),
     ('upholsterer','Tapeceiro',50),
     ('assembler','Montador',60),
     ('driver','Motorista',70),
     ('cleaning','Limpeza',80),
     ('security','Segurança',90),
     ('waiter','Garçom',100),
     ('other','Outro',999)
    on conflict (slug) do update set name=excluded.name, active=true;

    create table if not exists public.profile_specialties (
      profile_id uuid not null references public.profiles(id) on delete cascade,
      specialty_id uuid not null references public.specialties(id) on delete cascade,
      created_at timestamptz not null default now(),
      primary key(profile_id,specialty_id)
    );

    create table if not exists public.profile_private_identity (
      profile_id uuid primary key references public.profiles(id) on delete cascade,
      document_type text not null check (document_type in ('cpf','cnpj')),
      document_number text not null,
      document_last4 text generated always as (right(document_number,4)) stored,
      updated_at timestamptz not null default now(),
      constraint profile_private_identity_document_format check (
        (document_type='cpf' and document_number ~ '^[0-9]{11}$')
        or (document_type='cnpj' and document_number ~ '^[0-9]{14}$')
      ),
      constraint profile_private_identity_document_unique unique(document_type,document_number)
    );

    create table if not exists public.organizations (
      id uuid primary key default gen_random_uuid(),
      owner_profile_id uuid not null references public.profiles(id) on delete restrict,
      organization_type text not null check (organization_type in ('team','company','agency')),
      legal_name text,
      trade_name text,
      display_name text not null,
      business_type text,
      active boolean not null default true,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now()
    );

    create table if not exists public.organization_members (
      organization_id uuid not null references public.organizations(id) on delete cascade,
      profile_id uuid not null references public.profiles(id) on delete cascade,
      member_role text not null default 'member' check (member_role in ('owner','manager','member')),
      active boolean not null default true,
      created_at timestamptz not null default now(),
      primary key(organization_id,profile_id)
    );

    create table if not exists public.organization_specialties (
      organization_id uuid not null references public.organizations(id) on delete cascade,
      specialty_id uuid not null references public.specialties(id) on delete cascade,
      created_at timestamptz not null default now(),
      primary key(organization_id,specialty_id)
    );
