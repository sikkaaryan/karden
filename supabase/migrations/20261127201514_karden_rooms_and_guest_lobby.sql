-- KARDEN fresh-project baseline snapshot.
-- This file creates the complete current schema and all game RPCs.
create schema if not exists karden_private;
create table public.karden_rooms (
 id uuid primary key default gen_random_uuid(), code text not null unique, host_id uuid not null,
 status text not null default 'lobby' check(status in ('lobby','playing','paused','finished')),
 config jsonb not null, round_number integer not null default 0, current_player_id uuid,
 turn_deadline timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 remaining_seconds integer
);
create table public.karden_players (
 id uuid primary key default gen_random_uuid(), room_id uuid not null references public.karden_rooms(id) on delete cascade,
 user_id uuid not null, display_name text not null check(char_length(display_name) between 1 and 24),
 avatar text not null default 'ace', seat integer not null, cumulative_score integer not null default 0,
 eliminated boolean not null default false, connected boolean not null default true, joined_at timestamptz not null default now(),
 unique(room_id,user_id), unique(room_id,seat)
);
create table karden_private.room_state (
 room_id uuid primary key references public.karden_rooms(id) on delete cascade,
 state jsonb not null default '{}'::jsonb, updated_at timestamptz not null default now()
);
alter table public.karden_rooms enable row level security;
alter table public.karden_players enable row level security;
alter table karden_private.room_state enable row level security;
revoke all on public.karden_rooms,public.karden_players from anon,authenticated;
revoke all on karden_private.room_state from anon,authenticated;
revoke all on schema karden_private from public,anon;
grant usage on schema karden_private to authenticated;

