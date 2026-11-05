#!/usr/bin/env python3
"""direct-swap-record.py — re-record a Uniswap v4 swap fixture against the chain (prd §1680).

    python3 scripts/direct-swap-record.py --network robinhood
    python3 scripts/direct-swap-record.py --network base
        Rewrite scripts/fixtures/direct-swap/uniswap-v4-<network>.json: every
        vector's quote asked of the network's v4 quoter at a fresh pinned
        block, its minimum and its calls written by the SHIPPED
        YourAccountSwap.swift (compiled here, the same sources
        direct-swap-selftest.sh compiles), then every vector's calls simulated
        in order in ONE eth_simulateV1 block as the fixture's account, its ETH
        balance overridden. Nothing is written unless every call returns
        status 1. No key, no signature, no transaction: simulation only.
    python3 scripts/direct-swap-record.py --self-test
        Offline (verify.sh): the RPC payloads, the quote and status decoding,
        and the rule that one failed call writes nothing.

Why it exists. The fixtures `direct-swap-selftest.sh` holds YourAccountSwap.swift
to were recorded by hand (2026-11-02); when the pool list moved (the nightly's
drift, 2026-11-04) nothing could re-record them. The selftest proves the app
still writes these bytes; this proves the bytes swap on chain.

What it keeps from the fixture: each vector's name, hops, ETH flags and amount
(a later vector sells what an earlier one bought, so the account must hold it:
the simulation says if it does not), and the `ask`'s hop and amount. What it
writes: `quoted`, `minimum`, `calls`, `ask.request`, `deadline`, `note`.
Base's original recording also overrode the account's USDC; a Base vector that
sells USDC it did not buy first fails here, loudly, rather than being faked.
"""
import argparse, json, os, subprocess, sys, tempfile, time, urllib.request
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIXTURES = os.path.join(ROOT, "scripts", "fixtures", "direct-swap")
RPC = {"robinhood": "https://rpc.mainnet.chain.robinhood.com", "base": "https://base.gateway.tenderly.co"}
CHAIN = {"robinhood": "Robinhood Chain", "base": "Base"}
BOOK = {"robinhood": "robinhood", "base": "base"}
ETH_OVERRIDE = hex(10 ** 20)   # 100 ETH, the account's balance in the simulation
DEADLINE_AHEAD = 7 * 86_400

SOURCES = ["Casberi/Shared/AddressTail.swift", "Casberi/Casberi/Model/YourAccountSwap.swift",
           "Casberi/Casberi/Model/OpenTokenList.swift", "Casberi/Casberi/Model/YourAccountAcross.swift",
           "Casberi/Casberi/Model/YourAccount.swift", "Casberi/Casberi/Model/YourAccountOp.swift",
           "Casberi/Casberi/Model/YourAccount7579.swift", "Casberi/Casberi/Model/SafeTransaction.swift",
           "Casberi/Casberi/Model/Keccak256.swift", "Casberi/Casberi/Model/ClearSign.swift",
           "Casberi/Casberi/Model/SafeWebAuthnSignature.swift", "Casberi/Casberi/Model/SafeTypedData.swift",
           "Casberi/Casberi/Model/RoundUps.swift"]

STUB = '''
enum YourAccountDemo {
    static var isOn: Bool { false }
    static var roundUps: RoundUps.Setting { RoundUps.Setting() }
}
enum PrivateMainnet { static let on = true }
enum YourAccountKey { static var stubbed: String? = nil; static var address: String? { stubbed } }
'''

