# KARDEN — The Private Card Club

A portrait-first, dark-luxury multiplayer card game PWA.

## Stack
- Next.js App Router + TypeScript
- Tailwind CSS 4
- Supabase Auth + Postgres (authoritative game state)
- Vercel deployment

## Local setup
1. Copy `.env.example` to `.env.local`.
2. Set `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`.
3. In Supabase Dashboard → Authentication → Providers, enable **Anonymous Sign-Ins**.
4. Run `npm install` and `npm run dev`.

## Security model
- Guests use Supabase anonymous Auth sessions.
- Game actions are server-authoritative Postgres RPCs.
- Hands and draw-pile state live in the non-exposed `karden_private` schema.
- Public room snapshots return only the requesting player's hand and opponent card counts.
- All public tables have RLS enabled and direct client table privileges revoked.
- Privileged functions are isolated in `karden_private`; exposed public RPC wrappers run as invoker.
- Never put a Supabase secret/service-role key in browser code.

## Database
The baseline migration is in `supabase/migrations`. It creates the room/player tables, private state store, and game RPCs.
