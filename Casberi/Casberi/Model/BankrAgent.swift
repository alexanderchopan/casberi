import Foundation

/// TALKING TO BANKR, AND LETTING IT ACT (prd §529, 2026-08-29).
///
/// Bankr is the one seat in the Agent group that is not a model behind a key —
/// it is an agent WITH A WALLET, running on somebody else's servers, and its
/// API takes plain English (`POST /agent/prompt` → poll `/agent/job/<id>`).
/// That means it has always been able to do more than answer: the same
/// endpoint that reads "what do I hold?" also reads "swap 1 ETH for USDC",
/// and the only thing that has ever stopped the second one is a sentence this
/// app puts at the top of every prompt.
///
/// ## WHAT CHANGED, AND WHAT DID NOT
///
/// Nothing about Bankr changed. What changed is that this app now signs and
/// sends elsewhere (Safe's co-signature §425, the two devnets §523/§525), so
/// "Casberi never causes a transaction" stopped being a fact about the code
/// and became a rule somebody has to keep. A rule with no surface is a rule
/// that gets broken by the next person who adds a feature — so rather than
/// leave the capability latent behind a prompt prefix, it is made explicit,
/// off by default, and given a door with a person standing in it.
///
/// ## TWO VERBS, BECAUSE WE CANNOT CLASSIFY THE THIRD
///
/// "Show me my automations" is a read. "Do a limit order for XYZ" is a write.
/// They are the same shape on the wire — free text to a remote agent — and
/// **no amount of parsing on this side can reliably tell them apart**, because
/// the classification happens inside somebody else's model, after we have
/// already sent it. Guessing would be the §83 fake status in the one place
/// believing it costs money.
///
/// So the person classifies, exactly as `Find` and `Ask` split the composer
/// (§215): **Ask** carries the answer-only prefix and can be sent freely;
/// **Do** drops it and asks first. The verb you tap IS the consent, and it is
/// a fact you know and we do not.
///
/// ## THREE RAILS
///
/// 1. **`canAct` is off by default and `act` refuses in the MODEL, not the
///    UI.** A screen that hides a button is a screen; a `guard` is a rule.
/// 2. **Corpus text never rides an acting instruction.** The ask path has
///    always pasted numbered candidates into the prompt, and the file's own
///    comment records that Bankr grounds on the wallet and never on them — so
///    on the acting path they buy nothing and carry a real hazard: a page you
///    saved is text somebody else wrote, sitting in a message to an agent that
///    can trade. `act` sends the instruction alone.
/// 3. **The confirmation shows YOUR WORDS, never a parsed transaction.**
///    Bankr replies in sentences, so this app cannot state what a job will do
///    before it does it. A sheet reading "1.0 ETH → 3,200 USDC" would be a
///    number we invented. It reads back what you typed and says plainly that
///    Bankr decides the rest.
///
/// ## UNMEASURED
///
/// No Bankr key has ever been stored on this host, so no prompt has been sent
/// and no job payload has been read. `probe` exists for exactly that: it dumps
/// the RAW job envelope key by key, because if Bankr reports what it did in
/// structured form (a hash, an order id, a status) then the receipt below can
/// stop being a transcript and start being a record. Until that is measured,
/// every failure returns rather than guesses.
enum BankrAgent {

    /// THE KEY IS THE PERMISSION (user, 2026-08-31: "it's either a read only
    /// key or it isn't", "and if it isn't it's a question for an answer or an
    /// action").
    ///
    /// This file used to carry a `canAct` switch and a second prompt that
    /// dropped an ANSWER-ONLY rail. Both are deleted, because neither was a
    /// permission: the rail was a SENTENCE IN A PROMPT that a model may
    /// ignore, and the switch governed which sentence we sent. What actually
    /// decides whether Bankr can move money is the scope of the key minted at
    /// bankr.bot/api-keys — a read-only key cannot act whatever we write, and
    /// a full key can act whatever we write.
    ///
    /// The catalog copy admitted this the whole time ("a read-only key can't
    /// act whatever you switch on"), which is a sentence conceding that the
    /// switch was subordinate to the key. So the switch goes, the two verbs
    /// collapse into one, and the setup screen names the real boundary at the
    /// moment somebody mints the key.
    ///
    /// `forget()` remains as a no-op door for `AgentKey.clear` — there is no
    /// stored permission left to clear, and a stale UserDefaults key from a
    /// build that had one is removed here on the way past.
    static func forget() {
        UserDefaults.standard.removeObject(forKey: "bankr.canAct")
    }

    // MARK: - Outcomes

    enum Failure: Error, Equatable {
        case noKey
        case actingOff
        case emptyInstruction
        case rejectedKey
        case rateLimited
        case refused(String)
        case empty
        case unreachable
        case timedOut
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
        \(text.trimmingCharacters(in: .whitespacesAndNewlines))

        Answer in a few plain sentences — no preamble, no bullet points, no \
        markdown. You may draw on this wallet's holdings and live market data. \
        Never invent a number or a detail. If you did something rather than \
        answered, say plainly what you did — the amounts, the assets, and any \
        identifier a person could look up later.
        """
        return extra.isEmpty ? body : "\(body)\n\n\(extra)"
    }

    // MARK: - The verb

    /// One verb. What you type is a question or an instruction, and Bankr
    /// decides which — that judgement happens inside their model either way,
    /// and this app never had a way to make it.
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

    /// Submit, then poll. ONE poller for both verbs — two would drift, and
    /// then an answer and an action would disagree about what "completed"
    /// means, which is the class of bug this repo keeps finding in duplicated
    /// parsers.
    static func run(prompt: String, onTick: ((Int) -> Void)? = nil) async -> Result<Reply, Failure> {
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

    /// Poll every 2s for ~90s (Bankr says most jobs land inside 30). An acting
    /// job may legitimately run longer than an answer — a trade waits on a
    /// chain — so a timeout is reported as a TIMEOUT and never as a failure:
    /// the job may still be running, and telling somebody their swap did not
    /// happen when we simply stopped watching is the worse of the two lies.
    private static func poll(jobId: String, key: String,
                             onTick: ((Int) -> Void)? = nil) async -> Result<Reply, Failure> {
        for attempt in 0..<45 {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            onTick?((attempt + 1) * 2)
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
        return .failure(.timedOut)
    }
}
