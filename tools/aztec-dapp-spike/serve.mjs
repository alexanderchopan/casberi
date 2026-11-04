// Serves dist/ on :8780 with the headers the engine needs (cross-origin
// isolation for WebAssembly threads; OPFS needs a secure context, and
// localhost is one). The iOS shell serves the same files itself.
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = join(fileURLToPath(new URL('.', import.meta.url)), 'dist');
const types = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.gz': 'application/gzip' };
createServer(async (req, res) => {
  const path = normalize(decodeURIComponent(new URL(req.url, 'http://x').pathname)).replace(/^(\.\.[/\\])+/, '');
  try {
    const file = join(root, path.endsWith('/') ? path + 'index.html' : path);
    const body = await readFile(file);
    res.writeHead(200, { 'content-type': types[extname(file)] ?? 'application/octet-stream', 'cross-origin-opener-policy': 'same-origin', 'cross-origin-embedder-policy': 'require-corp', 'cross-origin-resource-policy': 'cross-origin' });
    res.end(body);
  } catch { res.writeHead(404); res.end(); }
}).listen(8780, '127.0.0.1', () => console.log('serving dist/ on http://localhost:8780'));
