begin;

do $$
declare imported integer; earth jsonb; spray jsonb;
begin
 select count(*) into imported from public.quote_price_catalog where source='Munkalap árlista' and active;
 if imported<>47 then raise exception 'A Munkalap árlista elemszáma hibás: %',imported; end if;

 select calculation_rule into earth from public.quote_price_catalog where source='Munkalap árlista' and subcategory='Földelszállítás';
 if earth<>jsonb_build_object('type','fixed_plus_unit','unit_price',8000,'fixed',10000) then
  raise exception 'A földelszállítás számítási szabálya hibás: %',earth;
 end if;

 select calculation_rule into spray from public.quote_price_catalog where source='Munkalap árlista' and subcategory='Növényvédelem';
 if spray<>jsonb_build_object('type','tiered','first',25000,'middle',17000,'middle_count',3,'later',12000) then
  raise exception 'A növényvédelem sávos szabálya hibás: %',spray;
 end if;

 if exists(select 1 from public.quote_price_catalog where source='Munkalap árlista' and pricing_required and material_unit<>1) then
  raise exception 'Az ismeretlen Munkalap-ár nem 1 Ft jelzőárral szerepel.';
 end if;
end $$;

rollback;
