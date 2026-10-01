-- Quote-only project numbering. The original UUID remains the shared integration key.
lock table public.quote_projects in share row exclusive mode;
alter table public.quote_projects add column project_code text;
create table quote_private.project_number_counters(
 project_year integer primary key check(project_year between 1900 and 9999),
 last_number bigint not null check(last_number>0)
);
alter table quote_private.project_number_counters enable row level security;
revoke all on quote_private.project_number_counters from public,anon,authenticated;
create function quote_private.next_project_code(p_year integer) returns text
language plpgsql security definer set search_path='' as $$
declare n bigint;
begin
 insert into quote_private.project_number_counters(project_year,last_number) values(p_year,1)
 on conflict(project_year) do update set last_number=quote_private.project_number_counters.last_number+1
 returning last_number into n;
 return 'PR-'||p_year::text||'-'||lpad(n::text,greatest(4,length(n::text)),'0');
end $$;
revoke all on function quote_private.next_project_code(integer) from public,anon,authenticated;
do $backfill$
declare p record;
begin
 for p in select id,extract(year from created_at at time zone 'Europe/Budapest')::integer y
  from public.quote_projects order by created_at,id loop
  update public.quote_projects set project_code=quote_private.next_project_code(p.y) where id=p.id;
 end loop;
end $backfill$;
alter table public.quote_projects alter column project_code set not null;
alter table public.quote_projects add constraint quote_projects_code_unique unique(project_code);
alter table public.quote_projects add constraint quote_projects_code_format check(project_code ~ '^PR-[0-9]{4}-[0-9]{4,}$');
create function quote_private.assign_project_code() returns trigger
language plpgsql security definer set search_path='' as $$
declare existing_code text;
begin
 if TG_OP='INSERT' then
  select project_code into existing_code from public.quote_projects where id=new.id;
  if found then
   if new.project_code is not null and new.project_code<>existing_code then
    raise exception 'A projektszám nem módosítható.' using errcode='23514';
   end if;
   new.project_code=existing_code;
  else
   new.project_code=quote_private.next_project_code(extract(year from now() at time zone 'Europe/Budapest')::integer);
  end if;
 elsif new.id is distinct from old.id or new.project_code is distinct from old.project_code then
  raise exception 'A projektazonosító és a projektszám nem módosítható.' using errcode='23514';
 end if;
 return new;
end $$;
revoke all on function quote_private.assign_project_code() from public,anon,authenticated;
create trigger quote_projects_assign_code before insert or update of id,project_code on public.quote_projects
 for each row execute function quote_private.assign_project_code();
notify pgrst,'reload schema';
