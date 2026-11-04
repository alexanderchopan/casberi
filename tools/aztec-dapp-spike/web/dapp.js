// The APP side, built from Aztec's own @aztec-labs/wallet-sdk WalletManager —
// the same code Shield ships — so a page with dist/inject.js loaded proves the
// whole handshake: discovery, key exchange, emoji check, capabilities, and
// calls parsed through aztec.js's WalletSchema.
import { WalletManager } from '@aztec-labs/wallet-sdk/manager';
import { hashToEmoji } from '@aztec-labs/wallet-sdk/crypto';
import { Fr } from '@aztec-labs/aztec.js/fields';

const out = [];
const say = (step, value) => {
  out.push({ step, value });
  const el = document.getElementById('out');
  if (el) el.textContent = out.map(o => `${o.step}: ${JSON.stringify(o.value)}`).join('\n');
  console.log('[dapp]', step, JSON.stringify(value));
};

window.runDapp = async function runDapp() {
  // Aztec V6: mainnet is L1 chain 1, rollup 2070860440; the testnet is Sepolia, rollup 679261766.
  const testnet = new URLSearchParams(location.search).get('chain') === 'testnet';
  const chainInfo = testnet
    ? { chainId: new Fr(11155111n), version: new Fr(679261766n) }
    : { chainId: new Fr(1n), version: new Fr(2070860440n) };
  const started = performance.now();
  const discovery = WalletManager.configure({ extensions: { enabled: true } }).getAvailableWallets({
    chainInfo,
    appId: 'casberi-spike-dapp',
    timeout: 5000,
  });
  for await (const provider of discovery.wallets) {
    say('discovered', { id: provider.id, name: provider.name, type: provider.type });
    const pending = await provider.establishSecureChannel('casberi-spike-dapp');
    say('emoji', hashToEmoji(pending.verificationHash));
    const wallet = await pending.confirm();
    const caps = await wallet.requestCapabilities({
      version: '1.0',
      metadata: { name: 'Casberi spike dApp', version: '0.0.1' },
      capabilities: [{ type: 'accounts', canGet: true }],
    });
    say('capabilities', caps);
    say('accounts', (await wallet.getAccounts()).map(a => ({ alias: a.alias, item: a.item.toString() })));
    const chain = await wallet.getChainInfo();
    say('chainInfo', { chainId: chain.chainId.toBigInt().toString(), version: chain.version.toBigInt().toString() });
    const accounts = await wallet.getAccounts();
    const meta = await wallet.getContractMetadata(accounts[0].item);
    say('accountOnChain', { initialized: meta.isContractInitialized, published: meta.isContractPublished, hasInstance: !!meta.instance });
    say('msToHere', Math.round(performance.now() - started));
    try {
      await wallet.getPrivateEvents({}, {});
      say('privateEvents', 'answered?');
    } catch (e) {
      say('refusedAsExpected', String(e.message).slice(0, 160));
    }
    discovery.cancel();
    say('done', true);
    return out;
  }
  say('noWallet', true);
  return out;
};

// --- the send flow, testnet only ---------------------------------------------------
// What an Aztec app does through a connected wallet: deploy a token, mint to the
// person's PRIVATE balance, send part of it PRIVATELY to someone else, read both
// balances. Every transaction is the wallet's to approve, prove and send; fees
// come from the testnet's Sponsored FPC.
import { TokenContract } from '@aztec-labs/noir-contracts.js/Token';
import { SponsoredFPCContract } from '@aztec-labs/noir-contracts.js/SponsoredFPC';
import { SponsoredFeePaymentMethod } from '@aztec-labs/aztec.js/fee/testing';
import { getContractInstanceFromInstantiationParams } from '@aztec-labs/stdlib/contract';
import { AztecAddress } from '@aztec-labs/stdlib/aztec-address';
import { TxStatus } from '@aztec-labs/stdlib/tx';
import { createAztecNodeClient } from '@aztec-labs/stdlib/interfaces/client';

