// SPIKE: Railgun from a Safe, on Ethereum, with a token that is neither ETH
// nor USDC (DAI). A throwaway 1-of-1 SafeL2 1.4.1 (the kind Casberi's account
// is), owned by the test wallet in state/keys.json, does both moves itself:
// approve + shield in one Safe transaction, and later the unshield back to
// itself. The test wallet only executes as the Safe's owner and pays the gas.
// Nothing is sent without --send, and the --send runs are the person's.
//
//   node safe-test.mjs status
//   node safe-test.mjs deploy [--send]          make the Safe
//   node safe-test.mjs swap 0.0002 [--send]     ETH -> DAI, paid to the Safe
//   node safe-test.mjs shield [--send]          the Safe makes its DAI private
//   node safe-test.mjs unshield [--send]        private DAI back to the Safe (after the hour)
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import memdown from 'memdown';
import { JsonRpcProvider, Wallet, Contract, Interface, AbiCoder, keccak256, concat, toUtf8Bytes, zeroPadValue, solidityPacked,
  formatEther, formatUnits, parseEther, getAddress, ZeroAddress, getCreate2Address, toBeHex } from 'ethers';
import {
  walletForID, balanceForERC20Token, getRailgunAddress, populateShield,
  gasEstimateForUnprovenUnshield, generateUnshieldProof, populateProvedUnshield,
} from '@railgun-community/wallet';
import { NETWORK_CONFIG, TXIDVersion, EVMGasType } from '@railgun-community/shared-models';
import { spike, ArtifactStore } from './src/core.js';

const RPC = 'https://ethereum-rpc.publicnode.com';
const UTXO_TREE_START_BLOCK = 25849756;
const TXID_START_TREE = 2;
const V2 = TXIDVersion.V2_PoseidonMerkle;
// Safe 1.4.1's canonical deployments (safe-global/safe-deployments); each is
// checked for code before use.
const SAFE = {
  factory: '0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67',
  singletonL2: '0x29fcB43b46531BcA003ddC8FCB67FFE91900C762',
  fallbackHandler: '0xfd0732Dc9E303f09fCEf3a7388Ad10A83459Ec99',
  multiSendCallOnly: '0x9641d764fc13c8B624c04430C7356C1C7C8102e2',
};
const SALT = 26110701n;
const DAI = '0x6B175474E89094C44Da98b954EedeAC495271d0F';
const WETH = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2';
const UNI = { quoter: '0x61fFE014bA17989E743c5F6cB21bF9697530B21e', router: '0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45' };
const RAILGUN = NETWORK_CONFIG.Ethereum.proxyContract;

const here = dirname(fileURLToPath(import.meta.url));
const [mode = 'status', arg] = process.argv.slice(2);
const sending = process.argv.includes('--send');
const keysPath = join(here, 'state/keys.json');
const keys = JSON.parse(readFileSync(keysPath, 'utf8'));
const provider = new JsonRpcProvider(RPC, 1, { staticNetwork: true });
const owner = Wallet.fromPhrase(keys.mnemonic).connect(provider);
const out = (step, f) => console.log(JSON.stringify({ step, ...f }, (k, v) => (typeof v === 'bigint' ? String(v) : v)));

const safeIface = new Interface([
  'function setup(address[] _owners, uint256 _threshold, address to, bytes data, address fallbackHandler, address paymentToken, uint256 payment, address paymentReceiver)',
  'function execTransaction(address to, uint256 value, bytes data, uint8 operation, uint256 safeTxGas, uint256 baseGas, uint256 gasPrice, address gasToken, address refundReceiver, bytes signatures) payable returns (bool)',
  'function getOwners() view returns (address[])',
]);
const factory = new Contract(SAFE.factory, ['function createProxyWithNonce(address _singleton, bytes initializer, uint256 saltNonce) returns (address)'], owner);
const erc20 = new Interface(['function approve(address, uint256) returns (bool)', 'function balanceOf(address) view returns (uint256)']);
const initializer = safeIface.encodeFunctionData('setup', [[owner.address], 1, ZeroAddress, '0x', SAFE.fallbackHandler, ZeroAddress, 0, ZeroAddress]);
// The Safe's address is CREATE2's, from the factory's own proxy code: the same
// before and after it is deployed.
const proxyCode = await new Contract(SAFE.factory, ['function proxyCreationCode() pure returns (bytes)'], provider).proxyCreationCode();
const safeAddress = getCreate2Address(SAFE.factory, keccak256(concat([keccak256(initializer), zeroPadValue(toBeHex(SALT), 32)])),
  keccak256(concat([proxyCode, zeroPadValue(SAFE.singletonL2, 32)])));
