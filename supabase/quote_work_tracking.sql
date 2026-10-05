-- Kizárólag Árajánlat-objektumok. A Munkalap/Kassza forrást csak olvassuk.
begin;
alter table public.quote_projects add column if not exists started_on date;
create table if not exists public.quote_work_records (
  company_id uuid not null references public.companies(id),
  source_id uuid not null,
  project_id uuid not null references public.quote_projects(id),
  work_date date not null,
  source_updated_at timestamptz not null,
  form_data jsonb not null check(jsonb_typeof(form_data)='object'),
  calculation jsonb not null check(jsonb_typeof(calculation)='object'),
  active boolean not null default true,
  synced_at timestamptz not null default now(),
  primary key(company_id,source_id)
);
create index if not exists quote_work_records_project_idx on public.quote_work_records(project_id,work_date);
alter table public.quote_work_records enable row level security;
revoke all on public.quote_work_records from public,anon,authenticated;
grant select on public.quote_work_records to authenticated;
grant all on public.quote_work_records to service_role;
drop policy if exists quote_work_records_staff on public.quote_work_records;
create policy quote_work_records_staff on public.quote_work_records for select to authenticated
using(company_id=quote_private.staff_company() and quote_private.can_project(project_id));

create table if not exists public.quote_work_progress (
 item_id uuid primary key references public.quote_items(id) on delete cascade,
 project_id uuid not null references public.quote_projects(id),
 version_id uuid not null references public.quote_versions(id),
 source_code text,
 override_completed numeric check(override_completed>=0 and override_completed<=1000000),
 modified_by uuid not null default auth.uid(),
 modified_at timestamptz not null default now(),
 unique(version_id,source_code)
);
alter table public.quote_work_progress enable row level security;
create index if not exists quote_work_progress_project_idx on public.quote_work_progress(project_id);
revoke all on public.quote_work_progress from public,anon,authenticated;
grant select,insert,update,delete on public.quote_work_progress to authenticated;
grant all on public.quote_work_progress to service_role;
create or replace function quote_private.work_setting_valid(p_item uuid,p_project uuid,p_version uuid,p_code text)
returns boolean language sql stable security invoker set search_path='' as $$
 select exists(select 1 from public.quote_items i
 join public.quote_versions v on v.id=i.version_id join public.quote_quotes q on q.id=v.quote_id
 where i.id=p_item and i.version_id=p_version and q.project_id=p_project and v.status='accepted'
 and (p_code is null or (nullif(i.unit2,'') is null and
 replace(replace(lower(trim(i.unit1)),'²','2'),'³','3')=case
 when p_code in ('maintenance_0','construction_3','construction_4','construction_5','construction_6','construction_7','construction_8','construction_9','construction_10','construction_11','construction_12','construction_16','construction_17') then 'm3'
 when p_code='maintenance_18' then 'm2'
 when p_code in ('maintenance_1','maintenance_12','maintenance_13','maintenance_14','maintenance_15') then 'zsák'
 when p_code in ('maintenance_2','maintenance_16','maintenance_17','maintenance_19','construction_14','construction_15','construction_18') then 'db'
 when p_code in ('maintenance_3','maintenance_4','maintenance_5','maintenance_7') then 'tartály (15l)'
 when p_code in ('maintenance_8','maintenance_9','maintenance_10','maintenance_11') then 'adagoló'
 when p_code='construction_13' then '25kg/db'
 when p_code='maintenance_6' then 'liter'
 else null end)))
$$;
revoke all on function quote_private.work_setting_valid(uuid,uuid,uuid,text) from public;
grant execute on function quote_private.work_setting_valid(uuid,uuid,uuid,text) to authenticated,service_role;
drop policy if exists quote_work_progress_read on public.quote_work_progress;
drop policy if exists quote_work_progress_insert on public.quote_work_progress;
drop policy if exists quote_work_progress_update on public.quote_work_progress;
drop policy if exists quote_work_progress_delete on public.quote_work_progress;
create policy quote_work_progress_read on public.quote_work_progress for select to authenticated using(quote_private.can_project(project_id));
create policy quote_work_progress_insert on public.quote_work_progress for insert to authenticated with check(
 quote_private.can_project(project_id) and modified_by=auth.uid() and quote_private.work_setting_valid(item_id,project_id,version_id,source_code));
create policy quote_work_progress_update on public.quote_work_progress for update to authenticated using(quote_private.can_project(project_id)) with check(
 quote_private.can_project(project_id) and modified_by=auth.uid() and quote_private.work_setting_valid(item_id,project_id,version_id,source_code));
create policy quote_work_progress_delete on public.quote_work_progress for delete to authenticated using(quote_private.can_project(project_id));

