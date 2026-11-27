-- Explicit deny-all RLS policies document that clients must use the
-- narrowly-scoped RPC interface; security-definer functions remain authoritative.
drop policy if exists karden_deny_direct_access on public.karden_rooms;
create policy karden_deny_direct_access on public.karden_rooms
for all to anon, authenticated using (false) with check (false);

drop policy if exists karden_deny_direct_access on public.karden_players;
create policy karden_deny_direct_access on public.karden_players
for all to anon, authenticated using (false) with check (false);

drop policy if exists karden_deny_direct_access on public.karden_messages;
create policy karden_deny_direct_access on public.karden_messages
for all to anon, authenticated using (false) with check (false);

drop policy if exists karden_deny_direct_access on public.karden_profiles;
create policy karden_deny_direct_access on public.karden_profiles
for all to anon, authenticated using (false) with check (false);

drop policy if exists karden_deny_direct_access on karden_private.room_state;
create policy karden_deny_direct_access on karden_private.room_state
for all to authenticated using (false) with check (false);
