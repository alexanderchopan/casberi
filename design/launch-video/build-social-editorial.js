// Farcaster + Bluesky promos — EDITORIAL, no app screenshots. ONE generator,
// two clips, because the two networks share one renderer (Model/SocialBridge)
// and the 2026-07-27 social pass landed on both:
//   item 1  a cast/post sharing an ARTICLE lands that article as its own
//           `.link` thing (FarcasterIngest.linkEmbed / BlueskyIngest.linkEmbed
//           + landLinkedArticle). Bluesky's embed card carries the title and
//           thumb inline; Farcaster's renames itself once LinkTitle.enrich
//           fetches the real <title>.
//   item 2  the PERSON ROOM (Screens/PersonRoomScreen) — everything held about
//           one person in one chronology, filterable Everything/Posts/Onchain.
//           The onchain half is FARCASTER-ONLY: it joins the wallet moves of a
//           verified address (FarcasterIngest.verifiedEthAddresses). Bluesky
//           has no verified-address concept, so its room is words only.
//   item 5  SocialRosterHero — the social room's head is the roster's faces,
//           with a RING on anyone who posted since the room was last opened.
//   item 6  ThreadFold — consecutive self-replies fold into one card, rendered
//           oldest→newest, "the order the person actually wrote it in".
//   item 7  every attached image shows, not just the first.
// Everything else in each clip is shipped behaviour already documented in
// CLAUDE.md (keyless follow-by-name, likes/mentions/channels, replies, quotes
// and parents, follow import). Bluesky's likes stay UNBUILT and the clip says
// so — catalog copy: "Likes arrive with sign-in, later."
//
//   node build-social-editorial.js          # writes both HTMLs
//   node render.js clip-farcaster-2026.html --size=1080x1920
//   node render.js clip-bluesky-2026.html   --size=1080x1920
const fs = require('fs'), path = require('path');

const VIOLET = '#855dcd', SKY = '#0085ff', GREEN = '#3fb950', AMBER = '#ff9f0a';
const PURPLE = '#A526E8';   // Nostr — deliberately vivid, so it never reads as Farcaster's muted violet

