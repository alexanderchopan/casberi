#!/bin/zsh
# Casberi own-model self-test — the person's own OpenAI-compatible server as an
# agent seat (prd §1478):
#
#   Casberi/Casberi/Model/OwnModel.swift   (compiled whole, Foundation only)
#
# WHY A HARNESS. Every failure here looks like a working page. An address rule
# that lets `http://` through to a public host hands a question to the open
# internet in plain text (and Apple's ATS then fails it with no reason given);
# one that refuses `nixbox` or `100.64.0.1` turns a working home server away;
# a `/v1` appended to a typed path 404s every request; a check that reads a
# 404 as "connected" with no model sends nothing and says it works. And the
# tool-less memory must be keyed by address AND model, or one Ollama's refusal
# silences the tools on every server the person ever adds.
#
# The wiring half is grep: the answer path must read the memory, retry a
# refused round without tools, send no `Authorization` with no key, and
# attribute the host to the ledger by name — none of which a pure harness can
# run. Pure, local, deterministic. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

MODEL="Casberi/Casberi/Model/OwnModel.swift"
ANSWER="Casberi/Casberi/Model/AgentAnswer.swift"
MODELS="Casberi/Casberi/Model/AgentModels.swift"
SCREEN="Casberi/Casberi/Screens/OwnModelSetupScreen.swift"
SHELL_FILE="Casberi/Casberi/Shell/RootShell.swift"
VAULT="Casberi/Casberi/Model/TokenVault.swift"
for f in "$MODEL" "$ANSWER" "$MODELS" "$SCREEN" "$VAULT"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# --- Wiring (grep) ---------------------------------------------------------
grep -q 'OwnModel.isToolless(address: address, model: provider.model)' "$ANSWER" \
  || { echo "✗ the answer path no longer skips tools for a model that refused them"; exit 1; }
grep -q 'if provider == .ownModel, declareTools, case .toolsUnsupported = failure' "$ANSWER" \
  || { echo "✗ a refused tool round is no longer retried without tools"; exit 1; }
grep -q 'OwnModel.namesToolRefusal(body) ? .toolsUnsupported : .providerError(400)' "$ANSWER" \
  || { echo "✗ a 400 is read as a tool refusal without its body naming tools"; exit 1; }
# Your own model is ALWAYS asked (prd §1531, a tester: "asking it anything does
# nada"): nothing matched is an open ask under its own contract, never a
# request withheld — at the shell's gate, the loop's guard and the tool-less
# retry alike.
grep -q 'guard !hits.isEmpty || provider == .bankr || provider == .ownModel' "$SHELL_FILE" \
  || { echo "✗ the shell withholds your own model's question when nothing kept matched"; exit 1; }
grep -q 'let openAsk = provider == .ownModel && candidates.isEmpty' "$ANSWER" \
  || { echo "✗ an open ask is no longer your own model's alone"; exit 1; }
grep -q 'guard !candidates.isEmpty || toolsOn || openAsk else { return .failure(.empty) }' "$ANSWER" \
  || { echo "✗ a tool-less own model is not asked when nothing matched"; exit 1; }
grep -q 'system += openAsk ? openInstructions' "$ANSWER" \
  || { echo "✗ an open ask is sent the grounding contract over an empty list"; exit 1; }
grep -q 'let userText = history.isEmpty && !openAsk' "$ANSWER" \
  || { echo "✗ an open ask is sent an empty numbered list as its question"; exit 1; }
grep -q 'guard steps.isEmpty else { return .failure(.empty) }' "$ANSWER" \
  || { echo "✗ the tool-less retry no longer guards a spent tool round"; exit 1; }
# A reply that is only the marker is no prose: drawing the text back put
# "PICKS: 1, 2, 4, 5" on screen as the answer (prd §1531).
grep -q 'prose.isEmpty ? text' "$ANSWER" \
  && { echo "✗ a marker-only reply is drawn as its own answer again"; exit 1; }
grep -q 'It answered with these and no words.' "$ANSWER" \
  || { echo "✗ picks with no words have no line of their own"; exit 1; }
# Nothing kept is a FAILURE that names the agent, never a success the composer
# ticks as the agent's own answer (2026-10-24: "my logs show nothing").
grep -q 'return .failure(.nothingKept(agent: provider?.agent' "$SHELL_FILE" \
  || { echo "✗ an empty corpus no longer fails as nothingKept — the composer will tick an answer nobody was asked for"; exit 1; }
grep -q 'case .nothingKept(let agent):' "$ANSWER" \
  || { echo "✗ nothingKept has no sentence of its own"; exit 1; }
