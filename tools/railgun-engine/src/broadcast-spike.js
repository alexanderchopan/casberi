// SPIKE (prd §1721 item 3): Railgun's Waku broadcaster client, bundled for
// the browser exactly as the engine is, finds the broadcasters' fees over
// the three relays' WebSockets. Read-only: nothing is sent.
//   node build.mjs src/broadcast-spike.js && node dist/broadcast-spike.js
import { Buffer } from 'buffer';
globalThis.Buffer ??= Buffer;
import { WakuBroadcasterClient } from '@railgun-community/waku-broadcaster-client-web';
const hosts = new Set();
const Native = globalThis.WebSocket;
globalThis.WebSocket = class extends Native { constructor(u, p) { hosts.add(new URL(u).host); super(u, p); } };
const chain = { type: 0, id: 1 };
const t0 = Date.now();
await WakuBroadcasterClient.start(chain, { poiActiveListKeys: [], useDNSDiscovery: false, feeExpirationTimeout: 60000 }, () => {});
for (let i = 0; i < 12; i++) {
  await new Promise((r) => setTimeout(r, 10000));
  const all = WakuBroadcasterClient.findAllBroadcastersForChain(chain, false) ?? [];
  console.log(((Date.now() - t0) / 1000) | 0, 's fees', all.length, 'hosts', [...hosts].join(','));
  if (all.length) { console.log(JSON.stringify(all.map((b) => [b.tokenAddress, b.tokenFee.feePerUnitGas, b.tokenFee.relayAdapt, b.tokenFee.availableWallets]))); break; }
}
globalThis.process?.exit?.(0);
