// SPIKE: the first real-money test of the current-tree shortcut, on Ethereum.
// Every run syncs with the shortcut (UTXO tree 4, TXID tree 2), checks both
// roots, then does ONE step. Nothing is ever sent without --send, and the
// --send runs are the person's to make, not the assistant's.
//
//   node mainnet-test.mjs status                 balances, public and private
//   node mainnet-test.mjs shield 0.002 [--send]  make 0.002 ETH private
//   node mainnet-test.mjs unshield [--send]      move all spendable private ETH back
//
// The test account is the phrase in state/keys.json (gitignored, mode 600):
// a throwaway, never more than a few dollars on it.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import memdown from 'memdown';
import { JsonRpcProvider, keccak256, formatEther, parseEther } from 'ethers';
import {
  walletForID, balanceForERC20Token, getRailgunAddress, getShieldPrivateKeySignatureMessage, populateShieldBaseToken,
  gasEstimateForUnprovenUnshieldBaseToken, generateUnshieldBaseTokenProof, populateProvedUnshieldBaseToken,
} from '@railgun-community/wallet';
import { NETWORK_CONFIG, TXIDVersion, EVMGasType } from '@railgun-community/shared-models';
import { spike, ArtifactStore } from './src/core.js';

const UTXO_TREE_START_BLOCK = 25849756; // tree 4's first leaf (indexer; the root check proves it)
const TXID_START_TREE = 2;
const V2 = TXIDVersion.V2_PoseidonMerkle;

const here = dirname(fileURLToPath(import.meta.url));
const [mode = 'status', arg] = process.argv.slice(2);
const sending = process.argv.includes('--send');
const keysPath = join(here, 'state/keys.json');
const keys = JSON.parse(readFileSync(keysPath, 'utf8'));

const dir = join(here, '.artifacts');
const store = new ArtifactStore(
  async (p) => (existsSync(join(dir, p)) ? readFileSync(join(dir, p)) : null),
  async (d, p, item) => { mkdirSync(join(dir, d), { recursive: true }); writeFileSync(join(dir, p), item); },
  async (p) => existsSync(join(dir, p)),
);
const quiet = new Set(["shield-prepare-tx", 'progress', 'engineLog', 'wallet', 'network', 'engine']);
const log = (step, f) => { if (!quiet.has(step)) console.log(JSON.stringify({ step, ...f }, (k, v) => (typeof v === 'bigint' ? String(v) : v))); };

// The wallet's creation block is fixed on first run, so later runs still find
// what this wallet shielded.
const provider0 = new JsonRpcProvider('https://ethereum-rpc.publicnode.com', 1, { staticNetwork: true });
if (!keys.mainnetCreationBlock) {
  keys.mainnetCreationBlock = (await provider0.getBlockNumber()) - 10;
  writeFileSync(keysPath, JSON.stringify(keys, null, 1), { mode: 0o600 });
}

