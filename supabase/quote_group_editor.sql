-- Quote-only editor helpers. Existing Auth, client sources and other applications are unchanged.
begin;
create or replace function public.quote_template_save(p_id uuid,p_name text,p_items jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare t public.quote_templates; entry jsonb; n integer:=0; c public.quote_price_catalog;
begin
 if quote_private.staff_company() is null then raise exception 'Nincs árajánlatkészítői hozzáférés.'; end if;
 if coalesce(length(btrim(p_name)),0)=0 or length(p_name)>200 or jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items)<1 or jsonb_array_length(p_items)>200 then raise exception 'Ellenőrizd a munkasablon nevét és tételeit.'; end if;
 if p_id is null then insert into public.quote_templates(name) values(btrim(p_name)) returning * into t;
 else
  select * into t from public.quote_templates where id=p_id for update;
  if not found then raise exception 'A munkasablon nem elérhető.'; end if;
  update public.quote_templates set name=btrim(p_name) where id=p_id returning * into t;
 end if;
 delete from public.quote_template_items where template_id=t.id;
 for entry in select value from jsonb_array_elements(p_items) loop
  select * into c from public.quote_price_catalog where id=nullif(entry->>'catalog_id','')::uuid and active;
  if not found then raise exception 'Egy kiválasztott árlistatétel már nem elérhető. Válassz másikat.'; end if;
  n:=n+1;insert into public.quote_template_items(template_id,position,catalog_id,category,subcategory) values(t.id,n,c.id,c.category,c.subcategory);
 end loop;
 return to_jsonb(t);
end $$;
revoke all on function public.quote_template_save(uuid,text,jsonb) from public,anon;
grant execute on function public.quote_template_save(uuid,text,jsonb) to authenticated;

create or replace function public.quote_group_editor(p_quote uuid)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare d public.quote_quick_drafts; q public.quote_quotes; v public.quote_versions; p public.quote_projects; c public.quote_clients; payload jsonb;
begin
 if quote_private.staff_company() is null then raise exception 'Nincs árajánlatkészítői hozzáférés.'; end if;
 if p_quote is null then raise exception 'Válassz ajánlatot.'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_quote::text,0));
 select * into q from public.quote_quotes where id=p_quote;
 if not found then raise exception 'Az ajánlat nem elérhető.'; end if;
 select * into d from public.quote_quick_drafts where promoted_quote_id=p_quote limit 1;
 if found then d:=quote_private.refresh_quick(d.id);return to_jsonb(d);end if;
 select * into v from public.quote_versions where quote_id=q.id order by created_at desc,id desc limit 1;
 if not found then raise exception 'Az ajánlatváltozat nem elérhető.'; end if;
 select * into p from public.quote_projects where id=q.project_id;
 select * into c from public.quote_clients where id=p.client_id;
 payload:=jsonb_build_object('client_id',p.client_id,'customer',jsonb_build_object('name',c.name,'email',coalesce(c.email,''),'phone',coalesce(c.phone,'')),'address',coalesce(p.work_address,''),'title',coalesce(q.title,''),'terms',coalesce(q.terms,''),'valid_until',coalesce(q.valid_until::text,''),'issued_on',(now() at time zone 'Europe/Budapest')::date,'groups','[]'::jsonb,'issuer',jsonb_build_object('name','Díszkertek','email','info@diszkertek.hu','phone','+36 70 634 9630'),'linked_version_id',v.id,'linked_status',v.status,'items',coalesce((select jsonb_agg((to_jsonb(i)-'created_at'-'updated_at'-'version_id'-'position')||jsonb_build_object('full_item_id',i.id,'main_item','','measurement',jsonb_build_object('mode','quantity','quantity',i.quantity1)) order by i.position,i.id) from public.quote_items i where i.version_id=v.id),'[]'::jsonb));
 insert into public.quote_quick_drafts(number,payload) values(q.number,payload) returning * into d;
 update public.quote_quick_drafts set promoted_quote_id=q.id where id=d.id returning * into d;
 return to_jsonb(d);
end $$;
revoke all on function public.quote_group_editor(uuid) from public,anon;
grant execute on function public.quote_group_editor(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
