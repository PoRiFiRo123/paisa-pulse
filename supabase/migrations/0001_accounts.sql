-- Paisa Pulse accounts and sharing.
-- Only shared things live here: profiles, people you're connected with, shared groups and trips,
-- shared expenses with each person's share, settle-ups and an inbox. Personal ledgers stay on the phone.
--
-- The apps never touch tables directly: every read and write goes through the security definer
-- functions below, which check auth.uid(). Tables have row level security on and no policies.
-- Applied by .github/scripts/supabase-setup.py (each file once, tracked in public._paisa_migrations).

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------- tables

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique check (username ~ '^[a-z0-9_]{3,20}$'),
  display_name text not null default '' check (char_length(display_name) <= 60),
  upi_id text check (upi_id is null or char_length(upi_id) <= 80),
  -- sha256 hex of the last 10 digits of the phone number, and of the lower-case email. Only hashes are kept.
  phone_hash text,
  email_hash text,
  color text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists profiles_phone_hash on public.profiles(phone_hash);
create index if not exists profiles_email_hash on public.profiles(email_hash);

create table if not exists public.connections (
  user_id uuid not null references public.profiles(id) on delete cascade,
  friend_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, friend_id),
  check (user_id <> friend_id)
);

create table if not exists public.invites (
  code text primary key,
  owner uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '30 days'
);

