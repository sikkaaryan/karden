create or replace function karden_private.karden_update_profile(p_display_name text, p_avatar text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_name text;
  v_avatar text;
  v_prefix text;
  v_object text;
begin
  if auth.uid() is null then raise exception 'Guest session required'; end if;
  v_name:=btrim(coalesce(p_display_name,''));
  v_avatar:=coalesce(p_avatar,'ace');
  if char_length(v_name) not between 1 and 24 then
    raise exception 'Name must be between 1 and 24 characters';
  end if;
  if char_length(v_avatar)>512 then raise exception 'Invalid avatar'; end if;
  if v_avatar not in ('ace','♠','♥','♦','♣','🦊','🐺','🦅','🐉','🦁','🦉') then
    v_prefix:='https://osqnoflarmkgwbrxtvwi.supabase.co/storage/v1/object/public/karden-avatars/'||auth.uid()::text||'/avatar';
    if v_avatar<>v_prefix or not exists(
      select 1 from storage.objects where bucket_id='karden-avatars' and name=auth.uid()::text||'/avatar'
    ) then raise exception 'Avatar must be a built-in symbol or your uploaded photo'; end if;
  end if;
  insert into public.karden_profiles(user_id,display_name,avatar)
  values(auth.uid(),v_name,v_avatar)
  on conflict(user_id) do update set display_name=excluded.display_name,avatar=excluded.avatar,updated_at=now();
  return karden_private.karden_my_profile();
end
$function$;
revoke all on function karden_private.karden_update_profile(text,text) from public, anon;
grant execute on function karden_private.karden_update_profile(text,text) to authenticated;

create or replace function public.karden_update_profile(p_display_name text, p_avatar text)
returns jsonb
language sql
set search_path to ''
as $function$ select karden_private.karden_update_profile($1,$2); $function$;
revoke all on function public.karden_update_profile(text,text) from public, anon;
grant execute on function public.karden_update_profile(text,text) to authenticated;