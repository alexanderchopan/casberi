// Fileverse storage census — paste into DevTools' console on a signed-in
// docs.fileverse.io tab. It prints WHERE the page keeps things, never what:
// every localStorage key and IndexedDB record as field paths with a type and
// a length, and, for each value short enough to be a key (16–200 bytes), the
// first 16 hex of its SHA-256 (of the string, and of its base64-decoded bytes
// when it decodes) so a match against a known key can be checked off the page.
// The output is copied to the clipboard (`copy` is a DevTools console helper).
(async () => {
  const hex = (buf) => [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("").slice(0, 16);
  const sha = async (bytes) => hex(await crypto.subtle.digest("SHA-256", bytes));
  const unb64 = (s) => {
    try {
      const t = s.replace(/-/g, "+").replace(/_/g, "/");
      if (!/^[A-Za-z0-9+/]+=*$/.test(t)) return null;
      return Uint8Array.from(atob(t), (c) => c.charCodeAt(0));
    } catch { return null; }
  };
  const lines = [];
  const leaf = async (path, v) => {
    if (typeof v === "string") {
      let note = `string(${v.length})`;
      try {
        const j = JSON.parse(v);
        if (j && typeof j === "object") return walk(path + "<json>", j);
      } catch {}
      if (v.length >= 16 && v.length <= 200) {
        note += ` str:${await sha(new TextEncoder().encode(v))}`;
        const raw = unb64(v);
        if (raw && raw.length >= 16) note += ` raw(${raw.length}):${await sha(raw)}`;
      }
      lines.push(`${path} ${note}`);
    } else if (v instanceof ArrayBuffer || ArrayBuffer.isView(v)) {
      const u = new Uint8Array(v.buffer ?? v, v.byteOffset ?? 0, v.byteLength);
      lines.push(`${path} bytes(${u.length})${u.length >= 16 && u.length <= 200 ? ` raw:${await sha(u)}` : ""}`);
    } else if (v instanceof CryptoKey) {
      lines.push(`${path} CryptoKey ${v.type} ${v.algorithm.name} extractable=${v.extractable}`);
    } else if (v === null || typeof v !== "object") {
      lines.push(`${path} ${v === null ? "null" : typeof v}`);
    } else await walk(path, v);
  };
  const walk = async (path, o) => {
    const entries = Array.isArray(o) ? o.slice(0, 5).map((v, i) => [i, v]) : Object.entries(o);
    if (Array.isArray(o)) lines.push(`${path} array(${o.length})`);
    for (const [k, v] of entries) await leaf(`${path}.${k}`, v);
  };

  for (const k of Object.keys(localStorage).sort()) await leaf(`ls:${k}`, localStorage.getItem(k));
  for (const k of Object.keys(sessionStorage).sort()) await leaf(`ss:${k}`, sessionStorage.getItem(k));
  for (const d of await indexedDB.databases()) {
    const db = await new Promise((res, rej) => { const r = indexedDB.open(d.name); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
    for (const s of db.objectStoreNames) {
      const store = db.transaction(s, "readonly").objectStore(s);
      const [keys, values] = await Promise.all(["getAllKeys", "getAll"].map((m) => new Promise((res) => { const r = store[m](); r.onsuccess = () => res(r.result); r.onerror = () => res([]); })));
      lines.push(`idb:${d.name}/${s} count=${keys.length}`);
      for (let i = 0; i < Math.min(keys.length, 8); i++) await leaf(`idb:${d.name}/${s}[${String(keys[i]).slice(0, 12)}]`, values[i]);
    }
    db.close();
  }
  const out = lines.join("\n");
  if (typeof copy === "function") {
    copy(out);
    console.log(`${lines.length} lines copied to the clipboard`);
  }
  return out;
})();