-- A shared split group or trip. data holds the trip's details (dates, places, budget items).
create table if not exists public.spaces (
  id uuid primary key,
  kind text not null check (kind in ('group', 'trip')),
  name text not null check (char_length(name) between 1 and 80),
  data jsonb not null default '{}'::jsonb,
  created_by uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.space_members (
  space_id uuid not null references public.spaces(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  added_by uuid references public.profiles(id) on delete set null,
  left_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (space_id, user_id)
);
create index if not exists space_members_user on public.space_members(user_id);

-- A shared expense. amount is in minor units of currency (paise for INR).
create table if not exists public.expenses (
  id uuid primary key,
  space_id uuid references public.spaces(id) on delete set null,
  created_by uuid not null references public.profiles(id) on delete cascade,
  paid_by uuid not null references public.profiles(id) on delete cascade,
  amount bigint not null check (amount > 0),
  currency text not null default 'INR',
  original_amount bigint,
  original_currency text,
  payee text,
  note text,
  occurred_at timestamptz not null,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index if not exists expenses_space on public.expenses(space_id);
create index if not exists expenses_updated on public.expenses(updated_at);

create table if not exists public.expense_shares (
  expense_id uuid not null references public.expenses(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  amount bigint not null check (amount >= 0),
  status text not null default 'pending' check (status in ('pending', 'accepted', 'rejected')),
  updated_at timestamptz not null default now(),
  primary key (expense_id, user_id)
);
create index if not exists expense_shares_user on public.expense_shares(user_id);

-- Money paid back: from_user paid to_user. The person who didn't record it confirms it.
create table if not exists public.settlements (
  id uuid primary key,
  space_id uuid references public.spaces(id) on delete set null,
  created_by uuid not null references public.profiles(id) on delete cascade,
  from_user uuid not null references public.profiles(id) on delete cascade,
  to_user uuid not null references public.profiles(id) on delete cascade,
  amount bigint not null check (amount > 0),
  currency text not null default 'INR',
  note text,
  status text not null default 'pending' check (status in ('pending', 'confirmed', 'rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (from_user <> to_user)
);
create index if not exists settlements_from on public.settlements(from_user);
create index if not exists settlements_to on public.settlements(to_user);

create table if not exists public.inbox (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null,
  actor uuid references public.profiles(id) on delete set null,
  ref_id uuid,
  title text not null,
  body text,
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index if not exists inbox_user on public.inbox(user_id, created_at);

alter table public.profiles enable row level security;
alter table public.connections enable row level security;
alter table public.invites enable row level security;
alter table public.spaces enable row level security;
alter table public.space_members enable row level security;
alter table public.expenses enable row level security;
alter table public.expense_shares enable row level security;
alter table public.settlements enable row level security;
alter table public.inbox enable row level security;

-- ---------------------------------------------------------------- helpers

create or replace function public._me() returns uuid language plpgsql stable as $$
declare u uuid := auth.uid();
begin
  if u is null then raise exception 'Not signed in' using errcode = '28000'; end if;
  return u;
end $$;

create or replace function public._hash(t text) returns text language sql immutable as $$
  select encode(extensions.digest(convert_to(t, 'UTF8'), 'sha256'), 'hex')
$$;

-- Last 10 digits of a phone number, hashed. Same rule as the apps (CloudLogic.phoneHash).
create or replace function public._phone_hash(p text) returns text language sql immutable as $$
  select case when length(regexp_replace(coalesce(p, ''), '\D', '', 'g')) >= 10
    then public._hash(right(regexp_replace(p, '\D', '', 'g'), 10)) end
$$;

create or replace function public._name(u uuid) returns text language sql stable security definer set search_path = public as $$
  select coalesce(nullif(display_name, ''), '@' || username, 'Someone') from public.profiles where id = u
$$;

create or replace function public._notify(target uuid, k text, ref uuid, t text, b text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if target is null or target = auth.uid() then return; end if;
  insert into public.inbox(user_id, kind, actor, ref_id, title, body) values (target, k, auth.uid(), ref, t, b);
end $$;

create or replace function public._is_member(s uuid, u uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.space_members m where m.space_id = s and m.user_id = u and m.left_at is null)
$$;

create or replace function public._money(a bigint, c text) returns text language sql immutable as $$
  select case when c = 'INR' then '₹' else c || ' ' end || to_char(a / 100.0, 'FM999G999G999G990D00')
$$;

-- New sign-ups get a profile with the email hash, so friends can find them by email.
create or replace function public._on_new_user() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles(id, email_hash) values (new.id, public._hash(lower(trim(coalesce(new.email, '')))))
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists paisa_on_new_user on auth.users;
create trigger paisa_on_new_user after insert on auth.users for each row execute function public._on_new_user();

-- ---------------------------------------------------------------- profile

create or replace function public.ensure_profile() returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := public._me(); e text;
begin
  select email into e from auth.users where id = me;
  insert into public.profiles(id, email_hash) values (me, public._hash(lower(trim(coalesce(e, '')))))
  on conflict (id) do update set email_hash = excluded.email_hash;
  return (select to_jsonb(p) - 'phone_hash' - 'email_hash' || jsonb_build_object('email', e, 'has_phone', p.phone_hash is not null)
          from public.profiles p where p.id = me);
end $$;

create or replace function public.update_profile(p_username text, p_display_name text, p_upi_id text, p_phone text, p_color text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := public._me(); u text := lower(trim(p_username));
begin
  if u is not null and u !~ '^[a-z0-9_]{3,20}$' then
    raise exception 'Usernames are 3 to 20 letters, numbers or _' using errcode = '22023';
  end if;
  if u is not null and exists(select 1 from public.profiles where username = u and id <> me) then
    raise exception 'That username is taken' using errcode = '23505';
  end if;
  update public.profiles set
    username = coalesce(u, username),
    display_name = coalesce(trim(p_display_name), display_name),
    upi_id = case when p_upi_id is null then upi_id else nullif(trim(p_upi_id), '') end,
    phone_hash = case when p_phone is null then phone_hash when trim(p_phone) = '' then null else public._phone_hash(p_phone) end,
    color = coalesce(p_color, color),
    updated_at = now()
  where id = me;
  return public.ensure_profile();
end $$;

create or replace function public.username_available(p_username text) returns boolean
language sql stable security definer set search_path = public as $$
  select lower(trim(p_username)) ~ '^[a-z0-9_]{3,20}$'
     and not exists(select 1 from public.profiles where username = lower(trim(p_username)) and id <> auth.uid())
$$;

-- ---------------------------------------------------------------- people

create or replace function public._card(p public.profiles) returns jsonb language sql stable as $$
  select jsonb_build_object('id', p.id, 'username', p.username, 'display_name', p.display_name, 'upi_id', p.upi_id,
    'color', p.color, 'updated_at', p.updated_at)
$$;

-- Find people by @username (prefix), exact email or exact phone number.
create or replace function public.find_people(q text) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := public._me(); s text := lower(trim(coalesce(q, ''))); digits text := regexp_replace(s, '\D', '', 'g');
begin
  if s like '@%' then s := substr(s, 2); end if;
  if length(s) < 2 then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(t.card) from (
      select public._card(p) || jsonb_build_object('connected',
        exists(select 1 from public.connections c where c.user_id = me and c.friend_id = p.id)) as card
      from public.profiles p
      where p.id <> me and p.username is not null and (
        (position('@' in s) > 0 and p.email_hash = public._hash(s))
        or (length(digits) >= 10 and length(digits) >= length(s) - 3 and p.phone_hash = public._phone_hash(digits))
        or (p.username like replace(replace(s, '_', '\_'), '%', '\%') || '%'))
      order by p.username limit 20) t), '[]'::jsonb);
end $$;

-- Which of these phone hashes (from your contacts, hashed on the phone) are on Paisa Pulse.
create or replace function public.match_contacts(hashes text[]) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare me uuid := public._me();
begin
  return coalesce((select jsonb_agg(public._card(p) || jsonb_build_object('phone_hash', p.phone_hash, 'connected',
      exists(select 1 from public.connections c where c.user_id = me and c.friend_id = p.id)))
    from public.profiles p where p.id <> me and p.username is not null and p.phone_hash = any(hashes[1:2000])), '[]'::jsonb);
end $$;

create or replace function public.connect(p_friend uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := public._me(); p public.profiles;
begin
  select * into p from public.profiles where id = p_friend and username is not null;
  if p.id is null or p.id = me then raise exception 'Person not found' using errcode = 'P0002'; end if;
  insert into public.connections(user_id, friend_id) values (me, p.id), (p.id, me) on conflict do nothing;
  perform public._notify(p.id, 'connected', me, public._name(me) || ' added you', 'You can now split bills and trips together.');
  return public._card(p);
end $$;

create or replace function public.disconnect(p_friend uuid) returns void language sql security definer set search_path = public as $$
  delete from public.connections where (user_id = auth.uid() and friend_id = p_friend) or (user_id = p_friend and friend_id = auth.uid())
$$;

create or replace function public.create_invite() returns text language plpgsql security definer set search_path = public as $$
declare me uuid := public._me(); c text;
begin
  select code into c from public.invites where owner = me and expires_at > now() + interval '7 days' order by created_at desc limit 1;
  if c is not null then return c; end if;
  c := upper(substr(translate(encode(extensions.gen_random_bytes(9), 'base64'), '+/=0O1Il', ''), 1, 8));
  insert into public.invites(code, owner) values (c, me);
  return c;
end $$;

create or replace function public.accept_invite(p_code text) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := public._me(); o uuid;
begin
  select owner into o from public.invites where code = upper(trim(p_code)) and expires_at > now();
  if o is null then raise exception 'This invite has expired or is wrong' using errcode = 'P0002'; end if;
  if o = me then raise exception 'That is your own invite' using errcode = '22023'; end if;
  return public.connect(o);
end $$;

-- ---------------------------------------------------------------- groups and trips

-- Create or update a shared group or trip you made. Members must be people you're connected with.
create or replace function public.save_space(p_id uuid, p_kind text, p_name text, p_data jsonb, p_members uuid[])
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := public._me(); s public.spaces; m uuid; added boolean;
begin
  select * into s from public.spaces where id = p_id;
  if s.id is not null and s.created_by <> me then raise exception 'Only the person who made it can change it' using errcode = '42501'; end if;
  insert into public.spaces(id, kind, name, data, created_by) values (p_id, p_kind, trim(p_name), coalesce(p_data, '{}'::jsonb), me)
  on conflict (id) do update set kind = excluded.kind, name = excluded.name, data = excluded.data, updated_at = now(), deleted_at = null;
  insert into public.space_members(space_id, user_id, added_by) values (p_id, me, me)
  on conflict (space_id, user_id) do update set left_at = null, updated_at = now();
  foreach m in array coalesce(p_members, '{}') loop
    continue when m = me or not exists(select 1 from public.connections where user_id = me and friend_id = m);
    added := not exists(select 1 from public.space_members where space_id = p_id and user_id = m and left_at is null);
    insert into public.space_members(space_id, user_id, added_by) values (p_id, m, me)
    on conflict (space_id, user_id) do update set left_at = null, updated_at = now();
    if added then
      perform public._notify(m, 'space', p_id, public._name(me) || ' added you to ' || trim(p_name),
        case when p_kind = 'trip' then 'A shared trip. Expenses you split in it show up for everyone.' else 'A shared split group.' end);
    end if;
  end loop;
  -- Members no longer listed have been removed.
  update public.space_members set left_at = now(), updated_at = now()
  where space_id = p_id and user_id <> me and left_at is null and not (user_id = any(coalesce(p_members, '{}')));
end $$;

create or replace function public.leave_space(p_id uuid) returns void language plpgsql security definer set search_path = public as $$
declare me uuid := public._me(); s public.spaces;
begin
  select * into s from public.spaces where id = p_id;
  if s.created_by = me then
    update public.spaces set deleted_at = now(), updated_at = now() where id = p_id;
  else
    update public.space_members set left_at = now(), updated_at = now() where space_id = p_id and user_id = me;
    update public.spaces set updated_at = now() where id = p_id;
  end if;
end $$;

-- ---------------------------------------------------------------- expenses

-- Create or update a shared expense you recorded. p_shares: [{"user": uuid, "amount": paise}].
-- Your own share and the payer's are accepted straight away; everyone else confirms theirs.
create or replace function public.save_expense(p_id uuid, p_space uuid, p_paid_by uuid, p_amount bigint, p_currency text,
  p_original_amount bigint, p_original_currency text, p_payee text, p_note text, p_occurred_at timestamptz, p_data jsonb, p_shares jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := public._me(); e public.expenses; sh jsonb; u uuid; a bigint; old public.expense_shares; what text;
begin
  select * into e from public.expenses where id = p_id;
  if e.id is not null and e.created_by <> me then raise exception 'Only the person who added it can change it' using errcode = '42501'; end if;
  if p_space is not null and not public._is_member(p_space, me) then raise exception 'Not in that group' using errcode = '42501'; end if;
  if p_paid_by <> me and not exists(select 1 from public.connections where user_id = me and friend_id = p_paid_by)
     and not (p_space is not null and public._is_member(p_space, p_paid_by)) then
    raise exception 'Not connected with the payer' using errcode = '42501';
  end if;
  insert into public.expenses(id, space_id, created_by, paid_by, amount, currency, original_amount, original_currency, payee, note, occurred_at, data)
  values (p_id, p_space, me, p_paid_by, p_amount, coalesce(p_currency, 'INR'), p_original_amount, p_original_currency, p_payee, p_note, p_occurred_at, coalesce(p_data, '{}'))
  on conflict (id) do update set space_id = excluded.space_id, paid_by = excluded.paid_by, amount = excluded.amount, currency = excluded.currency,
    original_amount = excluded.original_amount, original_currency = excluded.original_currency, payee = excluded.payee, note = excluded.note,
    occurred_at = excluded.occurred_at, data = excluded.data, updated_at = now(), deleted_at = null;
  what := coalesce(nullif(p_payee, ''), nullif(p_note, ''), 'an expense');
  delete from public.expense_shares s where s.expense_id = p_id
    and not exists(select 1 from jsonb_array_elements(coalesce(p_shares, '[]')) x where (x->>'user')::uuid = s.user_id);
  for sh in select * from jsonb_array_elements(coalesce(p_shares, '[]')) loop
    u := (sh->>'user')::uuid; a := (sh->>'amount')::bigint;
    continue when u is null or a is null or a < 0;
    if u <> me and u <> p_paid_by and not exists(select 1 from public.connections where user_id = me and friend_id = u)
       and not (p_space is not null and public._is_member(p_space, u)) then continue; end if;
    select * into old from public.expense_shares where expense_id = p_id and user_id = u;
    if old.user_id is null then
      insert into public.expense_shares(expense_id, user_id, amount, status)
      values (p_id, u, a, case when u = me or (u = p_paid_by and p_paid_by = me) then 'accepted' else 'pending' end);
      if u <> me then
        perform public._notify(u, 'expense', p_id,
          case when p_paid_by = u then public._name(me) || ' says you paid for ' || what
               when p_paid_by = me then public._name(me) || ' split ' || what || ' with you'
               else public._name(p_paid_by) || ' paid for ' || what end,
          'Your share: ' || public._money(a, coalesce(p_currency, 'INR')) || case when p_paid_by = u then ' of what others owe you' else '' end);
      end if;
    elsif old.amount <> a then
      update public.expense_shares set amount = a, status = case when u = me then 'accepted' else 'pending' end, updated_at = now()
      where expense_id = p_id and user_id = u;
      perform public._notify(u, 'expense', p_id, public._name(me) || ' changed ' || what,
        'Your share is now ' || public._money(a, coalesce(p_currency, 'INR')));
    else
      update public.expense_shares set updated_at = now() where expense_id = p_id and user_id = u;
    end if;
  end loop;
end $$;

create or replace function public.delete_expense(p_id uuid) returns void language plpgsql security definer set search_path = public as $$
declare me uuid := public._me(); e public.expenses; u uuid;
begin
  select * into e from public.expenses where id = p_id;
  if e.id is null then return; end if;
  if e.created_by <> me then raise exception 'Only the person who added it can delete it' using errcode = '42501'; end if;
  update public.expenses set deleted_at = now(), updated_at = now() where id = p_id;
  for u in select user_id from public.expense_shares where expense_id = p_id and user_id <> me loop
    perform public._notify(u, 'expense_deleted', p_id, public._name(me) || ' removed ' || coalesce(nullif(e.payee, ''), nullif(e.note, ''), 'an expense'), null);
  end loop;
end $$;

create or replace function public.respond_share(p_expense uuid, p_accept boolean) returns void language plpgsql security definer set search_path = public as $$
declare me uuid := public._me(); e public.expenses;
begin
  update public.expense_shares set status = case when p_accept then 'accepted' else 'rejected' end, updated_at = now()
  where expense_id = p_expense and user_id = me;
  select * into e from public.expenses where id = p_expense;
  update public.expenses set updated_at = now() where id = p_expense;
  if not p_accept then
    perform public._notify(e.created_by, 'share_rejected', p_expense,
      public._name(me) || ' declined ' || coalesce(nullif(e.payee, ''), nullif(e.note, ''), 'an expense'), 'You may want to check it with them.');
  end if;
end $$;

-- ---------------------------------------------------------------- settle up

create or replace function public.save_settlement(p_id uuid, p_space uuid, p_from uuid, p_to uuid, p_amount bigint, p_currency text, p_note text)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := public._me(); other uuid := case when p_from = me then p_to else p_from end; s public.settlements;
begin
  if me <> p_from and me <> p_to then raise exception 'You must be one of the two people' using errcode = '42501'; end if;
  if not exists(select 1 from public.connections where user_id = me and friend_id = other)
     and not (p_space is not null and public._is_member(p_space, other)) then
    raise exception 'Not connected' using errcode = '42501';
  end if;
  select * into s from public.settlements where id = p_id;
  if s.id is not null and s.created_by <> me then raise exception 'Only the person who recorded it can change it' using errcode = '42501'; end if;
  insert into public.settlements(id, space_id, created_by, from_user, to_user, amount, currency, note)
  values (p_id, p_space, me, p_from, p_to, p_amount, coalesce(p_currency, 'INR'), p_note)
  on conflict (id) do update set amount = excluded.amount, note = excluded.note, status = 'pending', updated_at = now(), deleted_at = null;
  if s.id is null then
    perform public._notify(other, 'settlement', p_id,
      case when p_from = me then public._name(me) || ' paid you ' || public._money(p_amount, coalesce(p_currency, 'INR'))
           else public._name(me) || ' says you paid them ' || public._money(p_amount, coalesce(p_currency, 'INR')) end,
      'Confirm it in Paisa Pulse to update your balance.');
  end if;
end $$;

create or replace function public.delete_settlement(p_id uuid) returns void language sql security definer set search_path = public as $$
  update public.settlements set deleted_at = now(), updated_at = now() where id = p_id and created_by = auth.uid()
$$;

create or replace function public.respond_settlement(p_id uuid, p_confirm boolean) returns void language plpgsql security definer set search_path = public as $$
declare me uuid := public._me(); s public.settlements;
begin
  select * into s from public.settlements where id = p_id and (from_user = me or to_user = me) and created_by <> me;
  if s.id is null then return; end if;
  update public.settlements set status = case when p_confirm then 'confirmed' else 'rejected' end, updated_at = now() where id = p_id;
  perform public._notify(s.created_by, case when p_confirm then 'settlement_confirmed' else 'settlement_rejected' end, p_id,
    public._name(me) || case when p_confirm then ' confirmed ' else ' did not confirm ' end || public._money(s.amount, s.currency), null);
end $$;

-- ---------------------------------------------------------------- sync

-- Everything shared with you that changed since p_since (null = everything).
create or replace function public.sync(p_since timestamptz) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := public._me(); since timestamptz := coalesce(p_since, 'epoch'::timestamptz) - interval '2 minutes';
  my_spaces uuid[]; my_expenses uuid[];
begin
  select coalesce(array_agg(space_id), '{}') into my_spaces from public.space_members where user_id = me;
  select coalesce(array_agg(distinct e.id), '{}') into my_expenses from public.expenses e
  where e.created_by = me or e.paid_by = me or e.space_id = any(my_spaces)
     or exists(select 1 from public.expense_shares s where s.expense_id = e.id and s.user_id = me);
  return jsonb_build_object(
    'server_time', now(),
    'me', public.ensure_profile(),
    'people', coalesce((select jsonb_agg(public._card(p) || jsonb_build_object('connected',
        exists(select 1 from public.connections c where c.user_id = me and c.friend_id = p.id)))
      from public.profiles p where p.id <> me and (
        p.id in (select friend_id from public.connections where user_id = me)
        or p.id in (select user_id from public.space_members where space_id = any(my_spaces))
        or p.id in (select user_id from public.expense_shares where expense_id = any(my_expenses))
        or p.id in (select paid_by from public.expenses where id = any(my_expenses)))), '[]'::jsonb),
    'spaces', coalesce((select jsonb_agg(to_jsonb(s) || jsonb_build_object('members',
        (select coalesce(jsonb_agg(jsonb_build_object('user_id', m.user_id, 'left', m.left_at is not null)), '[]'::jsonb)
         from public.space_members m where m.space_id = s.id)))
      from public.spaces s where s.id = any(my_spaces) and (s.updated_at > since
        or exists(select 1 from public.space_members m where m.space_id = s.id and m.updated_at > since))), '[]'::jsonb),
    'expenses', coalesce((select jsonb_agg(to_jsonb(e) || jsonb_build_object('shares',
        (select coalesce(jsonb_agg(jsonb_build_object('user_id', x.user_id, 'amount', x.amount, 'status', x.status)), '[]'::jsonb)
         from public.expense_shares x where x.expense_id = e.id)))
      from public.expenses e where e.id = any(my_expenses) and (e.updated_at > since
        or exists(select 1 from public.expense_shares x where x.expense_id = e.id and x.updated_at > since))), '[]'::jsonb),
    'settlements', coalesce((select jsonb_agg(to_jsonb(s)) from public.settlements s
      where (s.from_user = me or s.to_user = me) and s.updated_at > since), '[]'::jsonb),
    'inbox', coalesce((select jsonb_agg(to_jsonb(i) order by i.created_at desc) from public.inbox i
      where i.user_id = me and (i.created_at > since or (i.read_at is not null and i.read_at > since))), '[]'::jsonb)
  );
end $$;

create or replace function public.mark_read(p_ids bigint[]) returns void language sql security definer set search_path = public as $$
  update public.inbox set read_at = now() where user_id = auth.uid() and read_at is null and (p_ids is null or id = any(p_ids))
$$;

-- ---------------------------------------------------------------- your data

create or replace function public.export_my_data() returns jsonb language sql security definer set search_path = public as $$
  select public.sync(null)
$$;

-- Deletes your account and everything you made. Expenses others recorded keep their amounts, without you.
create or replace function public.delete_account() returns void language plpgsql security definer set search_path = public, auth as $$
declare me uuid := public._me();
begin
  delete from auth.users where id = me;
end $$;

-- ---------------------------------------------------------------- permissions

revoke all on all tables in schema public from anon, authenticated;
revoke execute on all functions in schema public from public, anon;
grant execute on function public.ensure_profile(), public.update_profile(text, text, text, text, text), public.username_available(text),
  public.find_people(text), public.match_contacts(text[]), public.connect(uuid), public.disconnect(uuid), public.create_invite(),
  public.accept_invite(text), public.save_space(uuid, text, text, jsonb, uuid[]), public.leave_space(uuid),
  public.save_expense(uuid, uuid, uuid, bigint, text, bigint, text, text, text, timestamptz, jsonb, jsonb), public.delete_expense(uuid),
  public.respond_share(uuid, boolean), public.save_settlement(uuid, uuid, uuid, uuid, bigint, text, text), public.delete_settlement(uuid),
  public.respond_settlement(uuid, boolean), public.sync(timestamptz), public.mark_read(bigint[]), public.export_my_data(), public.delete_account()
  to authenticated;
