"use client";
export const DEFAULT_AVATAR="character-01";
export const CHARACTER_AVATARS=Array.from({length:8},(_,i)=>`character-${String(i+1).padStart(2,"0")}`);
const STORED_AVATARS=["ace","♠","♥","♦","♣","🦊","🐺","🦅"];
export function toStoredAvatar(avatar:string){const index=CHARACTER_AVATARS.indexOf(avatar);return index>=0?STORED_AVATARS[index]:avatar;}
export function toCharacterAvatar(avatar:string){if(avatar.startsWith("https://"))return avatar;const characterIndex=CHARACTER_AVATARS.indexOf(avatar);if(characterIndex>=0)return avatar;const storedIndex=STORED_AVATARS.indexOf(avatar);return storedIndex>=0?CHARACTER_AVATARS[storedIndex]:DEFAULT_AVATAR;}

const looks=[
 {skin:"#D99B72",hair:"#24201F",shirt:"#B58A50",hairPath:"M18 29Q18 8 40 8Q62 8 62 31L57 27Q53 18 40 19Q26 18 23 31Z"},
 {skin:"#F0C49B",hair:"#6D3D2A",shirt:"#557A67",hairPath:"M18 31Q17 8 40 8Q63 8 62 32L56 23Q51 15 39 16Q27 16 22 27Z"},
 {skin:"#9B6248",hair:"#17191D",shirt:"#718AA8",hairPath:"M17 30Q15 8 40 8Q65 8 63 31L57 24Q53 17 40 18Q26 17 22 25Z"},
 {skin:"#E8B98D",hair:"#B77B39",shirt:"#9A6B8D",hairPath:"M17 34Q13 9 40 8Q67 9 63 34L57 25Q54 16 40 16Q26 16 23 26Z"},
 {skin:"#C78360",hair:"#292A32",shirt:"#4F7779",hairPath:"M17 32Q17 7 40 8Q63 7 63 32L56 23Q51 18 40 18Q28 18 23 25Z"},
 {skin:"#F2C9A8",hair:"#3C2A27",shirt:"#A36B59",hairPath:"M17 33Q14 8 40 8Q66 8 63 33L57 25Q52 17 40 17Q27 17 22 26Z"},
 {skin:"#A86C50",hair:"#171717",shirt:"#A28C55",hairPath:"M18 32Q15 8 40 8Q65 8 62 32L56 25Q51 17 40 18Q28 17 23 25Z"},
 {skin:"#DCA77F",hair:"#5B3828",shirt:"#786B9A",hairPath:"M17 32Q15 8 40 8Q65 8 63 32L57 24Q51 17 40 17Q28 17 22 25Z"}
];

export function CharacterAvatar({avatar=DEFAULT_AVATAR,name="Player",size=44,className=""}:{avatar?:string;name?:string;size?:number;className?:string}){
 if(avatar.startsWith("https://"))return <img src={avatar} alt={`${name} avatar`} width={size} height={size} className={`rounded-full object-cover ${className}`}/>;
 const index=Number(avatar.match(/character-(\d+)/)?.[1]??1)-1;
 const look=looks[((index%looks.length)+looks.length)%looks.length];
 return <svg role="img" aria-label={`${name} character avatar`} width={size} height={size} viewBox="0 0 80 80" className={className} style={{flexShrink:0}}>
  <circle cx="40" cy="40" r="39" fill="#183a2c"/><circle cx="25" cy="22" r="25" fill="#ffffff" opacity=".035"/>
  <path d="M11 80Q13 57 40 57Q67 57 69 80Z" fill={look.shirt}/>
  <path d="M25 36Q15 25 19 43Q21 51 28 48M55 36Q65 25 61 43Q59 51 52 48" fill={look.skin} stroke="#3A2924" strokeWidth="1.5"/>
  <ellipse cx="40" cy="39" rx="21" ry="24" fill={look.skin}/>
  <path d={look.hairPath} fill={look.hair}/>
  <path d="M30 39Q34 36 37 39M44 39Q48 36 51 39" fill="none" stroke="#38251F" strokeWidth="2" strokeLinecap="round"/>
  <ellipse cx="34" cy="43" rx="2" ry="2.8" fill="#241D1B"/><ellipse cx="47" cy="43" rx="2" ry="2.8" fill="#241D1B"/>
  <path d="M36 52Q40 55 45 51" fill="none" stroke="#8C4F43" strokeWidth="1.8" strokeLinecap="round"/>
  <circle cx="26" cy="49" r="3" fill="#E78F83" opacity=".35"/><circle cx="54" cy="49" r="3" fill="#E78F83" opacity=".35"/>
  <circle cx="40" cy="40" r="38.5" fill="none" stroke="#C9A96E" strokeOpacity=".6"/>
 </svg>;
}
