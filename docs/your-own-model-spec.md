# Your own model — spec

A new agent seat, **Your own model**: the person's own OpenAI-compatible server (Ollama, LM Studio, llama.cpp, vLLM, Open WebUI's API) as an agent in the composer, the same way Claude, ChatGPT and OpenRouter are.

Asked for by a user (2026-10-23): "does casberi work with custom OpenAI-compatible endpoint option under agents? Just a base URL, an optional API key, and a model name. I run my own model at home." His server runs NixOS. Today the answer is no: `AgentProvider` (`Model/AgentAnswer.swift`) is a closed list of nine providers with base URLs written in code, and OpenRouter reaches only its own catalogue.

Out of scope here: reading the chats he had with his model outside Casberi. That depends on which chat app he uses (Open WebUI has a live API; LM Studio keeps JSON files; `ollama run` keeps nothing) and is a separate spec once he answers.

## What the person sees

**The catalogue.** "Your own model" in the Agent group, tagline "A model you run, at an address you give". Generic glyph, no brand mark.

**The account page** (`AccountPage`, like `OpenRouterSetupScreen`/`NearAISetupScreen`). One entry well with three fields:

1. **Address** — required. Placeholder on the Mac `localhost:11434`; on the phone `192.168.1.20:11434`.
2. **Key** — optional. Placeholder "Only if your server asks for one".
3. **Model** — filled from the server's own list once the address answers; typed by hand when the server has no list.

Connect checks the address (below) and saves. On success the seat becomes the active agent (`AgentKey.activate`).

**Under an http address**, one line through `DSFootnote`: "Not encrypted. Anyone on your Wi-Fi could read what's sent."

**The capability line** (`AgentProvider.capabilityLine`): "Answers on your own server. Remembers this chat's answers so far — screenshots and web search stay off."

**Privacy line** wherever the other agents say where a question goes: "Goes to the address you gave. Casberi can't see what that server keeps." Never "stays on your device": the server is somebody's computer, and the honesty rule (prd §83) forbids the claim.

## The address rule

Parse what is typed, in this order:

- No scheme: `http` if the host is local (below), else `https`.
- No path: append `/v1` (Ollama, LM Studio and llama.cpp all serve the OpenAI shape under `/v1`). A path the person typed is kept as typed.
- A missing port means the scheme's default. Never guess 11434.
- Refuse `user:pass@` in the URL (a credential belongs in the Key field, in the Keychain).
- Refuse anything but `http` and `https`.

**http is allowed only for a local host:** `localhost`, `127.0.0.1`, `::1`, a `.local` name, a name with no dot (`nixbox`), and the private ranges `10/8`, `172.16/12`, `192.168/16`, `169.254/16`, and Tailscale's `100.64/10`. Anything else over http is refused at the field with "Use https for an address outside your home network." Apple's ATS would block it anyway; refusing at the field says why before a question fails.

`NSAllowsLocalNetworking` is already on (`Casberi/Casberi/Info.plist:55`). **Measure** that it lets http through to a private IP and to a dotless name on iOS 26/27 and on the Mac before relying on it. Do not add `NSAllowsArbitraryLoads`.

Reuse what `LogosWire.entry` / `LogosWire.nodeBase` (`Model/LogosWire.swift:865`, `:897`) already do for the Logos node's typed address where it fits; do not write a second host parser if that one can be shared.

## The check (connect)

`GET {base}/models` with `Authorization: Bearer <key>` when a key is set, none otherwise. Timeout 15s.

- 200 with an OpenAI-shaped `data: [{id}]` list → connected; the list fills the Model picker (`AgentModels`, a new branch beside `Model/AgentModels.swift:141`).
- 404 → the server has no list; connected if the person typed a model. Ollama, LM Studio, llama.cpp and vLLM all serve `/v1/models`; measure each one you can run.
- 401/403 → "That server wants a key" or "That key was refused".
- Unreachable/timeout → "Couldn't reach <host>. Is it on, and are you on its network?"

## Storing it

- `case ownModel` on `AgentProvider`, raw value `ownmodel`; `agent` and `company` both "Your own model".
- Key in the Keychain under `vaultKey` (`token.ownmodel-key`), as today. Optional.
- Address and model in `UserDefaults` through `Model/DefaultsWrite.swift` (`defaults-lock-audit.py`). The model choice rides the existing `AgentModelStore`.
- **"Configured" means an address is saved**, not a key. `AgentKey.configured`, `isConfigured`, `active` and `clear` read the address for this seat. Today they all read Keychain presence — this is the one structural change.
- `AgentKey.clear(.ownModel)` removes address, key, model choice, and the tool memory below.
- `defaultModel`: none. A request with no chosen model does not go out; the page asks for one.

## The request

