// The Mac's number to set beside the phone's: the same proofs the app's
// `bench` makes (src/synthetic.js, Sepolia's pinned dev keys), in Node.
// Fetches each pinned file once into .circuits/ (gitignored) and refuses any
// that does not hash to its pin in PrivacyArtifactPins.swift.
//   node bench-node.mjs [runs=3] [circuit ...]
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { PoseidonHashService } from '@0xbow/privacy-pools-v2-sdk';
import * as snarkjs from 'snarkjs';
import { syntheticInputs } from './src/synthetic.js';

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const runs = Number(args[0] ?? 3);
const names = args.slice(1).length ? args.slice(1) : ['deposit', 'transact_1x1', 'transact_1x2', 'transact_2x2'];
const gateways = ['https://gateway.pinata.cloud/ipfs/', 'https://ipfs.io/ipfs/'];

const swift = readFileSync(join(here, '../../Casberi/Casberi/Model/PrivacyArtifactPins.swift'), 'utf8');
function pin(name, kind) {
  const block = swift.match(new RegExp(`"${name}": Circuit\\(([\\s\\S]*?)\\)\\),`))?.[1];
  const m = block?.match(new RegExp(`${kind}: File\\(cid: "(\\w+)", sha256: "([0-9a-f]{64})"`));
  if (!m) throw new Error(`no pin for ${name}.${kind}`);
  return { cid: m[1], sha256: m[2] };
}
const sha = (b) => createHash('sha256').update(b).digest('hex');
async function file(name, kind) {
  const p = pin(name, kind);
  const dir = join(here, '.circuits'); mkdirSync(dir, { recursive: true });
  const path = join(dir, p.sha256);
  if (existsSync(path)) { const b = readFileSync(path); if (sha(b) === p.sha256) return b; }
  for (const g of gateways) {
    const res = await fetch(g + p.cid).catch(() => null);
    if (!res?.ok) continue;
    const b = Buffer.from(await res.arrayBuffer());
    if (sha(b) !== p.sha256) { console.warn(`refused ${name}.${kind} from ${g} (hash)`); continue; }
    writeFileSync(path, b);
    return b;
  }
  throw new Error(`no gateway served ${name}.${kind}`);
}

const h = await PoseidonHashService.create();
const H = (xs) => BigInt(h.hash(xs.map((x) => `0x${BigInt(x).toString(16)}`)));
const med = (a) => [...a].sort((x, y) => x - y)[Math.floor(a.length / 2)];
for (const name of names) {
  const [wasm, zkey, vkey] = [await file(name, 'wasm'), await file(name, 'zkey'), JSON.parse(await file(name, 'vkey'))];
  const w = [], p = []; let ok = true;
  for (let r = 0; r < runs; r++) {
    const wtns = { type: 'mem' };
    const t0 = performance.now();
    await snarkjs.wtns.calculate(syntheticInputs(name, H), new Uint8Array(wasm), wtns);
    const t1 = performance.now();
    const { proof, publicSignals } = await snarkjs.groth16.prove(new Uint8Array(zkey), wtns);
    const t2 = performance.now();
    ok &&= await snarkjs.groth16.verify(vkey, publicSignals, proof);
    w.push(t1 - t0); p.push(t2 - t1);
  }
  console.log(JSON.stringify({ circuit: name, runs, witnessMs: Math.round(med(w)), proveMs: Math.round(med(p)), verifies: ok, node: process.version }));
}
process.exit(0); // snarkjs leaves worker threads alive
