import Foundation
import SwiftData

/// SENDING TEST COINS ON THE LOGOS TESTNET (prd §1084, 2026-10-03; user:
/// "Frames send is fine b/c its testnet. build what you can now").
///
/// **The one file that writes to LEZ.** The watch (`LogosIngest`) stays
/// keyless and read-only, and `logos-selftest.sh` holds it there: the write
/// method may appear here and nowhere else in the seat.
///
/// **A native transfer, and nothing else.** One signer (this phone's
/// `LogosKey`), who also pays the fee. The bytes are `LogosWire`'s, proven
/// byte-for-byte against three signed transfers on the 10-01 chain, whose
/// signatures verify under BIP-340 over the same hash (`logos-selftest.sh`).
///
/// **No faucet.** LEZ v0.3 has none, on the web or in its source: an account
/// is funded by somebody sending to it. So the room offers Create and Send,
/// never Top up, and the account menu's line says what it holds.
@MainActor
enum LogosSend {

    /// What the sheet needs before it can arm Send: the balance, the fee
    /// reserve the sequencer will hold back, and the nonce to sign over.
    struct Quote: Equatable {
        let balance: Decimal
        let reserve: Decimal
        let nonce: Decimal
    }

    static func quote(for id: String) async -> Quote? {
        guard let b = await LogosIngest.balance(id),
              let n = LogosWire.nonce(await LogosIngest.call("getAccountsNonces", [[id]])),
              let f = LogosWire.feeState(await LogosIngest.call("getFeeState", [])) else { return nil }
        let reserve = LogosWire.feeReserve(baseFeeExec: f.exec, baseFeeStor: f.stor,
                                           dataBytes: LogosWire.transferBytes)
        return Quote(balance: b, reserve: reserve, nonce: n)
    }

    enum Failure: Error, Equatable {
        case noKey, badRecipient, unreachable, blocked(LogosWire.SendBlock)
        case refused(LogosWire.Refusal), cancelled, signing

        var words: String {
            switch self {
            case .noKey:        return String(localized: "This phone has no Logos account to send from.")
            case .badRecipient: return String(localized: "That isn't a public LEZ account id.")
            case .unreachable:  return String(localized: "Couldn't reach the testnet.")
            case .blocked(.sameAccount):   return String(localized: "That's this account.")
            case .blocked(.nothingToSend): return String(localized: "Enter an amount.")
            case .blocked(.short(let needs)):
                return String(localized: "This account needs \(LogosWire.amount(needs)) to send that, the fee included.")
            case .refused(.funds): return String(localized: "There isn't enough on this account for the amount and the fee.")
            case .refused(.nonce): return String(localized: "An earlier send from this account is still settling. Try again in a minute.")
            case .refused(.other): return String(localized: "The testnet refused the send.")
            case .cancelled:    return String(localized: "Not sent.")
            case .signing:      return String(localized: "This phone couldn't sign the send.")
            }
        }
    }

    /// Signs and submits a native transfer from this phone's account, and
    /// lands its row at once under the same ref the walk will compute, so the
    /// block that carries it adds no second row. Returns the transaction hash.
    static func send(to raw: String, amount: Decimal, context: ModelContext) async -> Result<String, Failure> {
        guard let from = LogosKey.accountID(), let fromBytes = LogosWire.base58Decode(from) else {
            return .failure(.noKey)
        }
        guard let to = LogosWire.watchableID(raw), let toBytes = LogosWire.base58Decode(to) else {
            return .failure(.badRecipient)
        }
        guard let quote = await quote(for: from) else { return .failure(.unreachable) }
        if let block = LogosWire.sendBlock(from: from, to: to, amount: amount,
                                           balance: quote.balance, reserve: quote.reserve) {
            return .failure(.blocked(block))
        }
        guard let message = LogosWire.transferMessage(from: fromBytes, to: toBytes,
                                                      amount: amount, nonce: quote.nonce)
        else { return .failure(.signing) }

        let witness: (signature: [UInt8], publicKey: [UInt8])
        do {
            witness = try LogosKey.sign(
                hash: LogosWire.messageHash(message),
                reason: String(localized: "Send \(LogosWire.amount(amount)) test coins on Logos"))
        } catch LogosKey.Failure.locked {
            return .failure(.cancelled)
        } catch {
            return .failure(.signing)
        }
        guard let tx = LogosWire.publicTransaction(message: message, signature: witness.signature,
                                                   publicKey: witness.publicKey)
        else { return .failure(.signing) }

        let reply = await IngestSupport.postJSON(
            LogosIngest.sequencer,
            body: LogosWire.request("sendTransaction", [Data(tx).base64EncodedString()]),
            service: LogosIngest.service)
        if let refusal = LogosWire.refusal(reply) { return .failure(.refused(refusal)) }
        guard LogosWire.result(reply) != nil else { return .failure(.unreachable) }

        let hash = LogosWire.transactionHash(tx)
        land(from: from, to: to, amount: amount, hash: hash, context: context)
        return .success(hash)
    }

    /// The sender's row, now — dated when it was sent, which the block will
    /// confirm within about thirty seconds. The ref is the walk's own, so the
    /// walk finds it in place. The account is watched (Create watches it), so
    /// the room lists it.
    private static func land(from: String, to: String, amount: Decimal, hash: String, context: ModelContext) {
        let ref = "logos:lez:\(from):\(hash)"
        guard !IngestSupport.existingSourceRefs(context, source: LogosRoom.source).contains(ref) else { return }
        let thing = Thing(kind: .link,
                          title: IngestSupport.titleLine("Sent \(LogosWire.amount(amount)) — to \(LogosWire.short(to))"),
                          content: "\(LogosIngest.explorer)/transaction/\(hash)",
                          source: LogosRoom.source, capturedAt: .now,
                          tags: ["Sent"], sourceRef: ref)
        thing.authorHandle = LogosWire.short(from)
        context.insert(thing)
        SpotlightIndex.index([thing])
        context.saveHonestly()
    }

    /// Create: this phone's account, made (or adopted after a reinstall) and
    /// watched, so the room lists it at once. Returns its id.
    static func create() throws -> String {
        let id: String
        do {
            id = try LogosKey.create()
        } catch LogosKey.Failure.alreadyExists {
            // The key outlived its watch (the page's Disconnect clears the
            // watch list, never the key): watch it again rather than refuse.
            guard let held = LogosKey.accountID() else { throw LogosKey.Failure.missing }
            id = held
        }
        LogosStore.shared.add(id)
        return id
    }
}