# The emitter: one JSON request in, one JSON answer out, through the shipped code.
EMIT = '''
import Foundation
typealias S = YourAccountSwap
let req = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]
let book = (req["book"] as! String) == "base" ? S.base : S.robinhood
let venue = book.venues.last!
let hops = (req["hops"] as? [[Any]] ?? []).map { S.Hop(from: $0[0] as! String, to: $0[2] as! String, step: $0[1] as! Int) }
var out: [String: Any] = [:]
switch req["mode"] as! String {
case "ask":
    let call = S.Ask(venue: venue, hops: hops, amount: req["amount"] as! String).call!
    out = ["to": call.to, "data": SafeABI.hex(call.data)]
case "minimum":
    out = ["minimum": S.minimum(req["quoted"] as! String, bps: book.slippageBps)!]
default:
    let calls = S.calls(S.Route(venue: venue, hops: hops), in: book, sellsETH: req["sellsETH"] as! Bool,
                        buysETH: req["buysETH"] as! Bool, amount: req["amount"] as! String,
                        minimum: req["minimum"] as! String, account: req["account"] as! String,
                        deadline: req["deadline"] as! Int)!
    out = ["calls": calls.map { ["to": $0.to, "value": $0.value, "data": SafeABI.hex($0.data)] }]
}
FileHandle.standardOutput.write(try! JSONSerialization.data(withJSONObject: out))
'''


# ── Pure parts (self-tested) ──────────────────────────────────────────────
def rpc_payload(method, params, ident=1):
    return {"jsonrpc": "2.0", "id": ident, "method": method, "params": params}


def simulate_params(account, calls, block_hex):
    """One eth_simulateV1 block: every call from the account, its ETH overridden."""
    return [{"blockStateCalls": [{
        "stateOverrides": {account: {"balance": ETH_OVERRIDE}},
        "calls": [{"from": account, "to": c["to"], "value": hex(int(c["value"])), "data": c["data"]} for c in calls],
    }], "validation": False}, block_hex]


def first_word(hexdata):
    """A quoter's amountOut: the first 32-byte word of its return."""
    h = hexdata[2:] if hexdata.startswith("0x") else hexdata
    if len(h) < 64:
        raise ValueError("the quoter answered no amount")
    return str(int(h[:64], 16))


def statuses(result):
    """Each simulated call's status, in order; anything but 0x1 is a failure."""
    return [c.get("status") == "0x1" for c in result[0]["calls"]]


def self_test():
    bad = []
    def check(ok, what):
        if not ok:
            bad.append(what)
    p = simulate_params("0xabc", [{"to": "0xdef", "value": "10", "data": "0x01"}], "0x10")
    call = p[0]["blockStateCalls"][0]["calls"][0]
    check(call == {"from": "0xabc", "to": "0xdef", "value": "0xa", "data": "0x01"}, "a call is not sent from the account with its value in hex")
    check(p[0]["blockStateCalls"][0]["stateOverrides"]["0xabc"]["balance"] == ETH_OVERRIDE, "the account's ETH is not overridden")
    check(p[1] == "0x10" and p[0]["validation"] is False, "the block is not pinned, or validation is on")
    check(first_word("0x" + "0" * 62 + "2a" + "f" * 64) == "42", "the quote is not the first word")
    try:
        first_word("0x12")
        check(False, "a short answer reads as an amount")
    except ValueError:
        pass
    check(statuses([{"calls": [{"status": "0x1"}, {"status": "0x0"}]}]) == [True, False], "a failed call reads as a success")
    check(statuses([{"calls": [{"status": "0x1"}, {}]}]) == [True, False], "a call with no status reads as a success")
    check(rpc_payload("eth_call", [1])["method"] == "eth_call", "the RPC payload names another method")
    for b in bad:
        print("  ✗ " + b)
    if bad:
        sys.exit(1)
    print("direct-swap-record self-test: OK")


# ── The network and the compiler ──────────────────────────────────────────
def rpc(net, method, params):
    req = urllib.request.Request(RPC[net], data=json.dumps(rpc_payload(method, params)).encode(),
                                 headers={"Content-Type": "application/json", "User-Agent": "casberi-dev"})
    with urllib.request.urlopen(req, timeout=60) as r:
        body = json.load(r)
    if "error" in body:
        raise RuntimeError(f"{method}: {body['error']}")
    return body["result"]


