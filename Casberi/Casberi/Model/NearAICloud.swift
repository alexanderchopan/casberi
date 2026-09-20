import Foundation

/// **NEAR AI Cloud's three reads** — the attestation report, the per-answer
/// signature, and which models can be verified at all.
///
/// The answer itself goes out through the ordinary agent path (`AgentAnswer`),
/// because it is an OpenAI-shaped chat completion like every other keyed seat.
/// What lives here is the half no other seat has: the evidence.
///
/// **Why verifiability is MEASURED and never listed.** `/v1/models` carries an
/// `owned_by` that looks like it answers this — `nearai` for the open-weight
/// models, `anthropic`/`openai`/`google` for proxied ones — and it does not.
/// There is a third value, `attested 3p`, and models under a vendor's own name
/// (`deepseek`) that may or may not be enclave-hosted. Reading a promise off
/// that field would put a "Verified" badge on a model that cannot produce one,
/// which is the §83 failure exactly. NEAR AI's own docs list the enclave models
/// by subdomain and that list is already stale (measured 2026-09-20:
/// `glm-5-1.completions.near.ai` does not resolve). So the app asks: a model is
/// verifiable when its attestation report answers with a signing address, and
/// that answer is cached per model (`NearAIVerifiable`).
enum NearAICloud {
    /// Every request here is built from this. There is deliberately no bare
    /// `host` constant beside it: the ledger records the REQUEST, so a host
    /// string that governed nothing would be a second, drifting answer to
    /// "where does this go?".
    static let base = URL(string: "https://cloud-api.near.ai")!

    // MARK: - Failures worth telling apart

    /// The same discipline as `SafeServiceGate` (prd §789): a read that did not
    /// answer is never reported as a read that answered "no".
    enum Failure: Error, Equatable {
        /// No key stored.
        case noKey
        /// The endpoint answered, and refused us.
        case refused(status: Int)
        /// Rate limited.
        case throttled
        /// Nothing answered.
        case unreachable
        /// Something answered in a shape this does not understand. Carries the
        /// keys it DID see, never a value (prd §780b).
        case unreadable(keysSeen: [String])
        /// A signature is not cached on the node we reached. Expected, and not
        /// an error the person should ever be shown as one.
        case signatureNotFound
    }

    // MARK: - The attestation report

    /// The signing addresses a report published, and nothing else.
    ///
    /// The full report is ~400KB — an Intel TDX quote, a 98KB NVIDIA Hopper
    /// payload, a 30-entry event log, an 18KB certificate. None of it is read
    /// here: verifying that hardware means shipping Intel's DCAP verifier and
    /// posting 98KB to NVIDIA per check, which is not a thing a phone does per
    /// answer. Only the addresses are kept, and `NearAIVerify`'s doc comment
    /// states plainly what that does and does not prove.
    struct Attestation: Equatable {
        /// One per enclave node serving the model.
        let modelSigners: [String]
        /// The gateway enclave's own address.
        let gatewaySigners: [String]
        /// Echoed back from our request. A report that does not echo the nonce
        /// we sent is a replay of an older one.
        let nonce: String?

        var canVerify: Bool { !modelSigners.isEmpty || !gatewaySigners.isEmpty }
    }

    /// Ask for a model's attestation report.
    ///
    /// The nonce is 32 random bytes. It is bound into the hardware reports we
    /// do not verify, so it buys less here than in a full verifier — but it
    /// also has to come back in `request_nonce`, and that much a phone can
    /// check, so it is sent and checked.
    static func attestation(model: String, key: String,
                            session: URLSession = .shared) async throws -> Attestation {
        let nonce = randomNonce()
        var components = URLComponents(url: base.appendingPathComponent("v1/attestation/report"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "signing_algo", value: "ecdsa"),
            URLQueryItem(name: "model", value: model),
            URLQueryItem(name: "nonce", value: nonce),
        ]
        let data = try await get(components.url!, key: key, session: session)

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.unreadable(keysSeen: [])
        }