const NETS = [
  {
    file: 'clip-farcaster-2026.html', mast: 'FARCASTER', brand: VIOLET,
    handle: '@dwr', display: 'Dan',            // decorative only — see NOTE below
    beats: [
      { kick: 'JUST A USERNAME', head: 'Follow anyone.\nNo sign-in.',       accent: VIOLET, card: 'follow' },
      { kick: 'ALL OF IT',       head: 'Casts, likes,\nmentions, channels.', accent: VIOLET, card: 'kinds' },
      { kick: 'WHOLE THREADS',   head: 'A chain reads\nlike a chain.',      accent: VIOLET, card: 'thread' },
      { kick: 'NOT JUST WORDS',  head: 'Every image.\nEvery article.',      accent: AMBER,  card: 'media' },
      { kick: 'THE PERSON ROOM', head: 'Their words\nbeside their money.',  accent: GREEN,  card: 'room' },
      { kick: "WHO'S NEW",       head: 'A ring on\nwhoever posted.',        accent: VIOLET, card: 'roster' },
    ],
    followSub: 'plus /channels by name',
    kinds: [
      { n: 'Casts',    s: 'Everything they post' },
      { n: 'Likes',    s: 'What they liked, when they liked it' },
      { n: 'Mentions', s: 'Casts naming them' },
      { n: 'Channels', s: '/design, /dev — followed by name' },
    ],
    roomFilters: ['Everything', 'Posts', 'Onchain'],
    roomRows: [
      { k: 'post',  t: '"Shipping the merge today."', s: '2h ago' },
      { k: 'chain', t: 'Swapped 0.5 ETH → 1,240 USDC', s: '3h ago' },
      { k: 'post',  t: '"Decimals were the whole bug."', s: 'yesterday' },
      { k: 'chain', t: 'Received 500 USDC', s: 'yesterday' },
    ],
    roomCap: 'A verified address joins their casts.<br><b>Nowhere else puts both in one line.</b>',
    closeCap: null,
  },
  {
    file: 'clip-bluesky-2026.html', mast: 'BLUESKY', brand: SKY,
    handle: '@alice.bsky.social', display: 'Alice',
    beats: [
      { kick: 'JUST A HANDLE',   head: 'Follow anyone.\nNo password.',      accent: SKY,   card: 'follow' },
      { kick: 'ALL OF IT',       head: 'Posts, mentions,\nand custom feeds.', accent: SKY,  card: 'kinds' },
      { kick: 'WHOLE THREADS',   head: 'A chain reads\nlike a chain.',      accent: SKY,   card: 'thread' },
      { kick: 'NOT JUST WORDS',  head: 'Every image.\nEvery article.',      accent: AMBER, card: 'media' },
      { kick: 'THE PERSON ROOM', head: 'Everything they\nsaid, in one place.', accent: GREEN, card: 'room' },
      { kick: 'ONE HONEST GAP',  head: "What we don't\nclaim to have.",     accent: AMBER, card: 'gap' },
    ],
    followSub: 'your own handle, or anyone\'s',
    kinds: [
      { n: 'Posts',    s: 'Everything they publish' },
      { n: 'Mentions', s: 'Posts naming them' },
      { n: 'Feeds',    s: 'Any custom feed, found by search' },
      { n: 'Replies',  s: 'The whole thread, faces and all' },
    ],
    roomFilters: ['Everything', 'Posts'],
    roomRows: [
      { k: 'post', t: '"Finally moved off the old stack."', s: '2h ago' },
      { k: 'post', t: '"The migration notes are public."',  s: '5h ago' },
      { k: 'post', t: '"Thanks for all the replies here."', s: 'yesterday' },
      { k: 'post', t: '"Shipping notes, part two."',        s: 'yesterday' },
    ],
    roomCap: 'Their posts, their replies, their links —<br><b>one chronology, not a search.</b>',
    closeCap: 'Likes need a sign-in, so we don\'t pretend<br><b>to have them. They arrive later.</b>',
  },
  {
    // Nostr (Model/NostrIngest.swift + NostrRelay.swift, 2026-07-27) — the
    // third social bridge, a full member of SocialBridge.sources, so it
    // inherits the person room, thread fold, roster and image handling for
    // free. Protocol-specific: relays not a host (NIP-01 over WebSocket, the
    // ONE socket in the app), reactions (kind:7) stand in for likes, #p tags
    // for mentions, a followed #hashtag for a channel, and identity is an
    // npub / raw hex pubkey / NIP-05 name@domain. There is deliberately NO
    // SEARCH — no reliable global user-search API exists, so you paste.
    file: 'clip-nostr-2026.html', mast: 'NOSTR', brand: PURPLE,
    handle: 'you@yourdomain.com', display: 'Ada',
    beats: [
      { kick: 'NO COMPANY',      head: 'Nobody hosts it.\nRelays just answer.', accent: PURPLE, card: 'relays' },
      { kick: 'PASTE AN IDENTITY', head: 'An npub, a key,\nor name@domain.',    accent: PURPLE, card: 'follow' },
      { kick: 'ALL OF IT',       head: 'Notes, reactions,\nmentions, #tags.',   accent: PURPLE, card: 'kinds' },
      { kick: 'WHOLE THREADS',   head: 'A chain reads\nlike a chain.',          accent: PURPLE, card: 'thread' },
      { kick: 'NOT JUST WORDS',  head: 'Every image.\nEvery article.',          accent: AMBER,  card: 'media' },
      { kick: 'THE PERSON ROOM', head: 'Everything they\nsaid, in one place.',  accent: GREEN,  card: 'room' },
    ],
    followSub: 'no search — you paste who you want',
    kinds: [
      { n: 'Notes',     s: 'Everything they publish' },
      { n: 'Reactions', s: 'What they reacted to (kind:7)' },
      { n: 'Mentions',  s: 'Notes tagging their key' },
      { n: '#hashtags', s: 'Followed by name, like a channel' },
    ],
    roomFilters: ['Everything', 'Notes'],
    roomRows: [
      { k: 'post', t: '"Relays answered in under a second."', s: '2h ago' },
      { k: 'post', t: '"No account, no key, no signup."',     s: '5h ago' },
      { k: 'post', t: '"Posting this from three clients."',   s: 'yesterday' },
      { k: 'post', t: '"The protocol is the product."',       s: 'yesterday' },
    ],
    roomCap: 'Their notes, their replies, their links —<br><b>one chronology, not a search.</b>',
    closeCap: null,
    relays: ['wss://nos.lol', 'wss://relay.damus.io'],
  },
];

