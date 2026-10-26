// Re-read every recorded tx's receipt from the node (status now, fee) — TESTNET ONLY.
import { readFileSync } from 'node:fs';
import { createAztecNodeClient } from '@aztec-labs/aztec.js/node';
import { TxHash } from '@aztec-labs/stdlib/tx';
const node = createAztecNodeClient(process.env.AZTEC_NODE_URL ?? 'https://aztec-testnet.drpc.org', { maxBatchSize: 3 });
const s = JSON.parse(readFileSync(new URL('./state.json', import.meta.url)));
for (const [k, v] of Object.entries(s.done)) if (v.tx) {
  const r = await node.getTxReceipt(TxHash.fromString(v.tx));
  console.log(k, 'block', r.blockNumber, 'epoch', r.epochNumber, 'status', r.status, 'fee FJ', r.transactionFee === undefined ? '-' : Number(r.transactionFee) / 1e18);
}
console.log('tip', await node.getBlockNumber(), 'proven', await node.getBlockNumber('proven'));
