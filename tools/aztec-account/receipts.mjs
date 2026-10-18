import { readFileSync } from 'node:fs';
import { createAztecNodeClient } from '@aztec/aztec.js/node';
import { TxHash } from '@aztec/stdlib/tx';
const node = createAztecNodeClient('https://v5.testnet.rpc.aztec-labs.com');
const s = JSON.parse(readFileSync(new URL('./state.json', import.meta.url)));
for (const [k, v] of Object.entries(s.done)) if (v.tx) {
  const r = await node.getTxReceipt(TxHash.fromString(v.tx));
  console.log(k, 'block', r.blockNumber, 'status', r.status, 'fee', r.transactionFee?.toString());
}
console.log('tip', await node.getBlockNumber());
