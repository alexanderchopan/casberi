// CASBERI'S AZTEC ENGINE (prd §1700): your Aztec account's wallet, in a hidden
// web view no app page can load. Aztec's own `EmbeddedWallet` (a PXE on this
// device) on Aztec mainnet; every proof on Aztec's native iOS prover
// (native-backend.js); every request through the app (net-shim.js). Built from
// the spike that proved it (tools/aztec-dapp-spike).
//
// Two callers:
//   - Casberi itself (`casberiEngine.call`): the account, its balances.
//   - Aztec apps in Casberi's browser, through Aztec's wallet-sdk background
//     handler: the shell relays their messages and names their origin; every
//     connect and every transaction asks the person natively first.
import './net-shim.js';
import './console-bridge.js';
import { BackgroundConnectionHandler } from '@aztec-labs/wallet-sdk/extension/handlers';
import { hashToEmoji } from '@aztec-labs/wallet-sdk/crypto';
import { connectGate } from './connect-gate.js';
import { BrowserEmbeddedWallet } from '@aztec-labs/wallets/embedded';
import { Fr, GrumpkinScalar } from '@aztec-labs/aztec.js/fields';
import { WalletSchema } from '@aztec-labs/aztec.js/wallet';
import { Contract } from '@aztec-labs/aztec.js/contracts';
import { AztecAddress } from '@aztec-labs/aztec.js/addresses';
import { getCanonicalFeeJuice } from '@aztec-labs/protocol-contracts/fee-juice/lazy';
import { computeSecretHash } from '@aztec-labs/aztec.js/crypto';
import { FeeJuicePaymentMethodWithClaim } from '@aztec-labs/aztec.js/fee';
import { isL1ToL2MessageReady } from '@aztec-labs/aztec.js/messaging';
import { loadContractArtifact } from '@aztec-labs/aztec.js/abi';
import shieldTokenJSON from '../shield/token.json';
import shieldBridgeJSON from '../shield/bridge.json';
import shieldProxyJSON from '../shield/proxy.json';
import { EthAddress } from '@aztec-labs/aztec.js/addresses';
import { TxHash } from '@aztec-labs/aztec.js/tx';
import { computeL2ToL1MessageHash } from '@aztec-labs/stdlib/hash';
import { sha256ToField } from '@aztec-labs/foundation/crypto/sha256';
import { jsonStringify } from '@aztec-labs/foundation/json-rpc';
import { getSchemaParameters, parseWithOptionals, schemaHasMethod } from '@aztec-labs/foundation/schemas';
import { poseidon2HashWithSeparator } from '@aztec-labs/foundation/crypto/poseidon';
import { Gas, GasFees } from '@aztec-labs/stdlib/gas';
import { siloNullifier } from '@aztec-labs/stdlib/hash';
import { MerkleTreeId } from '@aztec-labs/stdlib/trees';
import { DomainSeparator } from '@aztec-labs/constants';
import { ProtocolContractAddress } from '@aztec-labs/protocol-contracts';
import { PrivateFPCContract } from '@alejoamiras/private-fee-juice/artifacts/private';
import { FPCFeePaymentMethod, PrivateMintAndPayFeePaymentMethod } from '@alejoamiras/private-fee-juice/fee-payment-methods';
import { estimateGasSettings, maxFeesPerGasFromBaseFees, maxGasCostFor } from '@alejoamiras/private-fee-juice/utils';
import { WALLET_ICON } from './icon.js';
import { watched, sendsReached } from './steps.js';
import { PRIVATE_FEES, choose, sendPaying, inTurn } from './private-fees.js';

const params = new URLSearchParams(location.search);
// Aztec mainnet through dRPC's public node unless the person set their own.
const NODE_URL = params.get('node') ?? 'https://aztec-mainnet.drpc.org';
const WALLET = { walletId: 'casberi', walletName: 'Casberi', walletVersion: '1.0' };
// What an app may call without asking: reads. Anything else is a transaction.
const READS = new Set([
  'getChainInfo', 'getAccounts', 'getAddressBook', 'getContractMetadata', 'getContractClassMetadata',
  'registerSender', 'registerContract', 'getPrivateEvents', 'executeUtility', 'simulateTx', 'requestCapabilities',
]);

// Casberi's own calls that are sends: Move draws their steps (prd §1700w).
const WATCHED_OWN = new Set(['sendPrivately', 'shieldExit']);
const native = (name, value) => window.webkit?.messageHandlers?.[name]?.postMessage(JSON.stringify(value));
const t0 = performance.now();
const ms = () => Math.round(performance.now() - t0);
function log(event, detail) {
  native('engineLog', { event, detail, ms: ms() });
}

