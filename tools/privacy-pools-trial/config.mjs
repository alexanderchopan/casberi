// Sepolia ONLY. Every address here was read back from the ASP feed, the relayer's
// /v1/details and the chain itself on 2026-10-26 (see discover.mjs).
export const CHAIN_ID = 11155111;
export const RPC = process.env.SEPOLIA_RPC ?? 'https://ethereum-sepolia-rpc.publicnode.com';
// The dev ASP serves Sepolia (api-v2.0xbow.io is production-only and lists no 11155111 pool).
export const ASP_URL = 'https://api-dev.0xbow.io';
// The v2 STAGING relayer. testnet-relayer.privacypools.com is the v1 relayer
// (/relayer/details?chainId=…); it has no /v1/* routes.
export const RELAYER_URL = 'https://relayer-v2-staging-149184580131.us-east1.run.app';

export const SEPOLIA = {
  entrypoint: '0xEB3e3961008952348445513e418ad6F43C23ca9a',
  poolVault: '0x09b94d3127019298757A6ceeB7911922085f7C01',
  keystore: '0x6d264aCb9C3A7A3105c29470AfE2F5F1EC203C73',
  aspRegistry: '0x35D29EFDCf067599ab4A53cf40229477f0b1cA9c',
  // Batch-capable PrivacyPoolRelay the staging relayer calls through (withdrawal processor).
  relay: '0x7430cc030d7eb8C83E76cD983996982C8C054204',
  // Relayer signer EOA: the on-chain caller (and so the proof processor) for TRANSFERS.
  relayerSigner: '0x4Ba5fF376865b370790A56276C63e7984DCFf1f7',
  // Pool 4 in the ASP feed starts at 10994884.
  // The keystore predates pool 4 (its first event is block 10932354); scanning from the pool alone leaves holes in its tree.
  fromBlock: 10932354n,
  eth: '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE',
};

export function assertTestnet(chainId) {
  if (Number(chainId) !== CHAIN_ID) throw new Error(`refusing: chain ${chainId} is not Sepolia`);
}
