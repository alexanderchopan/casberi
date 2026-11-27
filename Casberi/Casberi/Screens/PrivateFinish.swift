import SwiftUI

/// **ONE FINISH FOR EVERY PRIVATE MOVE (prd §1990; user, of the Move polish
/// canvas's "One receipt for every verb": "Yes, then ship").** Privacy Pools
/// finished on "View on Etherscan" alone, Railgun and Aztec on a grey
/// "Sent privately · 12 s", and Tacit on a white line naming the amount and
/// the place. All four now say it Tacit's way: what went and where it is,
/// in the text's own ink; under it, grey, how long it took or what is left
/// to happen. Save and the explorer follow as each sheet had them, and a
/// finish deals the Wallet's rain, as a public move's does.
enum PrivateFinish {
    enum Place {
        /// Someone's private balance or account, by name or tail.
        case theirPrivate(String)
        /// Someone's public address, in the open.
        case theirPublic(String)
        /// Your own public account.
        case yourPublic
        /// One of your private places, or your co-signer, as words.
        case yours(String)
    }

    /// A book name, else the address's tail.
    static func who(_ address: String) -> String {
        AddressBook.shared.name(for: address) ?? AddressTail.short(address)
    }

    /// "25 USDC went to Mira, privately", "0.1 ETH is on its way to Railgun".
    static func headline(_ what: String, to place: Place, onItsWay: Bool = false) -> String {
        switch place {
        case .theirPrivate(let who):
            return String(localized: "\(what) went to \(who), privately")
        case .theirPublic(let who):
            return onItsWay ? String(localized: "\(what) is on its way to \(who)")
                : String(localized: "\(what) went to \(who)")
        case .yourPublic:
            return onItsWay ? String(localized: "\(what) is on its way to your public account")
                : String(localized: "\(what) is in your public account")
        case .yours(let place):
            return onItsWay ? String(localized: "\(what) is on its way to \(place)")
                : String(localized: "\(what) is in \(place)")
        }
    }

    /// "Took 12 s": the send's time, tap to landed (prd §1700w).
    static func took(_ seconds: Int?) -> String? {
        seconds.map { String(localized: "Took \($0) s") }
    }
}

/// The finish's two lines: what happened, then grey, what is left or how
/// long it took.
struct PrivateFinishLines: View {
    let headline: String
    var note: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(verbatim: headline)
                .dsText(.body17).foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let note {
                Text(verbatim: note)
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