// --- the account ---------------------------------------------------------------
// Its two keys come from ONE root the app keeps in iCloud Keychain (prd §1562's
// model): SHA-512 of the root and a label, reduced into each field. The root
// reaches this page only; nothing here stores it.
let rootResolve;
let rootBytes = null;
const rootPromise = new Promise(r => (rootResolve = r));
async function accountKeys() {
  native('engineNeedsRoot', {});
  const hex = await rootPromise;
  const root = Uint8Array.from(hex.match(/../g).map(h => parseInt(h, 16)));
  rootBytes = root;
  const derive = async label => {
    const input = new Uint8Array([...root, ...new TextEncoder().encode(label)]);
    return Buffer.from(await crypto.subtle.digest('SHA-512', input));
  };
  return {
    secret: Fr.fromBufferReduce(await derive('casberi/aztec/v1/secret')),
    signingKey: GrumpkinScalar.fromBufferReduce(await derive('casberi/aztec/v1/signing')),
  };
}

let walletPromise = null;
let accountAddress = null;
function getWallet() {
  walletPromise ??= (async () => {
    log('walletStarting', { node: new URL(NODE_URL).host });
    const wallet = await BrowserEmbeddedWallet.create(NODE_URL, {
      pxe: { proverEnabled: true },
      nodeClientOptions: { maxBatchSize: 3 }, // dRPC's free plan refuses larger batches
    });
    const chain = await wallet.getChainInfo();
    log('pxeReady', { chainId: chain.chainId.toBigInt().toString(), version: chain.version.toBigInt().toString() });
    const { secret, signingKey } = await accountKeys();
    const manager = await wallet.createSchnorrInitializerlessAccount(secret, Fr.ZERO, signingKey, 'Casberi');
    accountAddress = manager.address.toString();
    log('accountReady', { address: accountAddress });
    // The fee contract registers while the first balances are read, not in
    // front of them (prd §1700aa: it took ten seconds on a cold engine).
    privateFpc(wallet).catch(() => {});
    return wallet;
  })();
  walletPromise.catch(() => (walletPromise = null)); // a failed start can be tried again
  return walletPromise;
}

// A compressed string a token returns (a field, or `{ value }`), as text.
function fieldText(raw) {
  if (raw == null) return null;
  try {
    let n = BigInt((raw.value ?? raw).toString());
    const bytes = [];
    while (n > 0n) { bytes.unshift(Number(n & 0xffn)); n >>= 8n; }
    const text = new TextDecoder().decode(new Uint8Array(bytes.filter(b => b !== 0))).trim();
    return /^[\x20-\x7e]{1,16}$/.test(text) ? text : null;
  } catch {
    return null;
  }
}

// SHIELD (prd §1700d): the bridge Move uses. Its interfaces come from its own
// web app (fetch-shield.mjs, pinned to mainnet's classes); here each contract
// is registered only when the node runs the pinned class at that address.
const SHIELD = {
  tokenClass: '0x2ff0939914ff64bd3f7979926dbe8cf3332bc2fee55928bf3cc9ca802568ea9f',
  bridgeClass: '0x28fe903cd306bbc46fd908cc03989601c32368c4694b508499f18516062fefd3',
  // The minter proxy the bridge burns through on the way out (exit_to_l1_private).
  proxyClass: '0x18fa95a66c31125278bf4d07166e30fff3ad7e12b232710bf7e376f36f2d4b8a',
  assets: [
    { symbol: 'USDC', decimals: 6, token: '0x30112e52178143b74cf6037d047bbba924f4b0db8aab587a340aacfc6ecb4f38',
      bridge: '0x023aafff7595c5698625486a010e385144a4a960d268df8ccb205f9134afd775',
      proxy: '0x05fcce110ae9d190e0808596af79ffb21031a3eaf854cf5c74bac3437e86a5fd', portal: '0x6c34d66633ffc36be2dfddc7b0c652fbb305e74c' },
    { symbol: 'WETH', decimals: 18, token: '0x2a36cedc4f7fa6bd9fbb77ab799737f30d12cd86ffa9d9d63737d51a6e7247fe',
      bridge: '0x267a10e5463760e88f487a719bd38f09c46ec87260c51b0affc88fd9ff1d9ef4',
      proxy: '0x1a90eeb03bbfff70d97e1290376c550fa911c4b0ecbb0a8483516f66f7d05bf3', portal: '0x477a911f76c44a5d3e5e692c59945263f61426c4' },
  ],
};
const shieldToken = loadContractArtifact(shieldTokenJSON);
const shieldBridge = loadContractArtifact(shieldBridgeJSON);
const shieldProxy = loadContractArtifact(shieldProxyJSON);
let shieldRegistered = null;
async function registerShield(wallet) {
  shieldRegistered ??= (async () => {
    for (const asset of SHIELD.assets) {
      for (const [address, artifact, pin] of [[asset.token, shieldToken, SHIELD.tokenClass], [asset.bridge, shieldBridge, SHIELD.bridgeClass], [asset.proxy, shieldProxy, SHIELD.proxyClass]]) {
        const at = AztecAddress.fromStringUnsafe(address);
        if ((await wallet.getContractMetadata(at)).instance) continue;
        const instance = await wallet.aztecNode.getContract(at);
        const cls = (instance?.currentContractClassId ?? instance?.originalContractClassId)?.toString();
        if (cls !== pin) { log('shieldRefused', { address, cls }); continue; } // a different contract: never called
        await wallet.registerContract(instance, artifact);
      }
    }
  })();
  shieldRegistered.catch(() => (shieldRegistered = null));
  return shieldRegistered;
}

