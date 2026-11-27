-- Track player liveness without exposing direct table writes to clients.
alter table public.karden_players
  add column if not exists last_seen_at timestamptz not null default now();

create or replace function karden_private.broadcast_player_connection_refresh()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.connected is distinct from old.connected then
    perform realtime.send(
      jsonb_build_object('refresh',true,'player_id',new.id,'connected',new.connected),
      'state_changed',
      'room:'||new.room_id::text,
      true
    );
  end if;
  return new;
end
$function$;
revoke all on function karden_private.broadcast_player_connection_refresh() from public, anon, authenticated;

drop trigger if exists karden_player_connection_broadcast on public.karden_players;
create trigger karden_player_connection_broadcast
after update of connected on public.karden_players
for each row execute function karden_private.broadcast_player_connection_refresh();

create or replace function karden_private.karden_heartbeat(p_code text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare v_room public.karden_rooms; v_player public.karden_players; v_stale integer;
begin
  if auth.uid() is null then raise exception 'Guest session required'; end if;
  select * into v_room from public.karden_rooms where code=upper(trim(p_code));
  if not found then raise exception 'Room not found'; end if;
  select * into v_player from public.karden_players
  where room_id=v_room.id and user_id=auth.uid();
  if not found then raise exception 'You are not a member of this room'; end if;

  update public.karden_players
  set connected=false
  where room_id=v_room.id and id<>v_player.id and connected=true
    and not eliminated and last_seen_at < now()-interval '45 seconds';

  if not v_player.eliminated then
    update public.karden_players
    set connected=true,last_seen_at=now()
    where id=v_player.id;
  end if;

  select count(*) into v_stale from public.karden_players
  where room_id=v_room.id and not eliminated and not connected;
  return jsonb_build_object('alive',not v_player.eliminated,'disconnectedPlayers',v_stale);
end
$function$;
revoke all on function karden_private.karden_heartbeat(text) from public, anon;
grant execute on function karden_private.karden_heartbeat(text) to authenticated;

create or replace function public.karden_heartbeat(p_code text)
returns jsonb
language sql
set search_path to ''
as $function$ select karden_private.karden_heartbeat($1); $function$;
revoke all on function public.karden_heartbeat(text) from public, anon;
grant execute on function public.karden_heartbeat(text) to authenticated;