Rides the OpenAI-compatible branch (`AgentAnswer.swift:1430`): `POST {base}/chat/completions`, `stream: true`, SSE, `max_tokens: 1024`.

- No `Authorization` header when no key is set. `makeRequest` currently returns nil (→ `.noKey`) without a key; this seat must not.
- Never send `stream_options` or any OpenRouter-only body key.
- Answer timeout 180s for this seat (the branch uses 90s at `:1136`): a local model loads into memory before its first word, and that can take a minute.
- `seesImages`, `searchesWeb`, `fetchesLinks`: false.
- No spend row and no budget ceiling (`AgentSpend`, `AgentBudget`): there is no bill.
- Redaction (prd §277) applies unchanged: `AgentAnswer.synthesize` and `AgentCorpusTools` already scrub before anything leaves.

### Corpus tools

The four corpus tools (`Model/AgentCorpusTools.swift`: `search_things`, `recent_things`, `linked_things`, `list_sources`, up to `maxRounds = 3`) are offered.

Some local models reject a request that carries `tools`. **Measure the refusal shape on Ollama first** (expected: HTTP 400 whose body names tools, for a model without tool support). On that refusal:

1. Send the same round again with `declareTools: false`.
2. Remember the model as tool-less (`UserDefaults`, keyed by address + model id) so later questions skip the failed round.
3. Forget it when the model or the address changes, and in `AgentKey.clear`.

A model that accepts tools and misuses them is held by the existing 3-round cap.

## Wiring the seat in

The compiler finds most of these (exhaustive switches over `AgentProvider`), but not all:

- `AgentProvider` switches in `AgentAnswer.swift` (agent, company, console, placeholder, defaultModel, capabilities, check, request base).
- `AgentModels.swift` — list read and `usable` filter.
- `BridgeStore.keyedSeats` (`Model/BridgeStore.swift:506`) — the seat list keys on `vaultKey` presence; this seat has no key necessarily. Make the seat register on a saved address.
- `AgentConversationLanding.swift` — conversations land as `.chat` things (prd §839); add whatever registry entries the other agents have.
- `BridgeCatalog.offers` (`Model/BridgeCatalog.swift:436` area), `BridgeRouting` row (`Model/BridgeRouting.swift:451` area), a `OwnModelSetupScreen` on `AccountPage`.
- `DemoSeedAll.swift` cases (`:981`, `:1035`) — follow the compiler; the demo does not need a furnished own-model seat.
- `KeyShape.swift` — an absent key is not a wrong key.

## Network disclosure

- `NetworkReach.swift`: a new `Endpoint(service: "Your own model", …)` beside "Your agent key" (`:893`), with no fixed hosts and a purpose line: "Only when you ask, your question and the matched things go to the address you gave."
- Every request through this seat calls `NetworkLedger.shared.record(host:as: "Your own model")` (`Model/NetworkLedger.swift:110`).
- `network-reach-audit.sh` must pass. `.whenConnected(bridge:)` takes the catalogue name, never the seat id (prd §1163).
- `NSLocalNetworkUsageDescription` (pbxproj `:708`, `:762`) names only the Logos node. Reword it to cover both, e.g. "Casberi reaches your own Logos node or your own model at the address you give it, when it is on your network." `infoplist-strings-audit.py` must pass.

## The Mac half (prd §1402)

Same seat, same page. The Mac placeholder is `localhost:11434` because Ollama on the same Mac is the simplest setup. The Catalyst build already holds `com.apple.security.network.client`. Measure the local-network permission prompt on macOS for a LAN IP.

## Website

Per the website rule: a hero marquee tile, a `#catalog` Agents shelf cell, an `.ai-ownmodel` background, a base64-inlined generic icon, `?v=` cache-busters bumped, `catalog-sync.sh` green. Deploy is the user's call.

## Verify

1. `scripts/verify.sh` green (both platforms).
2. End to end on the Mac with a real local server: `brew install ollama`, `ollama serve`, pull one tool-capable model (e.g. a Qwen or Llama 3.1+ tag) and one without tool support. Connect at `localhost:11434` in the simulator and the Mac build.
   - Tool-capable model: answer arrives, a tool round happens (log it).
   - Tool-less model: first round refused, retry answers, second question skips the tools.
   - Server stopped: the unreachable message.
   - A conversation lands as a `.chat` thing.
3. The http line shows for `http://`, not for `https://`. A public `http://` address is refused at the field.
4. `-receiptsProbe` shows the host under "Your own model".
5. A `-byokProbe`-style DEBUG hook for this seat if the existing ones cannot drive it headless (record it in CLAUDE.md's hook index).

## Record

A new prd ruling (next free § after §1477) stating the decisions above and what was measured vs assumed; run `python3 scripts/law-digest.py`. One index line in CLAUDE.md pointing at it.
