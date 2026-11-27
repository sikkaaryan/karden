# KARDEN Release QA Plan

This is the independent release gate. Run only after the implementation branch is stable and CI is green.

## Agent structure

Use one supervisor plus six independent specialists. Give each specialist a separate worktree and read-only production access unless a test specifically requires a disposable test room. No specialist signs off on its own fixes.

1. **Supervisor / release captain** — owns the test matrix, evidence register, severity arbitration, and final go/no-go.
2. **Rules engine** — validates deck construction, values, turn rules, calling, burst logic, scoring, elimination, tie, and next-round starter.
3. **Database / security** — validates RPC authorization, RLS, private schema isolation, hand privacy, score integrity, avatar storage policies, and SQL concurrency.
4. **Multiplayer / reliability** — validates room joins, realtime refresh, heartbeat disconnect status, reconnects, simultaneous actions, timeout races, pause/resume, and host controls.
5. **Mobile UX / accessibility** — tests iPhone Safari and installed PWA, portrait layout, one-handed operation, card tap/long-press, keyboard/screen-reader basics, and safe-area handling.
6. **Build / platform** — validates CI, Next.js production build, Vercel production deployment, environment variables, PWA manifest/service worker, and runtime logs.
7. **Adversarial tester** — attempts invalid RPC calls, room-code guessing, cross-room reads, unauthorized kick/pause/end, malicious avatar URLs, oversized uploads, chat abuse, and race conditions.

## Required game scenarios

- 2, 4, 6, and 8 players; 1–4 decks; boundary room settings.
- All card values, including every host-selected Joker rank and no additional jokers.
- One-at-a-time clockwise dealing, random first player, one face-up discard.
- Call only at turn start and only when starting total is strictly below threshold.
- Face-up pickup versus draw-pile pickup; newly drawn card cannot be discarded that turn.
- One-or-more same-rank discards; mixed-rank and empty discards rejected.
- Empty draw pile reshuffle preserves the latest face-up discard.
- Clean call, burst call, equal-total burst, exact elimination threshold, multiple eliminations, tie, and winner.
- Clean caller starts next round; burst starter is lowest eligible surviving hand with random tie-break.
- Timeout before and after pickup; pending card returned; pause freezes remaining time; resume restores it.
- Host kick, host end, and rematch with identical room settings.

## Required multiplayer and security scenarios

- Two or more clients act concurrently on the same turn; only one action commits.
- Disconnected player becomes stale after heartbeat timeout; reconnect restores online status.
- Private Realtime room topic rejects non-members.
- A player can read only their own hand; opponent hands and draw pile remain hidden.
- Direct table reads/writes are denied by RLS and revoked privileges.
- RPCs reject non-members, wrong-turn players, eliminated players, and expired turns.
- Clients cannot alter scores, hands, penalties, turn deadlines, or room settings after creation.
- Avatar upload accepts only JPEG/PNG/WebP up to 2 MB, one object per user, and rejects cross-user paths or arbitrary remote URLs.
- Profile RPC returns only the current guest's profile and statistics.

## Required mobile / PWA checks

- Test current iPhone Safari and Add to Home Screen installation.
- Portrait orientation, notched-device safe areas, small screens, and keyboard-open layouts.
- One-handed reachability for draw, discard, call, chat, and host actions.
- Tap and long-press card selection; invalid rank combinations cannot be submitted.
- No background music; card interaction sound is subtle and only plays after user interaction.
- Verify online reconnect and graceful error messaging. Offline mode is an app-shell fallback, not offline multiplayer.

## Evidence format

Every finding must include:
- Severity: Critical / High / Medium / Low
- Exact environment, device, browser, room size, and settings
- Reproduction steps and expected versus actual result
- Relevant route, file, RPC, SQL object, or deployment ID
- Screenshot, log excerpt, or query result where possible

## Release acceptance

- GitHub Actions lint, typecheck, build, and high-severity dependency audit pass.
- Supabase security and health advisors have no findings; performance notices are reviewed.
- No open Critical or High findings.
- Every fixed finding is independently retested by a different specialist.
- Real multi-device iPhone testing passes.
- The production Vercel deployment is READY and its public alias loads.
- Supervisor records a final GO decision with evidence links.

Do not call KARDEN production-ready until all acceptance items are evidenced.
