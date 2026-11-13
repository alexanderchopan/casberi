// WHAT A CALL SAYS (prd §1763). An app's transaction reaches the sheet as
// calls: a function's name, a contract, and a flat list of field values. The
// contract's own interface, which the app registered with the wallet, names
// those values; this file lays one over the other so the sheet can read
// "to ...4f2a · amount 5 USDC" where it read the function's name alone.
//
// It says what the call's own arguments say and nothing else: not what a
// private call goes on to do, and not a value it cannot place.

// How many flat fields one ABI type takes.
export function width(type) {
  switch (type?.kind) {
    case 'field': case 'boolean': case 'integer': return 1;
    case 'string': return type.length ?? 0;
    case 'array': return (type.length ?? 0) * width(type.type);
    case 'struct': return (type.fields ?? []).reduce((n, f) => n + width(f.type), 0);
    case 'tuple': return (type.fields ?? []).reduce((n, t) => n + width(t), 0);
    default: return NaN;
  }
}

const isAddress = type => type?.kind === 'struct' && /(aztec_address::AztecAddress|eth_address::EthAddress)$/.test(type.path ?? '');
const tail = hex => '...' + hex.slice(-4);

// One value in short words: an address by its tail, a number in decimal
// (shifted by `decimals` when it is a known token's amount), a boolean as
// yes or no, anything wider than one field as how many values it holds.
function word(type, fields, amount) {
  if (isAddress(type)) return tail(BigInt(fields[0]).toString(16).padStart(64, '0'));
  if (type.kind === 'boolean') return BigInt(fields[0]) === 0n ? 'no' : 'yes';
  if (type.kind === 'integer' || type.kind === 'field') {
    const n = BigInt(fields[0]);
    if (amount) return units(n, amount.decimals) + ' ' + amount.symbol;
    const s = n.toString();
    return s.length > 14 ? tail(n.toString(16)) : s;
  }
  return `${fields.length} values`;
}

// Base units as a decimal figure, trailing zeros dropped, six places at most.
export function units(n, decimals) {
  const d = BigInt(10) ** BigInt(decimals);
  const whole = n / d, part = (n % d).toString().padStart(decimals, '0').slice(0, 6).replace(/0+$/, '');
  // An amount too small for six places is not nothing.
  if (!part && whole === 0n && n > 0n) return '<0.000001';
  return part ? `${whole}.${part}` : `${whole}`;
}

const AMOUNT = /^(amount|value|quantity)$/;

// The words for one call: `fn` is the function's ABI entry, `flat` its
// arguments as the wire carries them (field strings), `token` the contract's
// symbol and decimals when Casberi knows it. Five arguments at most, then
// how many more. Null when the arguments do not fit the interface: the sheet
// then shows the name alone, as before, and never a guess.
export function callWords(fn, flat, token) {
  const params = fn?.parameters ?? [];
  const sizes = params.map(p => width(p.type));
  if (!Array.isArray(flat) || sizes.some(Number.isNaN) || sizes.reduce((a, b) => a + b, 0) !== flat.length) return null;
  const out = [];
  let at = 0;
  for (let i = 0; i < params.length; i++) {
    const fields = flat.slice(at, at + sizes[i]);
    at += sizes[i];
    try {
      const amount = token && AMOUNT.test(params[i].name) && params[i].type.kind !== 'boolean' ? token : null;
      out.push(`${params[i].name.replace(/_/g, ' ')} ${word(params[i].type, fields, amount)}`);
    } catch {
      return null;
    }
  }
  return out.length > 5 ? [...out.slice(0, 5), `+${out.length - 5}`] : out;
}
