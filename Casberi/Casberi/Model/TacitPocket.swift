import Foundation

/// AN EXISTING TACIT ACCOUNT, READ.
///
/// Casberi makes no Tacit account. It opens one a person already has, with
/// the key that account's own wallet makes by signing Tacit's message
/// (`TacitIdentity`), and reads it: the address, each network's receive
/// address, and what its notes add up to. Nothing here sends.
@MainActor
enum TacitPocket {

    /// One network's reading, with its receive address beside it.
    struct NetworkReading: Equatable {
        let network: TacitNetwork
        let receive: String
        /// nil when the network could not be read; the account still stands.
        let reading: TacitEngineWire.Reading?
        let error: String?
    }

    struct Overview: Equatable {
        /// The address others pay the account privately at: one for every network.
        let address: String
        let networks: [NetworkReading]
        /// Private TAC on the Tacit chain; nil when it could not be read.
        var chain: TacitEngineWire.ChainReading? = nil
    }

    /// The key of the Tacit account `coSigner` opens: your co-signer's own
    /// wallet signs Tacit's message once, over a pairing of its own that asks
    /// for that one method (`YourAccountSignerLink.signForApp`), and the
    /// answer must recover to the co-signer or nothing is derived.
    ///
    /// ONE signature, where Tacit's site asks twice the first time. Its
    /// second ask guards money sent to a key the wallet cannot make again;
    /// Casberi only reads, so a wallet that signs differently each time shows
    /// an empty account and loses nothing. Anything that SENDS to the account
    /// must ask twice first, as Tacit does.
    ///
    /// The key is returned, never stored: it lives in the engine's page for
    /// as long as the account is open.
    static func signIn(coSigner: String) async throws -> [UInt8] {
        let signature = try await SignerRequestSheet.asking(
            signer: coSigner, title: String(localized: "Your co-signer opens your Tacit account")) { ask in
            try await YourAccountSignerLink.signForApp(
                method: "personal_sign", params: [TacitIdentity.messageHex, coSigner],
                digest: TacitIdentity.digest, signer: coSigner,
                resend: ask.resends, sent: { ask.ask(kept: $0) },
                show: { ask.pair($0); ShieldBridge.openCoSignerWallet(coSigner, onto: $0) })
        }
        return try TacitIdentity.key(fromSignature: signature)
    }

    /// Opens the account `key` belongs to and reads every network, one after
    /// another. A network that does not answer is reported, not thrown.
    static func overview(key: [UInt8], networks: [TacitNetwork] = TacitNetwork.all) async throws -> Overview {
        let engine = TacitEngine.shared
        let opened = try await engine.open(key: key, networks: networks)
        guard let address = opened.address else {
            throw TacitEngineWire.Failure(name: "NotOpen", message: "no network opened")
        }
        var readings: [NetworkReading] = []
        for network in networks {
            let receive = opened.networks.first { $0.chainId == network.chainId }?.receive ?? ""
            do {
                let reading = try await engine.read(chainId: network.chainId)
                readings.append(NetworkReading(network: network, receive: receive, reading: reading, error: nil))
            } catch {
                let why = (error as? TacitEngineWire.Failure).map { "\($0.name): \($0.message)" } ?? "\(error)"
                readings.append(NetworkReading(network: network, receive: receive, reading: nil, error: why))
            }
        }
        // The Tacit chain last: it is the slow read, and a failure there
        // leaves the rest standing.
        var chain: TacitEngineWire.ChainReading?
        do { chain = try await engine.chain() } catch {
            let why = (error as? TacitEngineWire.Failure).map { "\($0.name): \($0.message)" } ?? "\(error)"
            NSLog("tacitEngine| chain | FAILED %@", why)
        }
        return Overview(address: address, networks: readings, chain: chain)
    }

    // MARK: - Public TAC

    /// TAC, Tacit's token on Ethereum (18 decimals): `ADDR.tac` in Tacit's
    /// own deployments file, its symbol and decimals read on 2026-11-24.
    static let tacToken = "0xA1313eb9f3A445606D9583bcAc3ebeB56a858279"

    /// The TAC `wallet` holds in public: what Tacit's own page calls Public
    /// (the connected wallet's balance, `readPublicTac`). One `balanceOf` at
    /// the Ethereum node the engine already reads, through the same funnel.
    /// nil when the node did not answer.
    static func publicTAC(of wallet: String) async -> Double? {
        let hex = wallet.lowercased().dropFirst(wallet.hasPrefix("0x") || wallet.hasPrefix("0X") ? 2 : 0)
        guard hex.count == 40, hex.allSatisfy(\.isHexDigit),
              let url = URL(string: TacitNetwork.ethereum.rpcUrl) else { return nil }
        let call: [String: Any] = ["to": tacToken, "data": "0x70a08231" + String(repeating: "0", count: 24) + hex]
        let body: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "eth_call", "params": [call, "latest"]]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30
        guard let (data, http) = await IngestSupport.sendRequest(request, service: TacitEngine.service),
              http.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? String, result.count == 66,
              let amount = TacitEngineWire.eth(result) else { return nil }
        return NSDecimalNumber(decimal: amount).doubleValue
    }
}