// A deposit's claim secret: the root, a label and the deposit's nonce.
async function depositSecret(nonce) {
  return derivedSecret(`feejuice/${nonce}`);
}
async function derivedSecret(label) {
  if (!rootBytes) await getWallet();
  const input = new Uint8Array([...rootBytes, ...new TextEncoder().encode(`casberi/aztec/v1/${label}`)]);
  return Fr.fromBufferReduce(Buffer.from(await crypto.subtle.digest('SHA-512', input)));
}

// --- private gas (prd §1700aa; private-fees.js says why) ---------------------------
// The shared PrivateFPC, registered with this wallet — never deployed, it has
// no public half — only on the rollup it was compiled for and only when the
// address its bytecode derives is the pinned one. Null anywhere else, and the
// account pays from its own Fee Juice as before.
let privateFpcPromise = null;
function privateFpc(wallet) {
  privateFpcPromise ??= (async () => {
    const chain = await wallet.getChainInfo();
    const version = chain.version.toBigInt();
    if (version !== PRIVATE_FEES.rollupVersion) {
      log('privateFeesOff', { why: 'rollup', version: version.toString() });
      return null;
    }
    const deploy = PrivateFPCContract.deploy(wallet, { salt: new Fr(PRIVATE_FEES.salt), universalDeploy: true });
    const derived = (await deploy.getInstance()).address;
    if (!derived.equals(AztecAddress.fromStringUnsafe(PRIVATE_FEES.address))) {
      log('privateFeesOff', { why: 'address', derived: derived.toString() });
      return null;
    }
    const fpc = await deploy.register();
    log('privateFeesReady', { address: fpc.address.toString() });
    return fpc;
  })();
  privateFpcPromise.catch(() => (privateFpcPromise = null));
  return privateFpcPromise;
}

// A private gas deposit's two values: its salt, from the root and the
// deposit's nonce (a new phone can still mint it), and the claim secret the
// contract derives from that salt and THIS account, so only this account can
// mint it. Shield's own client derives it the same way (read 2026-11-10).
async function gasSecret(nonce) {
  const salt = await derivedSecret(`fpc/${nonce}`);
  const secret = await poseidon2HashWithSeparator([salt, Fr.fromString(accountAddress)], PRIVATE_FEES.bridgeSeparator);
  return { salt, secret };
}

// Whether a private gas deposit was already claimed (and so minted: the two
// happen in one transaction's setup). Read from the chain, never the app's
// memory, which loses a send that finished while the app was away. The claim's
// nullifier is Aztec's own: the message hash and the secret under
// MESSAGE_NULLIFIER, siloed by the Fee Juice contract. A wrong answer can only
// be "not yet" — then the mint is measured, fails, and the next way is tried.
async function gasMinted(wallet, item) {
  try {
    const { secret } = await gasSecret(item.nonce);
    const inner = await poseidon2HashWithSeparator([Fr.fromString(item.messageHash), secret], DomainSeparator.MESSAGE_NULLIFIER);
    const siloed = await siloNullifier(ProtocolContractAddress.FeeJuice, inner);
    const [found] = await wallet.aztecNode.findLeavesIndexes('latest', MerkleTreeId.NULLIFIER_TREE, [siloed]);
    return found !== undefined;
  } catch (e) {
    log('gasMintedUnread', { error: String(e?.message ?? e).slice(0, 160) });
    return false;
  }
}

// What the account holds inside the contract, base units; zero when unread.
async function privateGasBalance(fpc, me) {
  try {
    const { result } = await fpc.methods.balance_of(me).simulate({ from: me });
    return BigInt(result.toString());
  } catch (e) {
    log('privateGasUnread', { error: String(e?.message ?? e).slice(0, 160) });
    return 0n;
  }
}

