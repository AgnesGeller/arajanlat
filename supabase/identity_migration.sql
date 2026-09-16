-- The public link remains the primary secret. Every public operation also verifies one customer identifier.
alter table public.quote_plants add column if not exists sale_price_placeholder boolean not null default false;
update public.quote_plants set sale_net=1, sale_price_placeholder=true where sale_net is null;

create or replace function quote_private.normalize_phone(raw text) returns text
language sql immutable set search_path = '' as $$
 with digits as (select regexp_replace(coalesce(raw,''),'[^0-9]','','g') as value)
 select case when left(value,2)='00' then substring(value from 3)
             when left(value,2)='06' then '36'||substring(value from 3)
             when length(value) in (8,9) then '36'||value
             else value end from digits
$$;
revoke all on function quote_private.normalize_phone(text) from public;

create or replace function quote_private.public_identity_matches(p_project_id uuid,p_identity_type text,p_identity_value text)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare customer_name text; contact_name text; customer_email text; customer_phone text; normalized text;
begin
 if p_identity_type is null or p_identity_type not in ('name','email','phone') or length(coalesce(p_identity_value,''))>254 then return false; end if;
 select c.name,c.contact_name,c.email,c.phone into customer_name,contact_name,customer_email,customer_phone
 from public.quote_projects p join public.clients c on c.id=p.client_id where p.id=p_project_id;
 if not found then return false; end if;
 if p_identity_type='name' then
  normalized=lower(regexp_replace(btrim(coalesce(p_identity_value,'')),'[[:space:]]+',' ','g'));
  return length(normalized)>=2 and (normalized=lower(regexp_replace(btrim(coalesce(customer_name,'')),'[[:space:]]+',' ','g'))
    or normalized=lower(regexp_replace(btrim(coalesce(contact_name,'')),'[[:space:]]+',' ','g')));
 elsif p_identity_type='email' then
  normalized=lower(btrim(coalesce(p_identity_value,'')));
  return length(normalized)>=3 and normalized=lower(btrim(coalesce(customer_email,'')));
 else
  normalized=quote_private.normalize_phone(p_identity_value);
  return length(normalized)>=8 and normalized=quote_private.normalize_phone(customer_phone);
 end if;
end $$;
revoke all on function quote_private.public_identity_matches(uuid,text,text) from public;

-- Remove the token-only RPC signatures so they cannot bypass the additional check.
drop function if exists public.quote_public_read(text);
drop function if exists public.quote_public_submit(text,jsonb);
drop function if exists public.quote_public_decide(text,text,text,text,boolean);

create or replace function public.quote_public_read(p_token text,p_identity_type text,p_identity_value text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare tok public.quote_public_tokens%rowtype; result jsonb;
begin
 if length(coalesce(p_token,''))<>64 or p_token !~ '^[0-9a-f]{64}$' then return null; end if;
 select * into tok from public.quote_public_tokens
 where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and revoked_at is null and expires_at>now();
 if not found or not quote_private.public_identity_matches(tok.project_id,p_identity_type,p_identity_value) then return null; end if;
 if tok.purpose='request' then
  select jsonb_build_object('purpose','request','project',p.name,'work_address',p.work_address)
  into result from public.quote_projects p where p.id=tok.project_id;
 else
  select v.published_snapshot into result from public.quote_versions v
  where v.id=tok.version_id and v.status in ('published','accepted','rejected');
 end if;
 return result;
end $$;

create or replace function public.quote_public_submit(p_token text,p_identity_type text,p_identity_value text,p_answers jsonb)
returns boolean language plpgsql security definer set search_path = '' as $$
declare tok public.quote_public_tokens%rowtype;
begin
 if length(coalesce(p_token,''))<>64 or p_token !~ '^[0-9a-f]{64}$' or jsonb_typeof(p_answers)<>'object' or octet_length(p_answers::text)>20000 then return false; end if;
 select * into tok from public.quote_public_tokens where token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
 and purpose='request' and revoked_at is null and expires_at>now() for update;
 if not found or not quote_private.public_identity_matches(tok.project_id,p_identity_type,p_identity_value) then return false; end if;
 insert into public.quote_client_requests(project_id,answers) values(tok.project_id,p_answers);
 insert into public.quote_timeline(project_id,event) values(tok.project_id,'Ügyfél adatbekérő visszaérkezett');
 update public.quote_projects set status='Ügyfél kitöltötte' where id=tok.project_id;
 update public.quote_public_tokens set revoked_at=now() where id=tok.id;
 return true;
end $$;

create or replace function public.quote_public_decide(p_token text,p_identity_type text,p_identity_value text,p_decision text,p_name text,p_note text,p_confirm boolean)
returns boolean language plpgsql security definer set search_path = '' as $$
declare tok public.quote_public_tokens%rowtype; current_status text;
begin
 if length(coalesce(p_token,''))<>64 or p_token !~ '^[0-9a-f]{64}$' or p_decision not in ('accepted','change','rejected') or length(trim(coalesce(p_name,'')))<2 or length(coalesce(p_note,''))>2000 then return false; end if;
 if p_decision='accepted' and p_confirm is not true then return false; end if;
 select * into tok from public.quote_public_tokens where token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
 and purpose='offer' and revoked_at is null and expires_at>now() for update;
 if not found or not quote_private.public_identity_matches(tok.project_id,p_identity_type,p_identity_value) then return false; end if;
 select status into current_status from public.quote_versions where id=tok.version_id for update;
 if current_status<>'published' then return false; end if;
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

revoke all on function public.quote_public_read(text,text,text) from public;
revoke all on function public.quote_public_submit(text,text,text,jsonb) from public;
revoke all on function public.quote_public_decide(text,text,text,text,text,text,boolean) from public;
grant execute on function public.quote_public_read(text,text,text) to anon,authenticated;
grant execute on function public.quote_public_submit(text,text,text,jsonb) to anon,authenticated;
grant execute on function public.quote_public_decide(text,text,text,text,text,text,boolean) to anon,authenticated;
