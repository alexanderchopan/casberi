// Desktop debugging only: serves Casberi/AztecEngine on the app's origin
// (127.0.0.1:48713) with the same headers, and stands in for the app's `/net`
// door (forwarding to the same two declared host families, no Tor) so the
// engine page can be driven in Chrome where its console is readable.
// `/bb` answers 501: the page then proves with WebAssembly.
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = join(fileURLToPath(new URL('.', import.meta.url)), '../../Casberi/AztecEngine');
const allowed = ['aztec-mainnet.drpc.org', 'aztec-testnet.drpc.org', 'crs.aztec-cdn.foundation', 'crs.aztec-labs.com'];
const types = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json' };
const iso = { 'cross-origin-opener-policy': 'same-origin', 'cross-origin-embedder-policy': 'require-corp', 'cross-origin-resource-policy': 'same-origin' };
createServer(async (req, res) => {
  const path = new URL(req.url, 'http://x').pathname;
  if (req.method === 'POST' && path === '/net') {
    try {
    const chunks = []; for await (const c of req) chunks.push(c);
    console.log('asked', req.headers['x-casberi-method'], req.headers['x-casberi-target'], Object.keys(req.headers).join(','));
    const target = new URL(req.headers['x-casberi-target']);
    if (!allowed.includes(target.host)) { res.writeHead(403, iso); return res.end('host not declared'); }
    const headers = Object.fromEntries(Object.entries(req.headers).filter(([k]) => !['host', 'connection', 'content-length', 'origin', 'referer', 'user-agent', 'accept-encoding', 'x-casberi-target', 'x-casberi-method'].includes(k) && !k.startsWith('sec-')));
    const t = Date.now();
    const r = await fetch(target, { method: req.headers['x-casberi-method'] ?? 'GET', headers, body: chunks.length ? Buffer.concat(chunks) : undefined });
    const body = Buffer.from(await r.arrayBuffer());
    console.log('net', target.host, r.status, body.length, `${Date.now() - t}ms`);
    res.writeHead(r.status, { ...iso, 'content-type': r.headers.get('content-type') ?? 'application/octet-stream' });
    return res.end(body);
    } catch (e) { console.log('net failed', String(e?.cause ?? e)); res.writeHead(502, iso); return res.end(String(e)); }
  }
  if (path === '/bb') { res.writeHead(501, iso); return res.end('no prover'); }
  try {
    const file = join(root, normalize(path.endsWith('/') ? path + 'index.html' : path));
    const body = await readFile(file);
    res.writeHead(200, { ...iso, 'content-type': types[extname(file)] ?? 'application/octet-stream' });
    res.end(body);
  } catch { res.writeHead(404, iso); res.end(); }
}).listen(48713, '127.0.0.1', () => console.log('engine on http://127.0.0.1:48713'));