-- A teljes, sikeresen lekért forráslista egy tranzakcióban cseréli az aktív állapotot.
-- Javított munkalap: ugyanaz a forrás-UUID, felülírás; nem új elszámolás.
create table if not exists public.quote_work_sync_state (
 company_id uuid primary key references public.companies(id),
 read_started_at timestamptz not null
);
alter table public.quote_work_sync_state enable row level security;
revoke all on public.quote_work_sync_state from public,anon,authenticated;
grant all on public.quote_work_sync_state to service_role;
create or replace function public.quote_work_records_sync(p_company uuid,p_records jsonb,p_read_started_at timestamptz)
returns integer language plpgsql security invoker set search_path='' as $$
declare r jsonb; n integer:=0;
begin
  if current_user <> 'service_role' then raise exception 'Szerveroldali hozzáférés szükséges.' using errcode='42501'; end if;
  if p_company is null or jsonb_typeof(p_records) is distinct from 'array' then raise exception 'Érvénytelen munkalaplista.'; end if;
  if jsonb_array_length(p_records)>10000 then raise exception 'Túl nagy munkalaplista.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_company::text||':quote_work_records',0));
  if p_read_started_at is null or p_read_started_at>now()+interval '1 minute' then raise exception 'Érvénytelen lekérési időpont.'; end if;
  if exists(select 1 from public.quote_work_sync_state where company_id=p_company and read_started_at>p_read_started_at) then return 0; end if;
  for r in select value from jsonb_array_elements(p_records) loop
    if not exists(select 1 from public.quote_projects p join public.quote_clients c on c.id=p.client_id
       where p.id=(r->>'project_id')::uuid and c.company_id=p_company and p.started_on is not null
       and (r->>'work_date')::date>=p.started_on) then raise exception 'A projekt nem indult el, vagy nem elérhető.'; end if;
  end loop;
  update public.quote_work_records set active=false where company_id=p_company and active;
  for r in select value from jsonb_array_elements(p_records) loop
    insert into public.quote_work_records(company_id,source_id,project_id,work_date,source_updated_at,form_data,calculation)
    values(p_company,(r->>'source_id')::uuid,(r->>'project_id')::uuid,(r->>'work_date')::date,
      (r->>'source_updated_at')::timestamptz,r->'form_data',r->'calculation')
    on conflict(company_id,source_id) do update set project_id=excluded.project_id,work_date=excluded.work_date,
      source_updated_at=excluded.source_updated_at,form_data=excluded.form_data,calculation=excluded.calculation,
      active=true,synced_at=now()
    where excluded.source_updated_at>=public.quote_work_records.source_updated_at;
    -- Egy korábban átvett frissebb javítást nem írhat felül egy régi párhuzamos lekérés.
    update public.quote_work_records set active=true where company_id=p_company and source_id=(r->>'source_id')::uuid;
    n:=n+1;
  end loop;
  insert into public.quote_work_sync_state values(p_company,p_read_started_at)
    on conflict(company_id) do update set read_started_at=excluded.read_started_at;
  return n;
end $$;
revoke all on function public.quote_work_records_sync(uuid,jsonb,timestamptz) from public,anon,authenticated;
grant execute on function public.quote_work_records_sync(uuid,jsonb,timestamptz) to service_role;

create or replace function public.quote_project_work_summary(p_project uuid)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare versions uuid[]; budget numeric; records jsonb; items jsonb:='[]'::jsonb; settings jsonb:='[]'::jsonb;
begin
  if current_user<>'service_role' and not quote_private.can_project(p_project) then raise exception 'Nincs projekt-hozzáférés.' using errcode='42501'; end if;
  select array_agg(v.id) into versions from public.quote_versions v join public.quote_quotes q on q.id=v.quote_id
    where q.project_id=p_project and v.status='accepted';
  if cardinality(versions)=1 then
    select coalesce(sum(quantity1*case when nullif(unit2,'') is not null then coalesce(quantity2,0) else 1 end*labor_unit),0)
      into budget from public.quote_items where version_id=versions[1];
    select coalesce(jsonb_agg(to_jsonb(i) order by position),'[]'::jsonb) into items from public.quote_items i where version_id=versions[1];
    select coalesce(jsonb_agg(to_jsonb(s)),'[]'::jsonb) into settings from public.quote_work_progress s where version_id=versions[1];
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',source_id,'work_date',work_date,
    'updated_at',source_updated_at,'form_data',form_data,'calculation',calculation,'synced_at',synced_at)
    order by work_date,source_id),'[]'::jsonb) into records from public.quote_work_records where project_id=p_project and active;
  return jsonb_build_object('labor_budget',budget,'accepted_versions',coalesce(cardinality(versions),0),'records',records,'items',items,'settings',settings);
end $$;
revoke all on function public.quote_project_work_summary(uuid) from public,anon;
grant execute on function public.quote_project_work_summary(uuid) to authenticated,service_role;
notify pgrst,'reload schema';
commit;
