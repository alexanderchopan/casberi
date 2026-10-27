import Foundation

extension PrivateBridge {
    /// The ride for a save of `budget` (the dollar's units) leaving from `net`:
    /// the deposit proved for what arrives, Across asked for this message,
    /// the calls checked, and the note kept once the operation is sent.
    static func ride(budget: String, from net: Op.Network, account: String) async throws -> PrivateOnEthereum.Ride {
        guard carries(from: net.chainId) else { throw PrivateOnEthereum.Failure.noPool }
        let proved = try await PrivateOnEthereum.bridgedDeposit(budget: budget)
        guard let message = message(router: proved.router, deposit: proved.data, budget: budget, account: account),
              let url = feesURL(from: net.chainId, amount: budget, account: account, message: message) else {
            throw PrivateOnEthereum.Failure.noPool
        }
        guard let (data, http) = await IngestSupport.sendRequest(URLRequest(url: url), service: "Your account"),
              http.statusCode == 200, let fees = Across.fees(try? JSONSerialization.jsonObject(with: data), from: net.chainId),
              !fees.tooLow else {
            throw YourAccountChain.Failure(message: String(localized: "Across did not answer"))
        }
        let now = Int(Date().timeIntervalSince1970)
        guard let input = input(budget: budget, quotedOutput: fees.outputAmount),
              fees.fillDeadline > now, fees.fillDeadline <= now + Across.maxDeadlineSeconds,
              let calls = calls(from: net.chainId, input: input, budget: budget, fees: fees, message: message, account: account) else {
            throw YourAccountChain.Failure(message: String(localized: "Across's fee is too high for this amount"))
        }
        return PrivateOnEthereum.Ride(calls: calls.map { ($0.to, SafeABI.hex($0.data), $0.value) }, keep: proved.note,
                                      figure: proved.figure, spends: input)
    }
}
