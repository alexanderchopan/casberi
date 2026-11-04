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
  document.getElementById('out').textContent = out.map(o => `${o.step}: ${JSON.stringify(o.value)}`).join('\n');
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
