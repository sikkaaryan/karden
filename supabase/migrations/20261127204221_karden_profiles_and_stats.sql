-- Persistent guest profiles and match statistics.
create table if not exists public.karden_profiles (
  user_id uuid primary key,
  display_name text not null default 'Player',
  avatar text not null default 'ace',
  games_played integer not null default 0,
  wins integer not null default 0,
  losses integer not null default 0,
  draws integer not null default 0,
  updated_at timestamptz not null default now(),
  constraint karden_profile_stats_nonnegative check (
    games_played >= 0 and wins >= 0 and losses >= 0 and draws >= 0
  )
);
alter table public.karden_profiles enable row level security;
revoke all on public.karden_profiles from anon, authenticated;

create or replace function karden_private.sync_profile_from_player()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  insert into public.karden_profiles(user_id, display_name, avatar)
  values(new.user_id, new.display_name, new.avatar)
  on conflict(user_id) do update
    set display_name=excluded.display_name,
        avatar=excluded.avatar,
        updated_at=now();
  return new;
end
$function$;
revoke all on function karden_private.sync_profile_from_player() from public, anon, authenticated;

drop trigger if exists karden_sync_profile_from_player on public.karden_players;
create trigger karden_sync_profile_from_player
after insert or update of display_name, avatar on public.karden_players
for each row execute function karden_private.sync_profile_from_player();

create or replace function karden_private.record_completed_game_stats()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_state jsonb;
  v_survivors integer;
  v_winner uuid;
  v_player record;
begin
  if new.status <> 'finished' or old.status = 'finished' then
    return new;
  end if;

  select state into v_state
  from karden_private.room_state
  where room_id=new.id
  for update;

  if coalesce(v_state->>'lastAction','') = 'The host ended the room'
     or coalesce(v_state->>'statsRecorded','false') = 'true' then
    return new;
  end if;

  select count(*) into v_survivors
  from public.karden_players
  where room_id=new.id and not eliminated;

  select id into v_winner
  from public.karden_players
  where room_id=new.id and not eliminated
  order by seat
  limit 1;

  for v_player in
    select user_id, display_name, avatar, id, eliminated
    from public.karden_players
    where room_id=new.id
  loop
    insert into public.karden_profiles(
      user_id, display_name, avatar, games_played, wins, losses, draws
    )
    values (
      v_player.user_id, v_player.display_name, v_player.avatar, 1,
      case when v_survivors=1 and v_player.id=v_winner then 1 else 0 end,
      case when v_survivors=1 and v_player.eliminated then 1 else 0 end,
      case when v_survivors=0 then 1 else 0 end
    )
    on conflict(user_id) do update set
      display_name=excluded.display_name,
      avatar=excluded.avatar,
      games_played=public.karden_profiles.games_played+1,
      wins=public.karden_profiles.wins+excluded.wins,
      losses=public.karden_profiles.losses+excluded.losses,
      draws=public.karden_profiles.draws+excluded.draws,
      updated_at=now();
  end loop;

  update karden_private.room_state
  set state=jsonb_set(coalesce(state,'{}'::jsonb),'{statsRecorded}','true'::jsonb),
      updated_at=now()
  where room_id=new.id;

  return new;
end
$function$;
revoke all on function karden_private.record_completed_game_stats() from public, anon, authenticated;

drop trigger if exists karden_record_completed_game_stats on public.karden_rooms;
create trigger karden_record_completed_game_stats
after update of status on public.karden_rooms
for each row execute function karden_private.record_completed_game_stats();

create or replace function karden_private.karden_my_profile()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare v_profile public.karden_profiles;
begin
  if auth.uid() is null then raise exception 'Guest session required'; end if;
  select * into v_profile from public.karden_profiles where user_id=auth.uid();
  if not found then
    return jsonb_build_object(
      'displayName','Player','avatar','ace',
      'gamesPlayed',0,'wins',0,'losses',0,'draws',0
    );
  end if;
  return jsonb_build_object(
    'displayName',v_profile.display_name,'avatar',v_profile.avatar,
    'gamesPlayed',v_profile.games_played,'wins',v_profile.wins,
    'losses',v_profile.losses,'draws',v_profile.draws
  );
end
$function$;
revoke all on function karden_private.karden_my_profile() from public, anon;
grant execute on function karden_private.karden_my_profile() to authenticated;

create or replace function public.karden_my_profile()
returns jsonb
language sql
set search_path to ''
as $function$ select karden_private.karden_my_profile(); $function$;
revoke all on function public.karden_my_profile() from public, anon;
grant execute on function public.karden_my_profile() to authenticated;
