#!/bin/zsh
# tor-health-selftest.sh — Tor watched after it connects (prd §1546).
#
# On the phone, Move's and Security's reads failed for minutes while the Tor
# row read "On": the watch stopped at 100% bootstrap, nothing happened when the
# app came back from the background, and a tor that exited left every request
# pointed at a dead port until the app was relaunched. `TorHealth` is the pure
# half — what tor's answers mean, what the Wallet is told, when circuits are
# renewed or tor's connections reset, how many runs a process gets — so this
# compiles it alone and drives it. It also asserts the USE in `TorClient`: the
# watch keeps asking after the connect, a return resets, a changed network
# resets, a run that ends clears the port and lets `start` run again — or the
# rule is a type nothing calls. Seven mutations prove the assertions bite, each
# checked to have CHANGED the source.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="Casberi/Casberi/Model/TorHealth.swift"
CLIENT="Casberi/Casberi/Model/TorClient.swift"
ROWS="Casberi/Casberi/Screens/TorRows.swift"
for f in "$SRC" "$CLIENT" "$ROWS"; do
    [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done
echo "tor-health self-test"

use() { grep -qF -- "$2" "$1" || { echo "✗ $3"; exit 1; } }
# Only inside one function of the client: the use has to be where it does its job.
in_fn() {
    awk -v start="$2" 'index($0, start) { on = 1 } on { print } on && /^    }$/ { exit }' "$1" | grep -qF -- "$3" \
        || { echo "✗ $4"; exit 1; }
}
# 1. The watch keeps asking after the connect, and publishes what tor says.
in_fn "$CLIENT" 'private func watch(fd: Int32, run: Int)' 'while isCurrent(run) {' "the watch stops once tor has connected"
in_fn "$CLIENT" 'private func watch(fd: Int32, run: Int)' 'command(fd, TorHealth.healthQuery)' "the watch no longer asks tor for its circuits"
in_fn "$CLIENT" 'private func watch(fd: Int32, run: Int)' 'health.note(TorHealth.reading(in: reply), at: Date())' "the watch no longer reads tor's answer through TorHealth"
in_fn "$CLIENT" 'private func watch(fd: Int32, run: Int)' 'publish(state, run: run)' "the watch no longer publishes what tor says"
in_fn "$CLIENT" 'private func watch(fd: Int32, run: Int)' 'if noted.act == .resetNetwork { resetNetwork(' "a circuit lost past resetAfter no longer resets tor's connections"
use "$SRC" 'static let healthQuery = "GETINFO status/circuit-established network-liveness"' "the health question changed"
# 2. Back from the background, and another network.
use "$CLIENT" 'forName: UIApplication.willEnterForegroundNotification' "nothing happens when the app comes back"
use "$CLIENT" 'forName: UIApplication.didEnterBackgroundNotification' "the client no longer knows how long the app was away"
in_fn "$CLIENT" 'private func cameBack()' 'TorHealth.onForeground(away: away) == .renew' "a return no longer asks TorHealth whether to renew"
in_fn "$CLIENT" 'private func cameBack()' 'dropSessions()' "a return keeps the sessions, whose kept-alive streams ride old circuits"
# NEWNYM keeps the guard connection a suspension outlives the NAT of (prd §1597).
in_fn "$CLIENT" 'private func cameBack()' 'self?.resetNetwork(why: "back after' "a return no longer resets tor's connections"
if awk '/private func cameBack\(\)/,/^    }$/' "$CLIENT" | grep -q 'NEWNYM'; then
    echo "✗ a return asks only for new circuits, over the guard connection it may have lost"; exit 1
fi
in_fn "$CLIENT" 'private func network(_ signature: String?)' 'path.moved(to: signature)' "a changed network no longer reaches the rule"
in_fn "$CLIENT" 'private func network(_ signature: String?)' 'resetNetwork(why:' "a changed network no longer resets tor's connections"
in_fn "$CLIENT" 'private func resetNetwork(why: String)' '"SETCONF DisableNetwork=1"' "a reset no longer closes tor's connections"
in_fn "$CLIENT" 'private func resetNetwork(why: String)' '"GETINFO net/listeners/socks"' "a reset no longer reads the SOCKS port it reopened on"
in_fn "$CLIENT" 'private func resetNetwork(why: String)' 'socksPort = nil' "requests may reach the closed port during a reset"
in_fn "$CLIENT" 'private func resetNetwork(why: String)' 'let fd = started && connected ? control : -1' "a reset may start a bootstrap over"
# 3. A run that ends.
in_fn "$CLIENT" 'func start()' 'guard !started, TorHealth.mayStart(runs: runs)' "start no longer runs tor again, or runs it without a limit"
in_fn "$CLIENT" 'func start()' 'self?.ended(run: run)' "a run that exits is not reported"
in_fn "$CLIENT" 'private func ended(run: Int)' 'started = false' "a run that exited leaves start unable to run tor again"
in_fn "$CLIENT" 'private func ended(run: Int)' 'socksPort = nil' "a run that exited leaves requests pointed at its dead port"
in_fn "$CLIENT" 'private func ended(run: Int)' 'Self.retire(dropped)' "a run that exited keeps its sessions"
in_fn "$CLIENT" 'private static func retire(_ dropped: [URLSession])' 'asyncAfter(deadline: .now() + requestTimeout * 2)' "a dropped session is invalidated while a caller may still hold it"
# A task made on an invalidated session raises: `session` hands sessions out.
if grep -n 'invalidateAndCancel' "$CLIENT" >/dev/null; then
    echo "✗ a session is invalidated at once, under a caller that may be about to use it"; exit 1
fi
in_fn "$CLIENT" 'func session(isolation key: String) async' 'guard running() else { return nil }' "a process out of runs makes every request wait 45s for nothing"
in_fn "$CLIENT" 'private func command(_ fd: Int32, _ line: String)' 'let open = fd >= 0 && control == fd' "a command may reach a closed control socket"
in_fn "$CLIENT" 'private func command(_ fd: Int32, _ line: String)' 'if n < 0, errno == EINTR { continue }' "a signal mid-command stops tor"
in_fn "$CLIENT" 'nonisolated static func publish(_ state: State)' 'guard n > shared.applied else { return }' "an older state may land over a newer one"
use "$CLIENT" 'SO_NOSIGPIPE' "a write after tor exits raises SIGPIPE and kills the app"
# Never around Tor (prd §1495 item 5): no recovery here reads a wallet directly.
if grep -nE 'URLSession\.shared|allowFailover = true' "$CLIENT" >/dev/null; then
    echo "✗ TorClient reaches a direct session"; exit 1
fi
# The row's word follows the state: a lost circuit is "Connecting", never "On".
use "$ROWS" 'case .connecting: String(localized: "Connecting")' "the Tor row no longer says Connecting"
echo "  ok   the watch keeps asking, a return resets, a new network resets, an ended run runs again"

TMP=$(mktemp -d /tmp/tor-health-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}

// Replies measured from tor 0.4.9.11's control port, 2026-10-26.
let measured = "250-status/circuit-established=0\r\n250-network-liveness=up\r\n250 OK\r\n"
check(TorHealth.reading(in: measured) == TorHealth.Reading(circuits: false, networkUp: true), "the measured reply reads")
let live = "250-status/circuit-established=1\r\n250-network-liveness=up\r\n250 OK\r\n"
let down = "250-status/circuit-established=1\r\n250-network-liveness=down\r\n250 OK\r\n"
let noCircuit = "250-status/circuit-established=0\r\n250-network-liveness=down\r\n250 OK\r\n"
check(TorHealth.reading(in: live)?.live == true, "a circuit and the network up is live")
check(TorHealth.reading(in: down)?.live == false, "a circuit with the network down is not live")
check(TorHealth.reading(in: measured)?.live == false, "no circuit is not live")
check(TorHealth.reading(in: "552 Unrecognized key \"network-liveness\"\r\n") == nil, "an unrecognized key reads as nothing")
check(TorHealth.reading(in: "250-status/circuit-established=1\r\n") == nil, "a half reply reads as nothing")
check(TorHealth.reading(in: "250-status/circuit-established=yes\r\n250-network-liveness=up\r\n250 OK\r\n") == nil,
      "a value tor never gives reads as nothing")
check(TorHealth.reading(in: "250-network-liveness=up\r\n250 status/circuit-established=1\r\n") != nil,
      "keys read in either order and on the final line")

// One run, watched.
let t0 = Date(timeIntervalSince1970: 1_800_000_000)
func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }
let liveR = TorHealth.reading(in: live)!, lostR = TorHealth.reading(in: noCircuit)!
var w = TorHealth.Watch(connectedIn: 9.5)
func gives(_ n: (state: TorState, act: TorHealth.Watch.Act)?,
           _ state: TorState, _ act: TorHealth.Watch.Act) -> Bool {
    n?.state == state && n?.act == act
}
check(w.note(nil, at: at(0)) == nil, "an answer that could not be read changes nothing")
check(gives(w.note(liveR, at: at(0)), .ready(seconds: 9.5), .none), "live is ready, with the connect's time")
check(gives(w.note(lostR, at: at(5)), .connecting(100), .none), "a lost circuit says Connecting at once, never On")
check(gives(w.note(lostR, at: at(20)), .connecting(100), .none), "under resetAfter, no reset")
check(gives(w.note(lostR, at: at(25)), .connecting(100), .resetNetwork), "lost for resetAfter resets tor's connections")
check(gives(w.note(lostR, at: at(30)), .connecting(100), .none), "no second reset straight after the first")
check(gives(w.note(lostR, at: at(50)), .failed, .none), "lost for connectWait says Can't connect")
check(gives(w.note(lostR, at: at(140)), .failed, .none), "under resetEvery since the last reset, no reset")
check(gives(w.note(lostR, at: at(145)), .failed, .resetNetwork), "a spell that lasts resets again every resetEvery")
check(gives(w.note(lostR, at: at(150)), .failed, .none), "one reset each resetEvery")
check(w.note(nil, at: at(55)) == nil, "an unread answer keeps the state")
check(gives(w.note(liveR, at: at(60)), .ready(seconds: 9.5), .none), "a circuit again is On again")
check(w.lostSince == nil, "a recovery ends the spell")
check(gives(w.note(lostR, at: at(600)), .connecting(100), .none), "a new spell starts from Connecting")
check(gives(w.note(lostR, at: at(620)), .connecting(100), .resetNetwork), "a new spell may reset again")
check(TorHealth.connectWait == 45, "a request still waits 45s for Tor (prd §1495)")

