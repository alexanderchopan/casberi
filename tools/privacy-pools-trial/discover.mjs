// Step 1: confirm the live Sepolia deployment on chain, at the ASP and at the relayer.
// Reads only. `node discover.mjs`
import { createPublicClient, http, parseAbi } from 'viem';
import { sepolia } from 'viem/chains';
import { ASP_URL, RELAYER_URL, RPC, SEPOLIA, assertTestnet } from './config.mjs';

const c = createPublicClient({ chain: sepolia, transport: http(RPC) });
assertTestnet(await c.getChainId());

const out = { block: Number(await c.getBlockNumber()), code: {}, reads: {}, asp: {}, relayer: {} };
for (const [k, a] of Object.entries(SEPOLIA)) {
  if (typeof a !== 'string' || a === SEPOLIA.eth) continue;
  const code = await c.getCode({ address: a });
  out.code[k] = code ? `${(code.length - 2) / 2} bytes` : 'EOA / none';
}
const relayAbi = parseAbi(['function POOL() view returns (address)', 'function ENTRYPOINT() view returns (address)', 'function MAX_BATCH() view returns (uint256)']);
const tryRead = async (label, args) => { try { out.reads[label] = String(await c.readContract(args)); } catch (e) { out.reads[label] = `ERR ${e.shortMessage ?? e.message}`.slice(0, 120); } };
await tryRead('relay.POOL()', { address: SEPOLIA.relay, abi: relayAbi, functionName: 'POOL' });
await tryRead('relay.ENTRYPOINT()', { address: SEPOLIA.relay, abi: relayAbi, functionName: 'ENTRYPOINT' });
await tryRead('relay.MAX_BATCH()', { address: SEPOLIA.relay, abi: relayAbi, functionName: 'MAX_BATCH' });
await tryRead('aspRegistry.latestASPRoot()', { address: SEPOLIA.aspRegistry, abi: parseAbi(['function latestASPRoot() view returns (uint256)']), functionName: 'latestASPRoot' });
out.reads['relayerSigner balance (wei)'] = String(await c.getBalance({ address: SEPOLIA.relayerSigner }));
out.reads['poolVault ETH balance (wei)'] = String(await c.getBalance({ address: SEPOLIA.poolVault }));

const get = async (url) => { const t = Date.now(); try { const r = await fetch(url); const body = await r.text(); return { status: r.status, ms: Date.now() - t, body: body.slice(0, 300) }; } catch (e) { return { error: e.message, ms: Date.now() - t }; } };
out.asp.entrypoints = await get(`${ASP_URL}/global/public/entrypoints`);
out.asp.root = await get(`${ASP_URL}/association-set/root?chainId=11155111&entrypoint=${SEPOLIA.entrypoint}`);
out.asp.publicKey = await get(`${ASP_URL}/public-key`);
const leaves = await get(`${ASP_URL}/association-set/leaves?chainId=11155111&entrypoint=${SEPOLIA.entrypoint}`);
out.asp.leaves = { status: leaves.status, ms: leaves.ms };
out.relayer.details = await get(`${RELAYER_URL}/v1/details/evm/11155111`);
console.log(JSON.stringify(out, null, 2));