// How `interaction` pays (private-fees.js `choose`), with the options its
// send takes. `gasJSON` is the app's list of private gas deposits nobody has
// minted yet: [{ nonce, amount, leafIndex, messageHash }].
async function feeFor(wallet, interaction, gasJSON) {
  const fpc = await privateFpc(wallet);
  if (!fpc) return { how: 'own' };
  const me = AztecAddress.fromStringUnsafe(accountAddress);
  const maxFeesPerGas = maxFeesPerGasFromBaseFees(await wallet.aztecNode.getCurrentMinFees());
  const limits = Gas.from(PRIVATE_FEES.limits);
  const pending = [];
  for (const g of JSON.parse(gasJSON || '[]')) {
    const item = { nonce: String(g.nonce), amount: BigInt(g.amount), leafIndex: BigInt(g.leafIndex), messageHash: g.messageHash };
    if (await gasMinted(wallet, item)) continue; // spent by an earlier send
    item.ready = await isL1ToL2MessageReady(wallet.aztecNode, Fr.fromString(g.messageHash)).catch(() => false);
    pending.push(item);
  }
  const method = async (how, item) => {
    if (how === 'private') return new FPCFeePaymentMethod(fpc.address);
    const { salt, secret } = await gasSecret(item.nonce);
    return new PrivateMintAndPayFeePaymentMethod(fpc.address, item.amount, secret, salt, new Fr(item.leafIndex));
  };
  const picked = await choose({
    balance: await privateGasBalance(fpc, me),
    ceiling: maxGasCostFor(maxFeesPerGas, limits),
    pending,
    // Measured first, and never above what is there: the contract keeps the
    // whole declared limit, so a node that overstates the fee is refused.
    estimate: async (how, cap, item) => estimateGasSettings(interaction, {
      aztecNode: wallet.aztecNode, from: me, paymentMethod: await method(how, item),
      additionalScopes: [fpc.address], maxAcceptableGasCost: cap,
    }),
  });
  if (picked.how === 'own') return picked;
  const gasSettings = picked.settings ?? {
    gasLimits: limits, teardownGasLimits: Gas.from({ l2Gas: 0, daGas: 0 }),
    maxFeesPerGas, maxPriorityFeesPerGas: GasFees.empty(),
  };
  log('privateFee', { how: picked.how, measured: picked.settings != null });
  return { ...picked, options: { additionalScopes: [fpc.address], fee: { paymentMethod: await method(picked.how, picked.item), gasSettings } } };
}

// One of Casberi's own sends, paid privately when it can be, in its turn:
// it chooses how to pay only once the send before it has landed.
const ownTurn = inTurn();
function sendOwn(wallet, interaction, gasJSON) {
  const me = AztecAddress.fromStringUnsafe(accountAddress);
  const wait = { waitForStatus: 'proposed', timeout: 1800 };
  return ownTurn(() => sendPaying({
    pay: () => feeFor(wallet, interaction, gasJSON),
    send: async options => (await interaction.send({ from: me, ...(options ?? {}), wait })).receipt,
    reached: sendsReached,
    log,
  }));
}

