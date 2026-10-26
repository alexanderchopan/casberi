// Local JSON-RPC router for the trial: old logs from Tenderly (full history), the rest from PublicNode; retries 429s.
import http from 'node:http';
const LOGS = 'https://sepolia.gateway.tenderly.co', REST = 'https://ethereum-sepolia-rpc.publicnode.com';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function call(url, body) {
  for (let i = 0; ; i++) {
    const r = await fetch(url, { method: 'POST', headers: { 'content-type': 'application/json' }, body });
    const t = await r.text();
    if ((r.status === 429 || /Too Many|rate.?limit/i.test(t)) && i < 12) { await sleep(500 * 2 ** Math.min(i, 5)); continue; }
    return [r.status, t];
  }
}
let queue = Promise.resolve();
http.createServer((req, res) => {
  let b = ''; req.on('data', (c) => (b += c)); req.on('end', () => {
    const j = JSON.parse(b), methods = [].concat(j).map((x) => x.method);
    const url = methods.includes('eth_getLogs') ? LOGS : REST;
    const go = () => call(url, b).then(async ([s, t]) => { if (url === LOGS && /beyond current head/.test(t)) [s, t] = await call(REST, b); res.writeHead(s, { 'content-type': 'application/json' }); res.end(t); });
    if (url === LOGS) { queue = queue.then(go, go); } else go();
  });
}).listen(8547, () => console.log('rpc proxy on 8547'));
