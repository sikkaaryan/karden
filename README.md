# KARDEN — The Private Card Club

A portrait-first, dark-luxury multiplayer card game PWA.

## Stack
- Next.js App Router + TypeScript
- Tailwind CSS 4
- Supabase Anonymous Auth + Postgres + private Realtime Broadcast
- Vercel hosting

## Local setup
1. Copy `.env.example` to `.env.local`.
2. Set `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`.
3. In Supabase Dashboard → Authentication → Providers, enable **Anonymous Sign-Ins**.
4. In Supabase Dashboard → Realtime Settings, disable **Allow public access** so room channels remain private.
5. Run `npm install` and `npm run dev`.

## Security model
- Guests use Supabase anonymous Auth sessions.
- Game actions are authoritative Postgres RPCs; clients cannot set scores, hands, turns, or penalties.
- Hands and draw-pile state live in the non-exposed `karden_private` schema.
- Room snapshots return only the requesting player's hand; opponents' card counts are public to room members.
- Public tables have RLS enabled and direct client table privileges revoked.
- Privileged database functions live in `karden_private`; public RPC wrappers run as invoker.
- Realtime sends only a refresh signal over authenticated, room-authorized private channels. Clients fetch a sanitized snapshot after each signal.
- Never put a Supabase secret/service-role key in browser code.

## Database
`supabase/migrations` contains a fresh-project baseline snapshot plus history markers matching the already-deployed project migrations. The live KARDEN database has the baseline schema, game engine, chat, private Realtime triggers, secure avatar storage, and profile/statistics migrations applied.

## Current features
- Guest room creation/joining and host-configurable rules
- Random dealing, turn flow, pickup, same-rank discard, calling and burst scoring
- Elimination, round progression, timeout removal and winner/tie states
- Host pause/resume, kick and end-room controls
- Private room broadcasts, table chat and quick reactions
- Portrait PWA shell, How to Play guide, and persistent guest profile/statistics
- Optional personal photo avatars stored in a dedicated, size/type-limited Supabase Storage bucket
- Host rematch flow that carries forward the previous room settings