// NOTE (memory, hard rule): the Farcaster account "dwr" is never connected,
// featured, or named in any demo, screenshot or marketing material. The handle
// below is therefore a neutral placeholder, not a real account being shown.
NETS[0].handle = '@yourfriend';
NETS[0].display = 'Ada';

const build = (N) => {
  const INTRO = 0.45, BEAT = 2.9;
  const OUT_AT = INTRO + N.beats.length * BEAT, TOTAL = OUT_AT + 1.9;
  const DATA = N.beats.map(b => ({ kick: b.kick, head: b.head, accent: b.accent }));

  const card = (b, i) => {
    if (b.card === 'relays') return `
      <div class="shd mono">HOW IT READS</div>
      <div class="rnode" id="rme${i}"><span class="rdotb" style="background:${N.brand}"></span><span class="rn2">This iPhone</span></div>
      <div class="rfan">${(N.relays||[]).map((r,j)=>`<div class="rlink" id="rl${i}_${j}"><span class="rline"></span><span class="rhost mono">${r}</span></div>`).join('')}</div>
      <div class="rnote" id="rnote${i}">A plain read. <b>No account, no key</b> — measured against every relay listed.</div>
      <div class="cap">No company owns the feed.<br><b>Whichever relay answers, answers.</b></div>`;
    if (b.card === 'follow') return `
      <div class="shd mono">CONNECT</div>
      <div class="field" id="field${i}"><span id="typed${i}"></span><span class="caret" id="caret${i}"></span></div>
      <div class="fsub">${N.followSub}</div>
      <div class="pledge"><span class="pdot"></span><span>No password. Nothing stored but the name.</span></div>
      <div class="cap">It's an open protocol —<br><b>the posts were already public.</b></div>`;
    if (b.card === 'kinds') return `
      <div class="shd mono">WHAT LANDS</div>
      ${N.kinds.map((k, j) => `<div class="krow" data-i="${j}"><span class="kdot" style="background:${N.brand}"></span><div><div class="kn">${k.n}</div><div class="ks">${k.s}</div></div></div>`).join('')}`;
    if (b.card === 'thread') return `
      <div class="shd mono">SELF-REPLIES, FOLDED</div>
      <div class="tcard">
        <div class="thead"><span class="tav" style="background:${N.brand}"></span><div><div class="tn">${N.display}</div><div class="tt">${N.handle} · 4h ago</div></div></div>
        <div class="treply" data-i="0"><span class="trule"></span><span>Been chasing this bug all morning.</span></div>
        <div class="treply" data-i="1"><span class="trule"></span><span>Turns out the decimals diverge per token.</span></div>
        <div class="treply" data-i="2"><span class="trule"></span><span>Fixed. Shipping it tonight.</span></div>
      </div>
      <div class="cap">Oldest to newest —<br><b>the order they actually wrote it.</b></div>`;
    if (b.card === 'media') return `
      <div class="shd mono">EMBEDS</div>
      <div class="gal">${[0,1,2].map(j=>`<span class="gcell" id="g${i}_${j}" style="background:linear-gradient(${130+j*24}deg,#3b4d70,#1e2a42)"></span>`).join('')}</div>
      <div class="galcap">Every attached image, not just the first</div>
      <div class="lcard" id="lcard${i}">
        <span class="lthumb"></span>
        <div><div class="lt">The case for open social protocols</div><div class="lh">theverge.com</div></div>
      </div>
      <div class="cap">A shared article lands as<br><b>its own thing you can find later.</b></div>`;
    if (b.card === 'room') return `
      <div class="shd mono">THE PERSON ROOM</div>
      <div class="rhead"><span class="rav" style="background:${N.brand}"></span><div><div class="rn">${N.display}</div><div class="rh">${N.handle}</div></div></div>
      <div class="segs">${N.roomFilters.map((f,j)=>`<span class="seg${j===0?' on':''}" style="${j===0?`background:${N.brand}`:''}">${f}</span>`).join('')}</div>
      ${N.roomRows.map((r,j)=>`<div class="rrow" data-i="${j}"><span class="rdot" style="background:${r.k==='chain'?GREEN:N.brand}"></span><div><div class="rt">${r.t}</div><div class="rs">${r.s}</div></div></div>`).join('')}
      <div class="cap">${N.roomCap}</div>`;
    if (b.card === 'roster') return `
      <div class="shd mono">THE ROOM'S OWN HEAD</div>
      <div class="faces">${[0,1,2,3,4].map(j=>`<span class="face" id="fc${i}_${j}"><span class="fin" style="background:${['#f2a03d','#6ec1a0','#c98bd6','#7fa8e8','#e8807f'][j]}"></span></span>`).join('')}</div>
      <div class="facecap">Everyone you follow here</div>
      <div class="cap">A ring means they've posted<br><b>since you last looked in.</b></div>`;
    if (b.card === 'gap') return `
      <div class="shd mono">NOT BUILT — AND WE SAY SO</div>
      <div class="grow" data-i="0"><s>✕</s><div><div class="gn">Likes</div><div class="gs">The API needs an authenticated sign-in</div></div></div>
      <div class="ggood"><i>✓</i> Everything else needs nothing at all</div>
      <div class="cap">${N.closeCap}</div>`;
    return '';
  };

  return `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><style>
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box;transition:none!important}
html,body{width:1080px;height:1920px;overflow:hidden;background:#EEEAE1;font-family:-apple-system,"Helvetica Neue","SF Pro Display",system-ui,sans-serif;-webkit-font-smoothing:antialiased;}
.mono{font-family:ui-monospace,"SF Mono","Menlo",monospace;}
.stage{position:absolute;inset:0;overflow:hidden;background:#EEEAE1;}
.grain{position:absolute;inset:0;opacity:.5;background-image:radial-gradient(circle at 20% 30%, rgba(0,0,0,.03) 0 1px, transparent 1px),radial-gradient(circle at 70% 65%, rgba(0,0,0,.025) 0 1px, transparent 1px);background-size:7px 7px, 9px 9px;}
.mast{position:absolute;left:70px;right:70px;top:74px;display:flex;justify-content:space-between;font-size:27px;letter-spacing:.16em;color:#14110d;font-weight:600;}
.rule{position:absolute;left:70px;right:70px;top:126px;height:3px;background:#14110d;transform-origin:left;}
.wm{position:absolute;right:20px;top:150px;font-size:280px;line-height:.82;white-space:nowrap;text-align:right;font-weight:800;letter-spacing:-.04em;opacity:.08;will-change:opacity,transform;}
.kick{position:absolute;left:74px;top:238px;font-size:32px;letter-spacing:.14em;font-weight:600;will-change:transform,opacity;}
.head{position:absolute;left:70px;top:284px;right:70px;font-size:98px;line-height:.98;font-weight:800;letter-spacing:-.045em;color:#14110d;white-space:pre-line;will-change:transform,opacity;}
.foot{position:absolute;left:74px;right:74px;bottom:70px;display:flex;justify-content:space-between;font-size:26px;letter-spacing:.12em;color:#14110d;font-weight:600;}
.wipe{position:absolute;top:-12%;left:0;width:135%;height:124%;transform:skewX(-9deg) translateX(160%);will-change:transform;}
.comp{position:absolute;left:120px;top:800px;width:840px;height:860px;border-radius:34px;overflow:hidden;box-shadow:34px 40px 0 rgba(20,17,13,.13), inset 0 0 0 1px rgba(255,255,255,.05), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:52px;color:#fff;background:#0d0a16;display:flex;flex-direction:column;justify-content:center;}
.comp > .shd{position:absolute;top:52px;left:52px;right:52px;margin:0;font-size:24px;letter-spacing:.12em;color:rgba(255,255,255,.45);}
.cap{margin-top:30px;font-size:26px;font-weight:650;color:rgba(255,255,255,.75);text-align:center;line-height:1.45;}
.cap b{color:#fff;}
/* relays */
.rnode{display:flex;align-items:center;gap:18px;background:rgba(255,255,255,.07);border-radius:20px;padding:22px 26px;justify-content:center;}
.rdotb{width:20px;height:20px;border-radius:50%;flex:none;}
.rn2{font-size:28px;font-weight:700;}
.rfan{margin:10px 0 6px;}
.rlink{display:flex;flex-direction:column;align-items:center;gap:10px;will-change:opacity;}
.rline{width:3px;height:34px;border-radius:2px;background:rgba(255,255,255,.2);}
.rhost{font-size:24px;font-weight:700;color:rgba(255,255,255,.8);background:rgba(255,255,255,.06);border-radius:100px;padding:14px 26px;}
.rnote{margin-top:22px;text-align:center;font-size:22px;color:rgba(255,255,255,.5);font-weight:600;will-change:opacity;}
.rnote b{color:#fff;}
/* follow */
.field{background:rgba(255,255,255,.07);border-radius:100px;padding:24px 30px;font-size:30px;font-weight:650;box-shadow:inset 0 0 0 2px rgba(255,255,255,.1);display:flex;align-items:center;}
.caret{width:3px;height:32px;background:#fff;margin-left:3px;display:inline-block;}
.fsub{margin-top:16px;text-align:center;font-size:22px;color:rgba(255,255,255,.4);font-weight:600;}
.pledge{margin-top:30px;display:flex;align-items:center;gap:16px;justify-content:center;font-size:23px;color:rgba(255,255,255,.6);font-weight:600;}
.pdot{width:12px;height:12px;border-radius:50%;background:${GREEN};flex:none;}
/* kinds */
.krow{display:flex;align-items:center;gap:20px;padding:20px 0;will-change:opacity,transform;}
.kdot{width:16px;height:16px;border-radius:50%;flex:none;margin:0 18px;}
.kn{font-size:29px;font-weight:700;}
.ks{font-size:21px;color:rgba(255,255,255,.44);margin-top:3px;}
/* thread */
.tcard{background:rgba(255,255,255,.05);border-radius:24px;padding:30px;}
.thead{display:flex;align-items:center;gap:16px;margin-bottom:22px;}
.tav{width:52px;height:52px;border-radius:50%;flex:none;}
.tn{font-size:26px;font-weight:700;} .tt{font-size:20px;color:rgba(255,255,255,.42);margin-top:2px;}
.treply{display:flex;align-items:flex-start;gap:18px;padding:14px 0;font-size:24px;color:rgba(255,255,255,.82);line-height:1.4;will-change:opacity,transform;}
.trule{width:3px;align-self:stretch;min-height:30px;border-radius:2px;background:rgba(255,255,255,.18);flex:none;margin-left:24px;}
/* media */
.gal{display:grid;grid-template-columns:repeat(3,1fr);gap:14px;}
.gcell{aspect-ratio:1;border-radius:18px;display:block;will-change:opacity,transform;}
.galcap{margin-top:14px;text-align:center;font-size:21px;color:rgba(255,255,255,.4);font-weight:600;}
.lcard{margin-top:26px;display:flex;align-items:center;gap:18px;background:rgba(255,255,255,.06);border-radius:20px;padding:20px;will-change:opacity,transform;}
.lthumb{width:70px;height:70px;border-radius:14px;flex:none;background:linear-gradient(140deg,#4a5f88,#26324c);}
.lt{font-size:24px;font-weight:700;} .lh{font-size:20px;color:rgba(255,255,255,.4);margin-top:4px;font-family:ui-monospace,monospace;}
/* room */
.rhead{display:flex;align-items:center;gap:18px;}
.rav{width:64px;height:64px;border-radius:50%;flex:none;}
.rn{font-size:29px;font-weight:750;} .rh{font-size:21px;color:rgba(255,255,255,.42);margin-top:2px;}
.segs{display:flex;gap:10px;margin:24px 0 8px;}
.seg{font-size:21px;font-weight:700;padding:11px 20px;border-radius:100px;background:rgba(255,255,255,.08);color:rgba(255,255,255,.5);}
.seg.on{color:#fff;}
.rrow{display:flex;align-items:center;gap:18px;padding:15px 0;will-change:opacity,transform;}
.rdot{width:14px;height:14px;border-radius:50%;flex:none;margin:0 12px;}
.rt{font-size:24px;font-weight:650;} .rs{font-size:19px;color:rgba(255,255,255,.4);margin-top:3px;}
/* roster */
.faces{display:flex;gap:22px;justify-content:center;padding:10px 0 6px;}
.face{width:112px;height:112px;border-radius:50%;display:flex;align-items:center;justify-content:center;flex:none;will-change:box-shadow,transform;}
.fin{width:96px;height:96px;border-radius:50%;display:block;}
.facecap{margin-top:16px;text-align:center;font-size:21px;color:rgba(255,255,255,.4);font-weight:600;}
/* gap */
.grow{display:flex;align-items:center;gap:22px;padding:20px 0;will-change:opacity,transform;}
.grow s{width:52px;height:52px;border-radius:50%;flex:none;background:rgba(255,255,255,.06);color:#FF6B4A;display:flex;align-items:center;justify-content:center;font-size:26px;text-decoration:none;font-weight:700;}
.gn{font-size:28px;font-weight:700;} .gs{font-size:21px;color:rgba(255,255,255,.44);margin-top:3px;}
.ggood{display:flex;align-items:center;gap:20px;margin-top:22px;font-size:26px;font-weight:700;color:${GREEN};}
.ggood i{width:48px;height:48px;border-radius:50%;flex:none;background:${GREEN};color:#04140a;display:flex;align-items:center;justify-content:center;font-style:normal;font-size:25px;}
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .b{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;} .outro .u b{color:${N.brand};}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>${N.mast}</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>
  ${N.beats.map((b, i) => `<div class="comp" id="comp${i}">${card(b, i)}</div>`).join('\n')}
  <div class="kick mono" id="kick"></div>
  <div class="head" id="head"></div>
  <div class="foot mono"><span>casberi.app</span><span>—</span></div>
  <div class="wipe" id="wipe"></div>
  <div class="outro" id="outro"><div class="b">Casberi</div><div class="u mono"><b>casberi.app</b></div></div>
</div>
<script>
const clamp01=v=>Math.max(0,Math.min(1,v)),easeOut=p=>1-Math.pow(1-p,3),back=p=>{const c=1.7;return 1+(c+1)*Math.pow(p-1,3)+c*Math.pow(p-1,2);};
const INTRO=${INTRO},BEAT=${BEAT},OUT_AT=${OUT_AT},N=${N.beats.length};
const D=${JSON.stringify(DATA)};window.TOTAL=${TOTAL};
const KINDS=${JSON.stringify(N.beats.map(b=>b.card))};
const HANDLE=${JSON.stringify(N.handle)}, BRAND=${JSON.stringify(N.brand)};
const comps=[...document.querySelectorAll('.comp')];
function stag(sel,p,st,dur,dy){document.querySelectorAll(sel).forEach((r,k)=>{const rp=clamp01((p-k*st)/dur);r.style.opacity=rp;r.style.transform='translateY('+((1-back(rp))*(dy||20))+'px)';});}
window.seek=function(t){
  let active=Math.max(0,Math.min(N-1,Math.floor((t-INTRO)/BEAT)));
  const bs=INTRO+active*BEAT, local=t-bs, acc=D[active].accent, pIn=clamp01((local-0.26)/1.7);
  let coverAcc=acc,wipeX=200;const bounds=[];for(let k=1;k<N;k++)bounds.push({t:INTRO+k*BEAT,c:D[k].accent});bounds.push({t:OUT_AT,c:'#14110d'});
  for(const b of bounds){const p=(t-(b.t-0.34))/0.68;if(p>=0&&p<=1){wipeX=(1-p)*135-p*135*1.15;coverAcc=b.c;}}
  const wp=document.getElementById('wipe');wp.style.background=coverAcc;wp.style.transform='skewX(-9deg) translateX('+wipeX+'%)';
  document.getElementById('rule').style.transform='scaleX('+easeOut(clamp01(t/0.6))+')';
  const wm=document.getElementById('wm');wm.textContent=D[active].kick;wm.style.fontSize=Math.max(50,Math.min(300,880/(0.6*D[active].kick.length)))+'px';wm.style.color=acc;wm.style.opacity=0.09*clamp01(local/0.4);wm.style.transform='translateY('+((1-easeOut(clamp01(local/0.5)))*30)+'px)';
  const ki=document.getElementById('kick');ki.textContent=D[active].kick;ki.style.color=acc;const kin=clamp01(local/0.4);ki.style.opacity=easeOut(kin);ki.style.transform='translateX('+((1-easeOut(kin))*-40)+'px)';
  const he=document.getElementById('head');he.innerHTML=D[active].head.replace(/\\n/g,'<br>');const hin=clamp01((local-0.06)/0.5);he.style.opacity=clamp01(local/0.2);he.style.transform='translateY('+((1-back(hin))*80)+'px)';
  comps.forEach((c,i)=>{const cbs=INTRO+i*BEAT,cl=t-cbs,cin=clamp01((cl-0.12)/0.6);const beatEnd=INTRO+(i+1)*BEAT,outp=clamp01((t-(beatEnd-0.3))/0.4);let op=(i===active?1:0)*clamp01(cl/0.15);if(t>OUT_AT)op*=(1-clamp01((t-OUT_AT)/0.25));const y=(1-back(cin))*180+outp*200+Math.sin(t*0.9+i)*5;const rot=(-2.2)+(1-easeOut(cin))*-5+outp*4;c.style.opacity=op;c.style.transform='translateY('+y+'px) rotate('+rot+'deg)';});
  animateComp(active,pIn,t,local);
  const fo=(t>OUT_AT)?(1-clamp01((t-OUT_AT)/0.25)):1;['kick','head'].forEach(id=>{const e=document.getElementById(id);e.style.opacity=Math.min(+e.style.opacity||1,fo);});
  document.getElementById('outro').style.opacity=easeOut(clamp01((t-(OUT_AT+0.25))/0.5));
};
function animateComp(i,p,t,local){
  const kind=KINDS[i], cap=document.querySelector('#comp'+i+' .cap');
  if(kind==='relays'){
    document.getElementById('rme'+i).style.opacity=clamp01((p-0.02)/0.2);
    document.querySelectorAll('#comp'+i+' .rlink').forEach((l,k)=>{
      l.style.opacity=clamp01((p-0.2-k*0.16)/0.26);
    });
    document.getElementById('rnote'+i).style.opacity=clamp01((p-0.56)/0.24);
    if(cap)cap.style.opacity=clamp01((p-0.72)/0.24);
  } else if(kind==='follow'){
    const n=Math.round(clamp01((p-0.08)/0.4)*HANDLE.length);
    document.getElementById('typed'+i).textContent=HANDLE.slice(0,n);
    document.getElementById('caret'+i).style.opacity=(n<HANDLE.length)?((Math.floor(t*2.6)%2)?1:0.15):0;
    document.querySelector('#comp'+i+' .fsub').style.opacity=clamp01((p-0.44)/0.24);
    document.querySelector('#comp'+i+' .pledge').style.opacity=clamp01((p-0.56)/0.26);
    if(cap)cap.style.opacity=clamp01((p-0.7)/0.26);
  } else if(kind==='kinds'){
    stag('#comp'+i+' .krow',p,0.14,0.3,24);
  } else if(kind==='thread'){
    document.querySelector('#comp'+i+' .tcard').style.opacity=clamp01((p-0.02)/0.2);
    stag('#comp'+i+' .treply',clamp01((p-0.16)/0.84),0.17,0.32,16);
    if(cap)cap.style.opacity=clamp01((p-0.7)/0.26);
  } else if(kind==='media'){
    document.querySelectorAll('#comp'+i+' .gcell').forEach((c,k)=>{const rp=clamp01((p-0.06-k*0.11)/0.3);c.style.opacity=rp;c.style.transform='scale('+(0.8+0.2*back(rp))+')';});
    document.querySelector('#comp'+i+' .galcap').style.opacity=clamp01((p-0.36)/0.2);
    const lp=clamp01((p-0.46)/0.28);const lc=document.getElementById('lcard'+i);
    lc.style.opacity=lp;lc.style.transform='translateY('+((1-back(lp))*22)+'px)';
    if(cap)cap.style.opacity=clamp01((p-0.72)/0.24);
  } else if(kind==='room'){
    document.querySelector('#comp'+i+' .rhead').style.opacity=clamp01((p-0.02)/0.18);
    document.querySelector('#comp'+i+' .segs').style.opacity=clamp01((p-0.14)/0.2);
    stag('#comp'+i+' .rrow',clamp01((p-0.22)/0.78),0.13,0.3,18);
    if(cap)cap.style.opacity=clamp01((p-0.72)/0.24);
  } else if(kind==='roster'){
    document.querySelectorAll('#comp'+i+' .face').forEach((f,k)=>{
      const rp=clamp01((p-0.06-k*0.08)/0.28);
      f.style.opacity=rp;f.style.transform='scale('+(0.8+0.2*back(rp))+')';
      // the ring lights on the two who posted since the last visit
      const ringed=(k===1||k===3)&&p>0.54;
      f.style.boxShadow=ringed?('0 0 0 5px '+BRAND):'none';
    });
    document.querySelector('#comp'+i+' .facecap').style.opacity=clamp01((p-0.4)/0.2);
    if(cap)cap.style.opacity=clamp01((p-0.62)/0.26);
  } else if(kind==='gap'){
    stag('#comp'+i+' .grow',p,0.14,0.3,20);
    const g=document.querySelector('#comp'+i+' .ggood');
    const gp=clamp01((p-0.4)/0.26);g.style.opacity=gp;g.style.transform='translateY('+((1-back(gp))*16)+'px)';
    if(cap)cap.style.opacity=clamp01((p-0.62)/0.26);
  }
}
window.seek(0);
</script></body></html>`;
};

for (const N of NETS) {
  const html = build(N);
  fs.writeFileSync(path.join(__dirname, N.file), html);
  console.log('wrote', N.file, (html.length/1024).toFixed(0)+'KB',
              (0.45 + N.beats.length*2.9 + 1.9).toFixed(1)+'s');
}
