export type RoomConfig={maxPlayers:number;initialCards:number;decks:number;maxScore:number;burstPenalty:number;callThreshold:number;turnSeconds:number;jokerRank:string};
export type Card={id:string;rank:string;suit:"S"|"H"|"D"|"C";value:number};
export type Player={id:string;name:string;avatar:string;seat:number;score:number;eliminated:boolean;connected:boolean;cardCount:number;isHost:boolean};
export type RoundScore={playerId:string;handTotal:number;added:number;cards:Card[]};
export type RoundResult={callerId:string;callerName:string;callerTotal:number;burst:boolean;burstPenalty:number;scores:RoundScore[];nextStarterId:string|null;winnerId:string|null;tie:boolean};
export type RoomSnapshot={roomId:string;code:string;status:"lobby"|"playing"|"paused"|"finished";config:RoomConfig;round:number;currentPlayerId:string|null;turnDeadline:string|null;players:Player[];me:{id:string;hand:Card[]};drawCount:number;topDiscard:Card|null;lastAction:string|null;phase:"playing"|"round_result";roundResult:RoundResult|null;pendingPick:boolean;handTotal:number};
