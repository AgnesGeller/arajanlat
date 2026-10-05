import { createClient } from 'npm:@supabase/supabase-js@2.58.0';
import webpush from 'npm:web-push@3.6.7';

const client = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {auth:{persistSession:false,autoRefreshToken:false}});
const json = (body: unknown, status=200) => new Response(JSON.stringify(body), {status,headers:{'Content-Type':'application/json'}});
const rpc = async (name: string,args={}) => {const {data,error}=await client.rpc(name,args);if(error)throw error;return data;};
const titles: Record<string,string> = {booked:'Új találkozófoglalás',cancelled:'Találkozó lemondva',reminder:'Találkozó 1 órán belül',phone:'Telefonos időpont-egyeztetés'};
const date = (value: string) => new Intl.DateTimeFormat('hu-HU',{dateStyle:'long',timeStyle:'short',timeZone:'Europe/Budapest'}).format(new Date(value));

Deno.serve(async request => {
 if(request.method!=='POST')return json({error:'Method not allowed'},405);
 const schedulerKey=request.headers.get('x-quote-scheduler-key');
 if(!schedulerKey||!/^[0-9a-f]{64}$/.test(schedulerKey))return json({error:'Unauthorized'},401);
 try {
  if(!await rpc('quote_notification_worker_auth',{p_secret:schedulerKey}))return json({error:'Unauthorized'},401);
  const generated=webpush.generateVAPIDKeys();
  const keys=await rpc('quote_notification_worker_keys',{p_public:generated.publicKey,p_private:generated.privateKey});
  const input=await request.json().catch(()=>({}));
  // A transport-free check never claims events or contacts a delivery provider.
  if(input.self_check===true){
   const receiver=webpush.generateVAPIDKeys();
   const auth=btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(16)))).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
   const encrypted=webpush.generateRequestDetails({endpoint:'https://fcm.googleapis.com/fcm/send/quote-self-check',keys:{p256dh:receiver.publicKey,auth}},'Árajánlat értesítési ellenőrzés',{vapidDetails:{subject:'mailto:info@diszkertek.hu',...keys}});
   return json({self_check:true,encryption_ok:encrypted.body.length>0,authorization_ok:Boolean(encrypted.headers.Authorization)});
  }
  const events=await rpc('quote_notification_claim');
  const apiKey=Deno.env.get('RESEND_API_KEY');
  let emails=0,pushes=0;
  for(const event of events){
   // Recheck after claiming: a cancellation invalidates the old reminder.
   const {data:current,error:currentError}=await client.from('quote_appointment_events').select('cancelled,expires_at').eq('id',event.id).single();
   if(currentError||current.cancelled||new Date(current.expires_at)<=new Date())continue;
   const {data:project,error:projectError}=await client.from('quote_projects').select('name,project_code').eq('id',event.project_id).single();
   if(projectError)throw projectError;
   let startsAt='';
   if(event.appointment_id){const {data:appointment,error}=await client.from('quote_appointments').select('slot:quote_appointment_slots(starts_at)').eq('id',event.appointment_id).single();if(error)throw error;startsAt=(appointment.slot as unknown as {starts_at:string}).starts_at;}
   const title=titles[event.kind];
   const body=`${project.project_code} – ${project.name}${startsAt?'\nIdőpont: '+date(startsAt):''}`;
   const patch: Record<string,unknown>={lease_until:null,next_attempt_at:new Date(Date.now()+5*60_000).toISOString(),last_error:null};
   const errors: string[]=[];
   if(!event.email_sent_at){
    if(!apiKey)errors.push('Az automatikus emailküldés nincs beállítva.');
    else try {
     const response=await fetch('https://api.resend.com/emails',{method:'POST',redirect:'error',headers:{Authorization:`Bearer ${apiKey}`,'Content-Type':'application/json','Idempotency-Key':`quote-appointment-${event.id}`},body:JSON.stringify({from:Deno.env.get('QUOTE_EMAIL_FROM')||'Díszkertek <ertesites@diszkertek.hu>',to:['info@diszkertek.hu'],subject:`Díszkertek – ${title}`,text:`${title}\n\n${body}\n\nMegnyitás: https://agnesgeller.github.io/arajanlat/index.html`}),signal:AbortSignal.timeout(10000)});
     if(!response.ok)throw Error(`Email HTTP ${response.status}`);
     patch.email_sent_at=new Date().toISOString();emails++;
    }catch {errors.push('Az emailküldés nem sikerült; újrapróbáljuk.');}
   }
   if(!event.push_done_at){
    const {data:staff,error:staffError}=await client.from('quote_staff').select('user_id').eq('company_id',event.company_id);
    if(staffError)throw staffError;
    const {data:subscriptions,error:subscriptionError}=await client.from('quote_push_subscriptions').select('*').eq('company_id',event.company_id).eq('disabled',false).in('user_id',staff.map(s=>s.user_id));
    if(subscriptionError)throw subscriptionError;
    let failed=false;
    for(const subscription of subscriptions){
     if(await rpc('quote_push_delivery_done',{p_event:event.id,p_subscription:subscription.id}))continue;
     try {
      // Native fetch handles transport; the pinned library handles Web Push encryption.
      const details=webpush.generateRequestDetails({endpoint:subscription.endpoint,keys:subscription.keys},JSON.stringify({title,body,tag:`quote-${event.id}`,url:'/arajanlat/index.html'}),{vapidDetails:{subject:'mailto:info@diszkertek.hu',...keys},TTL:Math.max(0,Math.min(3600,Math.floor((new Date(event.expires_at).getTime()-Date.now())/1000))),urgency:'high'});
      const response=await fetch(details.endpoint,{method:details.method,redirect:'error',headers:details.headers,body:details.body,signal:AbortSignal.timeout(8000)});
      if(response.status===404||response.status===410){const {error}=await client.from('quote_push_subscriptions').update({disabled:true}).eq('id',subscription.id);if(error)throw error;continue;}
      if(!response.ok)throw Error(`Push HTTP ${response.status}`);
      await rpc('quote_push_delivery_mark',{p_event:event.id,p_subscription:subscription.id});pushes++;
     }catch{failed=true;}
    }
    if(!failed)patch.push_done_at=new Date().toISOString();else errors.push('Egy eszköz értesítése nem sikerült; újrapróbáljuk.');
   }
   patch.last_error=errors.join(' ')||null;
   const {error}=await client.from('quote_appointment_events').update(patch).eq('id',event.id);if(error)throw error;
  }
  return json({processed:events.length,emails,pushes,email_configured:Boolean(apiKey)});
 }catch {console.error('quote_appointment_notify_failed');return json({error:'Notification processing failed'},500);}
});