window.runSend = async function runSend() {
  const chainInfo = { chainId: new Fr(11155111n), version: new Fr(679261766n) };
  const discovery = WalletManager.configure({ extensions: { enabled: true } }).getAvailableWallets({
    chainInfo, appId: 'casberi-spike-send', timeout: 5000,
  });
  for await (const provider of discovery.wallets) {
    discovery.cancel();
    const pending = await provider.establishSecureChannel('casberi-spike-send');
    say('emoji', hashToEmoji(pending.verificationHash));
    const wallet = await pending.confirm();
    await wallet.requestCapabilities({
      version: '1.0', metadata: { name: 'Casberi send spike', version: '0.0.1' },
      capabilities: [{ type: 'accounts', canGet: true }],
    });
    const me = (await wallet.getAccounts())[0].item;
    say('from', me.toString());
    const fpc = await getContractInstanceFromInstantiationParams(SponsoredFPCContract.artifact, { salt: new Fr(0) });
    await wallet.registerContract(fpc, SponsoredFPCContract.artifact);
    const fee = { paymentMethod: new SponsoredFeePaymentMethod(fpc.address) };
    const wait = { waitForStatus: TxStatus.PROPOSED, timeout: 1800 };
    const timed = async (step, fn) => {
      const t = performance.now();
      const value = await fn();
      const { token: _drop, ...shown } = value; // a Contract holds the wallet proxy: never log it
      say(step, { ms: Math.round(performance.now() - t), ...shown });
      return value;
    };
    const { token } = await timed('deployToken', async () => {
      say('deploySending', true);
      const sent = await TokenContract.deploy(wallet, me, 'Casberi Test', 'CBT', 6).send({ from: me, fee, wait });
      say('deploySent', Object.keys(sent ?? {}));
      const { contract, receipt } = sent;
      return { token: contract, address: contract.address.toString(), tx: receipt.txHash.toString(), status: receipt.status };
    });
    await timed('mintPrivate', async () => {
      const { receipt } = await token.methods.mint_to_private(me, 1_000_000n).send({ from: me, fee, wait });
      return { tx: receipt.txHash.toString(), status: receipt.status };
    });
    const someoneElse = await AztecAddress.random();
    await timed('sendPrivately', async () => {
      const { receipt } = await token.methods.transfer(someoneElse, 250_000n).send({ from: me, fee, wait });
      return { to: someoneElse.toString(), tx: receipt.txHash.toString(), status: receipt.status };
    });
    await timed('balances', async () => {
      const { result } = await token.methods.balance_of_private(me).simulate({ from: me });
      return { mine: result.toString() };
    });
    say('done', true);
    return out;
  }
  say('noWallet', true);
  return out;
};

// Reads a token's private balance for the connected account: what a new phone
// sees for money the old one received.
window.runBalance = async function runBalance(tokenAddress) {
  const chainInfo = { chainId: new Fr(11155111n), version: new Fr(679261766n) };
  const discovery = WalletManager.configure({ extensions: { enabled: true } }).getAvailableWallets({
    chainInfo, appId: 'casberi-spike-balance', timeout: 5000,
  });
  for await (const provider of discovery.wallets) {
    discovery.cancel();
    const wallet = await (await provider.establishSecureChannel('casberi-spike-balance')).confirm();
    await wallet.requestCapabilities({ version: '1.0', metadata: { name: 'Casberi balance spike', version: '0.0.1' }, capabilities: [{ type: 'accounts', canGet: true }] });
    const me = (await wallet.getAccounts())[0].item;
    say('account', me.toString());
    const address = AztecAddress.fromStringUnsafe(tokenAddress);
    // The contract's public instance comes from an Aztec node, as any app reads it.
    const node = createAztecNodeClient('https://aztec-testnet.drpc.org', { maxBatchSize: 3 });
    const instance = await node.getContract(address);
    await wallet.registerContract(instance, TokenContract.artifact);
    const token = await TokenContract.at(address, wallet);
    const t = performance.now();
    const { result } = await token.methods.balance_of_private(me).simulate({ from: me });
    say('balance', { token: tokenAddress, mine: result.toString(), ms: Math.round(performance.now() - t) });
    say('done', true);
    return out;
  }
  say('noWallet', true);
  return out;
};
