// The chain read finds YOUR notes and no one else's, with Tacit's own wallet
// (vendor/dapp/) and no network: two accounts' notes are made with the
// wallet's own `makeNote`, served by a stand-in leader two to a page, and
// each account's scan must add up to exactly its own unspent notes.
//   node test/chain-scan.mjs
import { makeChainWallet, worthOf } from '../vendor/dapp/tacit-chain-wallet.js';
import { chainSeed } from '../vendor/dapp/tacit-chain-lane.js';
import { poseidon2, poseidon3, poseidon4, poseidon5 } from '../vendor/dapp/vendor/tacit-poseidon.min.js';

const POSEIDON = { 2: poseidon2, 3: poseidon3, 4: poseidon4, 5: poseidon5 };
const poseidon = (xs) => POSEIDON[xs.length](xs);
const hx = (b) => '0x' + Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('');
let failures = 0;
const check = (ok, what) => { if (!ok) { console.log(`  ✗ ${what}`); failures++; } };

const w = makeChainWallet({ poseidon, prover: null, chain: '0x' + '11'.repeat(32), asset: 7n });
const key = (byte) => w.keys(chainSeed(new Uint8Array(32).fill(byte)));
const mine = key(1), theirs = key(2);
const made = [
  w.makeNote(w.address(mine), 500_000_000n),
  w.makeNote(w.address(theirs), 900_000_000n),
  w.makeNote(w.address(mine), 200_000_000n),
  w.makeNote(w.address(mine), 100_000_000n),
  w.makeNote(w.address(theirs), 1n),
];
const leaves = made.map((n) => '0x' + n.leaf.toString(16).padStart(64, '0')), memos = made.map((n) => hx(n.memo));

function leader({ spendNth = null } = {}) {
  let asked = 0, pages = 0;
  return {
    get pages() { return pages; },
    notes: async (from, limit) => {
      pages++;
      const size = Math.min(limit, 2), to = Math.min(from + size, leaves.length);
      return { from, leaves: leaves.slice(from, to), memos: memos.slice(from, to), next: to, total: leaves.length };
    },
    spent: async () => asked++ === spendNth,
  };
}
const sum = (r) => r.notes.reduce((a, n) => a + BigInt(n.value), 0n);

const all = leader();
const a = await w.scan(mine, all, { from: 0, keep: false });
check(a.notes.length === 3 && sum(a) === 800_000_000n, `your three notes add up to 8 TAC (found ${a.notes.length}, ${sum(a)})`);
check(a.next === 5 && all.pages === 3, 'every page is read to the end');
const b = await w.scan(theirs, leader(), { from: 0, keep: false });
check(b.notes.length === 2 && sum(b) === 900_000_001n, 'another account finds its own notes, not yours');
const s = await w.scan(mine, leader({ spendNth: 1 }), { from: 0, keep: false });
check(s.notes.length === 2 && s.spent.length === 1 && sum(s) === 600_000_000n, 'a spent note is not counted');
const none = await w.scan(key(3), leader(), { from: 0, keep: false });
check(none.notes.length === 0, 'a third account finds nothing');
// A leaf that is not the one the memo opens to is not yours: the leader
// cannot hand you a note by pairing your memo with another leaf.
const swapped = { notes: async () => ({ from: 0, leaves: [leaves[1]], memos: [memos[0]], next: 1, total: 1 }), spent: async () => false };
check((await w.scan(mine, swapped, { from: 0, keep: false })).notes.length === 0, 'a memo beside the wrong leaf is not counted');
// Shares are worth the pool's rate, rounded down.
check(worthOf(800_000_000n, { pool: 27979219725395n, shares: 27511884039471n }) === 813_589_297n, `8 shares at the rate read on 2026-11-24 (${worthOf(800_000_000n, { pool: 27979219725395n, shares: 27511884039471n })})`);

if (failures) { console.log(`${failures} assertion(s) failed`); process.exit(1); }
console.log('  ok   the chain scan finds your notes, skips spent ones and other accounts\'');
