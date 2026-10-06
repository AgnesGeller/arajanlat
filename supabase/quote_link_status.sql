-- Status only after the existing token-bound customer identity check.
create or replace function public.quote_public_link_status(p_token text,p_identity_type text,p_identity_value text)
returns text language plpgsql security definer set search_path='' as $$
declare tok public.quote_public_tokens%rowtype;
begin
 if length(coalesce(p_token,''))<>64 or p_token !~ '^[0-9a-f]{64}$' then return 'unavailable'; end if;
 select * into tok from public.quote_public_tokens where token_hash=encode(extensions.digest(p_token,'sha256'),'hex');
 if not found or not quote_private.public_identity_matches(tok.project_id,p_identity_type,p_identity_value) then return 'unavailable'; end if;
 if tok.revoked_at is not null then return 'used'; end if;
 if tok.expires_at<=now() then return 'expired'; end if;
 return 'active';
end $$;
revoke all on function public.quote_public_link_status(text,text,text) from public;
grant execute on function public.quote_public_link_status(text,text,text) to anon,authenticated;
notify pgrst,'reload schema';