// --- Casberi's own calls -----------------------------------------------------------
const own = {
  async account() {
    await getWallet();
    return { address: accountAddress };
  },
  // What the account holds (prd §1700, step 2): Fee Juice, the gas every
  // transaction pays, read from Aztec's own protocol contract; and every token
  // an app taught the wallet (an app registers its contracts, interface and
  // all, when it connects — Shield's USDC and WETH, measured 2026-11-04), read
  // privately and publicly. Nothing is hard-coded but Fee Juice.
  async holdings() {
    const wallet = await getWallet();
    await registerShield(wallet).catch(e => log('shieldSkipped', { error: String(e?.message ?? e).slice(0, 160) }));
    const me = AztecAddress.fromStringUnsafe(accountAddress);
    const out = [];
    const read = async (contract, fn) => {
      try {
        const { result } = await contract.methods[fn](me).simulate({ from: me });
        return BigInt(result.toString()).toString();
      } catch (e) {
        log('holdingSkipped', { fn, error: String(e?.message ?? e).slice(0, 160) });
        return null;
      }
    };
    const feeJuice = await getCanonicalFeeJuice();
    if (!(await wallet.getContractMetadata(feeJuice.address)).instance) {
      await wallet.registerContract(feeJuice.instance, feeJuice.artifact);
    }
    const fj = await Contract.at(feeJuice.address, feeJuice.artifact, wallet);
    // Gas is the account's own Fee Juice (public) and what it keeps inside
    // the private fee contract (prd §1700aa); the app adds the two.
    const fpc = await privateFpc(wallet).catch(() => null);
    out.push({ kind: 'feeJuice', address: feeJuice.address.toString(), symbol: 'Fee Juice', decimals: 18,
               public: await read(fj, 'balance_of_public'),
               private: fpc ? (await privateGasBalance(fpc, me)).toString() : null });
    for (const address of await wallet.pxe.getContracts()) {
      if (address.equals(feeJuice.address) || address.equals(me)) continue;
      try {
        const instance = await wallet.pxe.getContractInstance(address);
        const classId = instance?.currentContractClassId ?? instance?.originalContractClassId;
        const artifact = classId && (await wallet.pxe.getContractArtifact(classId));
        const names = new Set((artifact?.functions ?? []).map(f => f.name));
        if (!names.has('balance_of_private')) continue;
        const token = await Contract.at(address, artifact, wallet);
        // Its decimals and symbol from its own functions, whichever spelling it
        // uses; unknown stays null (the app then shows no amount, never a guess).
        const view = async candidates => {
          for (const fn of candidates.filter(n => names.has(n))) {
            try {
              const { result } = await token.methods[fn]().simulate({ from: me });
              return result;
            } catch {}
          }
          return null;
        };
        const known = SHIELD.assets.find(a => AztecAddress.fromStringUnsafe(a.token).equals(address));
        const decimalsRaw = known ? known.decimals : await view(['decimals', 'public_get_decimals', 'private_get_decimals']);
        const symbolRaw = known ? null : await view(['symbol', 'public_get_symbol', 'private_get_symbol']);
        out.push({
          kind: 'token', address: address.toString(), name: artifact.name,
          symbol: known ? known.symbol : fieldText(symbolRaw),
          decimals: decimalsRaw == null ? null : Number(BigInt((decimalsRaw.value ?? decimalsRaw).toString())),
          private: await read(token, 'balance_of_private'),
          public: names.has('balance_of_public') ? await read(token, 'balance_of_public') : null,
        });
      } catch (e) {
        log('holdingSkipped', { address: address.toString(), error: String(e?.message ?? e).slice(0, 160) });
      }
    }
    return out;
  },
  // GAS (prd §1700e item 2): your Safe deposits AZTEC into Aztec's own Fee
  // Juice portal for this account; the claim's secret is derived from the
  // root and the deposit's nonce, so a new phone can still claim it.
  // Since prd §1700aa the deposit goes to the private fee contract, claimable
  // by this account alone (`kind: 'private'`), so Ethereum never names the
  // account; where that contract is not this rollup's, to the account itself
  // as before (`kind: 'own'`).
  async feeJuicePlan(nonce) {
    const wallet = await getWallet();
    if (await privateFpc(wallet).catch(() => null)) {
      const { secret } = await gasSecret(nonce);
      return { to: PRIVATE_FEES.address, secretHash: (await computeSecretHash(secret)).toString(), kind: 'private' };
    }
    const secret = await depositSecret(nonce);
    return { to: accountAddress, secretHash: (await computeSecretHash(secret)).toString(), kind: 'own' };
  },
  // Whether Aztec has the deposit's message yet (minutes after it lands).
  async feeJuiceReady(messageHash) {
    const wallet = await getWallet();
    return { ready: await isL1ToL2MessageReady(wallet.aztecNode, Fr.fromString(messageHash)) };
  },
  // Claims it: a transaction whose own fee is paid from what it claims.
  async feeJuiceClaim(nonce, amount, leafIndex) {
    const wallet = await getWallet();
    const me = AztecAddress.fromStringUnsafe(accountAddress);
    const feeJuice = await getCanonicalFeeJuice();
    if (!(await wallet.getContractMetadata(feeJuice.address)).instance) {
      await wallet.registerContract(feeJuice.instance, feeJuice.artifact);
    }
    const paymentMethod = new FeeJuicePaymentMethodWithClaim(me, {
      claimAmount: BigInt(amount), claimSecret: await depositSecret(nonce), messageLeafIndex: BigInt(leafIndex),
    });
    const fj = await Contract.at(feeJuice.address, feeJuice.artifact, wallet);
    const { receipt } = await fj.methods.check_balance(0n).send({ from: me, fee: { paymentMethod }, wait: { waitForStatus: 'proposed', timeout: 1800 } });
    log('feeJuiceClaimed', { tx: receipt.txHash.toString(), status: receipt.status });
    return { tx: receipt.txHash.toString(), status: String(receipt.status) };
  },
  // SHIELD INTO AZTEC (prd §1700e): the deposit's claim secret, derived from
  // the root and a nonce like gas's, and the claim on Aztec once the bridge's
  // message is there; its fee is the account's own Fee Juice.
  async shieldPlan(nonce) {
    await getWallet();
    const secret = await derivedSecret(`shield/${nonce}`);
    return { to: accountAddress, secretHash: (await computeSecretHash(secret)).toString() };
  },
  async messageReady(messageHash) {
    const wallet = await getWallet();
    return { ready: await isL1ToL2MessageReady(wallet.aztecNode, Fr.fromString(messageHash)) };
  },
  // Each of the three sends below takes `gasJSON`, the private gas deposits
  // nobody has minted yet, and answers how it paid (`paid`) and the deposit it
  // minted (`gasNonce`), if any (prd §1700aa).
  async shieldClaim(symbol, amount, nonce, leafIndex, gasJSON) {
    const wallet = await getWallet();
    await registerShield(wallet);
    const asset = SHIELD.assets.find(a => a.symbol === symbol);
    if (!asset) throw new Error(`no ${symbol} on Aztec`);
    const me = AztecAddress.fromStringUnsafe(accountAddress);
    const bridge = await Contract.at(AztecAddress.fromStringUnsafe(asset.bridge), shieldBridge, wallet);
    const claim = bridge.methods.claim_private(me, BigInt(amount), await derivedSecret(`shield/${nonce}`), BigInt(leafIndex));
    const { receipt, paid, gasNonce } = await sendOwn(wallet, claim, gasJSON);
    log('shieldClaimed', { tx: receipt.txHash.toString(), status: receipt.status, paid });
    return { tx: receipt.txHash.toString(), status: String(receipt.status), paid, gasNonce };
  },
  // A private send inside Aztec (prd §1700e): Shield's token, account to
  // account, no one's permission; the app has asked Face ID before calling.
  async sendPrivately(symbol, to, units, gasJSON) {
    const wallet = await getWallet();
    await registerShield(wallet);
    const asset = SHIELD.assets.find(a => a.symbol === symbol);
    if (!asset) throw new Error(`no ${symbol} on Aztec`);
    const me = AztecAddress.fromStringUnsafe(accountAddress);
    const token = await Contract.at(AztecAddress.fromStringUnsafe(asset.token), shieldToken, wallet);
    const send = token.methods.transfer_private_to_private(me, AztecAddress.fromStringUnsafe(to), BigInt(units), 0n);
    const { receipt, paid, gasNonce } = await sendOwn(wallet, send, gasJSON);
    log('sentPrivately', { tx: receipt.txHash.toString(), status: receipt.status, paid });
    return { tx: receipt.txHash.toString(), status: String(receipt.status), paid, gasNonce };
  },
  // SHIELD OUT OF AZTEC (prd §1700b, §1700d): read from Shield's own client.
  // The bridge checks Shield's signed Passport limit (an Aztec signature over
  // this account), sends a message to the portal on Ethereum and burns the
  // tokens through its minter proxy, which this account authorises for
  // exactly this burn. Anyone may finish it on Ethereum (caller_on_l1 zero);
  // the money goes to `recipient` only.
  async shieldExit(symbol, units, recipient, passportJSON, gasJSON) {
    const wallet = await getWallet();
    await registerShield(wallet);
    const asset = SHIELD.assets.find(a => a.symbol === symbol);
    if (!asset) throw new Error(`no ${symbol} on Aztec`);
    const p = JSON.parse(passportJSON);
    if (!Array.isArray(p.signature) || p.signature.length !== 64) throw new Error('Shield gave no Aztec signature');
    const me = AztecAddress.fromStringUnsafe(accountAddress);
    const amount = BigInt(units);
    const token = await Contract.at(AztecAddress.fromStringUnsafe(asset.token), shieldToken, wallet);
    const bridge = await Contract.at(AztecAddress.fromStringUnsafe(asset.bridge), shieldBridge, wallet);
    const nonce = Fr.random();
    const burn = await token.methods.burn_private(me, amount, nonce).getFunctionCall();
    const witness = await wallet.createAuthWit(me, { caller: AztecAddress.fromStringUnsafe(asset.proxy), call: burn });
    const to = EthAddress.fromString(recipient);
    const exit = bridge.methods.exit_to_l1_private(
      to, amount, EthAddress.ZERO, nonce,
      { nonce: 0n, signature: Array(64).fill(0) },
      { max_amount: BigInt(p.maxAmount), nonce: BigInt(p.nonce), deadline: BigInt(p.deadline), signature: p.signature },
    ).with({ authWitnesses: [witness] });
    const { receipt, paid, gasNonce } = await sendOwn(wallet, exit, gasJSON);
    const info = await wallet.aztecNode.getNodeInfo();
    // The message the portal will consume: sha256 of withdraw(address,uint256,address)'s
    // selector, the recipient, the amount and caller_on_l1 (zero).
    const content = sha256ToField([Buffer.from('69328dec', 'hex'), to.toBuffer32(), new Fr(amount).toBuffer(), EthAddress.ZERO.toBuffer32()]);
    const message = computeL2ToL1MessageHash({
      l2Sender: AztecAddress.fromStringUnsafe(asset.bridge), l1Recipient: EthAddress.fromString(asset.portal), content,
      rollupVersion: new Fr(BigInt(info.rollupVersion)), chainId: new Fr(BigInt(info.l1ChainId)),
    });
    log('shieldExited', { tx: receipt.txHash.toString(), status: receipt.status, paid });
    return { tx: receipt.txHash.toString(), block: String(receipt.blockNumber ?? ''), message: message.toString(),
             outbox: info.l1ContractAddresses?.outboxAddress?.toString() ?? null, paid, gasNonce };
  },
  // Once the epoch holding the exit is proven on Ethereum: where its message
  // sits in the outbox, for the portal's withdraw. Null until then.
  async exitWitness(txHash, message) {
    const wallet = await getWallet();
    const w = await wallet.aztecNode.getL2ToL1MembershipWitness(TxHash.fromString(txHash), Fr.fromString(message)).catch(() => undefined);
    if (!w) return null;
    return { epoch: String(w.epochNumber), checkpoints: String(w.numCheckpointsInEpoch), leaf: String(w.leafIndex),
             path: w.siblingPath.toBufferArray().map(b => '0x' + b.toString('hex')) };
  },
  // REVEAL KEY (prd §1700f item 6): what another Aztec wallet needs to open
  // this same account — its secret key, its Schnorr signing key, the salt and
  // the account's kind. Casberi's own call only (never an app's); the app has
  // asked Face ID and the co-signer before calling.
  async exportKeys() {
    await getWallet();
    const { secret, signingKey } = await accountKeys();
    return { address: accountAddress, secretKey: secret.toString(), signingKey: signingKey.toString(),
             salt: Fr.ZERO.toString(), kind: 'schnorr-initializerless' };
  },
  // What a send costs right now (prd §1700y): the node's minimum fee per
  // unit of gas, Fee Juice in its smallest unit. Move multiplies it by a
  // send's measured gas for "Costs about $0.02".
  async minFees() {
    const f = await (await getWallet()).aztecNode.getCurrentMinFees();
    return { l2: f.feePerL2Gas.toString(), da: f.feePerDaGas.toString() };
  },
  // Which of the app's unminted private gas deposits a send has in fact
  // spent (prd §1700aa): the app forgets them, however that send ended.
  async gasSpent(gasJSON) {
    const wallet = await getWallet();
    const spent = [];
    for (const g of JSON.parse(gasJSON || '[]')) {
      if (await gasMinted(wallet, { nonce: String(g.nonce), messageHash: g.messageHash })) spent.push(String(g.nonce));
    }
    return { spent };
  },
  // Whether private gas is on for this rollup, and what the account keeps in
  // the contract (prd §1700aa): the probe's line, and nothing sent.
  async privateFees() {
    const wallet = await getWallet();
    const fpc = await privateFpc(wallet).catch(() => null);
    if (!fpc) return { on: false };
    const balance = await privateGasBalance(fpc, AztecAddress.fromStringUnsafe(accountAddress));
    return { on: true, address: fpc.address.toString(), balance: balance.toString() };
  },
  async chain() {
    const c = await (await getWallet()).getChainInfo();
    return { chainId: c.chainId.toBigInt().toString(), version: c.version.toBigInt().toString() };
  },
};

