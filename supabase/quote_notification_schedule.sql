-- Only this named quotation job is added; no existing jobs are changed.
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;
do $$ begin
 if not exists(select 1 from vault.secrets where name='quote_notification_scheduler_key') then
  perform vault.create_secret(encode(extensions.gen_random_bytes(32),'hex'),'quote_notification_scheduler_key');
 end if;
end $$;
select cron.schedule('quote-appointment-notifications','* * * * *', $job$
 select net.http_post(
  url:='https://cszsxjsiwaaibrocibyd.supabase.co/functions/v1/quote-appointment-notify',
  headers:=jsonb_build_object('Content-Type','application/json','x-quote-scheduler-key',
    (select decrypted_secret from vault.decrypted_secrets where name='quote_notification_scheduler_key')),
  body:='{}'::jsonb,timeout_milliseconds:=55000
 );
$job$);