# An explicit ask is owed its failure (prd §1502, a tester: "nothing is hitting
# my local server"): read before the flag clears, and drawn, never the phone's
# answer under the phone's badge. Only a follow-up falls back.
COMPOSER_FILE="Casberi/Casberi/Shell/Composer.swift"
awk '/let stayKeyed = forceKeyedThisAsk/{on=1} on && /let askedExplicitly = forceKeyedThisAsk/{seen=1} on && /forceKeyedThisAsk = false/{ok=seen; exit} END{exit !ok}' "$COMPOSER_FILE" \
  || { echo "✗ the explicit ask is read after its flag clears — every ask reads as a follow-up and falls back"; exit 1; }
grep -q 'var owedItsLine = askedExplicitly' "$COMPOSER_FILE" \
  || { echo "✗ a failed explicit agent ask falls back to the phone's answer again"; exit 1; }
grep -q 'if case .nothingKept = failure { owedItsLine = true }' "$COMPOSER_FILE" \
  || { echo "✗ nothing kept no longer says so on a follow-up"; exit 1; }
grep -q 'system = systemPrompt(tools: false)' "$ANSWER" \
  || { echo "✗ the tool-less retry still tells the model to use tools"; exit 1; }
grep -q 'OwnModel.rememberToolless(address: address, model: wire.model)' "$ANSWER" \
  || { echo "✗ a refusal is no longer remembered"; exit 1; }
perl -0ne 'exit((/if !key\.isEmpty \{\s*request\.setValue\("Bearer \\\(key\)", forHTTPHeaderField: "Authorization"\)/) ? 0 : 1)' "$ANSWER" \
  || { echo "✗ an empty key no longer withholds the Authorization header"; exit 1; }
grep -q 'var answerTimeout: TimeInterval { self == .ownModel ? 180 : 90 }' "$ANSWER" \
  && grep -q 'request.timeoutInterval = provider.answerTimeout' "$ANSWER" \
  && grep -q 'request.timeoutInterval = max(60, provider.answerTimeout)' "$ANSWER" \
  || { echo "✗ the seat lost its 180s answer timeout (a local model loads before its first word)"; exit 1; }
grep -q 'NetworkLedger.shared.record(own, as: OwnModel.name)' "$ANSWER" \
  || { echo "✗ a request no longer names the seat to the ledger (its host is undeclarable)"; exit 1; }
grep -q 'if chosenModel.isEmpty, provider.keyOptional { return nil }' "$ANSWER" \
  || { echo "✗ a request with no model can go out"; exit 1; }
# A switch since §1619 (Muse, then every signed-in agent, counts a session);
# the rule is unchanged: Your own model is configured by its ADDRESS.
grep -q 'case .ownModel: OwnModel.address != nil' "$ANSWER" \
  || { echo "✗ configured is read off the key again, not the address"; exit 1; }
grep -q 'if provider == .ownModel { OwnModel.forget() }' "$ANSWER" \
  || { echo "✗ clearing the seat no longer forgets its address and tool memory"; exit 1; }
grep -q 'var billed: Bool { self != .ownModel }' "$ANSWER" \
  && [[ $(grep -c 'if provider.billed' "$ANSWER") -ge 2 ]] \
  || { echo "✗ the seat writes a spend row — there is no bill"; exit 1; }
grep -q '\$0 != .bankr && \$0 != .ownModel' "$VAULT" \
  || { echo "✗ the seat's key syncs through iCloud Keychain without its address"; exit 1; }
grep -q 'case .ownModel:' "$MODELS" \
  || { echo "✗ the models list has no branch for the seat"; exit 1; }
grep -q 'OwnModel.isPlainHTTP(url)' "$SCREEN" \
  || { echo "✗ the page no longer shows the http line"; exit 1; }
grep -q 'mode: .noAccount' "$SCREEN" \
  || { echo "✗ the page claims a key is pasted"; exit 1; }
grep -q 'keyed: hasKey' "$SCREEN" \
  || { echo "✗ the Your key row draws over no key"; exit 1; }
# The composer opens on an agent when one exists, so every send is an explicit
# ask and §1502's failure line covers it; the device key is gone (prd §1505).
COMPOSER="Casberi/Casberi/Shell/Composer.swift"
grep -q 'if chosenAgent == nil, let agent = AgentKey.active,' "$COMPOSER" \
  || { echo "✗ the composer no longer opens on the active agent"; exit 1; }