const code = async (a) => (await provider.getCode(a)).length > 2;
const daiOf = async (a) => BigInt(await provider.call({ to: DAI, data: erc20.encodeFunctionData('balanceOf', [a]) }));
const fees = async () => { const f = await provider.getFeeData(); return { maxFeePerGas: f.maxFeePerGas, maxPriorityFeePerGas: f.maxPriorityFeePerGas }; };

// The Safe runs `to.data` itself; signed by the owner being the sender (a
// pre-validated signature: v = 1, r = the owner).
const preValidated = concat([zeroPadValue(owner.address, 32), zeroPadValue('0x', 32), '0x01']);
const execAsSafe = (to, data, operation = 0) => safeIface.encodeFunctionData('execTransaction', [to, 0, data, operation, 0, 0, 0, ZeroAddress, ZeroAddress, preValidated]);
const multiSend = (calls) => new Interface(['function multiSend(bytes)']).encodeFunctionData('multiSend', [
  concat(calls.map((c) => solidityPacked(['uint8', 'address', 'uint256', 'uint256', 'bytes'], [0, c.to, 0, (c.data.length - 2) / 2, c.data]))),
]);

// Estimate as the owner, show the worst-case cost, send only with --send.
async function run(step, tx, note) {
  const f = await fees();
  const gas = await provider.estimateGas({ ...tx, from: owner.address }).catch((e) => e.shortMessage ?? e.message);
  const ownerETH = await provider.getBalance(owner.address);
  const ok = typeof gas === 'bigint';
  const maxCost = ok ? (gas * 12n / 10n) * f.maxFeePerGas + (tx.value ?? 0n) : null;
  out(step, { to: tx.to, gas: String(gas), maxCostETH: ok ? formatEther(maxCost) : null, ownerETH: formatEther(ownerETH), ...note });
  if (!ok) throw new Error(`${step} would fail: ${gas}`);
  if (!sending) return out('dryRun', { note: 'add --send to run it' });
  if (ownerETH < maxCost) return out('notSent', { note: `the owner needs ${formatEther(maxCost)} ETH` });
  const sent = await owner.sendTransaction({ ...tx, gasLimit: gas * 12n / 10n, ...f });
  const receipt = await sent.wait();
  out(`${step}-sent`, { hash: sent.hash, status: receipt.status, gasUsed: receipt.gasUsed });
}

out('safe', { safe: safeAddress, owner: owner.address, deployed: await code(safeAddress) });
for (const [k, a] of Object.entries(SAFE)) if (!(await code(a))) throw new Error(`no code at ${k} ${a}`);

if (mode === 'deploy') {
  if (await code(safeAddress)) { out('deploy', { already: true }); process.exit(0); }
  await run('deploy', { to: SAFE.factory, data: factory.interface.encodeFunctionData('createProxyWithNonce', [SAFE.singletonL2, initializer, SALT]) });
  process.exit(0);
}