// Back from the background.
check(TorHealth.onForeground(away: nil) == .none, "a foreground with no background before it renews nothing")
check(TorHealth.onForeground(away: 5) == .none, "a glance at another app renews nothing")
check(TorHealth.onForeground(away: TorHealth.awayBeforeRenew) == .renew, "away for awayBeforeRenew renews")
check(TorHealth.onForeground(away: 3_600) == .renew, "away an hour renews")

// Another network.
var p = TorHealth.PathWatch()
check(!p.moved(to: "en0 192.168.1.1:0"), "the first path is the baseline")
check(!p.moved(to: "en0 192.168.1.1:0"), "the same path is no move")
check(p.moved(to: "pdp_ip0"), "Wi-Fi to cellular is a move")
check(!p.moved(to: nil), "going offline resets nothing")
check(p.moved(to: "pdp_ip0"), "back online is a move: tor's connections died while offline")
check(p.moved(to: "en0 10.0.0.1:0"), "another Wi-Fi is a move")

// Runs in one process.
check(TorHealth.mayStart(runs: 0), "the first run starts")
check(TorHealth.mayStart(runs: TorHealth.maxRuns - 1), "a run that ended may be followed")
check(!TorHealth.mayStart(runs: TorHealth.maxRuns), "a tor that keeps exiting is not run forever (BUG 23847)")

