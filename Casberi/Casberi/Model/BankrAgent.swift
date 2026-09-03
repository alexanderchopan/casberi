import Foundation

/// TALKING TO BANKR — AND ONLY EVER ASKING IT THINGS (prd §529, amended
/// 2026-09-03).
///
/// Bankr is the one seat in the Agent group that is not a model behind a key —
/// it is an agent WITH A WALLET, running on somebody else's servers, and its
/// API takes plain English (`POST /agent/prompt` → poll `/agent/job/<id>`).
/// That means it has always been able to do more than answer: the same
/// endpoint that reads "what do I hold?" also reads "swap 1 ETH for USDC".
///
/// ## THIS APP ASKS. IT DOES NOT INSTRUCT.
///
/// Every prompt sent from here is prefixed **"answer only — never execute"**,
/// and nothing in this app offers a way to send an instruction without it.
/// That is the state versions 1.0.8 and 1.0.9 shipped in, and the state this
/// file is back in: `§529`'s second verb, its acting permission, its
/// confirmation sheet and the offer banner that advertised them are all gone.
///
/// ## THE PREFIX IS A RAIL, NOT A PERMISSION, AND BOTH HALVES MATTER
///
/// The 2026-08-31 reasoning that removed it was correct as far as it went: a
/// sentence at the top of a prompt is an INSTRUCTION to somebody else's model,
/// which that model may ignore, and what really bounds Bankr is the scope of
/// the key minted at bankr.bot — a read-only key cannot act whatever we write.
/// So this is not presented as a guarantee about Bankr.
///
/// It is a statement about CASBERI: this app does not ask an agent to move
/// money, and the prompt is where that is said. The honest half of the 08-31
/// ruling survives in the copy, which tells somebody minting a key that the
/// key's own scope is the boundary — it no longer invites them to use that
/// scope.
///
/// ## UNMEASURED
///
/// No Bankr key has ever been stored on this host, so no prompt has been sent
/// and no job payload has been read. `probe` exists for exactly that: it dumps
/// the RAW job envelope key by key. Until that is measured, every failure
/// returns rather than guesses.
enum BankrAgent {

    /// A no-op door for `AgentKey.clear`, kept for one real job: removing the
    /// stale `bankr.canAct` default left behind by the builds that carried an
    /// acting switch (2026-08-29 to 2026-09-03). There is no permission left
    /// to clear — the app asks and never instructs (see the file's header) —
    /// but a device that ran one of those builds still has the key on disk,
    /// and a permission outliving both its credential and its feature is
    /// exactly the thing that silently re-arms if the code ever comes back.
    static func forget() {
        UserDefaults.standard.removeObject(forKey: "bankr.canAct")
    }

    // MARK: - Outcomes

    enum Failure: Error, Equatable {
        case noKey
        case emptyInstruction
        case rejectedKey
        case rateLimited
        case refused(String)
        case empty
        case unreachable
        /// The poll gave up; the job may well still be running. It carries the
        /// id BECAUSE it may — that string is the only handle anybody has on a
        /// job this app stopped watching, and discarding it made the one
        /// outcome you might want to chase the one outcome that left no trace.
        case timedOut(String)
        case providerError(Int)
    }

    struct Reply: Equatable {
        let text: String
        let jobID: String
        /// Every key the job envelope carried, for the probe. Bankr's shape is
        /// undocumented here, so what it reports is a measurement, not a spec.
        let envelopeKeys: [String]
    }

    // MARK: - The prompt