// --- apps' calls --------------------------------------------------------------------
let asks = 0;
const waiting = new Map();

// What the sheet says about a transaction, read from the request itself: each
// call's function and contract, private or public, and who pays the fee. (A
// private call can start public steps of its own; they are not read yet, so
// the sheet does not claim to know them.)
const tail = a => '...' + String(a ?? '').slice(-4);
function describe(args) {
  const calls = (args?.[0]?.calls ?? []).map(c => ({ name: c.name, to: tail(c.to), type: c.type }));
  return { calls, fee: 'Paid from your Fee Juice' };
}

function askPerson(method, args, origin) {
  const id = ++asks;
  native('engineApprove', { id, method, origin, ...describe(args) });
  return new Promise(resolve => waiting.set(id, resolve));
}

async function callForApp(method, args, origin) {
  const wallet = await getWallet();
  if (method === 'requestCapabilities') {
    const manifest = args?.[0] ?? {};
    const accounts = (await wallet.getAccounts()).map(a => ({ alias: a.alias, item: a.item.toString() }));
    return {
      version: '1.0',
      granted: (manifest.capabilities ?? []).map(c => (c.type === 'accounts' ? { ...c, accounts } : c)),
      wallet: { name: WALLET.walletName, version: WALLET.walletVersion },
    };
  }
  if (typeof wallet[method] !== 'function') throw new Error(`Unknown wallet method: ${method}`);
  if (!READS.has(method)) {
    const yes = await askPerson(method, args, origin);
    log('approval', { method, yes });
    if (!yes) throw new Error(`The person declined ${method}`);
  }
  const parsed = schemaHasMethod(WalletSchema, method)
    ? await parseWithOptionals(args ?? [], getSchemaParameters(WalletSchema[method]))
    : args ?? [];
  // An approved transaction reports its steps to the browser (prd §1700w).
  const run = () => wallet[method](...parsed);
  const result = await (READS.has(method) ? run() : watched('app', run));
  return result === undefined ? undefined : JSON.parse(jsonStringify(result));
}