async function buildSwap(amountIn) {
  const quoter = new Contract(UNI.quoter, ['function quoteExactInputSingle((address tokenIn,address tokenOut,uint256 amountIn,uint24 fee,uint160 sqrtPriceLimitX96)) returns (uint256 amountOut, uint160, uint32, uint256)'], provider);
  let best = null;
  for (const fee of [100, 500, 3000]) {
    try { const [o] = await quoter.quoteExactInputSingle.staticCall({ tokenIn: WETH, tokenOut: DAI, amountIn, fee, sqrtPriceLimitX96: 0 }); if (!best || o > best.o) best = { fee, o }; } catch {}
  }
  if (!best) throw new Error('no WETH/DAI pool quoted');
  const router = new Interface(['function exactInputSingle((address tokenIn,address tokenOut,uint24 fee,address recipient,uint256 amountIn,uint256 amountOutMinimum,uint160 sqrtPriceLimitX96)) payable returns (uint256)']);
  const data = router.encodeFunctionData('exactInputSingle', [{ tokenIn: WETH, tokenOut: DAI, fee: best.fee, recipient: safeAddress, amountIn, amountOutMinimum: best.o * 99n / 100n, sqrtPriceLimitX96: 0 }]);
  return { tx: { to: UNI.router, data, value: amountIn }, best };
}
if (mode === 'swap') {
  const amountIn = parseEther(arg ?? '0.0002');
  const { tx, best } = await buildSwap(amountIn);
  await run('swap', tx, { amountETH: formatEther(amountIn), quoteDAI: formatUnits(best.o, 18), poolFee: best.fee, paidTo: 'the Safe' });
  process.exit(0);
}

if (mode === 'status' && !(await code(safeAddress))) process.exit(0);
if (await code(safeAddress)) out('public', { safeETH: formatEther(await provider.getBalance(safeAddress)), safeDAI: formatUnits(await daiOf(safeAddress), 18), ownerETH: formatEther(await provider.getBalance(owner.address)) });