await spike({
  db: memdown(), artifactStore: store, mnemonic: keys.mnemonic, encryptionKey: keys.encryptionKey, log,
  network: 'Ethereum', syncCapMs: 900000, startBlock: UTXO_TREE_START_BLOCK, txidStartTree: TXID_START_TREE,
  creationBlock: keys.mainnetCreationBlock,
  then: async ({ walletID, eoa, network, rpc, step }) => {
    const provider = new JsonRpcProvider(rpc, 1, { staticNetwork: true });
    const signer = eoa.connect(provider);
    const weth = NETWORK_CONFIG[network].baseToken.wrappedAddress;
    const wallet = walletForID(walletID);
    const fees = async () => { const f = await provider.getFeeData(); return { maxFeePerGas: f.maxFeePerGas, maxPriorityFeePerGas: f.maxPriorityFeePerGas }; };

    const status = await step('status', async () => ({
      publicAddress: eoa.address,
      publicETH: formatEther(await provider.getBalance(eoa.address)),
      privateAddress: getRailgunAddress(walletID),
      privateETH: formatEther(await balanceForERC20Token(V2, wallet, network, weth, false)),
      privateETHSpendable: formatEther(await balanceForERC20Token(V2, wallet, network, weth, true)),
    }));
    if (mode === 'status') return status;

    if (mode === 'shield') {
      const amount = parseEther(arg ?? '0.002');
      const tx = await step('shield-prepare', async () => {
        const shieldPrivateKey = keccak256(await eoa.signMessage(getShieldPrivateKeySignatureMessage()));
        const f = await fees();
        const { transaction } = await populateShieldBaseToken(V2, network, getRailgunAddress(walletID), shieldPrivateKey,
          { tokenAddress: weth, amount }, { evmGasType: EVMGasType.Type2, gasEstimate: 1_000_000n, ...f });
        const gas = await provider.estimateGas({ ...transaction, from: eoa.address }).catch((e) => e.shortMessage ?? e.message);
        return { amountETH: formatEther(amount), railgunFeeETH: formatEther(amount * 25n / 10000n), gas: String(gas), maxGasCostETH: typeof gas === 'bigint' ? formatEther(gas * f.maxFeePerGas) : null, transaction };
      });
      if (!sending) return { dryRun: true, note: 'add --send to make it private' };
      return step('shield-send', async () => {
        const sent = await signer.sendTransaction({ to: tx.transaction.to, data: tx.transaction.data, value: tx.transaction.value });
        const receipt = await sent.wait();
        return { hash: sent.hash, status: receipt.status, gasUsed: String(receipt.gasUsed), note: 'spendable after Railgun\'s 1-hour screening' };
      });
    }

    if (mode === 'unshield') {
      const amount = await balanceForERC20Token(V2, wallet, network, weth, true);
      if (amount === 0n) return { nothingSpendable: true, status };
      const f = await fees();
      const gasEstimate = await step('unshield-estimate', async () => {
        const r = await gasEstimateForUnprovenUnshieldBaseToken(V2, network, eoa.address, walletID, keys.encryptionKey,
          { tokenAddress: weth, amount }, { evmGasType: EVMGasType.Type2, gasEstimate: 0n, ...f }, undefined, true);
        return { gasEstimate: r.gasEstimate };
      });
      await step('unshield-proof', async () => {
        await generateUnshieldBaseTokenProof(V2, network, eoa.address, walletID, keys.encryptionKey, { tokenAddress: weth, amount },
          undefined, true, undefined, () => {});
      });
      const populated = await step('unshield-populate', async () => {
        const { transaction } = await populateProvedUnshieldBaseToken(V2, network, eoa.address, walletID, { tokenAddress: weth, amount },
          undefined, true, undefined, { evmGasType: EVMGasType.Type2, gasEstimate: gasEstimate.gasEstimate, ...f });
        // An EIP-7702 transaction: a one-time address delegated to Railgun's
        // RelayAdapt7702, so `type` and `authorizationList` must ride the send.
        const delegate = transaction.authorizationList?.[0]?.address;
        if (transaction.type === 4 && delegate?.toLowerCase() !== NETWORK_CONFIG[network].relayAdapt7702Contract.toLowerCase()) throw new Error(`unexpected 7702 delegate ${delegate}`);
        const maxGasCost = transaction.gasLimit * transaction.maxFeePerGas;
        const publicWei = await provider.getBalance(eoa.address);
        return { amountETH: formatEther(amount), railgunFeeETH: formatEther(amount * 25n / 10000n), to: transaction.to, type: transaction.type, delegate,
          maxGasCostETH: formatEther(maxGasCost), publicETH: formatEther(publicWei), affordable: publicWei >= maxGasCost, transaction };
      });
      if (!sending) return { dryRun: true, note: 'add --send to move it back to the public address' };
      if (!populated.affordable) return { notSent: true, note: `needs ${populated.maxGasCostETH} ETH for gas at the public address, has ${populated.publicETH}` };
      return step('unshield-send', async () => {
        const t = populated.transaction;
        const sent = await signer.sendTransaction({ ...t, value: t.value ?? 0n });
        const receipt = await sent.wait();
        return { hash: sent.hash, status: receipt.status, gasUsed: String(receipt.gasUsed) };
      });
    }
    throw new Error(`unknown mode ${mode}`);
  },
});
process.exit(0);
