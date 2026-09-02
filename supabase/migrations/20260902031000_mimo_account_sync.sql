-- Mimo account sync v1. Apply to a Supabase project with Auth enabled.

create sequence if not exists public.mimo_sync_change_seq;

create table if not exists public.mimo_profiles (
    user_id uuid primary key references auth.users(id) on delete cascade,
    display_name text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.mimo_devices (
    user_id uuid not null references auth.users(id) on delete cascade,
    device_id uuid not null,
    platform text not null check (platform in ('ios', 'macos', 'android')),
    display_name text,
    last_seen_at timestamptz not null default now(),
    primary key (user_id, device_id)
);

create table if not exists public.mimo_sync_records (
    user_id uuid not null references auth.users(id) on delete cascade,
    record_id text not null,
    kind text not null check (kind in ('dictation', 'meeting')),
    schema_version integer not null default 1 check (schema_version > 0),
    payload jsonb not null,
    client_updated_at timestamptz not null,
    device_id uuid not null,
    deleted_at timestamptz,
    change_seq bigint not null default nextval('public.mimo_sync_change_seq'),
    server_updated_at timestamptz not null default now(),
    primary key (user_id, record_id)
);

create index if not exists mimo_sync_records_pull_idx
    on public.mimo_sync_records (user_id, change_seq);

create or replace function public.mimo_touch_sync_record()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.change_seq := nextval('public.mimo_sync_change_seq');
    new.server_updated_at := clock_timestamp();
    return new;
end;
$$;

drop trigger if exists mimo_touch_sync_record on public.mimo_sync_records;
create trigger mimo_touch_sync_record
before insert or update on public.mimo_sync_records
for each row execute function public.mimo_touch_sync_record();

alter table public.mimo_profiles enable row level security;
alter table public.mimo_devices enable row level security;
alter table public.mimo_sync_records enable row level security;

drop policy if exists "mimo profile owner" on public.mimo_profiles;
create policy "mimo profile owner" on public.mimo_profiles
    for all to authenticated
    using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);

drop policy if exists "mimo device owner" on public.mimo_devices;
create policy "mimo device owner" on public.mimo_devices
    for all to authenticated
    using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);

drop policy if exists "mimo record owner" on public.mimo_sync_records;
create policy "mimo record owner" on public.mimo_sync_records
    for all to authenticated
    using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);

revoke all on table public.mimo_profiles from anon;
revoke all on table public.mimo_devices from anon;
revoke all on table public.mimo_sync_records from anon;
revoke all on sequence public.mimo_sync_change_seq from anon;

grant select, insert, update, delete on table public.mimo_profiles to authenticated;
grant select, insert, update, delete on table public.mimo_devices to authenticated;
grant select, insert, update, delete on table public.mimo_sync_records to authenticated;
grant usage, select on sequence public.mimo_sync_change_seq to authenticated;

create or replace function public.mimo_push_sync_records(records jsonb)
returns setof public.mimo_sync_records
language plpgsql
security invoker
set search_path = ''
as $$
declare
    item jsonb;
    requested_ids text[] := array[]::text[];
    current_user uuid := (select auth.uid());
begin
    if current_user is null then
        raise exception 'authentication required' using errcode = '28000';
    end if;
    if jsonb_typeof(records) <> 'array' or jsonb_array_length(records) > 200 then
        raise exception 'records must be an array of at most 200 items' using errcode = '22023';
    end if;

    for item in select value from jsonb_array_elements(records)
    loop
        requested_ids := array_append(requested_ids, item ->> 'record_id');
        insert into public.mimo_sync_records (
            user_id,
            record_id,
            kind,
            schema_version,
            payload,
            client_updated_at,
            device_id,
            deleted_at
        ) values (
            current_user,
            item ->> 'record_id',
            item ->> 'kind',
            coalesce((item ->> 'schema_version')::integer, 1),
            coalesce(item -> 'payload', '{}'::jsonb),
            (item ->> 'client_updated_at')::timestamptz,
            (item ->> 'device_id')::uuid,
            nullif(item ->> 'deleted_at', '')::timestamptz
        )
        on conflict (user_id, record_id) do update set
            kind = excluded.kind,
            schema_version = excluded.schema_version,
            payload = excluded.payload,
            client_updated_at = excluded.client_updated_at,
            device_id = excluded.device_id,
            deleted_at = excluded.deleted_at
        where (excluded.client_updated_at, excluded.device_id::text)
            > (mimo_sync_records.client_updated_at, mimo_sync_records.device_id::text);
    end loop;

    return query
    select r.*
    from public.mimo_sync_records as r
    where r.user_id = current_user
      and r.record_id = any(requested_ids)
    order by r.change_seq asc;
end;
$$;

create or replace function public.mimo_pull_sync_records(
    after_change_seq bigint default 0,
    max_count integer default 200
)
returns setof public.mimo_sync_records
language sql
stable
security invoker
set search_path = ''
as $$
    select r.*
    from public.mimo_sync_records as r
    where r.user_id = (select auth.uid())
      and r.change_seq > greatest(after_change_seq, 0)
    order by r.change_seq asc
    limit least(greatest(max_count, 1), 200);
$$;

revoke all on function public.mimo_push_sync_records(jsonb) from public, anon;
revoke all on function public.mimo_pull_sync_records(bigint, integer) from public, anon;
grant execute on function public.mimo_push_sync_records(jsonb) to authenticated;
grant execute on function public.mimo_pull_sync_records(bigint, integer) to authenticated;

create or replace function public.mimo_create_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    insert into public.mimo_profiles (user_id, display_name)
    values (new.id, nullif(new.raw_user_meta_data ->> 'display_name', ''))
    on conflict (user_id) do nothing;
    return new;
end;
$$;

drop trigger if exists mimo_auth_user_created on auth.users;
create trigger mimo_auth_user_created
after insert on auth.users
for each row execute function public.mimo_create_profile_for_new_user();
