// How fast does the Sepolia ASP publish? No funds needed: labels are encrypted to the ASP
// (LabelRegistered(bytes ciphertext)), so a stranger's approval cannot be matched to its root,
// but every deposit's wait is at least "time to the next ASPRootUpdated". Reads ASPRegistry logs.
//   node asp-cadence.mjs [blocks=100000]
import { createPublicClient, http, parseAbiItem } from 'viem';
import { sepolia } from 'viem/chains';
import { RPC, SEPOLIA, assertTestnet } from './config.mjs';

const c = createPublicClient({ chain: sepolia, transport: http(RPC) });
assertTestnet(await c.getChainId());
const SPAN = BigInt(process.argv[2] ?? 100000);
const head = await c.getBlockNumber();
const rootEv = parseAbiItem('event ASPRootUpdated(uint256 indexed _root, bytes _ipfsCID)');
const labelEv = parseAbiItem('event LabelRegistered(bytes _ciphertext)');
const roots = [], labels = [], skipped = [];
for (let from = head - SPAN; from <= head; from += 10000n) {
  const to = from + 9999n > head ? head : from + 9999n;
  // publicnode load-balances over pruned and archive backends: retry a chunk, then skip it.
  const logs = async (event) => { for (let i = 0; i < 6; i++) { try { return await c.getLogs({ address: SEPOLIA.aspRegistry, event, fromBlock: from, toBlock: to }); } catch { await new Promise((r) => setTimeout(r, 1500)); } } skipped.push(String(from)); return []; };
  roots.push(...await logs(rootEv));
  labels.push(...await logs(labelEv));
}
const ts = new Map();
const time = async (bn) => { if (!ts.has(bn)) ts.set(bn, Number((await c.getBlock({ blockNumber: bn })).timestamp)); return ts.get(bn); };
const rootTimes = []; for (const r of roots) rootTimes.push(await time(r.blockNumber));
const waits = [];
for (const l of labels) {
  const t = await time(l.blockNumber);
  const next = rootTimes.find((rt) => rt > t);
  if (next) waits.push(next - t);
}
const gaps = rootTimes.slice(1).map((t, i) => t - rootTimes[i]);
const q = (a, p) => { const s = [...a].sort((x, y) => x - y); return s.length ? s[Math.min(s.length - 1, Math.floor(p * s.length))] : null; };
const min = (s) => (s == null ? null : +(s / 60).toFixed(1));
console.log(JSON.stringify({
  window: { blocks: Number(SPAN), from: new Date((await time(head - SPAN)) * 1000).toISOString(), to: new Date((await time(head)) * 1000).toISOString() },
  skippedChunks: skipped.length,
  rootUpdates: roots.length, labelsRegistered: labels.length,
  rootGapMin: { p50: min(q(gaps, 0.5)), p90: min(q(gaps, 0.9)), max: min(q(gaps, 1)) },
  depositToNextRootMin: { n: waits.length, p50: min(q(waits, 0.5)), p90: min(q(waits, 0.9)), max: min(q(waits, 1)) },
}, null, 2));
