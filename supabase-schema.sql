-- =============================================================================
-- DS Builder v2 — Supabase Database Schema & Row Level Security (RLS)
-- Run this script once in your Supabase Dashboard -> SQL Editor -> New query
-- =============================================================================

-- 1. Patient Discharge Summaries table (incomplete drafts & completed summaries)
create table if not exists public.discharge_summaries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  status text not null default 'incomplete' check (status in ('incomplete', 'completed')),
  patient_name text not null default '',
  ip_no text not null default '',
  doa text not null default '',
  dod text not null default '',
  unit text not null default '',
  diagnosis_preview text not null default '',
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 2. Per-user institution defaults, saved templates, theme preferences & frequent contacts
create table if not exists public.user_settings (
  user_id uuid primary key references auth.users(id) on delete cascade default auth.uid(),
  defaults jsonb not null default '{}'::jsonb,
  theme_color text not null default '#14425f',
  updated_at timestamptz not null default now()
);

-- 3. Directory of Google-authenticated doctors/users (used for instant recipient checks)
create table if not exists public.user_directory (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  full_name text not null default '',
  avatar_url text not null default '',
  provider text not null default 'google',
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

-- 4. Patient summary shares between Google-authenticated users
create table if not exists public.patient_shares (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  sender_email text not null,
  sender_name text not null default '',
  recipient_id uuid not null references auth.users(id) on delete cascade,
  recipient_email text not null,
  recipient_name text not null default '',
  source_summary_id uuid,
  recipient_summary_id uuid,
  status text not null default 'incomplete' check (status in ('incomplete', 'completed')),
  patient_name text not null default '',
  ip_no text not null default '',
  doa text not null default '',
  dod text not null default '',
  unit text not null default '',
  diagnosis_preview text not null default '',
  payload jsonb not null default '{}'::jsonb,
  note text not null default '',
  created_at timestamptz not null default now()
);

alter table public.patient_shares
  add column if not exists recipient_summary_id uuid;

-- 5. Performance indexes for dashboard & sharing queries
create index if not exists idx_discharge_summaries_user_updated
  on public.discharge_summaries (user_id, updated_at desc);

create index if not exists idx_discharge_summaries_user_status
  on public.discharge_summaries (user_id, status);

create index if not exists idx_user_directory_email
  on public.user_directory (email);

create index if not exists idx_patient_shares_recipient_created
  on public.patient_shares (recipient_id, created_at desc);

create index if not exists idx_patient_shares_sender_created
  on public.patient_shares (sender_id, created_at desc);

-- 6. Keep updated_at current automatically if omitted or unchanged
create or replace function public.ds_touch_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.updated_at is null then
    new.updated_at = now();
  elsif tg_op = 'UPDATE' and new.updated_at = old.updated_at then
    new.updated_at = now();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_discharge_summaries_updated_at on public.discharge_summaries;
create trigger trg_discharge_summaries_updated_at
  before insert or update on public.discharge_summaries
  for each row execute function public.ds_touch_updated_at();

drop trigger if exists trg_user_settings_updated_at on public.user_settings;
create trigger trg_user_settings_updated_at
  before insert or update on public.user_settings
  for each row execute function public.ds_touch_updated_at();

-- 7. Sync Google-authenticated users into public.user_directory
create or replace function public.ds_sync_google_user_directory()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_email text;
  v_is_google boolean;
  v_name text;
  v_avatar text;
begin
  v_email := lower(trim(coalesce(new.email, '')));
  if v_email = '' then
    return new;
  end if;

  v_is_google := (
    coalesce(new.raw_app_meta_data->>'provider', '') = 'google'
    or coalesce(new.raw_app_meta_data->'providers', '[]'::jsonb) ? 'google'
    or exists (
      select 1 from auth.identities i
      where i.user_id = new.id and i.provider = 'google'
    )
  );

  if not v_is_google then
    return new;
  end if;

  v_name := trim(coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', ''));
  v_avatar := trim(coalesce(new.raw_user_meta_data->>'avatar_url', new.raw_user_meta_data->>'picture', ''));

  delete from public.user_directory
  where email = v_email and user_id <> new.id;

  insert into public.user_directory (user_id, email, full_name, avatar_url, provider, last_seen_at)
  values (new.id, v_email, v_name, v_avatar, 'google', now())
  on conflict (user_id) do update
  set email = excluded.email,
      full_name = case when excluded.full_name <> '' then excluded.full_name else public.user_directory.full_name end,
      avatar_url = case when excluded.avatar_url <> '' then excluded.avatar_url else public.user_directory.avatar_url end,
      provider = 'google',
      last_seen_at = now();

  return new;
end;
$$;

do $$
begin
  drop trigger if exists trg_auth_users_google_directory on auth.users;
  create trigger trg_auth_users_google_directory
    after insert or update on auth.users
    for each row execute function public.ds_sync_google_user_directory();
exception
  when insufficient_privilege then
    raise notice 'Skipped auth.users trigger (insufficient privilege); verify_google_recipient RPC and client directory sync remain active.';
end;
$$;

-- Backfill any existing Google-signed-in users into public.user_directory
do $$
declare
  rec record;
begin
  for rec in
    select distinct on (lower(trim(u.email)))
      u.id as user_id,
      lower(trim(u.email)) as email,
      trim(coalesce(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name', '')) as full_name,
      trim(coalesce(u.raw_user_meta_data->>'avatar_url', u.raw_user_meta_data->>'picture', '')) as avatar_url,
      coalesce(u.last_sign_in_at, u.updated_at, u.created_at, now()) as last_seen_at,
      coalesce(u.created_at, now()) as created_at
    from auth.users u
    where coalesce(trim(u.email), '') <> ''
      and (
        coalesce(u.raw_app_meta_data->>'provider', '') = 'google'
        or coalesce(u.raw_app_meta_data->'providers', '[]'::jsonb) ? 'google'
        or exists (
          select 1 from auth.identities i
          where i.user_id = u.id and i.provider = 'google'
        )
      )
    order by lower(trim(u.email)), u.last_sign_in_at desc nulls last, u.created_at desc
  loop
    delete from public.user_directory where email = rec.email and user_id <> rec.user_id;
    insert into public.user_directory (user_id, email, full_name, avatar_url, provider, last_seen_at, created_at)
    values (rec.user_id, rec.email, rec.full_name, rec.avatar_url, 'google', rec.last_seen_at, rec.created_at)
    on conflict (user_id) do update
    set email = excluded.email,
        full_name = case when excluded.full_name <> '' then excluded.full_name else public.user_directory.full_name end,
        avatar_url = case when excluded.avatar_url <> '' then excluded.avatar_url else public.user_directory.avatar_url end,
        provider = 'google',
        last_seen_at = greatest(public.user_directory.last_seen_at, excluded.last_seen_at);
  end loop;
end;
$$;

-- 8. Enable Row Level Security
alter table public.discharge_summaries enable row level security;
alter table public.user_settings enable row level security;
alter table public.user_directory enable row level security;
alter table public.patient_shares enable row level security;

-- Policies for public.discharge_summaries
drop policy if exists "Users can view own summaries" on public.discharge_summaries;
create policy "Users can view own summaries"
  on public.discharge_summaries for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users can insert own summaries" on public.discharge_summaries;
create policy "Users can insert own summaries"
  on public.discharge_summaries for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users can update own summaries" on public.discharge_summaries;
create policy "Users can update own summaries"
  on public.discharge_summaries for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete own summaries" on public.discharge_summaries;
create policy "Users can delete own summaries"
  on public.discharge_summaries for delete
  to authenticated
  using (auth.uid() = user_id);

-- Policies for public.user_settings
drop policy if exists "Users can view own settings" on public.user_settings;
create policy "Users can view own settings"
  on public.user_settings for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users can upsert own settings" on public.user_settings;
create policy "Users can upsert own settings"
  on public.user_settings for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users can update own settings" on public.user_settings;
create policy "Users can update own settings"
  on public.user_settings for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete own settings" on public.user_settings;
create policy "Users can delete own settings"
  on public.user_settings for delete
  to authenticated
  using (auth.uid() = user_id);

-- Policies for public.user_directory
drop policy if exists "Authenticated users can view directory" on public.user_directory;
create policy "Authenticated users can view directory"
  on public.user_directory for select
  to authenticated
  using (true);

drop policy if exists "Users can insert own directory entry" on public.user_directory;
create policy "Users can insert own directory entry"
  on public.user_directory for insert
  to authenticated
  with check (auth.uid() = user_id and provider = 'google');

drop policy if exists "Users can update own directory entry" on public.user_directory;
create policy "Users can update own directory entry"
  on public.user_directory for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id and provider = 'google');

-- Policies for public.patient_shares
drop policy if exists "Users can view own sent or received shares" on public.patient_shares;
create policy "Users can view own sent or received shares"
  on public.patient_shares for select
  to authenticated
  using (auth.uid() = sender_id or auth.uid() = recipient_id);

drop policy if exists "Senders can insert own shares" on public.patient_shares;
create policy "Senders can insert own shares"
  on public.patient_shares for insert
  to authenticated
  with check (auth.uid() = sender_id);

drop policy if exists "Participants can delete own shares" on public.patient_shares;
create policy "Participants can delete own shares"
  on public.patient_shares for delete
  to authenticated
  using (auth.uid() = sender_id or auth.uid() = recipient_id);

-- 9. Security Definer RPCs for Google-recipient verification & patient handover
create or replace function public.verify_google_recipient(target_email text)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_email text;
  v_user record;
  v_dir record;
  v_name text;
  v_avatar text;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  v_email := lower(trim(coalesce(target_email, '')));
  if v_email = '' then
    return jsonb_build_object('verified', false, 'email', '', 'reason', 'empty_email');
  end if;

  select
    u.id,
    lower(trim(u.email)) as email,
    trim(coalesce(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name', '')) as full_name,
    trim(coalesce(u.raw_user_meta_data->>'avatar_url', u.raw_user_meta_data->>'picture', '')) as avatar_url
  into v_user
  from auth.users u
  where lower(trim(u.email)) = v_email
    and (
      coalesce(u.raw_app_meta_data->>'provider', '') = 'google'
      or coalesce(u.raw_app_meta_data->'providers', '[]'::jsonb) ? 'google'
      or exists (
        select 1 from auth.identities i
        where i.user_id = u.id and i.provider = 'google'
      )
    )
  order by u.last_sign_in_at desc nulls last, u.created_at desc
  limit 1;

  if found then
    v_name := coalesce(v_user.full_name, '');
    v_avatar := coalesce(v_user.avatar_url, '');

    delete from public.user_directory where email = v_email and user_id <> v_user.id;
    insert into public.user_directory (user_id, email, full_name, avatar_url, provider, last_seen_at)
    values (v_user.id, v_email, v_name, v_avatar, 'google', now())
    on conflict (user_id) do update
    set email = excluded.email,
        full_name = case when excluded.full_name <> '' then excluded.full_name else public.user_directory.full_name end,
        avatar_url = case when excluded.avatar_url <> '' then excluded.avatar_url else public.user_directory.avatar_url end,
        provider = 'google',
        last_seen_at = now();

    return jsonb_build_object(
      'verified', true,
      'user_id', v_user.id,
      'email', v_email,
      'full_name', v_name,
      'avatar_url', v_avatar
    );
  end if;

  select d.user_id, d.email, d.full_name, d.avatar_url
  into v_dir
  from public.user_directory d
  where lower(trim(d.email)) = v_email
    and d.provider = 'google'
  limit 1;

  if found then
    return jsonb_build_object(
      'verified', true,
      'user_id', v_dir.user_id,
      'email', v_dir.email,
      'full_name', coalesce(v_dir.full_name, ''),
      'avatar_url', coalesce(v_dir.avatar_url, '')
    );
  end if;

  return jsonb_build_object(
    'verified', false,
    'email', v_email,
    'reason', 'not_google_user'
  );
end;
$$;

grant execute on function public.verify_google_recipient(text) to authenticated;

create or replace function public.share_patient_summary(
  target_email text,
  summary_status text default 'incomplete',
  p_patient_name text default '',
  p_ip_no text default '',
  p_doa text default '',
  p_dod text default '',
  p_unit text default '',
  p_diagnosis_preview text default '',
  p_payload jsonb default '{}'::jsonb,
  p_note text default '',
  p_source_summary_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_sender_id uuid;
  v_sender_email text;
  v_sender_name text;
  v_sender_is_google boolean;
  v_recipient jsonb;
  v_recipient_id uuid;
  v_recipient_email text;
  v_recipient_name text;
  v_status text;
  v_share_id uuid;
  v_new_summary_id uuid;
  v_shared_meta jsonb;
  v_enriched_payload jsonb;
  v_now timestamptz := now();
begin
  v_sender_id := auth.uid();
  if v_sender_id is null then
    raise exception 'NOT_AUTHENTICATED: Please sign in with Google before sharing.';
  end if;

  select
    lower(trim(coalesce(u.email, ''))),
    trim(coalesce(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name', '')),
    (
      coalesce(u.raw_app_meta_data->>'provider', '') = 'google'
      or coalesce(u.raw_app_meta_data->'providers', '[]'::jsonb) ? 'google'
      or exists (
        select 1 from auth.identities i
        where i.user_id = u.id and i.provider = 'google'
      )
    )
  into v_sender_email, v_sender_name, v_sender_is_google
  from auth.users u
  where u.id = v_sender_id;

  if not found or coalesce(v_sender_email, '') = '' then
    raise exception 'SENDER_NOT_FOUND';
  end if;

  if not coalesce(v_sender_is_google, false) then
    raise exception 'SENDER_NOT_GOOGLE_USER: Only Google-authenticated accounts can share patient details.';
  end if;

  v_recipient := public.verify_google_recipient(target_email);
  if not coalesce((v_recipient->>'verified')::boolean, false) then
    raise exception 'RECIPIENT_NOT_GOOGLE_USER: Recipient has not signed in using Google yet.';
  end if;

  v_recipient_id := (v_recipient->>'user_id')::uuid;
  v_recipient_email := v_recipient->>'email';
  v_recipient_name := coalesce(v_recipient->>'full_name', '');

  if v_recipient_id = v_sender_id then
    raise exception 'CANNOT_SHARE_WITH_SELF: Please enter a colleague''s Google email address.';
  end if;

  v_status := case when summary_status = 'completed' then 'completed' else 'incomplete' end;
  v_share_id := gen_random_uuid();
  v_new_summary_id := gen_random_uuid();

  v_shared_meta := jsonb_build_object(
    'share_id', v_share_id,
    'sender_id', v_sender_id,
    'sender_email', v_sender_email,
    'sender_name', v_sender_name,
    'note', coalesce(p_note, ''),
    'shared_at', v_now,
    'source_summary_id', p_source_summary_id
  );

  v_enriched_payload := coalesce(p_payload, '{}'::jsonb) || jsonb_build_object('__shared_from', v_shared_meta);

  insert into public.patient_shares (
    id,
    sender_id,
    sender_email,
    sender_name,
    recipient_id,
    recipient_email,
    recipient_name,
    source_summary_id,
    recipient_summary_id,
    status,
    patient_name,
    ip_no,
    doa,
    dod,
    unit,
    diagnosis_preview,
    payload,
    note,
    created_at
  ) values (
    v_share_id,
    v_sender_id,
    v_sender_email,
    v_sender_name,
    v_recipient_id,
    v_recipient_email,
    v_recipient_name,
    p_source_summary_id,
    v_new_summary_id,
    v_status,
    coalesce(p_patient_name, ''),
    coalesce(p_ip_no, ''),
    coalesce(p_doa, ''),
    coalesce(p_dod, ''),
    coalesce(p_unit, ''),
    coalesce(p_diagnosis_preview, ''),
    v_enriched_payload,
    coalesce(p_note, ''),
    v_now
  );

  insert into public.discharge_summaries (
    id,
    user_id,
    status,
    patient_name,
    ip_no,
    doa,
    dod,
    unit,
    diagnosis_preview,
    payload,
    created_at,
    updated_at
  ) values (
    v_new_summary_id,
    v_recipient_id,
    v_status,
    coalesce(p_patient_name, ''),
    coalesce(p_ip_no, ''),
    coalesce(p_doa, ''),
    coalesce(p_dod, ''),
    coalesce(p_unit, ''),
    coalesce(p_diagnosis_preview, ''),
    v_enriched_payload,
    v_now,
    v_now
  );

  return jsonb_build_object(
    'ok', true,
    'share_id', v_share_id,
    'summary_id', v_new_summary_id,
    'recipient_id', v_recipient_id,
    'recipient_email', v_recipient_email,
    'recipient_name', v_recipient_name
  );
end;
$$;

grant execute on function public.share_patient_summary(text, text, text, text, text, text, text, text, jsonb, text, uuid) to authenticated;
