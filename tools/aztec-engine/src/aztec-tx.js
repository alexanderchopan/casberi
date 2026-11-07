// What Casberi's engine says about one Aztec transaction (prd §1711): its
// hash and fee off a receipt, who pays for an app's transaction, which
// transfer a token's own interface offers, and whether an Aztec address can
// receive at all. Pure over Aztec's own types, so the engine's self-test runs
// it in node (test/aztec-tx.test.mjs).

// A receipt as the app reads it: the hash, the status, and the fee the
// network charged in Fee Juice base units (null when the receipt has none).
export function receiptOut(receipt) {
  const fee = receipt?.transactionFee;
  return {
    tx: receipt?.txHash?.toString() ?? null,
    status: receipt?.status == null ? null : String(receipt.status),
    fee: fee == null ? null : BigInt(fee).toString(),
  };
}

// What an app's `sendTx` answered: `{ txHash }` when it did not wait, else
// `{ receipt }`. The hash and fee, or nulls.
export function sentOut(result) {
  if (result?.receipt) return receiptOut(result.receipt);
  const hash = result?.txHash ?? null;
  return { tx: hash == null ? null : hash.toString(), status: null, fee: null };
}

// Who pays for an app's transaction: `you` from your Fee Juice, `claim` from
// Fee Juice the same transaction claims, `app` when the payload names
// another payer (a sponsor, a fee contract).
export function feePayer(payload, from) {
  const payer = payload?.feePayer;
  if (!payer || payer.isZero?.()) return 'you';
  return from && payer.equals?.(from) ? 'claim' : 'app';
}

// The fee a simulation says this transaction costs at today's prices, in
// Fee Juice base units: the gas it used, priced at the node's current fees.
export function feeUnits(gasUsed, fees) {
  if (!gasUsed?.totalGas || !fees) return null;
  return gasUsed.totalGas.computeFee(fees).toBigInt().toString();
}

// The call that moves a token privately from you to someone, read off the
// token's own interface: Aztec's standard `transfer_private_to_private(from,
// to, amount, nonce)` (Shield's tokens, measured), else the older Token
// contract's private `transfer(to, amount)`. Null when it offers neither, so
// Casberi never guesses at a contract's meaning.
export function transferCall(artifact) {
  const fns = artifact?.functions ?? [];
  const named = (name, count) =>
    fns.find(f => f.name === name && (f.parameters ?? []).length === count && String(f.functionType ?? 'private') === 'private');
  if (named('transfer_private_to_private', 4)) {
    return { name: 'transfer_private_to_private', args: (me, to, amount) => [me, to, amount, 0n] };
  }
  if (named('transfer', 2)) {
    return { name: 'transfer', args: (_me, to, amount) => [to, amount] };
  }
  return null;
}

// Whether `text` is an Aztec address anyone can receive at: 0x and 64 hex
// digits, below the field's modulus, and the x-coordinate of a point on the
// Grumpkin curve (Aztec's own `isValid`). About half of all 64-digit values
// are not; a note sent to one can never be read by anybody.
export async function addressValid(AztecAddress, text) {
  const t = String(text ?? '').trim();
  if (!/^0x[0-9a-fA-F]{64}$/.test(t)) return false;
  let address;
  try {
    address = AztecAddress.fromStringUnsafe(t);
  } catch {
    return false; // at or above the field's modulus
  }
  return address.isValid();
}

// The calls an approval sheet lists: function, contract tail, private or public.
const tail = a => '...' + String(a ?? '').slice(-4);
export function describeCalls(payload) {
  return (payload?.calls ?? []).map(c => ({ name: c.name, to: tail(c.to), type: c.type }));
}