let contentListener = null;
// Discovery is answered at once; Connect and the emoji check are asked when
// the person picks Casberi in the app, and hold its calls (connect-gate.js).
let gate = null;
const background = new BackgroundConnectionHandler(
  { ...WALLET, walletIcon: WALLET_ICON },
  {
    sendToTab: (tabId, message) => native('engineToTab', { tabId, message }),
    addContentListener: handler => {
      contentListener = handler;
    },
  },
  {
    onPendingDiscovery: discovery => {
      log('discovered', { origin: discovery.origin, appId: discovery.appId });
      gate.discovered(discovery.requestId);
    },
    onSessionEstablished: session => {
      const id = session.sessionId ?? session.requestId;
      gate.established(id, session.origin, hashToEmoji(session.verificationHash));
    },
    onSessionTerminated: requestId => {
      gate.terminated(requestId);
      log('terminated', { requestId });
    },
    onWalletMessage: async (session, message) => {
      const id = session.sessionId ?? session.requestId;
      if (!gate.message(id, () => answerApp(session, message))) {
        await background.sendResponse(id, {
          messageId: message.messageId, error: { message: 'Not connected to Casberi' }, walletId: WALLET.walletId,
        });
      }
    },
  },
);
gate = connectGate({
  approveDiscovery: requestId => background.approveDiscovery(requestId),
  terminateSession: sessionId => background.terminateSession(sessionId),
  askConnect: (requestId, origin) => native('engineConnect', { requestId, origin }),
  askEmoji: (sessionId, origin, emoji) => native('engineEmoji', { sessionId, emoji, origin }),
  log,
});
background.initialize();

