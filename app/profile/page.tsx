"use client";
import { useEffect,useState } from "react";
import Link from "next/link";
import Image from "next/image";
import { ArrowLeft,Spade,Trophy,Gamepad2,Medal,Users,Save } from "lucide-react";
import { ensureGuest,supabase } from "@/lib/supabase";
import { CharacterAvatar,CHARACTER_AVATARS,DEFAULT_AVATAR } from "@/components/character-avatar";

type Profile={displayName:string;avatar:string;gamesPlayed:number;wins:number;losses:number;draws:number};

export default function ProfilePage(){
 const [profile,setProfile]=useState<Profile|null>(null);const [name,setName]=useState("");const [avatar,setAvatar]=useState(DEFAULT_AVATAR);const [error,setError]=useState("");const [busy,setBusy]=useState(false);const [saved,setSaved]=useState(false);
 useEffect(()=>{let active=true;void(async()=>{try{await ensureGuest();const {data,error}=await supabase().rpc("karden_my_profile");if(error)throw error;if(!active)return;const p=data as Profile;setProfile(p);setName(p.displayName==="Player"?"":p.displayName);setAvatar(p.avatar?.startsWith("character-")?p.avatar:DEFAULT_AVATAR)}catch(e){if(active)setError(e instanceof Error?e.message:"Could not load your profile.")}})();return()=>{active=false}},[]);
 async function save(){setBusy(true);setSaved(false);setError("");try{const {data,error}=await supabase().rpc("karden_update_profile",{p_display_name:name.trim(),p_avatar:avatar});if(error)throw error;setProfile(data as Profile);setSaved(true)}catch(e){setError(e instanceof Error?e.message:"Could not save profile.")}finally{setBusy(false)}}
 const rate=profile&&profile.gamesPlayed?Math.round(profile.wins/profile.gamesPlayed*100):0;
 return <main className="min-h-screen px-5 py-8 flex justify-center"><div className="w-full max-w-md">
 <header className="flex items-center justify-between mb-10"><Link href="/" className="secondary !p-2"><ArrowLeft size={18}/></Link><div className="flex items-center gap-2 tracking-[.25em] text-xs"><Spade size={15} className="gold"/> KARDEN</div><span className="eyebrow">Profile</span></header>
 <p className="eyebrow mb-2">Your club record</p><h1 className="serif text-4xl gold mb-7">Player profile</h1>
 {error&&<section className="panel p-4 mb-4 text-sm text-red-200">{error}</section>}
 {!profile?<section className="panel p-5 text-sm muted">Loading your profile…</section>:<>
 <section className="panel p-5 mb-4"><div className="flex items-center gap-3 mb-5"><div className="w-14 h-14 rounded-full border border-[var(--line)] bg-[#1c3025] flex items-center justify-center overflow-hidden">{avatar.startsWith("https://")?<Image src={avatar} alt="Your uploaded avatar" width={56} height={56} unoptimized className="w-full h-full object-cover"/>:<CharacterAvatar avatar={avatar} name={name||profile.displayName} size={56}/>}</div><div><p className="serif text-xl">{name||profile.displayName}</p><p className="muted text-xs mt-1">Private club member · Guest account</p></div></div>
 <label className="label">Display name</label><input className="field mb-4" maxLength={24} value={name} placeholder="Your table name" onChange={e=>{setName(e.target.value);setSaved(false)}}/>
 <label className="label">Your character</label><div className="grid grid-cols-4 gap-3 mb-4">{CHARACTER_AVATARS.map(v=><button key={v} type="button" aria-label={`Choose character ${v.slice(-2)}`} onClick={()=>{setAvatar(v);setSaved(false)}} className={`rounded-2xl p-2 border flex justify-center transition-all ${avatar===v?"border-[#c9a96e] bg-[#c9a96e]/10":"border-white/10 bg-white/[.03]"}`}><CharacterAvatar avatar={v} name="Character" size={58}/></button>)}</div>
 {avatar.startsWith("https://")&&<p className="text-xs muted mb-3">Your uploaded photo is active. Choose a character to switch back.</p>}
 <button onClick={()=>void save()} disabled={busy||!name.trim()||name.trim().length>24} className="primary w-full flex items-center justify-center gap-2 disabled:opacity-40">{busy?"Saving…":saved?"Saved":"Save profile"}<Save size={15}/></button>
 </section>
 <div className="grid grid-cols-2 gap-3 mb-4">
 <section className="panel p-4"><div className="flex items-center gap-2 gold mb-2"><Gamepad2 size={16}/><span className="eyebrow">Games</span></div><p className="serif text-3xl">{profile.gamesPlayed}</p><p className="muted text-xs mt-1">Completed matches</p></section>
 <section className="panel p-4"><div className="flex items-center gap-2 gold mb-2"><Trophy size={16}/><span className="eyebrow">Wins</span></div><p className="serif text-3xl">{profile.wins}</p><p className="muted text-xs mt-1">{rate}% win rate</p></section>
 <section className="panel p-4"><div className="flex items-center gap-2 gold mb-2"><Medal size={16}/><span className="eyebrow">Losses</span></div><p className="serif text-3xl">{profile.losses}</p><p className="muted text-xs mt-1">Matches lost</p></section>
 <section className="panel p-4"><div className="flex items-center gap-2 gold mb-2"><Users size={16}/><span className="eyebrow">Draws</span></div><p className="serif text-3xl">{profile.draws}</p><p className="muted text-xs mt-1">Tied matches</p></section>
 </div>
 <p className="muted text-xs leading-5 text-center px-3">Your record is linked to this guest session. Keep this browser&apos;s site data to retain access to your club profile.</p>
 </>}
 <Link href="/" className="primary block text-center mt-7">Back to the table</Link>
 </div></main>;
}
