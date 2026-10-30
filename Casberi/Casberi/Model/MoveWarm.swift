import Foundation

/// **MOVE IS READ BEFORE IT OPENS (prd §1610, user: "it takes a few seconds
/// to read which tokens i have … on fresh boot").** Opening the Wallet, or
/// the app coming back, starts what Move would ask the moment it opens:
/// what your account holds on every network, and what the account is
/// there (`YourAccountChain.readAhead`). Move then joins those reads, or
/// takes a holdings reading under `holdingsLife` old, instead of starting
/// cold, and Tor's circuits are already open.
@MainActor
enum MoveWarm {
    typealias Op = YourAccountOp

    /// One warm-up a minute at most, however often the Wallet is opened.
    private static var last: Date?
    static let every: TimeInterval = 60

    static func start() {
        guard let account = YourAccountKey.address, !YourAccountDemo.isDemo(account) else { return }
        if let last, Date().timeIntervalSince(last) < every { return }
        last = Date()
        for net in Op.networks {
            Task { _ = await YourAccountTokens.readShared(account, on: net) }
            Task { await YourAccountChain.readAhead(account, on: net) }
        }
    }
}

extension YourAccountTokens {
    /// How old a warm-up's holdings reading may be and still open Move.
    /// Move reads again whenever money may have arrived (back from Receive,
    /// the app coming back), and a send reads its own balances at the tap.
    static let holdingsLife: TimeInterval = 30

    private actor Shared {
        static let shared = Shared()
        private var kept: [String: (at: Date, held: [Held])] = [:]
        private var reading: [String: Task<[Held]?, Never>] = [:]

        func read(_ key: String, _ fresh: @escaping @Sendable () async -> [Held]?) async -> [Held]? {
            if let k = kept[key], Date().timeIntervalSince(k.at) < YourAccountTokens.holdingsLife { return k.held }
            let task: Task<[Held]?, Never>
            if let running = reading[key] {
                task = running
            } else {
                task = Task { await fresh() }
                reading[key] = task
            }
            let held = await task.value
            if reading[key] == task {
                reading[key] = nil
                if let held { kept[key] = (Date(), held) }
            }
            return held
        }

        func forget() { kept = [:]; reading = [:] }
    }

    /// A send went: the warm-up's reading is from before it.
    static func forgetShared() async { await Shared.shared.forget() }

    /// `read`, joined to a warm-up's read under way or taken from one under
    /// `holdingsLife` old. Only Move's opening read takes it.
    static func readShared(_ account: String, on net: Op.Network) async -> [Held]? {
        await Shared.shared.read("\(net.chainId)|\(account.lowercased())") { await read(account, on: net) }
    }
}