CREATE OR REPLACE FUNCTION karden_private.karden_call(p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_room public.karden_rooms; v_me public.karden_players; v_state jsonb; v_caller_total integer;
 v_burst boolean; v_starter uuid; v_penalty integer; v_result jsonb; v_entry jsonb;
 v_pid uuid; v_total integer; v_added integer; v_scores jsonb:='[]'::jsonb; v_survivors integer;
begin
 if auth.uid() is null then raise exception 'Guest session required'; end if;
 select * into v_room from public.karden_rooms where code=upper(trim(p_code)) for update;
 if not found or v_room.status<>'playing' then raise exception 'Game is not active'; end if;
 select * into v_me from public.karden_players where room_id=v_room.id and user_id=auth.uid() and not eliminated;
 if not found or v_me.id<>v_room.current_player_id then raise exception 'It is not your turn'; end if;
  if v_room.turn_deadline is not null and now()>=v_room.turn_deadline then raise exception 'Turn has expired'; end if;
 select state into v_state from karden_private.room_state where room_id=v_room.id for update;
 if coalesce(v_state->>'phase','playing')<>'playing' or v_state->>'pendingBy' is not null then raise exception 'You cannot call now'; end if;
 select coalesce((x.value->>'total')::integer,0) into v_caller_total from jsonb_array_elements(v_state->'players') x(value) where x.value->>'playerId'=v_me.id::text;
 if v_caller_total >= (v_room.config->>'callThreshold')::integer then raise exception 'Your hand must be strictly below the call threshold'; end if;
 select exists(select 1 from jsonb_array_elements(v_state->'players') x(value) where x.value->>'playerId'<>v_me.id::text and (x.value->>'total')::integer<=v_caller_total) into v_burst;
 v_penalty:=case when v_burst then (v_room.config->>'burstPenalty')::integer else 0 end;
 for v_entry in select value from jsonb_array_elements(v_state->'players') loop
   v_pid:=(v_entry->>'playerId')::uuid; v_total:=(v_entry->>'total')::integer;
   v_added:=case when v_pid=v_me.id then case when v_burst then v_total+v_penalty else 0 end else v_total end;
   update public.karden_players set cumulative_score=cumulative_score+v_added,eliminated=(cumulative_score+v_added)>=(v_room.config->>'maxScore')::integer where id=v_pid;
   v_scores:=v_scores||jsonb_build_array(jsonb_build_object('playerId',v_pid,'handTotal',v_total,'added',v_added,'cards',v_entry->'hand'));
 end loop;
 select count(*) into v_survivors from public.karden_players where room_id=v_room.id and not eliminated;
 if v_survivors=0 then v_starter:=null;
 elsif v_burst then
   select p.id into v_starter from public.karden_players p join jsonb_array_elements(v_state->'players') x(value) on x.value->>'playerId'=p.id::text
   where p.room_id=v_room.id and not p.eliminated and (x.value->>'total')::integer<=v_caller_total
   order by (x.value->>'total')::integer,random() limit 1;
   if v_starter is null then select id into v_starter from public.karden_players where room_id=v_room.id and not eliminated order by random() limit 1; end if;
 else
   select id into v_starter from public.karden_players where id=v_me.id and not eliminated;
   if v_starter is null then select id into v_starter from public.karden_players where room_id=v_room.id and not eliminated order by random() limit 1; end if;
 end if;
 v_result:=jsonb_build_object('callerId',v_me.id,'callerName',v_me.display_name,'callerTotal',v_caller_total,'burst',v_burst,
 'burstPenalty',v_penalty,'scores',v_scores,'nextStarterId',v_starter,
 'winnerId',case when v_survivors=1 then (select id from public.karden_players where room_id=v_room.id and not eliminated limit 1) else null end,'tie',v_survivors=0);
 v_state:=jsonb_set(v_state,'{phase}',to_jsonb('round_result'::text));
 v_state:=jsonb_set(v_state,'{roundResult}',v_result);
 v_state:=jsonb_set(v_state,'{lastAction}',to_jsonb(v_me.display_name||' called'));
 update karden_private.room_state set state=v_state,updated_at=now() where room_id=v_room.id;
 update public.karden_rooms set status=case when v_survivors<=1 then 'finished' else status end,current_player_id=v_starter,turn_deadline=null,updated_at=now() where id=v_room.id;
 return v_result;
end $function$
;
revoke all on function karden_private.karden_call(text) from public,anon;
grant execute on function karden_private.karden_call(text) to authenticated;
CREATE OR REPLACE FUNCTION karden_private.karden_create_room(p_name text, p_avatar text, p_config jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid(); v_room public.karden_rooms; v_player public.karden_players; v_code text;
 v_max_players integer:=coalesce((p_config->>'maxPlayers')::integer,4);
begin
 if v_uid is null then raise exception 'Guest session required'; end if;
 if char_length(trim(p_name)) not between 1 and 24 then raise exception 'Name must be 1–24 characters'; end if;
 if v_max_players not between 2 and 8 then raise exception 'Players must be between 2 and 8'; end if;
 if coalesce((p_config->>'initialCards')::integer,5) not between 1 and 10
 or coalesce((p_config->>'decks')::integer,1) not between 1 and 4
 or coalesce((p_config->>'maxScore')::integer,150) not between 20 and 500
 or coalesce((p_config->>'burstPenalty')::integer,20) not between 0 and 100
 or coalesce((p_config->>'callThreshold')::integer,10) not between 1 and 100
 or coalesce((p_config->>'turnSeconds')::integer,60) not between 15 and 180
 then raise exception 'Invalid room settings'; end if;
 if coalesce(p_config->>'jokerRank','J') not in ('A','2','3','4','5','6','7','8','9','10','J','Q','K') then raise exception 'Invalid Joker rank'; end if;
 loop
   v_code:=upper(substr(md5(random()::text||clock_timestamp()::text),1,6));
   exit when not exists(select 1 from public.karden_rooms where code=v_code);
 end loop;
 insert into public.karden_rooms(code,host_id,config) values(v_code,v_uid,
 jsonb_build_object('maxPlayers',v_max_players,'initialCards',coalesce((p_config->>'initialCards')::integer,5),
 'decks',coalesce((p_config->>'decks')::integer,1),'maxScore',coalesce((p_config->>'maxScore')::integer,150),
 'burstPenalty',coalesce((p_config->>'burstPenalty')::integer,20),'callThreshold',coalesce((p_config->>'callThreshold')::integer,10),
 'turnSeconds',coalesce((p_config->>'turnSeconds')::integer,60),'jokerRank',coalesce(p_config->>'jokerRank','J'))) returning * into v_room;
 insert into public.karden_players(room_id,user_id,display_name,avatar,seat) values(v_room.id,v_uid,trim(p_name),coalesce(nullif(p_avatar,''),'ace'),1) returning * into v_player;
 insert into karden_private.room_state(room_id,state) values(v_room.id,jsonb_build_object('players',jsonb_build_array(jsonb_build_object('playerId',v_player.id,'hand','[]'::jsonb,'total',0)),'drawPile','[]'::jsonb,'discardPile','[]'::jsonb,'callerId',null,'lastAction',null));
 return jsonb_build_object('roomId',v_room.id,'code',v_room.code,'playerId',v_player.id);
end $function$
;
revoke all on function karden_private.karden_create_room(text,text,jsonb) from public,anon;
grant execute on function karden_private.karden_create_room(text,text,jsonb) to authenticated;
CREATE OR REPLACE FUNCTION karden_private.karden_discard_cards(p_code text, p_card_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_room public.karden_rooms;
  v_me public.karden_players;
  v_state jsonb;
  v_players jsonb;
  v_hand jsonb;
  v_new_hand jsonb := '[]'::jsonb;
  v_discard jsonb;
  v_pending jsonb;
  v_rank text;
  v_card jsonb;
  v_item jsonb;
  v_idx integer;
  v_next uuid;
  v_seat integer;
begin
  if auth.uid() is null then raise exception 'Guest session required'; end if;
  if coalesce(array_length(p_card_ids,1),0)<1 then raise exception 'Discard at least one card'; end if;
  select * into v_room from public.karden_rooms where code=upper(trim(p_code)) for update;
  if not found or v_room.status<>'playing' then raise exception 'Game is not active'; end if;
  select * into v_me from public.karden_players where room_id=v_room.id and user_id=auth.uid() and not eliminated;
  if not found or v_me.id<>v_room.current_player_id then raise exception 'It is not your turn'; end if;
  if v_room.turn_deadline is not null and now()>=v_room.turn_deadline then raise exception 'Turn has expired'; end if;
  select state into v_state from karden_private.room_state where room_id=v_room.id for update;
  if v_state->>'pendingBy' is distinct from v_me.id::text then raise exception 'Pick a card before discarding'; end if;
  v_players:=v_state->'players';
  select p.value->'hand' into v_hand from jsonb_array_elements(v_players) p(value) where p.value->>'playerId'=v_me.id::text;
  if cardinality(p_card_ids)<>(select count(distinct x) from unnest(p_card_ids) x) then raise exception 'Duplicate card selection'; end if;
  for v_idx in 0..jsonb_array_length(v_hand)-1 loop
    v_card:=v_hand->v_idx;
    if (v_card->>'id')::uuid=any(p_card_ids) then
      if v_rank is null then v_rank:=v_card->>'rank'; elsif v_rank<>v_card->>'rank' then raise exception 'Discarded cards must have the same rank'; end if;
      v_discard:=coalesce(v_discard,'[]'::jsonb)||jsonb_build_array(v_card);
    else v_new_hand:=v_new_hand||jsonb_build_array(v_card); end if;
  end loop;
  if jsonb_array_length(coalesce(v_discard,'[]'::jsonb))<>cardinality(p_card_ids) then raise exception 'Selected cards are not all in your hand'; end if;
  v_pending:=v_state->'pendingCard';
  v_new_hand:=v_new_hand||jsonb_build_array(v_pending);
  for v_idx in 0..jsonb_array_length(v_players)-1 loop
    if v_players->v_idx->>'playerId'=v_me.id::text then
      v_players:=jsonb_set(v_players,array[v_idx::text,'hand'],v_new_hand);
      v_players:=jsonb_set(v_players,array[v_idx::text,'total'],to_jsonb((select coalesce(sum((x->>'value')::integer),0) from jsonb_array_elements(v_new_hand) x)));
    end if;
  end loop;
  v_state:=jsonb_set(v_state,'{players}',v_players);
  v_state:=jsonb_set(v_state,'{discardPile}',coalesce(v_state->'discardPile','[]'::jsonb)||coalesce(v_discard,'[]'::jsonb));
  v_state:=v_state-'pendingCard'-'pendingBy';
  select p.id into v_next from public.karden_players p
  where p.room_id=v_room.id and not p.eliminated and p.seat>v_me.seat
  order by p.seat limit 1;
  if v_next is null then select p.id into v_next from public.karden_players p where p.room_id=v_room.id and not p.eliminated order by p.seat limit 1; end if;
  update karden_private.room_state set state=jsonb_set(v_state,'{lastAction}',to_jsonb(v_me.display_name||' discarded '||cardinality(p_card_ids)||' card(s)')),updated_at=now() where room_id=v_room.id;
  update public.karden_rooms set current_player_id=v_next,turn_deadline=now()+make_interval(secs=>(config->>'turnSeconds')::integer),updated_at=now() where id=v_room.id;
  return jsonb_build_object('discarded',cardinality(p_card_ids),'nextPlayerId',v_next);
end $function$
;
revoke all on function karden_private.karden_discard_cards(text,uuid[]) from public,anon;
grant execute on function karden_private.karden_discard_cards(text,uuid[]) to authenticated;
CREATE OR REPLACE FUNCTION karden_private.karden_end_room(p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_room public.karden_rooms; v_state jsonb;
begin
 if auth.uid() is null then raise exception 'Guest session required'; end if;
 select * into v_room from public.karden_rooms where code=upper(trim(p_code)) for update;
 if not found or v_room.host_id<>auth.uid() then raise exception 'Only the host can end the room'; end if;
 select state into v_state from karden_private.room_state where room_id=v_room.id for update;
 v_state:=jsonb_set(v_state,'{phase}',to_jsonb('finished'::text));
 v_state:=jsonb_set(v_state,'{lastAction}',to_jsonb('The host ended the room'));
 update karden_private.room_state set state=v_state,updated_at=now() where room_id=v_room.id;
 update public.karden_rooms set status='finished',turn_deadline=null,remaining_seconds=null,updated_at=now() where id=v_room.id;
 return jsonb_build_object('ended',true);
end $function$
;
revoke all on function karden_private.karden_end_room(text) from public,anon;
grant execute on function karden_private.karden_end_room(text) to authenticated;
CREATE OR REPLACE FUNCTION karden_private.karden_expire_turn(p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_room public.karden_rooms; v_current public.karden_players; v_next uuid; v_count integer; v_state jsonb; v_players jsonb;
begin
 if auth.uid() is null then raise exception 'Guest session required'; end if;
 select * into v_room from public.karden_rooms where code=upper(trim(p_code)) for update;
 if not found then raise exception 'Room not found'; end if;
 if not exists(select 1 from public.karden_players where room_id=v_room.id and user_id=auth.uid()) then raise exception 'You are not a member of this room'; end if;
 if v_room.status<>'playing' or v_room.turn_deadline is null or now()<v_room.turn_deadline then return jsonb_build_object('expired',false); end if;
 select * into v_current from public.karden_players where id=v_room.current_player_id and room_id=v_room.id and not eliminated;
 if not found then return jsonb_build_object('expired',false); end if;
 update public.karden_players set eliminated=true,connected=false where id=v_current.id;
 select state into v_state from karden_private.room_state where room_id=v_room.id for update;
 select coalesce(jsonb_agg(x.value),'[]'::jsonb) into v_players from jsonb_array_elements(v_state->'players') x(value) where x.value->>'playerId'<>v_current.id::text;
 v_state:=jsonb_set(v_state,'{players}',v_players);
 v_state:=jsonb_set(v_state,'{lastAction}',to_jsonb(v_current.display_name||' timed out and was eliminated'));
 select count(*) into v_count from public.karden_players where room_id=v_room.id and not eliminated;
 if v_count<=1 then
   select id into v_next from public.karden_players where room_id=v_room.id and not eliminated limit 1;
   v_state:=jsonb_set(v_state,'{phase}',to_jsonb('finished'::text));
 else
   select id into v_next from public.karden_players where room_id=v_room.id and not eliminated and seat>v_current.seat order by seat limit 1;
   if v_next is null then select id into v_next from public.karden_players where room_id=v_room.id and not eliminated order by seat limit 1; end if;
 end if;
 update karden_private.room_state set state=v_state,updated_at=now() where room_id=v_room.id;
 update public.karden_rooms set status=case when v_count<=1 then 'finished' else 'playing' end,current_player_id=v_next,
   turn_deadline=case when v_count<=1 then null else now()+make_interval(secs=>(config->>'turnSeconds')::integer) end,updated_at=now()
 where id=v_room.id;
 return jsonb_build_object('expired',true,'eliminatedPlayerId',v_current.id,'winnerId',case when v_count=1 then v_next else null end);
end $function$
;
revoke all on function karden_private.karden_expire_turn(text) from public,anon;
grant execute on function karden_private.karden_expire_turn(text) to authenticated;
CREATE OR REPLACE FUNCTION karden_private.karden_join_room(p_code text, p_name text, p_avatar text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_room public.karden_rooms;
  v_player public.karden_players;
  v_seat integer;
begin
  if v_uid is null then raise exception 'Guest session required'; end if;
  if char_length(trim(p_name)) not between 1 and 24 then raise exception 'Name must be 1–24 characters'; end if;
  select * into v_room from public.karden_rooms where code=upper(trim(p_code)) for update;
  if not found then raise exception 'Room not found'; end if;
  if v_room.status <> 'lobby' then raise exception 'Game has already started'; end if;
  if exists(select 1 from public.karden_players where room_id=v_room.id and user_id=v_uid) then
    select * into v_player from public.karden_players where room_id=v_room.id and user_id=v_uid;
    return jsonb_build_object('roomId',v_room.id,'code',v_room.code,'playerId',v_player.id);
  end if;
  if (select count(*) from public.karden_players where room_id=v_room.id) >= (v_room.config->>'maxPlayers')::integer then
    raise exception 'Room is full';
  end if;
  select coalesce(max(seat),0)+1 into v_seat from public.karden_players where room_id=v_room.id;
  insert into public.karden_players(room_id,user_id,display_name,avatar,seat)
  values(v_room.id,v_uid,trim(p_name),coalesce(nullif(p_avatar,''),'ace'),v_seat)
  returning * into v_player;
  update karden_private.room_state set state=jsonb_set(state,'{players}',
    coalesce(state->'players','[]'::jsonb) || jsonb_build_array(jsonb_build_object(
      'playerId',v_player.id,'hand','[]'::jsonb,'total',0
    ))) where room_id=v_room.id;
  return jsonb_build_object('roomId',v_room.id,'code',v_room.code,'playerId',v_player.id);
end $function$
;
revoke all on function karden_private.karden_join_room(text,text,text) from public,anon;
grant execute on function karden_private.karden_join_room(text,text,text) to authenticated;
CREATE OR REPLACE FUNCTION karden_private.karden_kick_player(p_code text, p_player_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_room public.karden_rooms; v_target public.karden_players; v_state jsonb; v_players jsonb; v_next uuid; v_count integer;
begin
 if auth.uid() is null then raise exception 'Guest session required'; end if;
 select * into v_room from public.karden_rooms where code=upper(trim(p_code)) for update;
 if not found or v_room.host_id<>auth.uid() then raise exception 'Only the host can manage players'; end if;
 select * into v_target from public.karden_players where id=p_player_id and room_id=v_room.id;
 if not found or v_target.user_id=v_room.host_id then raise exception 'Player cannot be removed'; end if;
 if v_room.status='lobby' then delete from public.karden_players where id=v_target.id;
 else update public.karden_players set eliminated=true,connected=false where id=v_target.id; end if;
 select state into v_state from karden_private.room_state where room_id=v_room.id for update;
 select coalesce(jsonb_agg(x.value),'[]'::jsonb) into v_players from jsonb_array_elements(v_state->'players') x(value) where x.value->>'playerId'<>v_target.id::text;
 v_state:=jsonb_set(v_state,'{players}',v_players);
 v_state:=jsonb_set(v_state,'{lastAction}',to_jsonb(v_target.display_name||' was removed by the host'));
 select count(*) into v_count from public.karden_players where room_id=v_room.id and not eliminated;
 if v_room.current_player_id=v_target.id then
   select id into v_next from public.karden_players where room_id=v_room.id and not eliminated and seat>v_target.seat order by seat limit 1;
   if v_next is null then select id into v_next from public.karden_players where room_id=v_room.id and not eliminated order by seat limit 1; end if;
 else v_next:=v_room.current_player_id; end if;
 update karden_private.room_state set state=v_state,updated_at=now() where room_id=v_room.id;
 update public.karden_rooms set status=case when v_room.status<>'lobby' and v_count<=1 then 'finished' else status end,
   current_player_id=v_next,
   turn_deadline=case when v_count<=1 then null when v_room.status='playing' and v_room.current_player_id=v_target.id then now()+make_interval(secs=>(config->>'turnSeconds')::integer) else turn_deadline end,
   updated_at=now() where id=v_room.id;
 return jsonb_build_object('removed',true,'playerId',v_target.id);
end $function$
;
revoke all on function karden_private.karden_kick_player(text,uuid) from public,anon;
grant execute on function karden_private.karden_kick_player(text,uuid) to authenticated;
CREATE OR REPLACE FUNCTION karden_private.karden_next_round(p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_room public.karden_rooms; v_uid uuid:=auth.uid(); v_state jsonb; v_players jsonb;
  v_deck jsonb:='[]'::jsonb; v_card jsonb; v_hand jsonb; v_rank text; v_suit text;
  v_value integer; v_i integer; v_j integer; v_start uuid; v_count integer;
begin
  if v_uid is null then raise exception 'Guest session required'; end if;
  select * into v_room from public.karden_rooms where code=upper(trim(p_code)) for update;
  if not found or v_room.status not in ('playing','paused') then raise exception 'Game is not active'; end if;
  if not exists(select 1 from public.karden_players where room_id=v_room.id and user_id=v_uid and not eliminated) then raise exception 'You are not an active player'; end if;
  select state into v_state from karden_private.room_state where room_id=v_room.id for update;
  if v_state->>'phase'<>'round_result' then raise exception 'The round has not ended'; end if;
  v_start:=(v_state->'roundResult'->>'nextStarterId')::uuid;
  if v_start is null then raise exception 'The game is over'; end if;
  select count(*) into v_count from public.karden_players where room_id=v_room.id and not eliminated;
  if (v_room.config->>'decks')::integer*52 < v_count*(v_room.config->>'initialCards')::integer+1 then raise exception 'Not enough cards for remaining players'; end if;
  for v_i in 1..(v_room.config->>'decks')::integer loop
    foreach v_suit in array array['S','H','D','C'] loop
      foreach v_rank in array array['A','2','3','4','5','6','7','8','9','10','J','Q','K'] loop
        v_value:=case when v_rank=v_room.config->>'jokerRank' then 0 when v_rank='A' then 1 when v_rank='J' then 11 when v_rank='Q' then 12 when v_rank='K' then 13 else v_rank::integer end;
        v_deck:=v_deck||jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'rank',v_rank,'suit',v_suit,'value',v_value));
      end loop;
    end loop;
  end loop;
  select coalesce(jsonb_agg(x.card order by random()),'[]'::jsonb) into v_deck from jsonb_array_elements(v_deck) x(card);
  select jsonb_agg(jsonb_build_object('playerId',p.id,'hand','[]'::jsonb,'total',0) order by p.seat)
  into v_players from public.karden_players p where p.room_id=v_room.id and not p.eliminated;
  for v_i in 0..jsonb_array_length(v_players)-1 loop
    v_hand:='[]'::jsonb;
    for v_j in 1..(v_room.config->>'initialCards')::integer loop
      v_card:=v_deck->0; v_deck:=v_deck-0; v_hand:=v_hand||jsonb_build_array(v_card);
    end loop;
    v_players:=jsonb_set(v_players,array[v_i::text,'hand'],v_hand);
    v_players:=jsonb_set(v_players,array[v_i::text,'total'],to_jsonb((select coalesce(sum((x->>'value')::integer),0) from jsonb_array_elements(v_hand) x)));
  end loop;
  v_card:=v_deck->0; v_deck:=v_deck-0;
  v_state:=jsonb_build_object('players',v_players,'drawPile',v_deck,'discardPile',jsonb_build_array(v_card),
    'pendingCard',null,'pendingBy',null,'callerId',null,'phase','playing','lastAction','New round dealt','roundResult',v_state->'roundResult');
  update karden_private.room_state set state=v_state,updated_at=now() where room_id=v_room.id;
  update public.karden_rooms set status='playing',round_number=round_number+1,current_player_id=v_start,
    turn_deadline=now()+make_interval(secs=>(config->>'turnSeconds')::integer),updated_at=now() where id=v_room.id;
  return jsonb_build_object('round',v_room.round_number+1,'startingPlayerId',v_start);
end $function$
;
revoke all on function karden_private.karden_next_round(text) from public,anon;
grant execute on function karden_private.karden_next_round(text) to authenticated;
CREATE OR REPLACE FUNCTION karden_private.karden_pause_room(p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_room public.karden_rooms; v_remaining integer; v_state jsonb;
begin
 if auth.uid() is null then raise exception 'Guest session required'; end if;
 select * into v_room from public.karden_rooms where code=upper(trim(p_code)) for update;
 if not found or v_room.host_id<>auth.uid() then raise exception 'Only the host can pause the room'; end if;
 if v_room.status<>'playing' then raise exception 'Room is not currently running'; end if;
 select state into v_state from karden_private.room_state where room_id=v_room.id;
 if coalesce(v_state->>'phase','playing')<>'playing' then raise exception 'A round result cannot be paused'; end if;
 v_remaining:=greatest(0,ceil(extract(epoch from (v_room.turn_deadline-now())))::integer);
 update public.karden_rooms set status='paused',remaining_seconds=v_remaining,turn_deadline=null,updated_at=now() where id=v_room.id;
 return jsonb_build_object('paused',true,'remainingSeconds',v_remaining);
end $function$
;
revoke all on function karden_private.karden_pause_room(text) from public,anon;
grant execute on function karden_private.karden_pause_room(text) to authenticated;
CREATE OR REPLACE FUNCTION karden_private.karden_resume_room(p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_room public.karden_rooms;
begin
 if auth.uid() is null then raise exception 'Guest session required'; end if;
 select * into v_room from public.karden_rooms where code=upper(trim(p_code)) for update;
 if not found or v_room.host_id<>auth.uid() then raise exception 'Only the host can resume the room'; end if;
 if v_room.status<>'paused' then raise exception 'Room is not paused'; end if;
 update public.karden_rooms set status='playing',turn_deadline=now()+make_interval(secs=>coalesce(remaining_seconds,(config->>'turnSeconds')::integer)),
   remaining_seconds=null,updated_at=now() where id=v_room.id;
 return jsonb_build_object('resumed',true);
end $function$
;
revoke all on function karden_private.karden_resume_room(text) from public,anon;
grant execute on function karden_private.karden_resume_room(text) to authenticated;
CREATE OR REPLACE FUNCTION karden_private.karden_room_snapshot(p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid(); v_room public.karden_rooms; v_me public.karden_players;
  v_state jsonb; v_hand jsonb; v_players jsonb;
begin
  if v_uid is null then raise exception 'Guest session required'; end if;
  select * into v_room from public.karden_rooms where code=upper(trim(p_code));
  if not found then raise exception 'Room not found'; end if;
  select * into v_me from public.karden_players where room_id=v_room.id and user_id=v_uid;
  if not found then raise exception 'You are not a player in this room'; end if;
  select state into v_state from karden_private.room_state where room_id=v_room.id;
  select coalesce((select x.value->'hand' from jsonb_array_elements(v_state->'players') x(value) where x.value->>'playerId'=v_me.id::text),'[]'::jsonb) into v_hand;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',pl.id,'name',pl.display_name,'avatar',pl.avatar,'seat',pl.seat,
    'score',pl.cumulative_score,'eliminated',pl.eliminated,'connected',pl.connected,
    'cardCount',coalesce(jsonb_array_length((select x.value->'hand' from jsonb_array_elements(v_state->'players') x(value) where x.value->>'playerId'=pl.id::text)),0),
    'isHost',pl.user_id=v_room.host_id
  ) order by pl.seat),'[]'::jsonb) into v_players
  from public.karden_players pl where pl.room_id=v_room.id;
  return jsonb_build_object(
    'roomId',v_room.id,'code',v_room.code,'status',v_room.status,'config',v_room.config,
    'round',v_room.round_number,'currentPlayerId',v_room.current_player_id,
    'turnDeadline',v_room.turn_deadline,'players',v_players,
    'me',jsonb_build_object('id',v_me.id,'hand',v_hand),
    'drawCount',coalesce(jsonb_array_length(v_state->'drawPile'),0),
    'topDiscard',case when coalesce(jsonb_array_length(v_state->'discardPile'),0)>0 then v_state->'discardPile'->(jsonb_array_length(v_state->'discardPile')-1) else null end,
    'lastAction',v_state->'lastAction','phase',coalesce(v_state->>'phase','playing'),
    'roundResult',v_state->'roundResult','pendingPick',v_state->>'pendingBy'=v_me.id::text,
    'handTotal',coalesce((select sum((x.value->>'value')::integer) from jsonb_array_elements(v_hand) x(value)),0)
  );
end $function$
;
revoke all on function karden_private.karden_room_snapshot(text) from public,anon;
grant execute on function karden_private.karden_room_snapshot(text) to authenticated;
CREATE OR REPLACE FUNCTION karden_private.karden_start_game(p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_room public.karden_rooms;
  v_uid uuid := auth.uid();
  v_players jsonb;
  v_deck jsonb := '[]'::jsonb;
  v_card jsonb;
  v_hand jsonb;
  v_state jsonb;
  v_start uuid;
  v_rank text;
  v_suit text;
  v_value integer;
  v_i integer;
  v_j integer;
  v_count integer;
begin
  if v_uid is null then raise exception 'Guest session required'; end if;
  select * into v_room from public.karden_rooms where code=upper(trim(p_code)) for update;
  if not found then raise exception 'Room not found'; end if;
  if v_room.host_id <> v_uid then raise exception 'Only the host can start the game'; end if;
  if v_room.status <> 'lobby' then raise exception 'This room has already started'; end if;
  select count(*) into v_count from public.karden_players where room_id=v_room.id and not eliminated;
  if v_count < 2 then raise exception 'At least two players are required'; end if;
  if v_count > (v_room.config->>'maxPlayers')::integer then raise exception 'Room is full'; end if;
  if (v_room.config->>'decks')::integer * 52 < v_count * (v_room.config->>'initialCards')::integer + 1 then
    raise exception 'Not enough cards for this player count and deck setting';
  end if;

  for v_i in 1..(v_room.config->>'decks')::integer loop
    foreach v_suit in array array['S','H','D','C'] loop
      foreach v_rank in array array['A','2','3','4','5','6','7','8','9','10','J','Q','K'] loop
        v_value := case when v_rank = v_room.config->>'jokerRank' then 0
          when v_rank='A' then 1 when v_rank in ('J','Q','K') then case v_rank when 'J' then 11 when 'Q' then 12 else 13 end
          else v_rank::integer end;
        v_deck := v_deck || jsonb_build_array(jsonb_build_object(
          'id',gen_random_uuid(),'rank',v_rank,'suit',v_suit,'value',v_value
        ));
      end loop;
    end loop;
  end loop;
  select coalesce(jsonb_agg(x.card order by random()),'[]'::jsonb) into v_deck
  from jsonb_array_elements(v_deck) as x(card);

  select jsonb_agg(jsonb_build_object('playerId',p.id,'hand','[]'::jsonb,'total',0) order by p.seat)
  into v_players from public.karden_players p where p.room_id=v_room.id and not p.eliminated;

  for v_i in 0..jsonb_array_length(v_players)-1 loop
    v_hand := '[]'::jsonb;
    for v_j in 1..(v_room.config->>'initialCards')::integer loop
      v_card := v_deck->0;
      v_deck := v_deck - 0;
      v_hand := v_hand || jsonb_build_array(v_card);
    end loop;
    v_players := jsonb_set(v_players, array[v_i::text,'hand'],v_hand);
    v_players := jsonb_set(v_players, array[v_i::text,'total'],to_jsonb((select coalesce(sum((c->>'value')::integer),0) from jsonb_array_elements(v_hand) c)));
  end loop;

  v_card := v_deck->0;
  v_deck := v_deck - 0;
  select p.id into v_start from public.karden_players p
  where p.room_id=v_room.id and not p.eliminated order by random() limit 1;

  v_state := jsonb_build_object('players',v_players,'drawPile',v_deck,
    'discardPile',jsonb_build_array(v_card),'pendingCard',null,'pendingBy',null,
    'callerId',null,'lastAction','Game started');
  insert into karden_private.room_state(room_id,state,updated_at)
  values(v_room.id,v_state,now())
  on conflict(room_id) do update set state=excluded.state,updated_at=now();

  update public.karden_rooms set status='playing',round_number=1,current_player_id=v_start,
    turn_deadline=now()+make_interval(secs=>(config->>'turnSeconds')::integer),updated_at=now()
  where id=v_room.id;
  return jsonb_build_object('started',true,'round',1,'currentPlayerId',v_start);
end $function$
;
revoke all on function karden_private.karden_start_game(text) from public,anon;
grant execute on function karden_private.karden_start_game(text) to authenticated;
CREATE OR REPLACE FUNCTION karden_private.karden_take_card(p_code text, p_source text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_room public.karden_rooms;
  v_me public.karden_players;
  v_state jsonb;
  v_card jsonb;
  v_discard jsonb;
  v_draw jsonb;
begin
  if auth.uid() is null then raise exception 'Guest session required'; end if;
  select * into v_room from public.karden_rooms where code=upper(trim(p_code)) for update;
  if not found or v_room.status<>'playing' then raise exception 'Game is not active'; end if;
  select * into v_me from public.karden_players where room_id=v_room.id and user_id=auth.uid() and not eliminated;
  if not found or v_me.id<>v_room.current_player_id then raise exception 'It is not your turn'; end if;
  if v_room.turn_deadline is not null and now()>=v_room.turn_deadline then raise exception 'Turn has expired'; end if;
  select state into v_state from karden_private.room_state where room_id=v_room.id for update;
  if v_state->>'pendingBy' is not null then raise exception 'You already picked a card'; end if;
  if p_source='open' then
    v_discard:=v_state->'discardPile';
    if jsonb_array_length(v_discard)=0 then raise exception 'Discard pile is empty'; end if;
    v_card:=v_discard->(jsonb_array_length(v_discard)-1);
    v_state:=jsonb_set(v_state,'{discardPile}',v_discard - (jsonb_array_length(v_discard)-1));
  elsif p_source='draw' then
    v_draw:=v_state->'drawPile';
    if jsonb_array_length(v_draw)=0 then
      v_discard:=v_state->'discardPile';
      if jsonb_array_length(v_discard)<=1 then raise exception 'No cards remain to draw'; end if;
      v_card:=v_discard->(jsonb_array_length(v_discard)-1);
      select coalesce(jsonb_agg(x.card order by random()),'[]'::jsonb) into v_draw
      from jsonb_array_elements(v_discard - (jsonb_array_length(v_discard)-1)) x(card);
      v_state:=jsonb_set(v_state,'{discardPile}',jsonb_build_array(v_card));
    end if;
    v_card:=v_draw->0;
    v_state:=jsonb_set(v_state,'{drawPile}',v_draw - 0);
  else raise exception 'Invalid pickup source'; end if;
  v_state:=jsonb_set(v_state,'{pendingCard}',v_card);
  v_state:=jsonb_set(v_state,'{pendingBy}',to_jsonb(v_me.id::text));
  update karden_private.room_state set state=v_state,updated_at=now() where room_id=v_room.id;
  return jsonb_build_object('picked',true);
end $function$
;
revoke all on function karden_private.karden_take_card(text,text) from public,anon;
grant execute on function karden_private.karden_take_card(text,text) to authenticated;
CREATE OR REPLACE FUNCTION public.karden_call(p_code text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select karden_private.karden_call($1); $function$
;
revoke all on function public.karden_call(text) from public,anon;
grant execute on function public.karden_call(text) to authenticated;
CREATE OR REPLACE FUNCTION public.karden_create_room(p_name text, p_avatar text, p_config jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select karden_private.karden_create_room($1,$2,$3); $function$
;
revoke all on function public.karden_create_room(text,text,jsonb) from public,anon;
grant execute on function public.karden_create_room(text,text,jsonb) to authenticated;
CREATE OR REPLACE FUNCTION public.karden_discard_cards(p_code text, p_card_ids uuid[])
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select karden_private.karden_discard_cards($1,$2); $function$
;
revoke all on function public.karden_discard_cards(text,uuid[]) from public,anon;
grant execute on function public.karden_discard_cards(text,uuid[]) to authenticated;
CREATE OR REPLACE FUNCTION public.karden_end_room(p_code text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select karden_private.karden_end_room($1); $function$
;
revoke all on function public.karden_end_room(text) from public,anon;
grant execute on function public.karden_end_room(text) to authenticated;
CREATE OR REPLACE FUNCTION public.karden_expire_turn(p_code text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select karden_private.karden_expire_turn($1); $function$
;
revoke all on function public.karden_expire_turn(text) from public,anon;
grant execute on function public.karden_expire_turn(text) to authenticated;
CREATE OR REPLACE FUNCTION public.karden_join_room(p_code text, p_name text, p_avatar text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select karden_private.karden_join_room($1,$2,$3); $function$
;
revoke all on function public.karden_join_room(text,text,text) from public,anon;
grant execute on function public.karden_join_room(text,text,text) to authenticated;
CREATE OR REPLACE FUNCTION public.karden_kick_player(p_code text, p_player_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select karden_private.karden_kick_player($1,$2); $function$
;
revoke all on function public.karden_kick_player(text,uuid) from public,anon;
grant execute on function public.karden_kick_player(text,uuid) to authenticated;
CREATE OR REPLACE FUNCTION public.karden_next_round(p_code text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select karden_private.karden_next_round($1); $function$
;
revoke all on function public.karden_next_round(text) from public,anon;
grant execute on function public.karden_next_round(text) to authenticated;
CREATE OR REPLACE FUNCTION public.karden_pause_room(p_code text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select karden_private.karden_pause_room($1); $function$
;
revoke all on function public.karden_pause_room(text) from public,anon;
grant execute on function public.karden_pause_room(text) to authenticated;
CREATE OR REPLACE FUNCTION public.karden_resume_room(p_code text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select karden_private.karden_resume_room($1); $function$
;
revoke all on function public.karden_resume_room(text) from public,anon;
grant execute on function public.karden_resume_room(text) to authenticated;
CREATE OR REPLACE FUNCTION public.karden_room_snapshot(p_code text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select karden_private.karden_room_snapshot($1); $function$
;
revoke all on function public.karden_room_snapshot(text) from public,anon;
grant execute on function public.karden_room_snapshot(text) to authenticated;
CREATE OR REPLACE FUNCTION public.karden_start_game(p_code text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select karden_private.karden_start_game($1); $function$
;
revoke all on function public.karden_start_game(text) from public,anon;
grant execute on function public.karden_start_game(text) to authenticated;
CREATE OR REPLACE FUNCTION public.karden_take_card(p_code text, p_source text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select karden_private.karden_take_card($1,$2); $function$
;
revoke all on function public.karden_take_card(text,text) from public,anon;
grant execute on function public.karden_take_card(text,text) to authenticated;