grep -q 'onDevice' "Casberi/Casberi/Shell/AgentTerminal.swift" \
  && { echo "✗ the device key is back in the composer's foot"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp "$MODEL" "$TMP/OwnModel.swift"
cat > "$TMP/stubs.swift" <<'SWIFT'
import Foundation
enum TokenVault {
    nonisolated(unsafe) static var generation = 0
    static func noteArrivals() { generation += 1 }
}
SWIFT
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { failures += 1; print("✗ \(what)") }
}
func base(_ raw: String) -> String? { OwnModel.parse(raw).url?.absoluteString }

// The address rule.
check(base("localhost:11434") == "http://localhost:11434/v1", "a bare local host:port takes http and /v1")
check(base("192.168.1.20:11434") == "http://192.168.1.20:11434/v1", "a private IP takes http")
check(base("nixbox:11434") == "http://nixbox:11434/v1", "a dotless name is local")
check(base("nixbox") == "http://nixbox/v1", "no port means the scheme's own, never 11434")
check(base("studio.local:1234/") == "http://studio.local:1234/v1", "a .local name is local; a trailing slash is dropped")
check(base("100.64.0.7:8000") == "http://100.64.0.7:8000/v1", "Tailscale's range is local")
check(base("172.20.1.1") == "http://172.20.1.1/v1", "172.16/12 is local")
check(base("172.32.1.1") == "https://172.32.1.1/v1", "172.32 is not in 172.16/12")
check(base("169.254.9.9") == "http://169.254.9.9/v1", "link-local is local")
check(base("models.example.org") == "https://models.example.org/v1", "a public name takes https")
check(base("https://models.example.org/openai/v1") == "https://models.example.org/openai/v1", "a typed path is kept as typed")
check(base("http://192.168.1.20:11434/v1") == "http://192.168.1.20:11434/v1", "a full http URL to a private host passes")
check(base("HTTPS://Models.Example.org") == "https://models.example.org/v1", "scheme and host are lowercased")
check(base("  localhost:11434  ") == "http://localhost:11434/v1", "whitespace is trimmed")
check(OwnModel.parse("http://models.example.org") == .publicHTTP, "http to a public host is refused")
check(OwnModel.parse("http://8.8.8.8:11434") == .publicHTTP, "http to a public IP is refused")
check(OwnModel.parse("http://user:pw@192.168.1.20:11434") == .credentialInURL, "a credential in the URL is refused")
check(OwnModel.parse("ftp://192.168.1.20") == .badScheme, "ftp is refused")
check(OwnModel.parse("") == .empty, "empty is empty")
check(OwnModel.parse("   ") == .empty, "blank is empty")
check(OwnModel.parse("not an address") == .invalid, "a sentence is invalid")
check(OwnModel.parse("host:port") == .invalid, "a non-numeric port is invalid")
check(OwnModel.parse("http://192.168.1.20:11434").refusal == nil, "a good address has no refusal")
check(OwnModel.parse("http://models.example.org").refusal == "Use https for an address outside your home network.", "the public-http refusal says why")
check(OwnModel.isLocal(host: "::1"), "::1 is local")
check(OwnModel.isLocal(host: "[::1]"), "a bracketed ::1 is local")
check(OwnModel.isLocal(host: "127.0.0.1"), "loopback is local")
check(OwnModel.isLocal(host: "10.0.0.5"), "10/8 is local")
check(!OwnModel.isLocal(host: "11.0.0.5"), "11/8 is not")
check(!OwnModel.isLocal(host: "api.openai.com"), "a public name is not local")
check(OwnModel.isLocal(host: "fe80::1"), "an IPv6 link-local literal is local")
check(!OwnModel.isLocal(host: "2606:4700::1"), "a public IPv6 literal is not local")

// The host line and the http test.
let lan = OwnModel.parse("192.168.1.20:11434").url!
check(OwnModel.hostLine(lan) == "192.168.1.20:11434", "the host line keeps a non-default port")
check(OwnModel.hostLine(OwnModel.parse("models.example.org").url!) == "models.example.org", "the host line drops a default port")
check(OwnModel.isPlainHTTP(lan), "a local address is plain http")
check(!OwnModel.isPlainHTTP(OwnModel.parse("models.example.org").url!), "a public address is not")

