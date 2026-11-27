-- Prevent arbitrary remote URLs in avatar fields. Photo URLs must point to an
-- uploaded object in this player's own folder in the KARDEN avatar bucket.
create or replace function karden_private.validate_player_avatar()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare
  v_prefix text;
  v_object_name text;
begin
  if new.avatar is null or char_length(new.avatar) > 512 then
    raise exception 'Invalid avatar';
  end if;

  if new.avatar in ('ace','♠','♥','♦','♣','🦊','🐺','🦅','🐉','🦁','🦉') then
    return new;
  end if;

  v_prefix := 'https://osqnoflarmkgwbrxtvwi.supabase.co/storage/v1/object/public/karden-avatars/' || new.user_id::text || '/';
  if left(new.avatar, char_length(v_prefix)) <> v_prefix then
    raise exception 'Avatar must be a built-in symbol or your own uploaded photo';
  end if;

  v_object_name := substring(new.avatar from char_length(v_prefix) + 1);
  if v_object_name = '' or position('..' in v_object_name) > 0
     or not exists (
       select 1 from storage.objects
       where bucket_id='karden-avatars'
         and name=new.user_id::text || '/' || v_object_name
     ) then
    raise exception 'Uploaded avatar was not found';
  end if;

  return new;
end
$function$;
revoke all on function karden_private.validate_player_avatar() from public, anon, authenticated;

drop trigger if exists karden_validate_player_avatar on public.karden_players;
create trigger karden_validate_player_avatar
before insert or update of avatar on public.karden_players
for each row execute function karden_private.validate_player_avatar();
