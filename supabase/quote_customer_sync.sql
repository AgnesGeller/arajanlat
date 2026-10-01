-- Queue only newly created quote customers for insert-only shared publishing.
create table public.quote_customer_sync (
 client_id uuid primary key references public.quote_clients(id) on delete cascade,
 created_at timestamptz not null default now(),
 synced_at timestamptz,
 last_attempt_at timestamptz,
 last_error text
);
alter table public.quote_customer_sync enable row level security;
revoke all on public.quote_customer_sync from anon, authenticated;
grant select on public.quote_customer_sync to authenticated;
grant all on public.quote_customer_sync, public.quote_clients to service_role;
create policy quote_customer_sync_staff_read on public.quote_customer_sync for select to authenticated
using (quote_private.can_client(client_id));
create or replace function quote_private.queue_new_customer()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.quote_customer_sync(client_id) values(new.id);
 return new;
end $$;
revoke all on function quote_private.queue_new_customer() from public,anon,authenticated;
create trigger quote_clients_queue after insert on public.quote_clients
for each row execute function quote_private.queue_new_customer();
notify pgrst,'reload schema';
