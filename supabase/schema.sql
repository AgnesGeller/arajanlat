-- Run in the existing KAP project. This file only creates quote_* objects.
create extension if not exists pgcrypto;
create schema if not exists quote_private;

create table if not exists public.quote_staff (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create or replace function quote_private.is_staff() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.quote_staff where user_id = (select auth.uid()))
$$;
revoke all on function quote_private.is_staff() from public;
grant usage on schema quote_private to authenticated;
grant execute on function quote_private.is_staff() to authenticated;

create or replace function quote_private.touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$ begin new.updated_at = now(); return new; end $$;

create table if not exists public.quote_projects (
 id uuid primary key default gen_random_uuid(), client_id uuid not null references public.clients(id) on delete restrict,
 name text not null, work_address text, status text not null default 'Új érdeklődés',
 description text, internal_notes text, client_notes text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.quote_price_catalog (
 id uuid primary key default gen_random_uuid(), source text not null default 'Kalkulátor', source_row integer,
 category text not null, subcategory text not null, description text, internal_notes text,
 unit1 text, unit2 text, material_unit numeric(14,2) not null default 0, labor_unit numeric(14,2) not null default 0,
 active boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(source,source_row)
);
create table if not exists public.quote_plants (
 id uuid primary key default gen_random_uuid(), sku text, latin_name text, name text not null,
 package text, category text, purchase_net numeric(14,2), sale_net numeric(14,2), active boolean not null default true,
 price_date date, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.quote_price_components (
 id uuid primary key default gen_random_uuid(), catalog_id uuid not null references public.quote_price_catalog(id) on delete cascade,
 position integer not null, name text, quantity numeric(14,4), unit text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(catalog_id,position)
);
create table if not exists public.quote_price_breakdown (
 id uuid primary key default gen_random_uuid(), source_row integer not null, source_group integer not null,
 heading text, line_name text, note text, material_value text, labor_value text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(source_row,source_group)
);
create table if not exists public.quote_quotes (
 id uuid primary key default gen_random_uuid(), project_id uuid not null references public.quote_projects(id) on delete cascade,
 number text not null unique, title text, valid_until date, terms text, detail_level text not null default 'detailed' check(detail_level in ('detailed','total')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.quote_versions (
 id uuid primary key default gen_random_uuid(), quote_id uuid not null references public.quote_quotes(id) on delete cascade,
 name text not null default 'A változat', status text not null default 'draft' check(status in ('draft','published','accepted','rejected')),
 published_snapshot jsonb, published_at timestamptz, accepted_at timestamptz, accepted_name text, accepted_note text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.quote_items (
 id uuid primary key default gen_random_uuid(), version_id uuid not null references public.quote_versions(id) on delete cascade,
 position integer not null default 0, category text, subcategory text, name text not null, description text,
 quantity1 numeric(14,3) not null default 1, unit1 text, quantity2 numeric(14,3), unit2 text,
 material_unit numeric(14,2) not null default 0, labor_unit numeric(14,2) not null default 0,
 other_cost numeric(14,2) not null default 0, vat_rate numeric(5,4) not null default 0 check(vat_rate between 0 and 1),
 internal_note text, public_note text, pricing_required boolean not null default false,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.quote_templates (
 id uuid primary key default gen_random_uuid(), name text not null unique,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.quote_template_items (
 id uuid primary key default gen_random_uuid(), template_id uuid not null references public.quote_templates(id) on delete cascade,
 position integer not null, catalog_id uuid references public.quote_price_catalog(id) on delete set null,
 category text, subcategory text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.quote_timeline (
 id uuid primary key default gen_random_uuid(), project_id uuid not null references public.quote_projects(id) on delete cascade,
 event text not null, note text, occurred_at timestamptz not null default now(),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.quote_client_requests (
 id uuid primary key default gen_random_uuid(), project_id uuid not null references public.quote_projects(id) on delete cascade,
 answers jsonb not null default '{}'::jsonb, submitted_at timestamptz not null default now(),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.quote_received_files (
 id uuid primary key default gen_random_uuid(), project_id uuid not null references public.quote_projects(id) on delete cascade,
 file_name text not null, file_type text, note text, received_at timestamptz not null default now(),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.quote_public_tokens (
 id uuid primary key default gen_random_uuid(), project_id uuid not null references public.quote_projects(id) on delete cascade,
 version_id uuid references public.quote_versions(id) on delete cascade,
 purpose text not null check(purpose in ('request','offer')), token_hash text not null unique,
 expires_at timestamptz not null, revoked_at timestamptz,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create index if not exists quote_projects_client_idx on public.quote_projects(client_id);
create index if not exists quote_price_catalog_search_idx on public.quote_price_catalog(category,subcategory);
create index if not exists quote_quotes_project_idx on public.quote_quotes(project_id);
create index if not exists quote_versions_quote_idx on public.quote_versions(quote_id);
create index if not exists quote_items_version_position_idx on public.quote_items(version_id,position);
create index if not exists quote_timeline_project_date_idx on public.quote_timeline(project_id,occurred_at desc);
create index if not exists quote_tokens_project_idx on public.quote_public_tokens(project_id);
create index if not exists quote_tokens_version_idx on public.quote_public_tokens(version_id);
create index if not exists quote_requests_project_idx on public.quote_client_requests(project_id);
create index if not exists quote_received_files_project_idx on public.quote_received_files(project_id);
create index if not exists quote_template_items_template_idx on public.quote_template_items(template_id);
create index if not exists quote_template_items_catalog_idx on public.quote_template_items(catalog_id);

create or replace function quote_private.protect_version() returns trigger
language plpgsql set search_path = '' as $$
begin
 if old.status in ('accepted','rejected') then
  raise exception 'A lezárt ajánlati változat nem módosítható';
 end if;
 if old.status='published' and (new.published_snapshot is distinct from old.published_snapshot or new.quote_id is distinct from old.quote_id) then
  raise exception 'A kiküldött ajánlat tartalma nem módosítható';
 end if;
 return new;
end $$;
drop trigger if exists quote_protect_version on public.quote_versions;
create trigger quote_protect_version before update on public.quote_versions for each row execute function quote_private.protect_version();

create or replace function quote_private.protect_item() returns trigger
language plpgsql set search_path = '' as $$
declare old_state text; new_state text;
begin
 if tg_op <> 'INSERT' then
  select status into old_state from public.quote_versions where id=old.version_id;
  if old_state <> 'draft' then raise exception 'A kiküldött ajánlat tételei nem módosíthatók'; end if;
 end if;
 if tg_op <> 'DELETE' then
  select status into new_state from public.quote_versions where id=new.version_id;
  if new_state <> 'draft' then raise exception 'A kiküldött ajánlat tételei nem módosíthatók'; end if;
 end if;
 if tg_op = 'DELETE' then return old; end if;
 return new;
end $$;
drop trigger if exists quote_protect_item on public.quote_items;
create trigger quote_protect_item before insert or update or delete on public.quote_items for each row execute function quote_private.protect_item();

do $$ declare t text; begin
 foreach t in array array['quote_staff','quote_projects','quote_price_catalog','quote_price_components','quote_price_breakdown','quote_plants','quote_quotes','quote_versions','quote_items','quote_templates','quote_template_items','quote_timeline','quote_client_requests','quote_received_files','quote_public_tokens'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('drop policy if exists quote_staff_only on public.%I',t);
  execute format('create policy quote_staff_only on public.%I for all to authenticated using (quote_private.is_staff()) with check (quote_private.is_staff())',t);
  execute format('grant select,insert,update,delete on public.%I to authenticated',t);
  execute format('revoke all on public.%I from anon',t);
  execute format('drop trigger if exists quote_touch on public.%I',t);
  execute format('create trigger quote_touch before update on public.%I for each row execute function quote_private.touch_updated_at()',t);
 end loop;
end $$;

-- Company boundary: existing clients/profiles are read, never altered by this schema.
create or replace function quote_private.staff_company() returns uuid
language sql stable security definer set search_path = '' as $$
 select p.company_id from public.profiles p join public.quote_staff s on s.user_id=p.id
 where p.id=(select auth.uid()) limit 1
$$;
create or replace function quote_private.can_client(p_client uuid) returns boolean
language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.clients c where c.id=p_client and c.company_id=quote_private.staff_company())
$$;
create or replace function quote_private.can_project(p_project uuid) returns boolean
language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.quote_projects p where p.id=p_project and quote_private.can_client(p.client_id))
$$;
revoke all on function quote_private.staff_company() from public;
revoke all on function quote_private.can_client(uuid) from public;
revoke all on function quote_private.can_project(uuid) from public;
grant execute on function quote_private.staff_company() to authenticated;
grant execute on function quote_private.can_client(uuid) to authenticated;
grant execute on function quote_private.can_project(uuid) to authenticated;

drop policy if exists quote_staff_only on public.quote_staff;
revoke insert,update,delete on public.quote_staff from authenticated;
drop policy if exists quote_staff_self on public.quote_staff;
create policy quote_staff_self on public.quote_staff for select to authenticated using(user_id=(select auth.uid()));
drop policy if exists quote_staff_only on public.quote_projects;
drop policy if exists quote_project_company on public.quote_projects;
create policy quote_project_company on public.quote_projects for all to authenticated
using(quote_private.can_client(client_id)) with check(quote_private.can_client(client_id));
drop policy if exists quote_staff_only on public.quote_quotes;
drop policy if exists quote_quotes_company on public.quote_quotes;
create policy quote_quotes_company on public.quote_quotes for all to authenticated
using(quote_private.can_project(project_id)) with check(quote_private.can_project(project_id));
drop policy if exists quote_staff_only on public.quote_versions;
drop policy if exists quote_versions_company on public.quote_versions;
create policy quote_versions_company on public.quote_versions for all to authenticated
using(exists(select 1 from public.quote_quotes q where q.id=quote_id and quote_private.can_project(q.project_id)))
with check(exists(select 1 from public.quote_quotes q where q.id=quote_id and quote_private.can_project(q.project_id)));
drop policy if exists quote_staff_only on public.quote_items;
drop policy if exists quote_items_company on public.quote_items;
create policy quote_items_company on public.quote_items for all to authenticated
using(exists(select 1 from public.quote_versions v join public.quote_quotes q on q.id=v.quote_id where v.id=version_id and quote_private.can_project(q.project_id)))
with check(exists(select 1 from public.quote_versions v join public.quote_quotes q on q.id=v.quote_id where v.id=version_id and quote_private.can_project(q.project_id)));
do $$ declare t text; begin
 foreach t in array array['quote_timeline','quote_client_requests','quote_received_files','quote_public_tokens'] loop
  execute format('drop policy if exists quote_staff_only on public.%I',t);
  execute format('drop policy if exists quote_company on public.%I',t);
  execute format('create policy quote_company on public.%I for all to authenticated using(quote_private.can_project(project_id)) with check(quote_private.can_project(project_id))',t);
 end loop;
end $$;

-- Public RPCs are narrow, token scoped, and return only customer-facing fields.
create or replace function public.quote_public_read(p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare tok public.quote_public_tokens%rowtype; result jsonb;
begin
 if length(coalesce(p_token,'')) < 32 then return null; end if;
 select * into tok from public.quote_public_tokens
 where token_hash = encode(extensions.digest(p_token,'sha256'),'hex') and revoked_at is null and expires_at > now();
 if not found then return null; end if;
 if tok.purpose = 'request' then
   select jsonb_build_object('purpose','request','project',p.name,'work_address',p.work_address)
   into result from public.quote_projects p where p.id = tok.project_id;
 else
   select v.published_snapshot into result from public.quote_versions v
   where v.id = tok.version_id and v.status in ('published','accepted','rejected');
 end if;
 return result;
end $$;

create or replace function public.quote_public_submit(p_token text,p_answers jsonb)
returns boolean language plpgsql security definer set search_path = '' as $$
declare tok public.quote_public_tokens%rowtype;
begin
 if length(coalesce(p_token,'')) < 32 or jsonb_typeof(p_answers) <> 'object' or octet_length(p_answers::text)>20000 then return false; end if;
 select * into tok from public.quote_public_tokens where token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
 and purpose='request' and revoked_at is null and expires_at>now() for update;
 if not found then return false; end if;
 insert into public.quote_client_requests(project_id,answers) values(tok.project_id,p_answers);
 insert into public.quote_timeline(project_id,event) values(tok.project_id,'Ügyfél adatbekérő visszaérkezett');
 update public.quote_projects set status='Ügyfél kitöltötte' where id=tok.project_id;
 update public.quote_public_tokens set revoked_at=now() where id=tok.id;
 return true;
end $$;

create or replace function public.quote_public_decide(p_token text,p_decision text,p_name text,p_note text,p_confirm boolean)
returns boolean language plpgsql security definer set search_path = '' as $$
declare tok public.quote_public_tokens%rowtype; current_status text;
begin
 if length(coalesce(p_token,''))<32 or p_decision is null or p_decision not in ('accepted','change','rejected') or length(trim(coalesce(p_name,'')))<2 or length(coalesce(p_note,''))>2000 then return false; end if;
 if p_decision='accepted' and p_confirm is not true then return false; end if;
 select * into tok from public.quote_public_tokens where token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
 and purpose='offer' and revoked_at is null and expires_at>now() for update;
 if not found then return false; end if;
 select status into current_status from public.quote_versions where id=tok.version_id for update;
 if current_status <> 'published' then return false; end if;
 if p_decision='accepted' then
  update public.quote_versions set status='accepted',accepted_at=now(),accepted_name=trim(p_name),accepted_note=p_note where id=tok.version_id;
 elsif p_decision='rejected' then
  update public.quote_versions set status='rejected',accepted_at=now(),accepted_name=trim(p_name),accepted_note=p_note where id=tok.version_id;
 end if;
 insert into public.quote_timeline(project_id,event,note) values(tok.project_id,
 case p_decision when 'accepted' then 'Árajánlat elfogadva' when 'rejected' then 'Árajánlat elutasítva' else 'Módosítás kérése' end,
 trim(p_name)||case when coalesce(p_note,'')='' then '' else ': '||p_note end);
 update public.quote_projects set status=case p_decision when 'accepted' then 'Elfogadva' when 'rejected' then 'Elutasítva' else 'Módosítás alatt' end where id=tok.project_id;
 update public.quote_public_tokens set revoked_at=now() where id=tok.id;
 return true;
end $$;

revoke all on function public.quote_public_read(text) from public;
revoke all on function public.quote_public_submit(text,jsonb) from public;
revoke all on function public.quote_public_decide(text,text,text,text,boolean) from public;
grant execute on function public.quote_public_read(text) to anon,authenticated;
grant execute on function public.quote_public_submit(text,jsonb) to anon,authenticated;
grant execute on function public.quote_public_decide(text,text,text,text,boolean) to anon,authenticated;

-- Bootstrap: insert the intended auth.users UUID into quote_staff in SQL Editor.
