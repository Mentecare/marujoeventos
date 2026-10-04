alter table public.clients
      add column if not exists organization_id uuid references public.organizations(id) on delete set null;

    alter table public.events
      add column if not exists created_by_profile_id uuid references public.profiles(id) on delete set null,
      add column if not exists organization_id uuid references public.organizations(id) on delete set null;

    update public.events
    set created_by_profile_id=coordinator_id
    where created_by_profile_id is null and coordinator_id is not null;

    alter table public.event_services
      add column if not exists specialty_id uuid references public.specialties(id) on delete set null,
      add column if not exists visibility text not null default 'private',
      add column if not exists application_enabled boolean not null default false,
      add column if not exists requirements text;

    do $$ begin
      if not exists (select 1 from pg_constraint where conname='event_services_visibility_check') then
        alter table public.event_services
          add constraint event_services_visibility_check check (visibility in ('private','open'));
      end if;
    end $$;

    update public.event_services es
    set specialty_id=s.id
    from public.specialties s
    where es.specialty_id is null and (
      (es.service_type='loader' and s.slug='loader') or
      (es.service_type='security' and s.slug='security') or
      (es.service_type='waiter' and s.slug='waiter') or
      (es.service_type='other' and s.slug='other')
    );

    create table if not exists public.job_applications (
      id uuid primary key default gen_random_uuid(),
      event_service_id uuid not null references public.event_services(id) on delete cascade,
      freelancer_id uuid not null references public.freelancers(id) on delete cascade,
      status text not null default 'interested'
        check (status in ('interested','shortlisted','accepted','rejected','withdrawn')),
      message text,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),
      unique(event_service_id,freelancer_id)
    );

    alter table public.assignments
      add column if not exists contractor_profile_id uuid references public.profiles(id) on delete set null,
      add column if not exists application_id uuid unique references public.job_applications(id) on delete set null,
      add column if not exists hired_at timestamptz;

    create table if not exists public.ratings (
      id uuid primary key default gen_random_uuid(),
      assignment_id uuid not null unique references public.assignments(id) on delete cascade,
      event_id uuid not null references public.events(id) on delete cascade,
      freelancer_id uuid not null references public.freelancers(id) on delete cascade,
      reviewer_profile_id uuid not null references public.profiles(id) on delete restrict,
      rating smallint not null check (rating between 1 and 5),
      comment text,
      created_at timestamptz not null default now()
    );

    create index if not exists idx_profile_specialties_specialty on public.profile_specialties(specialty_id);
    create index if not exists idx_org_members_profile on public.organization_members(profile_id);
    create index if not exists idx_org_specialties_specialty on public.organization_specialties(specialty_id);
    create index if not exists idx_clients_org on public.clients(organization_id);
    create index if not exists idx_events_created_by on public.events(created_by_profile_id);
    create index if not exists idx_events_org on public.events(organization_id);
    create index if not exists idx_event_services_specialty on public.event_services(specialty_id);
    create index if not exists idx_applications_freelancer on public.job_applications(freelancer_id);
    create index if not exists idx_applications_service_status on public.job_applications(event_service_id,status);
    create index if not exists idx_assignments_contractor on public.assignments(contractor_profile_id);
    create index if not exists idx_ratings_freelancer on public.ratings(freelancer_id);
    create index if not exists idx_ratings_reviewer on public.ratings(reviewer_profile_id);
    create index if not exists idx_ratings_event on public.ratings(event_id);
