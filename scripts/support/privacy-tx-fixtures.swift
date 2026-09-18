// Two real type-0x6 transactions off the RELAUNCHED Ethrex Privacy devnet
// (genesis 0x2036e3fe…, read 2026-09-18 with eth_getTransactionByHash on
// rpc1.privacy.ethrex.xyz). `fx_simple` is the pool's first deposit (block
// 8150); `fx_rich` is the pool's own spend (block 8155): two 32-byte nonce
// keys and a recent-root reference riding as a frame to 0x…8272.

let fx_simple = (hash: "0x2a5948088aa9e81549ec19f26a806b33d686090906eec4ce007952bb810b6772", f: PrivacyDevnetTransaction.Fields(
    chainID: 8141,
    nonceKeys: [hx("00")],
    nonce: 5,
    sender: hx("30eac2d1bad148af79173b8cf1b6ec461e517128"),
    frames: [F(mode: 1, flags: 3, target: hx("30eac2d1bad148af79173b8cf1b6ec461e517128"), gasLimit: 80000, stateLimit: 0, value: hx("00"), data: hx("")),
            F(mode: 2, flags: 0, target: hx("8fdab78244c5fa43809d064fc93e6c0e5041971d"), gasLimit: 979537, stateLimit: 550000, value: hx("0de0b6b3a7640000"), data: hx("261235482dbb6517aacdd5efb9f76038024b535919bf021a854eb09e549cfa03bddecdd4"))],
    signatures: [S(scheme: 1, signer: hx("30eac2d1bad148af79173b8cf1b6ec461e517128"), msg: hx(""), signature: hx("00931ab862bee7c39e1a09ff19303ceeb284c9857782ffa9593b16fb13979bbd5f0db9baa9d6b7c8f3cf9d959386f9ee0a01d82d37d4fa09694459f86e2f5dc4a2"))],
    maxPriorityFeePerGas: 1000000000,
    maxFeePerGas: 1000000014,
    maxFeePerBlobGas: 0,
    blobVersionedHashes: []))

let fx_rich = (hash: "0x2b90c598179b0cb8fca70a1c7c9211ca9a27945eeaae6c51ad0d8d0d501b45ac", f: PrivacyDevnetTransaction.Fields(
    chainID: 8141,
    nonceKeys: [hx("1479940291777d1f0f3d58bf8a46cf21c33e7cfcd8b9876766a33d3a39b3e821"), hx("2e0eb2f5b5991e31cdde9b66c0da09e603e20744ec9c708e93ba4409bc3e8cbc")],
    nonce: 0,
    sender: hx("8fdab78244c5fa43809d064fc93e6c0e5041971d"),
    frames: [F(mode: 1, flags: 0, target: hx("0000000000000000000000000000000000008272"), gasLimit: 30000, stateLimit: 0, value: hx("00"), data: hx("e06e601046631b3e1dc3943f4f7d058de6da6772644dca7af1a42500c810b2f8000000000000214b2dd32b6609c5a8e80505ac44c5cb8e9f712115c1f63f59b18be08fc9b9250bf4")),
            F(mode: 1, flags: 3, target: hx("8fdab78244c5fa43809d064fc93e6c0e5041971d"), gasLimit: 320000, stateLimit: 195840, value: hx("00"), data: hx("142c5f6d9a8738a54e2ee90f4409a6af834e9104df472933979972022c350cec1b8366bedf0be780c8eddfbc9a220c5e23f9394a2e4c9cb95b9715362587ae440742b159781b0b9b6a9f8b54b592d10ead22e27f91be0a381e59ccad3b7e684915b39b0e9e8458b919b3d632bbd81ddab4a2206e7a84493f95925ae811ef714e2da7102c987266852bb48814048f69134d5966c152093c34965845fb1a61d26e2395f196c441a0de516e35e00d7c04d6d4eeb3b0b804584864ab5c14dca148422e14cdbae16846eb9719ea3a90798843ccf6e40446fe01e99eaa2bbec6bac8232117f5c268e6b8f2eabe99cbff62087937230654d484c73d2723d8a76aaa74a9")),
            F(mode: 2, flags: 0, target: hx("8fdab78244c5fa43809d064fc93e6c0e5041971d"), gasLimit: 1400000, stateLimit: 550000, value: hx("00"), data: hx("921fcac72dd32b6609c5a8e80505ac44c5cb8e9f712115c1f63f59b18be08fc9b9250bf4000000000000000000000000000000000000000000000000000000000000214b0000000000000000000000000000000000000000000000000000000000000000216043a52690fc9df26a1cafc64da798262b2e15c05d28325da41c71382734921479940291777d1f0f3d58bf8a46cf21c33e7cfcd8b9876766a33d3a39b3e8212e0eb2f5b5991e31cdde9b66c0da09e603e20744ec9c708e93ba4409bc3e8cbc2a50d6a48d22560f434a83f4f5d13b5dbdbe9c9ea9756518c97795baf29ce8cd265eaed4eaf0cf73d07a90560bab4c1c65975ac7d2362396c0a93c5d14d1dabc000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b1a2bc2ec500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000278b8a2fc5fd3cc62c5e181bf22462569554b197"))],
    signatures: [S(scheme: 1, signer: hx("278b8a2fc5fd3cc62c5e181bf22462569554b197"), msg: hx(""), signature: hx("018481b6062625571762def4943c90896074e97842377cd3bc64a21f120457a20e131ce869d65117c0ceaef18a64786d743ae1aec8a3a5eed8f95cb2b0d6c35b9e"))],
    maxPriorityFeePerGas: 1000000000,
    maxFeePerGas: 1000000014,
    maxFeePerBlobGas: 0,
    blobVersionedHashes: []))
