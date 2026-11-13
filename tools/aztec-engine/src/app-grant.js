// A PUBLIC AUTHORIZATION AN APP ASKS FOR (prd §1760). `grantPublicAuthwit`
// is not in Aztec's wallet interface: the Nulo wallet added it
// (github.com/nulo-sh/nulo, `wallet-sdk-schema-patch`), apps written against
// Nulo call it, and a wallet without it answers "Unknown wallet method".
// RavenHouse's "Verify with wallet" is this call.
//
// What it asks: let `caller` make one call, `method(args)` on `contract`, in
// the account's name. The wallet writes that into Aztec's public authorization
// registry with one transaction of the account's own and answers its hash.
// For a token's transfer that is a spending approval, so the sheet names the
// caller, the contract and the call, and it is approved like any send.
//
// This file is the part with no wallet in it: what a request must be before
// anything is built from it.

const ADDRESS = /^0x[0-9a-fA-F]{1,64}$/;
const METHOD = /^[A-Za-z_][A-Za-z0-9_]{0,63}$/;
const same = (a, b) => BigInt(a) === BigInt(b);

// `[account, { caller, contract, method, args }]` as it crossed the wire, or
// a refusal in words. The account must be the connected one: an app cannot
// name another account to grant from.
export function grantRequest(args, me) {
  const [account, content] = Array.isArray(args) ? args : [];
  if (typeof account !== 'string' || !ADDRESS.test(account)) throw new Error('grantPublicAuthwit needs the account it is for');
  if (!same(account, me)) throw new Error('That is not the account connected here');
  if (!content || typeof content !== 'object') throw new Error('grantPublicAuthwit needs what to authorize');
  const { caller, contract, method } = content;
  if (typeof caller !== 'string' || !ADDRESS.test(caller)) throw new Error('grantPublicAuthwit needs who may make the call');
  if (typeof contract !== 'string' || !ADDRESS.test(contract)) throw new Error('grantPublicAuthwit needs the contract to call');
  if (typeof method !== 'string' || !METHOD.test(method)) throw new Error('grantPublicAuthwit needs the function to call');
  if (!Array.isArray(content.args) || content.args.length > 32) throw new Error("grantPublicAuthwit needs the call's arguments");
  // An account that authorizes itself authorizes nothing new; a grant is for someone else.
  if (same(caller, me)) throw new Error('The account needs no authorization to act for itself');
  return { caller, contract, method, args: content.args };
}

// What the sheet draws of the call's arguments: each as short text, an
// address or a long number by its tail, at most six. Never the whole value:
// the sheet names the call, it is not a place to read 64 hex digits.
export function grantWords(list) {
  const word = v => {
    const s = typeof v === 'string' ? v : typeof v === 'number' || typeof v === 'bigint' || typeof v === 'boolean' ? String(v) : JSON.stringify(v) ?? '?';
    return s.length > 14 ? '...' + s.slice(-4) : s;
  };
  const shown = list.slice(0, 6).map(word);
  return list.length > 6 ? [...shown, `+${list.length - 6}`] : shown;
}
