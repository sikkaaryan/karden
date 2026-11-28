"use client";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { CharacterAvatar } from "@/components/character-avatar";
import { ArrowLeft, Copy, Crown, Shield, Users, Clock, Layers, MessageCircle, Send } from "lucide-react";
import { ensureGuest, supabase } from "@/lib/supabase";
import type { Card, RoomSnapshot } from "@/lib/types";

const suitGlyph = { S: "♠", H: "♥", D: "♦", C: "♣" };
function playCardSound() {
  try {
    const ctx = new AudioContext();
    const length = Math.floor(ctx.sampleRate * 0.055);
    const buffer = ctx.createBuffer(1, length, ctx.sampleRate);
    const samples = buffer.getChannelData(0);
    for (let i = 0; i < length; i++) {
      const fade = 1 - i / length;
      samples[i] = (Math.random() * 2 - 1) * fade * fade;
    }
    const source = ctx.createBufferSource();
    source.buffer = buffer;
    const filter = ctx.createBiquadFilter();
    filter.type = "lowpass";
    filter.frequency.value = 2600;
    const gain = ctx.createGain();
    gain.gain.setValueAtTime(0.12, ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.055);
    source.connect(filter);
    filter.connect(gain);
    gain.connect(ctx.destination);
    source.onended = () => void ctx.close();
    source.start();
  } catch {}
}
function PlayingCard({ card, selected, onClick, disabled = false }: { card: Card; selected?: boolean; onClick?: () => void; disabled?: boolean }) {
  const red = card.suit === "H" || card.suit === "D";
  const pressTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const longPressed = useRef(false);
  const choose = () => {
    playCardSound();
    onClick?.();
  };
  const clearPress = () => {
    if (pressTimer.current) {
      clearTimeout(pressTimer.current);
      pressTimer.current = null;
    }
  };
  return (
    <button
      disabled={disabled}
      onPointerDown={() => {
        longPressed.current = false;
        clearPress();
        pressTimer.current = setTimeout(() => {
          longPressed.current = true;
          choose();
        }, 420);
      }}
      onPointerUp={clearPress}
      onPointerLeave={clearPress}
      onContextMenu={(e) => e.preventDefault()}
      onClick={() => {
        if (longPressed.current) {
          longPressed.current = false;
          return;
        }
        choose();
      }}
      className={`playing-card relative w-[54px] h-[82px] sm:w-[62px] sm:h-[92px] shrink-0 p-1.5 flex flex-col justify-between text-left transition-all ${red ? "red" : ""} ${selected ? "selected-card -translate-y-3 ring-2 ring-[#c9a96e]" : ""} disabled:opacity-60`}
    >
      <span className="text-sm font-bold leading-none">{card.rank}</span>
      <span className="text-2xl self-center">{suitGlyph[card.suit]}</span>
      <span className="text-xs self-end rotate-180">{card.rank}</span>
    </button>
  );
}
function AvatarFace({ avatar, name }: { avatar: string; name: string }) {
  return <CharacterAvatar avatar={avatar} name={name} size={40} className="rounded-full" />;
}
export default function Room() {
  const params = useParams<{ code: string }>();
  const router = useRouter();
  const code = params.code.toUpperCase();
  const [room, setRoom] = useState<RoomSnapshot | null>(null);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [selected, setSelected] = useState<string[]>([]);
  const [handSort, setHandSort] = useState<"rank" | "suit">("rank");
  const [now, setNow] = useState(Date.now());
  const [showScores, setShowScores] = useState(false);
  const [showHostTools, setShowHostTools] = useState(false);
  const [showChat, setShowChat] = useState(false);
  const [copied, setCopied] = useState(false);
  const [chatText, setChatText] = useState("");
  const expiredDeadline = useRef<string | null>(null);
  const refresh = useCallback(async () => {
    try {
      await ensureGuest();
      const db = supabase();
      const { error: heartbeatError } = await db.rpc("karden_heartbeat", {
        p_code: code,
      });
      if (heartbeatError) throw heartbeatError;
      const { data: initialData, error } = await db.rpc("karden_room_snapshot", { p_code: code });
      if (error) throw error;
      let data = initialData;
      if (data.status === "playing" && data.turnDeadline && Date.parse(data.turnDeadline) <= Date.now()) {
        await db.rpc("karden_expire_turn", { p_code: code });
        const refreshed = await db.rpc("karden_room_snapshot", {
          p_code: code,
        });
        if (refreshed.error) throw refreshed.error;
        data = refreshed.data;
      }
      setRoom(data as RoomSnapshot);
      setError("");
    } catch (e) {
      setError(e instanceof Error ? e.message : "Unable to load room");
    } finally {
      setLoading(false);
    }
  }, [code]);
  useEffect(() => {
    void refresh();
    const poll = setInterval(() => void refresh(), 15000);
    const tick = setInterval(() => setNow(Date.now()), 1000);
    return () => {
      clearInterval(poll);
      clearInterval(tick);
    };
  }, [refresh]);
  useEffect(() => {
    if (!room?.roomId) return;
    let cancelled = false;
    let channel: ReturnType<ReturnType<typeof supabase>["channel"]> | null = null;
    const db = supabase();
    void (async () => {
      await db.realtime.setAuth();
      if (cancelled) return;
      channel = db
        .channel(`room:${room.roomId}`, { config: { private: true } })
        .on("broadcast", { event: "state_changed" }, () => void refresh())
        .subscribe();
    })();
    return () => {
      cancelled = true;
      if (channel) void db.removeChannel(channel);
    };
  }, [room?.roomId, refresh]);
  const me = room ? room.players.find((p) => p.id === room.me.id) : undefined;
  const isTurn = !!room && room.status === "playing" && room.currentPlayerId === room.me.id;
  const seconds = room?.turnDeadline ? Math.max(0, Math.ceil((new Date(room.turnDeadline).getTime() - now) / 1000)) : 0;
  useEffect(() => {
    if (room?.status !== "playing" || !room.turnDeadline || seconds > 0 || expiredDeadline.current === room.turnDeadline) return;
    expiredDeadline.current = room.turnDeadline;
    void refresh();
  }, [room?.status, room?.turnDeadline, seconds, refresh]);
  const selectedCards = useMemo(() => room?.me.hand.filter((c) => selected.includes(c.id)) ?? [], [room, selected]);
  const canCall = !!room && isTurn && room.phase === "playing" && !room.pendingPick && room.handTotal < room.config.callThreshold;
  const sameRank = selectedCards.length === 0 || selectedCards.every((c) => c.rank === selectedCards[0].rank);
  const sortedHand = useMemo(() => {
    const ranks: Record<string, number> = { A: 1, J: 11, Q: 12, K: 13 };
    const suits: Record<string, number> = { S: 0, H: 1, D: 2, C: 3 };
    return [...(room?.me.hand ?? [])].sort((a, b) => {
      const ar = ranks[a.rank] ?? Number(a.rank),
        br = ranks[b.rank] ?? Number(b.rank);
      return handSort === "rank" ? ar - br || suits[a.suit] - suits[b.suit] : suits[a.suit] - suits[b.suit] || ar - br;
    });
  }, [room?.me.hand, handSort]);
  async function action(fn: string, args: Record<string, unknown> = {}) {
    setBusy(true);
    setError("");
    try {
      const { error } = await supabase().rpc(fn, { p_code: code, ...args });
      if (error) throw error;
      setSelected([]);
      await refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Action failed");
    } finally {
      setBusy(false);
    }
  }
  async function rematch() {
    if (!room || !me) return;
    setBusy(true);
    setError("");
    try {
      const { data, error } = await supabase().rpc("karden_create_room", {
        p_name: me.name,
        p_avatar: me.avatar,
        p_config: room.config,
      });
      if (error) throw error;
      const nextCode = typeof data?.code === "string" ? data.code : "";
      if (!nextCode) throw new Error("The new room was created, but its code was not returned. Please try again.");
      router.push(`/room/${nextCode}`);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not start a rematch. Please check your connection and try again.");
    } finally {
      setBusy(false);
    }
  }
  async function copy() {
    const invite = `${window.location.origin}/room/${code}`;
    try {
      if (navigator.clipboard?.writeText && window.isSecureContext) {
        await navigator.clipboard.writeText(invite);
      } else {
        const field = document.createElement("textarea");
        field.value = invite;
        field.setAttribute("readonly", "");
        field.style.position = "fixed";
        field.style.opacity = "0";
        document.body.appendChild(field);
        field.select();
        const copied = document.execCommand("copy");
        field.remove();
        if (!copied) throw new Error("Clipboard access is unavailable. Copy this link manually: " + invite);
      }
      setCopied(true);
      window.setTimeout(() => setCopied(false), 2200);
    } catch (e) {
      setError(e instanceof Error ? e.message : `Could not copy the invite link: ${invite}`);
    }
  }
  async function sendChat(body: string, kind: "text" | "reaction") {
    if (!body.trim()) return;
    setBusy(true);
    setError("");
    try {
      const { error } = await supabase().rpc("karden_send_message", {
        p_code: code,
        p_body: body,
        p_kind: kind,
      });
      if (error) throw error;
      if (kind === "text") setChatText("");
      await refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not send message");
    } finally {
      setBusy(false);
    }
  }
  function toggle(id: string) {
    setSelected((s) => (s.includes(id) ? s.filter((x) => x !== id) : [...s, id]));
  }
  if (loading) return <main className="min-h-screen grid place-items-center muted text-sm">Opening your private table…</main>;
  return (
    <main className="karden-room min-h-screen px-3 py-4 flex justify-center safe-area">
      <div className="w-full max-w-md">
        <header className="flex justify-between items-center mb-6">
          <button className="secondary !p-2" onClick={() => router.push("/")}>
            <ArrowLeft size={18} />
          </button>
          <span className="karden-brand serif">
            <span className="brand-spade">♠</span>KARDEN
          </span>
          <div className="flex gap-2">
            <button className="secondary !p-2 text-xs gold" onClick={() => setShowChat((v) => !v)}>
              <MessageCircle size={16} />
            </button>
            <button className="secondary !p-2 text-xs gold" onClick={() => void copy()}>
              {copied ? <span className="text-[11px]">Copied!</span> : <Copy size={15} />
            </button>
          </div>
        </header>
        {error && <div className="mb-4 rounded-xl border border-red-900/60 bg-red-950/30 p-3 text-sm text-red-200">{error}</div>}
        {!room ? (
          <div className="panel p-6 text-sm muted">
            Room unavailable.{" "}
            <button onClick={() => void refresh()} className="gold underline">
              Retry
            </button>
          </div>
        ) : (
          <>
            <div className="text-center mb-5">
              <p className="eyebrow mb-1">{room.status === "lobby" ? "Private room" : `Round ${room.round}`}</p>
              <h1 className="serif text-3xl gold tracking-[.18em]">{room.code}</h1>
            </div>
            {room.status === "lobby" ? (
              <>
                <section className="panel p-5 mb-4">
                  <div className="flex justify-between items-center mb-4">
                    <div>
                      <p className="text-xs muted uppercase tracking-widest">Players at the table</p>
                      <p className="serif text-2xl mt-1">
                        {room.players.length}
                        <span className="muted text-base"> / {room.config.maxPlayers}</span>
                      </p>
                    </div>
                    <Users className="gold" size={22} />            </div>
                  <div className="space-y-3">
                    {room.players.map((p) => (
                      <div key={p.id} className="flex items-center gap-3 p-3 rounded-xl bg-white/[.035]">
                        <div className="w-10 h-10 rounded-full border border-[var(--line)] bg-[#1c3025] flex items-center justify-center overflow-hidden">
                          <AvatarFace avatar={p.avatar} name={p.name} />
                        </div>
                        <div className="flex-1">
                          <p className="text-sm">{p.name}</p>
                          <p className="text-[10px] muted uppercase tracking-wider">
                            {p.isHost ? "Host" : "Player"} · Seat {p.seat}
                          </p>
                        </div>
                        {p.isHost && <Crown size={16} className="gold" />}
                        {me?.isHost && p.id !== room.me.id && (
                          <button
                            onClick={() =>
                              void action("karden_kick_player", {
                                p_player_id: p.id,
                              })
                            }
                            className="text-[10px] text-red-300 border border-red-900/50 rounded-lg px-2 py-1"
                          >
                            Kick
                          </button>
                        )}
                        <span title={p.connected ? "Connected" : "Disconnected"} className={`w-2 h-2 rounded-full ${p.connected ? "bg-emerald-400" : "bg-red-400"}`} />
                      </div>
                    ))}
                  </div>
                  <p className="muted text-xs mt-4 text-center">Waiting for the host to start the game</p>
                </section>
                <section className="panel p-5 mb-4">
                  <div className="flex items-center gap-2 mb-4">
                    <Shield size={16} className="gold" />
                    <h2 className="text-sm">Table rules</h2>
                  </div>
                  <div className="grid grid-cols-2 gap-y-4 text-xs">
                    {[
                      ["Cards per player", room.config.initialCards],
                      ["Decks", room.config.decks],
                      ["Call below", room.config.callThreshold],
                      ["Burst penalty", `+${room.config.burstPenalty}`],
                      ["Elimination score", room.config.maxScore],
                      ["Turn timer", `${room.config.turnSeconds}s`],
                      ["Joker rank", room.config.jokerRank],
                    ].map(([k, v]) => (
                      <div key={k}>
                        <p className="muted">{k}</p>
                        <p className="mt-1">{v}</p>
                      </div>
                    ))}
                  </div>
                </section>
                {me?.isHost && (
                  <button disabled={busy || room.players.length < 2} onClick={() => void action("karden_start_game")} className="primary w-full disabled:opacity-40">
                    {busy ? "Starting…" : "Start game"}
                  </button>
                )}
              </>
            ) : (
              <>
                {room.status === "finished" && room.phase !== "round_result" ? (
                  <section className="panel p-6 text-center mb-4">
                    <p className="eyebrow mb-2">Table closed</p>
                    <h2 className="serif text-3xl gold">Game over</h2>
                    <p className="muted text-sm mt-2">{room.lastAction}</p>
                    {room.lastAction !== "The host ended the room"&& room.players.find((p) => !p.eliminated) && <p className="serif text-xl gold mt-3">Winner · {room.players.find((p) => !p.eliminated)?.name}</p>}
                    <div className="mt-5 space-y-2">
                      {room.players
                        .slice()
                        .sort((a, b) => a.score - b.score)
                        .map((p) => (
                          <div key={p.id} className="flex justify-between text-sm">
                            <span>{p.name}</span>
                            <b className="gold">{p.score}</b>
                          </div>
                        ))}
                    </div>
                    {me?.isHost && (
                      <button disabled={busy} onClick={() => void rematch()} className="primary w-full mt-5 disabled:opacity-40">
                        {busy ? "Opening new table…" : "Rematch · New room, same settings"}
                      </button>
                    )}
                    <button onClick={() => router.push("/")} className="secondary w-full mt-2">
                      Back to KARDEN
                    </button>
                  </section>
                ) : room.phase === "round_result" && room.roundResult ? (
                  <section className="panel result-panel p-5 mb-4">
                    <p className="eyebrow text-center mb-2">Round {room.round} result</p>
                    <h2 className="serif text-3xl text-center">{room.roundResult.burst ? "Caller burst" : "Clean call"}</h2>
                    <p className="muted text-xs text-center mt-2">
                      {room.roundResult.callerName} called with {room.roundResult.callerTotal}
                    </p>
                    {room.roundResult.burst && <p className="text-center text-sm text-amber-300 mt-2">Burst penalty +{room.roundResult.burstPenalty}</p>}
                    <div className="mt-5 space-y-2">
                      {room.roundResult.scores.map((s) => {
                        const p = room.players.find((x) => x.id === s.playerId);
                        return (
                          <div key={s.playerId} className="border-b border-white/5 pb-3">
                            <div className="flex justify-between text-sm">
                              <span>
                                {p?.name ?? "Player"} <span className="muted text-xs">({s.handTotal})</span>
                                {p?.eliminated && <span className="text-red-300 text-[10px] ml-2">OUT</span>}
                              </span>
                              <span className="gold text-xs">
                                +{s.added} · {p ? p.score - s.added : 0} → {p?.score ?? 0}
                              </span>
                            </div>
                            <div className="flex gap-1 mt-2">
                              {s.cards?.map((c) => (
                                <span key={c.id} className={`rounded-md bg-[#f5f0e4] px-1.5 py-1 text-[10px] font-bold ${c.suit === "H" || c.suit === "D" ? "text-red-700" : "text-black"}`}>
                                  {c.rank}
                                  {suitGlyph[c.suit]}
                                </span>
                              ))}
                            </div>
                          </div>
                        );
                      })}
                    </div>
                    {room.roundResult.winnerId ? (
                      <p className="text-center gold serif text-2xl mt-5">Winner: {room.players.find((p) => p.id === room.roundResult?.winnerId)?.name}</p>
                    ) : room.roundResult.tie ? (
                      <p className="text-center gold mt-5">It&apos;s a tie</p>
                    ) : (
                      <>
                        <p className="text-center muted text-xs mt-4">Next round starts with {room.players.find((p) => p.id === room.roundResult?.nextStarterId)?.name ?? "the next player"}</p>
                        <button disabled={busy} onClick={() => void action("karden_next_round")} className="primary w-full mt-4">
                          Deal next round
                        </button>
                      </>
                    )}
                    {room.status === "finished" && me?.isHost && (
                      <button disabled={busy} onClick={() => void rematch()} className="primary w-full mt-4 disabled:opacity-40">
                        {busy ? "Opening new table…" : "Rematch · New room, same settings"}
                      </button>
                    )}
                  </section>
                ) : (
                  <>
                    <div className="flex items-center justify-between mb-4">
                      <div className="text-xs muted">
                        ROUND <b className="text-white">{room.round}</b>
                      </div>
                      <div className="flex gap-2">
                        <button onClick={() => { setShowHostTools(false); setShowScores((v) => !v); }} className="secondary text-xs">
                          Scoreboard
                        </button>
                        {me?.isHost && (
                          <button onClick={() => { setShowScores(false); setShowHostTools((v) => !v); }} className="secondary text-xs gold">
                            Host
                          </button>
                        )}
                      </div>
                      <div className={`text-xs flex items-center gap-1 ${seconds <= 10 ? "text-red-300" : "gold"}`}>
                        <Clock size={13} />
                        {room.status === "paused" ? "Paused" : `${seconds}s`}
                      </div>
                    </div>
                    <section className="karden-table table-felt">
                      <div className="table-players">
                        {room.players
                          .filter((p) => p.id !== room.me.id && !p.eliminated)
                          .map((p) => (
                            <div key={p.id} className={`table-seat ${p.id === room.currentPlayerId ? "active-seat" : ""}`}>
                              <div className="seat-avatar">
                                <CharacterAvatar avatar={p.avatar} name={p.name} size={48} />
                                {p.isHost && (
                                  <span className="seat-crown">
                                    <Crown size={11} />
                                  </span>
                                )}
                              </div>
                              <span className="seat-name">{p.name}</span>
                              <span className="seat-score">{p.score}</span>
                              <div className="seat-cards">
                                {Array.from({
                                  length: Math.min(p.cardCount, 5),
                                }).map((_, i) => (
                                  <span className="mini-cardback" key={i} />
                                ))}
                              </div>
                            </div>
                          ))}
                      </div>
                      <div className="table-center">
                        <div className="table-piles">
                          <div className="pile-wrap">
                            <div className="cardback table-deck">
                              <span>♠</span>        </div>
                            <span className="pile-caption">DRAW · {room.drawCount}</span>
                          </div>
                          <div className="pile-wrap">
                            {room.topDiscard ? (
                              <button
                                type="button"
                                disabled={!isTurn || !!room.pendingPick || busy}
                                onClick={() =>
                                  void action("karden_take_card", {
                                    p_source: "open",
                                  })
                                }
                                className={`playing-card discard-card table-open-card ${room.topDiscard.suit === "H" || room.topDiscard.suit === "D" ? "red" : ""}`}
                                aria-label={`Pick open ${room.topDiscard.rank} ${room.topDiscard.suit}`}
                              >
                                <b>{room.topDiscard.rank}</b>
                                <span>{suitGlyph[room.topDiscard.suit]}</span>
                              </button>
                            ) : (
                              <div className="table-open-card empty-pile" />
                            )}
                            <span className="pile-caption">OPEN CARD</span>
                          </div>
                        </div>
                        <div className={`turn-pill ${seconds <= 10 && isTurn ? "turn-urgent" : ""}`}>
                          <span>{isTurn ? "Your Turn" : "Table Turn"}</span>
                          <b>
                            <Clock size={14} />
                            {room.status === "paused" ? "Paused" : `${seconds.toString().padStart(2, "0")}s`}
                          </b>
                        </div>
                        {canCall ? (
                          <button disabled={busy} onClick={() => void action("karden_call")} className="call-cta">
                            <span>♠</span> CALL
                          </button>
                        ) : (
                          <div className="call-placeholder">{isTurn ? (room.pendingPick ? "Choose your discard" : "Your move") : "Waiting for the table"}</div>
                        )}
                        {canCall && <p className="call-hint">Call before drawing · limit {room.config.callThreshold}</p>}
                      </div>
                      <div className={`self-seat ${isTurn ? "self-seat-active" : ""}`}>
                        <div className="seat-avatar">
                          <CharacterAvatar avatar={me?.avatar ?? "character-01"} name={me?.name ?? "You"} size={58} />
                        </div>
                        <span className="seat-name">{me?.name ?? "You"}</span>
                        <span className="seat-score">{me?.score ?? 0}</span>
                        <div className="seat-cards">
                          {Array.from({
                            length: Math.min(room.me.hand.length, 6),
                          }).map((_, i) => (
                            <span className="mini-cardback" key={i} />
                          ))}
                        </div>
                      </div>
                    </section>
                    <div className="mt-4">
                      <div className="flex justify-between items-center mb-2">
                        <span className="eyebrow">Your hand · {room.handTotal} points</span>
                        <span className="text-[10px] muted">{room.me.hand.length} cards</span>
                      </div>
                      <div className="hand-fan flex justify-center -space-x-3 overflow-x-auto py-3 px-1">
                        {sortedHand.map((card) => (
                          <PlayingCard key={card.id} card={card} selected={selected.includes(card.id)} disabled={!isTurn || !room.pendingPick || (selectedCards.length > 0 && card.rank !== selectedCards[0].rank && !selected.includes(card.id))} onClick={() => toggle(card.id)} />
                        ))}
                      </div>
                    </div>
                    <div className="table-actions">
                      <p className="action-hint">{!isTurn ? "Waiting for another player" : room.pendingPick ? "Select cards of the same rank to discard" : "Draw a card or pick the open card"}</p>
                      <div className="action-buttons">
                        <button type="button" onClick={() => setHandSort((v) => (v === "rank" ? "suit" : "rank"))} className="lounge-action">
                          <span>↕</span> Sort
                        </button>
                        <button
                          type="button"
                          disabled={!isTurn || busy || !!room.pendingPick}
                          onClick={() =>
                            void action("karden_take_card", {
                              p_source: "draw",
                            })
                          }
                          className="lounge-action"
                        >
                          <Layers size={17} /> Draw
                        </button>
                        <button
                          type="button"
                          disabled={!isTurn || busy || !room.pendingPick || selected.length === 0 || !sameRank}
                          onClick={() =>
                            void action("karden_discard_cards", {
                              p_card_ids: selected,
                            })
                          }
                          className="lounge-action lounge-action-gold"
                        >
                          <Shield size={17} /> Discard
                        </button>
                      </div>
                    </div>
                  </>
                )}
              </>
            )}
            {showChat && (
              <section className="panel p-4 mt-4">
                <div className="flex justify-between items-center mb-3">
                  <p className="eyebrow">Table chat</p>
                  <button onClick={() => setShowChat(false)} className="muted text-xs">
                    Close
                  </button>
                </div>
                <div className="max-h-48 overflow-y-auto space-y-2 mb-3">
                  {room.messages?.length ? (
                    room.messages.map((m) => (
                      <div key={m.id} className="flex gap-2 text-xs">
                        <span className="gold shrink-0">{m.name}</span>
                        <span className={m.kind === "reaction" ? "text-lg" : "text-[#d8ddd5]"}>{m.body}</span>
                        <span className="muted ml-auto shrink-0">
                          {new Date(m.createdAt).toLocaleTimeString([], {
                            hour: "2-digit",
                            minute: "2-digit",
                          })}
                        </span>
                      </div>
                    ))
                  ) : (
                    <p className="muted text-xs">No messages yet. Break the ice.</p>
                  )}
                </div>
                <div className="flex gap-2 mb-3">
                  {["👍", "😂", "🔥", "👏", "❤️", "😮"].map((emoji) => (
                    <button key={emoji} disabled={busy} onClick={() => void sendChat(emoji, "reaction")} className="rounded-lg bg-white/5 px-2 py-1.5 text-lg disabled:opacity-40">
                      {emoji}
                    </button>
                  ))}
                </div>
                <form
                  onSubmit={(e) => {
                    e.preventDefault();
                    void sendChat(chatText, "text");
                  }}
                  className="flex gap-2"
                >
                  <input value={chatText} onChange={(e) => setChatText(e.target.value)} maxLength={240} placeholder="Send a message…" className="field min-w-0" />
                  <button disabled={busy || !chatText.trim()} className="primary !px-3 disabled:opacity-40">
                    <Send size={16} />
                  </button>
                </form>
              </section>
            )}
            {showScores && (
              <section role="dialog" aria-modal="true" aria-label="Scoreboard" className="panel fixed inset-x-4 bottom-4 z-50 mx-auto max-w-lg p-4 max-h-[70dvh] overflow-y-auto shadow-2xl">
                <div className="flex justify-between mb-3">
                  <p className="eyebrow">Cumulative scores</p>
                  <button onClick={() => setShowScores(false)} className="muted text-xs">
                    Close
                  </button>
                </div>
                {room.players
                  .slice()
                  .sort((a, b) => a.score - b.score)
                  .map((p) => (
                    <div key={p.id} className="flex justify-between text-xs py-2 border-b border-white/5">
                      <span>
                        {p.name}
                        {p.eliminated ? " · OUT" : ""}
                      </span>
                      <b className="gold">
                        {p.score} / {room.config.maxScore}
                      </b>
                    </div>
                  ))}
              </section>
            )}
            {showHostTools && me?.isHost && (
              <section role="dialog" aria-modal="true" aria-label="Host controls" className="panel fixed inset-x-4 bottom-4 z-50 mx-auto max-w-lg p-4 max-h-[70dvh] overflow-y-auto shadow-2xl">
                <div className="flex justify-between items-center mb-3">
                  <p className="eyebrow">Host controls</p>
                  <button onClick={() => setShowHostTools(false)} className="muted text-xs">
                    Close
                  </button>
                </div>
                <div className="grid grid-cols-2 gap-2">
                  {room.status === "paused" ? (
                    <button onClick={() => void action("karden_resume_room")} className="primary text-xs">
                      Resume timer
                    </button>
                  ) : (
                    <button onClick={() => void action("karden_pause_room")} disabled={room.status !== "playing"} className="secondary text-xs">
                      Pause timer
                    </button>
                  )}
                  <button
                    onClick={() => {
                      if (confirm("End this room for everyone?")) void action("karden_end_room");
                    }}
                    className="secondary text-xs text-red-300"
                  >
                    End room
                  </button>
                </div>
                <div className="mt-4 space-y-2">
                  {room.players
                    .filter((p) => p.id !== room.me.id && !p.eliminated)
                    .map((p) => (
                      <div key={p.id} className="flex justify-between items-center text-xs">
                        <span>{p.name}</span>
                        <button
                          onClick={() =>
                            void action("karden_kick_player", {
                              p_player_id: p.id,
                            })
                          }  className="text-red-300 border border-red-900/50 rounded-lg px-2 py-1"
                        >
                          Remove
                        </button>
                      </div>
                    ))}
                </div>
              </section>
            )}
            <p className="text-center muted text-[10px] mt-5 tracking-wider uppercase">{room.lastAction ?? "KARDEN · Private table"}</p>
          </>
        )}
      </div>
    </main>
  );
}