if failures > 0 { print("✗ \(failures) failure(s)"); exit(1) }
print("ok")
SWIFT

compile_and_run() {
    swiftc -Onone "$1" "$TMP/main.swift" -o "$TMP/run" 2>"$TMP/err" \
        || { head -20 "$TMP/err"; return 2; }
    "$TMP/run"
}
compile_and_run "$SRC" || { echo "✗ the rule fails its own self-test"; exit 1; }
echo "  ok   tor's answers read, the states follow them, renew, reset and runs by the rule"

mutate() {
    local name="$1" perl_expr="$2"
    cp "$SRC" "$TMP/mut.swift"
    perl -0pi -e "$perl_expr" "$TMP/mut.swift"
    if cmp -s "$SRC" "$TMP/mut.swift"; then echo "✗ mutation did not apply: $name"; exit 1; fi
    if compile_and_run "$TMP/mut.swift" >/dev/null 2>&1; then
        echo "✗ SURVIVED  $name"; exit 1
    fi
    echo "  ok   catches  $name"
}
mutate "the network going down is ignored" 's/var live: Bool \{ circuits && networkUp \}/var live: Bool { circuits }/'
mutate "a lost circuit resets on every poll" 's/if lost >= TorHealth\.resetAfter,\n\s*lastReset\.map\(\{ now\.timeIntervalSince\(\$0\) >= TorHealth\.resetEvery \}\) \?\? true \{/if lost >= TorHealth.resetAfter {/'
mutate "a lost circuit never says Can't connect" 's/return \(lost >= TorHealth\.connectWait \? \.failed : \.connecting\(100\), act\)/return (.connecting(100), act)/'
mutate "a recovery keeps the old spell" 's/(if reading\.live \{\n\s*)lostSince = nil\n/$1/'
mutate "a return never renews" 's/return away >= awayBeforeRenew \? \.renew : \.none/return .none/'
mutate "the first path reads as a move" 's/guard seen, let signature else/guard let signature else/'
mutate "tor runs again without a limit" 's/static func mayStart\(runs: Int\) -> Bool \{ runs < maxRuns \}/static func mayStart(runs: Int) -> Bool { true }/'
echo "  ok   7 mutations"