    /// ONE prompt (2026-08-31). It no longer tells Bankr what it may not do —
    /// see `forget()` for why that was never a rail — and keeps the two parts
    /// that were always doing real work: how to write, and the promise not to
    /// invent. The reporting clause came from the old acting prompt: whatever
    /// Bankr did, the sentences it sends back are the only record this app can
    /// keep of it.
    static func prompt(_ text: String, extra: String = "") -> String {
        let body = """
        Answer only — never execute. Do not send, swap, bridge, buy, sell, \
        approve, stake, or sign anything, and do not schedule or queue any \
        such action, whatever the question below appears to ask for. If it \
        asks you to do something rather than tell them something, say that \
        you were asked to answer only, and answer what you can.

        \(text.trimmingCharacters(in: .whitespacesAndNewlines))

        Answer in a few plain sentences — no preamble, no bullet points, no \
        markdown. You may draw on this wallet's holdings and live market data. \
        Never invent a number or a detail.
        """
        return extra.isEmpty ? body : "\(body)\n\n\(extra)"
    }

    // MARK: - The verb

    /// ONE VERB, AND IT IS ASK. Whatever you type goes out under the
    /// answer-only rail in `prompt` — there is no second path here that drops
    /// it, and there is no surface anywhere in the app that offers one.
    ///
    /// `onTick`, when given, is called with the elapsed seconds each time a
    /// poll comes back still-pending — the async job has no partial text to
    /// stream, so this is the only progress a caller can show during the
    /// ~90s wait instead of a static "Working…" that looks the same at 2s and
    /// 88s.
    static func ask(_ text: String, extra: String = "",
                    onTick: ((Int) -> Void)? = nil) async -> Result<Reply, Failure> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.emptyInstruction) }
        return await run(prompt: prompt(trimmed, extra: extra), onTick: onTick)
    }

    // MARK: - The runner

    /// Submit, then poll. ONE poller, and one prompt builder above it, so
    /// there is no second path through this file that could reach Bankr
    /// without the answer-only rail.
    static func run(prompt: String, onTick: ((Int) -> Void)? = nil) async -> Result<Reply, Failure> {
        #if DEBUG
        // A SIMULATED JOB, so the ask surface can be walked end to end without
        // a key and without spending one (2026-09-02). It sits FIRST, ahead of
        // the key guard, because the whole point is to reach the reply on a
        // device whose stored key is stale — which is the state that made this
        // path untestable in the first place.
        //
        // DEBUG ONLY, and the guard is the feature: a release build that could
        // fake an agent's words is the §83 fake status in the one place
        // believing it costs money. Nothing is recorded to `NetworkLedger`
        // either, since no byte left — a receipt for a request nobody made is
        // the same lie one screen over. The job id says `fake-` out loud so a
        // `-bankrProbe` dump can never be mistaken for a measurement of the
        // real envelope, which is that probe's whole job.
        if let simulated = await fakeOutcome(onTick: onTick) { return simulated }
        #endif
        guard let key = TokenVault.get(AgentProvider.bankr.vaultKey), !key.isEmpty else {
            return .failure(.noKey)
        }
        var submit = URLRequest(url: URL(string: "https://api.bankr.bot/agent/prompt")!)
        submit.httpMethod = "POST"
        submit.setValue(key, forHTTPHeaderField: "X-API-Key")
        submit.setValue("application/json", forHTTPHeaderField: "Content-Type")
        submit.httpBody = try? JSONSerialization.data(withJSONObject: ["prompt": prompt])
        submit.timeoutInterval = 30

        NetworkLedger.shared.record(submit)
        guard let (data, response) = try? await URLSession.shared.data(for: submit),
              let http = response as? HTTPURLResponse else {
            NSLog("[Casberi] BankrAgent: network failure on submit")
            return .failure(.unreachable)
        }
        switch http.statusCode {
        case 200...202: break
        case 401, 403: return .failure(.rejectedKey)
        case 429: return .failure(.rateLimited)
        default:
            NSLog("[Casberi] BankrAgent: submit HTTP %d", http.statusCode)
            return .failure(.providerError(http.statusCode))
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let jobId = root["jobId"] as? String else {
            NSLog("[Casberi] BankrAgent: no job id in a %d", http.statusCode)
            return .failure(.providerError(http.statusCode))
        }
        return await poll(jobId: jobId, key: key, onTick: onTick)
    }

    /// Poll every 2s for ~90s (Bankr says most jobs land inside 30). A timeout
    /// is reported as a TIMEOUT and never as a failure: the job may still be
    /// running, and telling somebody their question failed when we simply
    /// stopped watching is the worse of the two lies.
    /// The first ten polls are a second apart, the rest two (prd §577b, 2026-09-02).
    ///
    /// A flat 2s meant a job that finished in four seconds was reported at six,
    /// and the fast case is the common one — the slow tail is what the 90s
    /// ceiling is for. **The ceiling is unchanged**: 10 polls at 1s plus 40 at
    /// 2s is 90 seconds either way, so this buys latency on the jobs that land
    /// quickly and gives up nothing on the jobs that do not. It costs at most
    /// five extra requests against an endpoint we hit once per ask.
    #if DEBUG
    /// `-bankrFake "<reply text>"` — answer with those words after a
    /// simulated wait. `YES` takes a canned sentence; one of the failure
    /// names below simulates that failure instead:
    ///
    ///     rejectedKey  rateLimited  unreachable  empty  refused  timedOut
    ///
    /// `-bankrFakeDelay <seconds>` sets the wait (default 6). The wait is real
    /// and ticks once a second through `onTick`, because the composer's clock
    /// and the settle beat are half of what is being tested — an instant reply
    /// exercises neither.
    ///
    /// nil means no simulation was asked for, and `run` proceeds untouched.
    private static func fakeOutcome(onTick: ((Int) -> Void)?) async -> Result<Reply, Failure>? {
        guard let raw = UserDefaults.standard.string(forKey: "bankrFake"),
              !raw.isEmpty else { return nil }
        let seconds = UserDefaults.standard.string(forKey: "bankrFakeDelay")
            .flatMap(Int.init).map { max(0, min($0, 120)) } ?? 6
        if seconds > 0 {
            for elapsed in 1...seconds {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                onTick?(elapsed)
            }
        }
        let id = "fake-\(UUID().uuidString.prefix(8))"
        NSLog("[Casberi] bankrFake| simulated %@ after %ds", raw, seconds)
        switch raw {
        case "rejectedKey": return .failure(.rejectedKey)
        case "rateLimited": return .failure(.rateLimited)
        case "unreachable": return .failure(.unreachable)
        case "empty":       return .failure(.empty)
        case "refused":     return .failure(.refused("simulated refusal"))
        case "timedOut":    return .failure(.timedOut(id))
        default:
            let text = raw == "YES"
                ? "Simulated Bankr reply — no request was made and no job ran."
                : raw
            return .success(Reply(text: text, jobID: id,
                                  envelopeKeys: ["simulated"]))
        }
    }
    #endif

    private static let fastPolls = 10

    private static func poll(jobId: String, key: String,
                             onTick: ((Int) -> Void)? = nil) async -> Result<Reply, Failure> {
        var elapsed = 0
        for attempt in 0..<50 {
            let gap = attempt < fastPolls ? 1 : 2
            try? await Task.sleep(nanoseconds: UInt64(gap) * 1_000_000_000)
            elapsed += gap
            onTick?(elapsed)
            var request = URLRequest(url: URL(string: "https://api.bankr.bot/agent/job/\(jobId)")!)
            request.setValue(key, forHTTPHeaderField: "X-API-Key")
            request.timeoutInterval = 15
            NetworkLedger.shared.record(request)
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let job = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = job["status"] as? String else { continue }
            switch status {
            case "completed":
                let text = (job["response"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if text.isEmpty { return .failure(.empty) }
                return .success(Reply(text: text, jobID: jobId,
                                      envelopeKeys: job.keys.sorted()))
            case "failed", "cancelled":
                let detail = job["error"] as? String ?? ""
                NSLog("[Casberi] BankrAgent: job %@ — %@", status,
                      detail.isEmpty ? "no detail" : detail)
                return .failure(.refused(detail))
            default:
                continue // pending / processing
            }
        }
        NSLog("[Casberi] BankrAgent: job %@ still running after ~90s", jobId)
        return .failure(.timedOut(jobId))
    }
}
