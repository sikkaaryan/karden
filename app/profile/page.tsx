"use client";
import { useEffect,useState } from "react";
import Link from "next/link";
import { ArrowLeft,Spade,Trophy,Gamepad2,Medal,Users } from "lucide-react";
import { ensureGuest,supabase } from "@/lib/supabase";

type Profile={displayName:string;avatar:string;gamesPlayed:number;wins:number;losses:number;draws:number};
export default function ProfilePage(){
 const [profile,setProfile]=useState<Profile|null>(null);const [error,setError]=useState("");
 useEffect(()=>{void(async()=>{try{await ensureGuest();const {data,error}=await supabase().rpc("karden_my_profile");if(error)throw error;setProfile(data as Profile)}catch(e){setError(e instanceof Error?e.message:"Could not load your profile.")}})()},[]);
 const rate=profile&&profile.gamesPlayed?Math.round(profile.wins/profile.gamesPlayed*100):0;
 return <main className="min-h-screen px-5 py-8 flex justify-center"><div className="w-full max-w-md">
 <header className="flex items-center justify-between mb-10"><Link href="/" className="secondary !p-2"><ArrowLeft size={18}/></Link><div className="flex items-center gap-2 tracking-[.25em] text-xs"><Spade size={15} className="gold"/> KARDEN</div><span className="eyebrow">Profile</span></header>
 <p className="eyebrow mb-2">Your club record</p><h1 className="serif text-4xl gold mb-7">Player profile</h1>
 {error?<section className="panel p-5 text-sm text-red-200">{error}</section>:!profile?<section className="panel p-5 text-sm muted">Loading your profile…</section>:<>
 <section className="panel p-6 mb-4 text-center"><div className="w-20 h-20 rounded-full mx-auto mb-4 border border-[var(--line)] bg-[#1c3025] flex items-center justify-center overflow-hidden text-3xl gold">{profile.avatar.startsWith("https://")?<img src={profile.avatar} alt="" className="w-full h-full object-cover"/>:profile.avatar==="ace"?profile.displayName.slice(0,1).toUpperCase():profile.avatar}</div><h2 className="serif text-2xl">{profile.displayName}</h2><p className="muted text-xs mt-2">Private club member · Guest account</p></section>
 <div className="grid grid-cols-2 gap-3 mb-4">
 <section className="panel p-4"><div className="flex items-center gap-2 gold mb-2"><Gamepad2 size={16}/><span className="eyebrow">Games</span></div><p className="serif text-3xl">{profile.gamesPlayed}</p><p className="muted text-xs mt-1">Completed matches</p></section>
 <section className="panel p-4"><div className="flex items-center gap-2 gold mb-2"><Trophy size={16}/><span className="eyebrow">Wins</span></div><p className="serif text-3xl">{profile.wins}</p><p className="muted text-xs mt-1">{rate}% win rate</p></section>
 <section className="panel p-4"><div className="flex items-center gap-2 gold mb-2"><Medal size={16}/><span className="eyebrow">Losses</span></div><p className="serif text-3xl">{profile.losses}</p><p className="muted text-xs mt-1">Matches lost</p></section>
 <section className="panel p-4"><div className="flex items-center gap-2 gold mb-2"><Users size={16}/><span className="eyebrow">Draws</span></div><p className="serif text-3xl">{profile.draws}</p><p className="muted text-xs mt-1">Tied matches</p></section>
 </div>
 <p className="muted text-xs leading-5 text-center px-3">Your profile is linked to this guest session. Clearing this browser&apos;s site data may reset access to your club record.</p>
 </>}
 <Link href="/" className="primary block text-center mt-7">Back to the table</Link>
 </div></main>;
}
