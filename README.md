# KARDEN — The Private Card Club

A portrait-first, dark-luxury multiplayer card game PWA.

## Stack
- Next.js App Router + TypeScript
- Tailwind CSS
- Supabase Auth, Postgres and Realtime
- Vercel deployment

## Local development
1. Copy `.env.example` to `.env.local`.
2. Add the KARDEN Supabase project URL and publishable key.
3. Enable **Anonymous Sign-Ins** in Supabase Authentication settings.
4. Run `npm install` and `npm run dev`.

The database migration is managed in Supabase. Never put a Supabase secret/service-role key in the browser.