// Shield and unshield need the private wallet: sync with the shortcut, then act.
const dir = join(here, '.artifacts');
const store = new ArtifactStore(
  async (p) => (existsSync(join(dir, p)) ? readFileSync(join(dir, p)) : null),
  async (d, p, item) => { mkdirSync(join(dir, d), { recursive: true }); writeFileSync(join(dir, p), item); },
  async (p) => existsSync(join(dir, p)),
);
const quiet = new Set(['progress', 'engineLog', 'wallet', 'network', 'engine', 'bench', 'profile']);
await spike({
  db: memdown(), artifactStore: store, mnemonic: keys.mnemonic, encryptionKey: keys.encryptionKey,
  log: (s, f) => { if (!quiet.has(s)) out(s, f); },
  network: 'Ethereum', syncCapMs: 900000, startBlock: UTXO_TREE_START_BLOCK, txidStartTree: TXID_START_TREE, creationBlock: keys.mainnetCreationBlock,
  then: async ({ walletID, step }) => {
    const wallet = walletForID(walletID);
    const privateAddress = getRailgunAddress(walletID);
    await step('private', async () => ({
      privateDAI: formatUnits(await balanceForERC20Token(V2, wallet, 'Ethereum', DAI, false), 18),
      privateDAISpendable: formatUnits(await balanceForERC20Token(V2, wallet, 'Ethereum', DAI, true), 18),
    }));
    if (mode === 'status') return;

    // Every step before any is sent: deploy, swap, then the Safe's approve +
    // shield, run in order over Ethereum's real state (eth_simulateV1).
    if (mode === 'simulate') {
      const { tx: swap, best } = await buildSwap(parseEther(arg ?? '0.0002'));
      const amount = best.o * 99n / 100n;
      const shieldPrivateKey = keccak256(concat([toUtf8Bytes('casberi railgun shield v1'), '0x' + keys.encryptionKey]));
      const { transaction } = await populateShield(V2, 'Ethereum', shieldPrivateKey, [{ tokenAddress: DAI, amount, recipientAddress: privateAddress }], []);
      const batch = multiSend([{ to: DAI, data: erc20.encodeFunctionData('approve', [RAILGUN, amount]) }, { to: RAILGUN, data: transaction.data }]);
      const hex = (n) => '0x' + BigInt(n).toString(16);
      const calls = [
        { from: owner.address, to: SAFE.factory, data: factory.interface.encodeFunctionData('createProxyWithNonce', [SAFE.singletonL2, initializer, SALT]) },
        { from: owner.address, to: swap.to, data: swap.data, value: hex(swap.value) },
        { from: owner.address, to: safeAddress, data: execAsSafe(SAFE.multiSendCallOnly, batch, 1) },
      ];
      const res = await (await fetch(RPC, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'eth_simulateV1',
        params: [{ blockStateCalls: [{ calls }], validation: false, traceTransfers: true }, 'latest'] }) })).json();
      if (res.error) throw new Error(`simulate: ${JSON.stringify(res.error).slice(0, 300)}`);
      const shieldTopic = keccak256(toUtf8Bytes('Shield(uint256,uint256,(bytes32,(uint8,address,uint256),uint120)[],(bytes32[3],bytes32)[],uint256[])'));
      res.result[0].calls.forEach((c, i) => out('simulated', { call: ['deploy', 'swap', 'shield'][i], status: c.status, gasUsed: BigInt(c.gasUsed),
        error: c.error?.message, railgunShieldEvent: c.logs?.some((l) => getAddress(l.address) === getAddress(RAILGUN) && l.topics[0] === shieldTopic) }));
      return;
    }

    if (mode === 'shield') {
      const amount = await daiOf(safeAddress);
      if (amount === 0n) return out('shield', { nothingToShield: true });
      // Railgun's shield key only encrypts the note for its receiver; derived
      // here from the wallet's own secret, never from a Safe signature.
      const shieldPrivateKey = keccak256(concat([toUtf8Bytes('casberi railgun shield v1'), '0x' + keys.encryptionKey]));
      const { transaction } = await populateShield(V2, 'Ethereum', shieldPrivateKey, [{ tokenAddress: DAI, amount, recipientAddress: privateAddress }], []);
      if (getAddress(transaction.to) !== getAddress(RAILGUN)) throw new Error(`shield goes to ${transaction.to}, not Railgun`);
      const batch = multiSend([{ to: DAI, data: erc20.encodeFunctionData('approve', [RAILGUN, amount]) }, { to: RAILGUN, data: transaction.data }]);
      await run('shield', { to: safeAddress, data: execAsSafe(SAFE.multiSendCallOnly, batch, 1) },
        { amountDAI: formatUnits(amount, 18), railgunFeeDAI: formatUnits(amount * 25n / 10000n, 18), calls: 'approve + shield, one Safe transaction' });
      return;
    }

    if (mode === 'unshield') {
      const amount = await balanceForERC20Token(V2, wallet, 'Ethereum', DAI, true);
      if (amount === 0n) return out('unshield', { nothingSpendable: true });
      const recipients = [{ tokenAddress: DAI, amount, recipientAddress: safeAddress }];
      const f = await fees();
      const est = await step('unshield-estimate', async () => {
        const r = await gasEstimateForUnprovenUnshield(V2, 'Ethereum', walletID, keys.encryptionKey, recipients, [],
          { evmGasType: EVMGasType.Type2, gasEstimate: 0n, ...f }, undefined, true);
        return { gasEstimate: r.gasEstimate };
      });
      await step('unshield-proof', () => generateUnshieldProof(V2, 'Ethereum', walletID, keys.encryptionKey, recipients, [], undefined, true, undefined, () => {}));
      const { transaction } = await populateProvedUnshield(V2, 'Ethereum', walletID, recipients, [], undefined, true, undefined,
        { evmGasType: EVMGasType.Type2, gasEstimate: est.gasEstimate, ...f });
      if (transaction.type === 4 || getAddress(transaction.to) !== getAddress(RAILGUN)) throw new Error(`unshield is type ${transaction.type} to ${transaction.to}: not a plain call to Railgun`);
      await run('unshield', { to: safeAddress, data: execAsSafe(RAILGUN, transaction.data) },
        { amountDAI: formatUnits(amount, 18), railgunFeeDAI: formatUnits(amount * 25n / 10000n, 18), paidTo: 'the Safe', sentBy: 'the Safe' });
      return;
    }
    throw new Error(`unknown mode ${mode}`);
  },
});
process.exit(0);
