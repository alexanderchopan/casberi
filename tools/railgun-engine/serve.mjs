// SPIKE: the page's host. Serves the page on 127.0.0.1 (a secure context,
// so IndexedDB works), carries the page's outside requests (`/net`, as the
// app's Swift side does for Privacy Pools) and prints what it logs (`/log`).
// The Sepolia test phrase goes to the page over loopback only.
//   node build.mjs && node serve.mjs [port=8491]
import { createServer } from 'node:http';
import { readFileSync, appendFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const port = Number(process.argv[2] ?? 8491);
const logPath = join(here, 'state/web-log.jsonl');
const html = '<!doctype html><meta charset=utf-8><meta name=viewport content="width=device-width"><title>Railgun spike</title><body style="font:12px ui-monospace;white-space:pre-wrap;word-break:break-all"><script type=module src="/page.js"></script>';
const read = (req) => new Promise((ok) => { const c = []; req.on('data', (d) => c.push(d)); req.on('end', () => ok(Buffer.concat(c))); });

createServer(async (req, res) => {
  if (req.url !== '/log') console.error('req', req.method, req.url);
  try {
    if (req.url.split('?')[0] === '/') { res.writeHead(200, { 'content-type': 'text/html' }); return res.end(html); }
    if (req.url === '/page.js') { res.writeHead(200, { 'content-type': 'text/javascript' }); return res.end(readFileSync(join(here, 'dist/page.js'))); }
    const wasm = { '/poseidon_hash_wasm_bg.wasm': 'poseidon-hash-wasm', '/curve25519_scalarmult_wasm_bg.wasm': 'curve25519-scalarmult-wasm' }[req.url];
    if (wasm) { res.writeHead(200, { 'content-type': 'application/wasm' }); return res.end(readFileSync(join(here, 'node_modules/@railgun-community', wasm, 'pkg-esm', req.url.slice(1)))); }
    if (req.url === '/keys') { res.writeHead(200, { 'content-type': 'application/json' }); return res.end(readFileSync(join(here, 'state/keys.json'))); }
    if (req.url === '/log' && req.method === 'POST') {
      const line = (await read(req)).toString();
      appendFileSync(logPath, line + '\n'); console.log(line); res.writeHead(204); return res.end();
    }
    if (req.url === '/net' && req.method === 'POST') {
      const { url, method, headers, body } = JSON.parse((await read(req)).toString());
      if (!/^https:\/\//.test(url)) { res.writeHead(400); return res.end('https only'); }
      delete headers.host; delete headers['content-length'];
      const t = Date.now();
      const r = await fetch(url, { method, headers, body: method === 'GET' || method === 'HEAD' ? undefined : body });
      const buf = Buffer.from(await r.arrayBuffer());
      console.error('net', new Date().toISOString().slice(11, 19), Date.now() - t, 'ms', buf.length, 'B', new URL(url).host, (body ?? '').slice(0, 90).replace(/\s+/g, ' '));
      res.writeHead(200, { 'x-status': String(r.status), 'x-content-type': r.headers.get('content-type') ?? '' }); return res.end(buf);
    }
    res.writeHead(404); res.end();
  } catch (e) { res.writeHead(200, { 'x-status': '502' }); res.end(String(e.message)); }
}).listen(port, '127.0.0.1', () => console.log(`http://127.0.0.1:${port}/`));