// The check's status codes (MEASURED on Ollama 0.40.9, 2026-10-23).
let list = Data(#"{"object":"list","data":[{"id":"gemma3:1b","object":"model"},{"id":"qwen2.5:1.5b"}]}"#.utf8)
check(OwnModel.check(status: 200, data: list, hasKey: false, typedModel: "") == .connected(models: ["gemma3:1b", "qwen2.5:1.5b"]), "200 with the envelope connects and lists")
check(OwnModel.check(status: 200, data: Data("<!DOCTYPE html><html>".utf8), hasKey: false, typedModel: "") == .webPage, "a 200 that is a web page says so (the field's Tailscale case)")
check(OwnModel.check(status: 200, data: Data("\n  <html>".utf8), hasKey: false, typedModel: "") == .webPage, "a page behind leading whitespace is still a page")
check(OwnModel.check(status: 200, data: Data(#"{"models":[]}"#.utf8), hasKey: false, typedModel: "") == .other(200), "a 200 that is JSON but not the envelope is not a server")
check(OwnModel.Check.webPage.line == "That address serves a web page, not the API. Ollama answers on its own port (host:11434); Open WebUI's API is under /api.", "the web-page line names where the API lives")
check(OwnModel.Check.other(200).line == "That server answered, but not with a model list. Is the address the API's base, like host:11434/v1?", "the 200 line asks for the API's base")
check(OwnModel.Check.other(502).line == "That server answered HTTP 502. Is it an OpenAI-compatible server?", "another code is reported as itself")
check(!OwnModel.looksLikeHTML(nil), "no body is no page")
check(OwnModel.check(status: 404, data: nil, hasKey: false, typedModel: "") == .needsModel, "404 with no model typed needs a model")
check(OwnModel.check(status: 404, data: nil, hasKey: false, typedModel: "llama3.1") == .connected(models: []), "404 with a typed model connects, listless")
check(OwnModel.check(status: 401, data: nil, hasKey: false, typedModel: "") == .wantsKey, "401 with no key wants one")
check(OwnModel.check(status: 401, data: nil, hasKey: true, typedModel: "") == .keyRefused, "401 with a key refused it")
check(OwnModel.check(status: 403, data: nil, hasKey: true, typedModel: "") == .keyRefused, "403 with a key refused it")
check(OwnModel.check(status: nil, data: nil, hasKey: false, typedModel: "") == .unreachable, "nothing back is unreachable")
check(OwnModel.check(status: 500, data: nil, hasKey: false, typedModel: "") == .other(500), "a 500 is reported as itself")
check(OwnModel.Check.unreachableLine(host: "nixbox:11434") == "Couldn't reach nixbox:11434. Is it on, and are you on its network?", "the unreachable line names the host")
check(OwnModel.Check.wantsKey.line == "That server wants a key.", "the wants-key line")
check(OwnModel.Check.keyRefused.line == "That key was refused.", "the key-refused line")
check(OwnModel.Check.connected(models: []).line == nil, "connected has no line")
check(OwnModel.check(status: 200, data: Data(#"{"data":[]}"#.utf8), hasKey: false, typedModel: "") == .noModels, "an empty list with nothing typed has no models yet")
check(OwnModel.check(status: 200, data: Data(#"{"data":[]}"#.utf8), hasKey: false, typedModel: "llama3.1") == .connected(models: []), "an empty list with a typed model connects")
check(OwnModel.Check.noModels.line == "That server has no models yet. Pull one, or type its name.", "the no-models line says what to do")
check(OwnModel.modelIDs(Data(#"{"data":"nope"}"#.utf8)) == nil, "a data field that is not a list is no envelope")

// The tool refusal is read off the 400's BODY (MEASURED on Ollama 0.40.9).
let ollama = Data(#"{"error":{"message":"registry.ollama.ai/library/gemma3:1b does not support tools","type":"invalid_request_error"}}"#.utf8)
check(OwnModel.namesToolRefusal(ollama), "Ollama's measured refusal is a tool refusal")
check(OwnModel.namesToolRefusal(Data("Tools are not supported for this model".utf8)), "llama.cpp's wording is too")
check(!OwnModel.namesToolRefusal(Data(#"{"error":{"message":"prompt is too long for the context window"}}"#.utf8)), "a context-length 400 is not")
check(!OwnModel.namesToolRefusal(Data()), "an empty body is not")

// The tool-less memory, keyed by address and model, in an isolated defaults.
UserDefaults.standard.removeObject(forKey: OwnModel.toollessKey)
UserDefaults.standard.removeObject(forKey: OwnModel.addressKey)
check(!OwnModel.isToolless(address: "nixbox:11434", model: "gemma3:1b"), "nothing remembered at first")
OwnModel.rememberToolless(address: "nixbox:11434", model: "gemma3:1b")
check(OwnModel.isToolless(address: "nixbox:11434", model: "gemma3:1b"), "a refusal is remembered")
check(OwnModel.isToolless(address: "NIXBOX:11434 ", model: "gemma3:1b"), "the address key ignores case and whitespace")
check(!OwnModel.isToolless(address: "nixbox:11434", model: "qwen2.5:1.5b"), "another model at the same address is not")
check(!OwnModel.isToolless(address: "studio.local:1234", model: "gemma3:1b"), "the same model at another address is not")
OwnModel.forgetToolless()
check(!OwnModel.isToolless(address: "nixbox:11434", model: "gemma3:1b"), "forgetting forgets")

// Configured is an address; forgetting removes it and bumps the generation.
let before = TokenVault.generation
check(OwnModel.address == nil, "no address at first")
OwnModel.setAddress("  nixbox:11434 ")
check(OwnModel.address == "nixbox:11434", "the address is saved trimmed")
check(OwnModel.base?.absoluteString == "http://nixbox:11434/v1", "the saved address parses to its base")
check(TokenVault.generation > before, "saving bumps the vault generation so the configured memo re-reads")
OwnModel.rememberToolless(address: "nixbox:11434", model: "x")
OwnModel.forget()
check(OwnModel.address == nil && OwnModel.base == nil, "forgetting removes the address")
check(!OwnModel.isToolless(address: "nixbox:11434", model: "x"), "forgetting removes the tool memory")
UserDefaults.standard.removeObject(forKey: OwnModel.toollessKey)
UserDefaults.standard.removeObject(forKey: OwnModel.addressKey)

// The words never claim the device.
for line in [OwnModel.capabilityLine, OwnModel.privacyLine, OwnModel.httpLine] {
    check(!line.lowercased().contains("your device") && !line.lowercased().contains("on-device"),
          "no line claims the server is this device: \(line)")
}
check(OwnModel.placeholder(isMac: true) == "localhost:11434", "the Mac's placeholder is the same Mac")
check(OwnModel.placeholder(isMac: false).hasPrefix("192.168."), "the phone's placeholder is a LAN box")

if failures > 0 { print("✗ own-model self-test: \(failures) failed"); exit(1) }
print("✓ own-model self-test passed")
SWIFT
xcrun swiftc -O "$TMP"/*.swift -o "$TMP/run" 2>&1 | grep -v "^$" || true
[[ -x "$TMP/run" ]] || { echo "✗ own-model harness did not compile"; exit 1; }
"$TMP/run"

# --- Mutations: each must make the harness FAIL ---------------------------
# A mutation that leaves the file unchanged did not run (prd §627).
mutate() {
  local name="$1" expr="$2"
  cp "$MODEL" "$TMP/OwnModel.swift"
  perl -0pi -e "$expr" "$TMP/OwnModel.swift"
  if cmp -s "$MODEL" "$TMP/OwnModel.swift"; then
    echo "✗ mutation '$name' changed nothing — its anchor drifted"; exit 1
  fi
  if xcrun swiftc -O "$TMP"/*.swift -o "$TMP/mrun" 2>/dev/null && "$TMP/mrun" >/dev/null 2>&1; then
    echo "✗ mutation '$name' SURVIVED — the harness does not hold it"; exit 1
  fi
  echo "  ✓ mutation caught: $name"
}
mutate "public http allowed" 's/if out\.scheme\?\.lowercased\(\) == "http", !local \{ return \.publicHTTP \}/if false { return .publicHTTP }/'
mutate "dotless name not local" 's/return !host\.contains\("\."\)/return false/'
mutate "Tailscale range dropped" 's/if a == 100, \(64\.\.\.127\)\.contains\(b\) \{ return true \}//'
mutate "/v1 appended over a typed path" 's/if out\.path\.isEmpty \|\| out\.path == "\/" \{ out\.path = "\/v1" \}/out.path = "\/v1"/'
mutate "404 connects with no model" 's/\? \.needsModel : \.connected\(models: \[\]\)/? .connected(models: []) : .connected(models: [])/'
mutate "401 ignores the key" 's/case 401: return hasKey \? \.keyRefused : \.wantsKey/case 401: return .wantsKey/'
mutate "tool memory keyed by model alone" 's/"\\\(address\.trimmingCharacters\(in: \.whitespacesAndNewlines\)\.lowercased\(\)\)\|\\\(model\)"/"\\(model)"/'
mutate "refusal without reading the body" 's/return text\.contains\("tool"\) && text\.contains\("support"\)/return true/'
mutate "empty list says choose" 's/if ids\.isEmpty, typedModel/if false, typedModel/'
mutate "forget keeps the tool memory" 's/UserDefaults\.standard\.removeObject\(forKey: toollessKey\)\n        TokenVault\.noteArrivals\(\)/TokenVault.noteArrivals()/'
mutate "a web page read as some other 200" 's/return looksLikeHTML\(data\) \? \.webPage : \.other\(200\)/return .other(200)/'
echo "✓ own-model self-test: 11 mutations caught"