async function answerApp(session, message) {
      const { messageId, type, args } = message;
      const started = ms();
      let result;
      let error;
      try {
        result = await callForApp(type, args, session.origin);
      } catch (e) {
        error = { message: String(e?.message ?? e).slice(0, 400) };
      }
      log(error ? 'refused' : 'answered', { type, origin: session.origin, took: ms() - started });
      await background.sendResponse(session.sessionId ?? session.requestId, { messageId, result, error, walletId: WALLET.walletId });
}

// --- the shell's door ------------------------------------------------------------
window.casberiEngine = {
  setRoot(hex) {
    rootResolve(hex);
  },
  // Casberi's own call: the answer comes back as `engineReply`.
  call(id, method, argsJSON) {
    const fn = own[method];
    const go = () => fn(...JSON.parse(argsJSON ?? '[]'));
    // Move's sends report their steps (prd §1700w); claims and reads do not.
    const run = !fn ? Promise.reject(new Error(`unknown call ${method}`))
      : WATCHED_OWN.has(method) ? watched('move', go) : go();
    run.then(
      result => native('engineReply', { id, result }),
      e => native('engineReply', { id, error: String(e?.message ?? e).slice(0, 400) }),
    );
  },
  fromContent(json, tabId, url) {
    contentListener?.(JSON.parse(json), { tab: { id: tabId, url } });
  },
  // The person's answer to Connect (the session's id is the discovery's).
  answerConnect(requestId, yes) {
    gate.answerConnect(requestId, yes);
  },
  // The person compared the two grids: they match, or the session ends and
  // its waiting calls with it.
  confirmEmoji(sessionId, match) {
    gate.confirmEmoji(sessionId, match);
  },
  answerApproval(id, yes) {
    waiting.get(id)?.(yes);
    waiting.delete(id);
  },
};

log('engineReady', { isolated: self.crossOriginIsolated, secure: self.isSecureContext });
native('engineReady', {});
