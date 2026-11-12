# Glossary

The words the code, comments and docs use. These are working names; the app's own screens do not always say them.

## What the app holds

| Word | Meaning |
| --- | --- |
| **Thing** | One item the app keeps: a link, screenshot, note, mail, event, chat, transaction and so on. The `Thing` model in `Casberi/Shared/Thing.swift`; its type is a `ThingKind`. |
| **Fact** | A typed detail attached to a thing, such as a fee, a reminder or an attachment. |
| **Corpus** | Every thing on the device, in one SwiftData store. |
| **Demo** | A built-in sample corpus, for trying the app with no accounts connected. "Pouring" the demo is loading it. |

## Where things come from

| Word | Meaning |
| --- | --- |
| **Bridge** | The code that reads one outside service and lands its items as things, for example `StripeBridge`. Read-only unless stated. |
| **Catalog** | The list of every app that can be connected: `BridgeCatalog.offers`. The website's list is checked against it. |
| **Offer** | One entry in the catalog. Its name is the key used everywhere. |
| **Seat** | A connected app: an offer once it has an account behind it. Has an id and a category. |
| **Rider** | A source with no connection of its own, which reads through another seat's. Strava reads through Health; several protocols read through watched wallets. |
| **Category** | One of seven groups the catalog sorts apps into. |
| **Sweep** | One pass of a bridge reading its service. |
| **Heal** | A pass that repairs or refreshes rows already stored. |
| **Engine** | A third-party JavaScript SDK run in a hidden web view with no direct network access: Aztec, Privacy Pools, Railgun. |

## What is on screen

| Word | Meaning |
| --- | --- |
| **Feed** | The main scroll: today's things in sections by category. |
| **Room** | The screen for one app or one category. A code word; the app's own copy does not use it. |
| **Lead**, **head** | The box at the top of a room. |
| **Lede** | A room's newest thing, drawn as its lead when the room has no chart. |
| **Tile** | A square control under the lead that picks what the room shows. Four at most. |
| **Door** | A row that takes you somewhere else. |
| **Tray** | A sheet that rises from the bottom (`DSTray`). |
| **Verb** | An action offered on a thing or a row. |
| **Face** | A person's or account's picture. |
| **Tab bar**, **rail** | The bottom bar on the phone (Feed, Wallet, Apps, and Move) and its equivalent down the side on the Mac. Older comments call an earlier version "the dock". |
| **Crown** | The Wallet's total at the top of its page. |

## The wallet

| Word | Meaning |
| --- | --- |
| **Your account** | The self-custody account the app creates: a Safe whose keys live in the Secure Enclave. |
| **Move** | The screen where money is sent, swapped, bought or received. Each action is written as a sentence. |
| **Co-signer**, **Signer** | An optional second key held in another wallet. When on, a send needs both. |
| **Recovery key** | The key in iCloud Keychain that can move the account to a new device. |
| **Private balance** | Money held through Privacy Pools, Railgun or Aztec. |

## How the project is run

| Word | Meaning |
| --- | --- |
| **Ruling**, **§N** | A numbered product or design decision in `docs/prd.md`. Code cites it as `prd §N`. |
| **Ledger** | `docs/prd.md`, the append-only record of rulings. Also `NetworkLedger`, the runtime record of hosts contacted. |
| **Law** | `docs/law.md`, the rulings currently in force. |
| **Reach** | The hosts the app is declared to contact (`NetworkReach`). |
| **Receipt** | One recorded contact with a host. |
| **Audit** | A static check over the source tree (`scripts/*-audit.*`). |
| **Self-test**, **harness** | A script that compiles part of the app against stubs and tests it (`scripts/*-selftest.*`). |
| **Mutation** | A deliberate break a self-test applies to prove it would notice. |
| **Hook**, **probe** | A DEBUG launch argument that runs one path without the UI and logs the result. Indexed in `docs/hooks/index.md`. |
| **UNMEASURED** | Written at the top of code that has not been exercised against the live service. |
