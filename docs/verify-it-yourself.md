# Verify it yourself

The claims this repo makes, and the command that checks each one on your own machine. Nothing here needs an account, a key or a signed build.

You need a Mac with Xcode 27 for the Swift checks, and Node 22 or later for the engine bundles. Run everything from the repo root.

## 1. The app contacts only the hosts it declares

**Claim.** Every host the app can reach is listed in `Model/NetworkReach.swift`, and published as [`hosts.md`](hosts.md).

```sh
scripts/network-reach-audit.sh
```

Expect: `network-reach-audit: OK — every host is disclosed in the reach registry or the non-reach denylist.` It scans the source for host literals and fails on one that is not declared.

```sh
python3 scripts/hosts-doc.py --check
```

Expect: `✓ hosts page current`. The published page matches the code.

What this does not prove: a host assembled at runtime from your own input (a feed you follow, your own node) cannot be listed by name. The app records every host it actually reached and shows them to you, so the two can be compared on a real device.

## 2. Keys are stored the way the threat model says

**Claim.** Every Keychain item is device-only and never synced, except four that sync by a stated rule ([`architecture.md`](architecture.md)).

```sh
python3 scripts/keychain-audit.py
```

Expect: `✓ keychain audit: every keychain write is device-only and non-syncing, or syncs by a stated rule into the shared group`. The exemptions and the reason for each are at the top of that script.

## 3. The bundled JavaScript is the published SDKs and nothing else

**Claim.** `Resources/privacy-engine.js` and `Resources/railgun-engine.js` are built from the pinned packages in `tools/`, byte for byte.

```sh
cd tools/privacy-pools-engine && npm ci && node build.mjs --check
```

Expect: `privacy-engine.js reproduces: <sha256>`.

```sh
cd tools/railgun-engine && npm ci && node build.mjs --check
```

Expect: `railgun-engine.js and its wasm reproduce: <sha256>`.

Each rebuilds in memory and fails if the committed file differs. CI runs both on every change to them (`.github/workflows/engine-reproducibility.yml`).

## 4. The Tor binary is the upstream release

**Claim.** `Vendor/TorKit/tor.xcframework.zip` is `iCepa/Tor.framework` v409.14.1, repackaged.

```sh
scripts/tor-repackage.sh
```

It downloads the release, refuses it unless its SHA-256 matches the pin in the script, and rebuilds the zip. See [`Vendor/README.md`](../Vendor/README.md) for how to compare the result.

## 5. What you are shown is what gets signed

**Claim.** A Safe transaction's hash, the typed data, the WebAuthn signature and the words a call is described in are computed correctly, and each refusal holds.

```sh
scripts/safe-signer-selftest.sh
```

Expect: `✓ safe-signer self-test: fixtures pinned, refusals proven, every mutation caught`. EIP-712 is pinned to the specification's own vector.

```sh
scripts/clearsign-selftest.sh
```

Expect: `✓ clear signing: the registry's own vectors read as its maintainers expect, and every refusal holds`. The call descriptions come from the Ethereum Foundation's ERC-7730 registry, bundled with the app, and are run against that registry's own test vectors.

Each of these also breaks the code on purpose, one rule at a time, and fails unless the break is caught.

## 6. No credential is committed

**Claim.** No signing key, user credential or developer key is in the tree. Two shared read-only data keys are, on purpose ([`architecture.md`](architecture.md)).

```sh
python3 scripts/secret-scan-selftest.py
```

Expect: `✓ secret-scan self-test passed`. This is the app's own detector for credentials in what you save, proven against known key shapes. GitHub secret scanning with push protection is also on for this repository.

## 7. A shipped build matches a commit

**Claim.** From build 983 on, each build is recorded in [`builds.md`](builds.md) with the commit it was archived from, and a build from a clean tree is tagged `build-<n>`.

```sh
scripts/build-record.sh --self-test
```

Expect: `✓ build-record self-test passed`. Earlier builds cannot be tied to a commit, and `builds.md` says so.

## Everything at once

```sh
scripts/verify.sh
```

Builds the app for iPhone and Mac, runs every audit and self-test, and sweeps the screens in the simulator. It takes a while; `docs/verify.md` says what each step checks.

## What none of this proves

- That the code is free of bugs. There has been no outside audit.
- That the binary on the App Store is this source. Apple re-signs and encrypts what it distributes; `builds.md` records what was uploaded, not what you downloaded.
- That the third-party services behave. Bundlers, relayers, broadcasters and data providers can withhold or delay. None of them holds a key.