def build_emitter(tmp):
    stub, main = os.path.join(tmp, "stub.swift"), os.path.join(tmp, "main.swift")
    open(stub, "w").write(STUB)
    open(main, "w").write(EMIT)
    exe = os.path.join(tmp, "emit")
    subprocess.run(["xcrun", "swiftc", "-Onone", "-o", exe, *[os.path.join(ROOT, s) for s in SOURCES], stub, main],
                   check=True, cwd=ROOT)
    return exe


def emit(exe, tmp, req):
    path = os.path.join(tmp, "req.json")
    json.dump(req, open(path, "w"))
    return json.loads(subprocess.run([exe, path], check=True, capture_output=True).stdout)


def record(net):
    path = os.path.join(FIXTURES, f"uniswap-v4-{net}.json")
    fx = json.load(open(path))
    block = rpc(net, "eth_getBlockByNumber", ["latest", False])
    number, stamp = int(block["number"], 16), int(block["timestamp"], 16)
    block_hex = hex(number)
    deadline = stamp + DEADLINE_AHEAD
    account = fx["account"]
    with tempfile.TemporaryDirectory() as tmp:
        exe = build_emitter(tmp)
        book = BOOK[net]
        ask = fx["ask"]
        q = emit(exe, tmp, {"mode": "ask", "book": book, "hops": [[ask["sell"], ask["step"], ask["buy"]]], "amount": ask["amount"]})
        ask["request"] = q["data"]
        every = []
        for v in fx["vectors"]:
            amount = v["amount"]; print(f"  asking {v['name']} …", flush=True)
            for i in range(len(v["hops"])):
                asked = emit(exe, tmp, {"mode": "ask", "book": book, "hops": v["hops"][: i + 1], "amount": amount})
                amount = first_word(rpc(net, "eth_call", [{"to": asked["to"], "data": asked["data"]}, block_hex]))
            v["quoted"] = amount
            v["minimum"] = emit(exe, tmp, {"mode": "minimum", "book": book, "quoted": amount})["minimum"]
            v["calls"] = emit(exe, tmp, {"mode": "calls", "book": book, "hops": v["hops"], "sellsETH": v["sellsETH"],
                                         "buysETH": v["buysETH"], "amount": v["amount"], "minimum": v["minimum"],
                                         "account": account, "deadline": deadline})["calls"]
            every += v["calls"]
            print(f"  {v['name']}: quoted {v['quoted']}, minimum {v['minimum']}, {len(v['calls'])} call(s)")
    result = rpc(net, "eth_simulateV1", simulate_params(account, every, block_hex))
    ok = statuses(result)
    if not all(ok):
        print(f"✗ {ok.count(False)} of {len(ok)} simulated call(s) failed — nothing written")
        sys.exit(1)
    day = datetime.fromtimestamp(stamp, timezone.utc).strftime("%Y-%m-%d")
    fx["deadline"] = deadline
    extra = " (and on Base its USDC)" if net == "base" and "USDC" in fx.get("note", "") else ""
    fx["note"] = (f"Every vector's calls simulated in order on {CHAIN[net]} in one eth_simulateV1 block at block "
                  f"{number} ({day}), as the account, its ETH{extra} balance overridden, every call status 1; "
                  "each later vector sells what an earlier one bought. Recorded by scripts/direct-swap-record.py.")
    open(path, "w").write(json.dumps(fx, indent=1, ensure_ascii=False))
    print(f"✓ {os.path.relpath(path, ROOT)}: {len(fx['vectors'])} vectors, {len(every)} calls, all status 1 at block {number}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--network", choices=sorted(RPC))
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()
    if a.self_test:
        self_test()
    elif a.network:
        record(a.network)
    else:
        ap.error("--network or --self-test")


if __name__ == "__main__":
    main()