        // Two shapes are served. The gateway returns `model_attestations` plus
        // `gateway_attestation`; a direct model subdomain returns one flat
        // report with `signing_address` at the root and an `all_attestations`
        // array. Both are read, because the flat one is what answers keylessly
        // and is the only reachable shape before a key exists.
        var modelSigners = addresses(in: root["model_attestations"])
        if modelSigners.isEmpty { modelSigners = addresses(in: root["all_attestations"]) }
        if modelSigners.isEmpty, let one = root["signing_address"] as? String { modelSigners = [one] }

        var gatewaySigners: [String] = []
        if let gateway = root["gateway_attestation"] as? [String: Any],
           let address = gateway["signing_address"] as? String { gatewaySigners = [address] }

        let echoed = root["request_nonce"] as? String
            ?? (root["model_attestations"] as? [[String: Any]])?.first?["request_nonce"] as? String

        guard !modelSigners.isEmpty || !gatewaySigners.isEmpty else {
            throw Failure.unreadable(keysSeen: root.keys.sorted())
        }
        // A report that echoes somebody else's nonce is not this report.
        if let echoed, echoed.lowercased() != nonce.lowercased() {
            throw Failure.unreadable(keysSeen: ["request_nonce"])
        }

        return Attestation(modelSigners: modelSigners,
                           gatewaySigners: gatewaySigners,
                           nonce: echoed)
    }

    private static func addresses(in value: Any?) -> [String] {
        guard let list = value as? [[String: Any]] else { return [] }
        return list.compactMap { $0["signing_address"] as? String }
    }

    // MARK: - The signature

    /// What the enclave signed, for one answer.
    struct Signature: Equatable {
        let text: String
        let signature: String
        let kind: String?
    }

    /// Fetch the signature for a completion.
    ///
    /// **A 404 here is ordinary.** A model runs on several enclave nodes and
    /// the signature is cached on whichever one answered, so a lookup can land
    /// on a different node and find nothing. NEAR AI's own example retries five
    /// times a second apart; this retries too, and when it still has nothing it
    /// returns `signatureNotFound`, which every surface must read as "not
    /// checked", never as "failed" (prd §83).
    static func signature(chatID: String, model: String, key: String,
                          retries: Int = 4, delay: Duration = .milliseconds(700),
                          session: URLSession = .shared) async throws -> Signature {
        var components = URLComponents(
            url: base.appendingPathComponent("v1/signature/\(chatID)"),
            resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "model", value: model),
            URLQueryItem(name: "signing_algo", value: "ecdsa"),
        ]
        guard let url = components.url else { throw Failure.unreachable }

        for attempt in 0...max(0, retries) {
            do {
                let data = try await get(url, key: key, session: session)
                guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let text = root["text"] as? String,
                      let signature = root["signature"] as? String
                else { throw Failure.unreadable(keysSeen: []) }
                return Signature(text: text, signature: signature,
                                 kind: root["signature_kind"] as? String)
            } catch Failure.refused(let status) where status == 404 && attempt < retries {
                try? await Task.sleep(for: delay)
                continue
            } catch Failure.refused(let status) where status == 404 {
                throw Failure.signatureNotFound
            }
        }
        throw Failure.signatureNotFound
    }

    // MARK: - One read

    private static func get(_ url: URL, key: String, session: URLSession) async throws -> Data {
        guard !key.isEmpty else { throw Failure.noKey }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        NetworkLedger.shared.record(request)

        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw Failure.unreachable }

        guard let http = response as? HTTPURLResponse else { throw Failure.unreachable }
        switch http.statusCode {
        case 200...299: return data
        case 429:       throw Failure.throttled
        default:        throw Failure.refused(status: http.statusCode)
        }
    }

    static func randomNonce() -> String {
        (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }
}
