import Foundation

/// Why a freshly pasted key did not connect, in words that say what to do
/// (prd §1162).
///
/// The token screen said one sentence for every failure — "That token didn't
/// work — check it (and your connection) and paste again" — so a key the
/// provider refused, a key missing one permission, a provider asking us to
/// slow down and a phone with no signal all read alike, and the remedy for
/// each is different: copy it again, make one with more access, wait a
/// minute, find a signal. The provider already said which; `BridgeHealth`
/// keeps the last status it answered with, and a fresh paste starts that
/// record clean, so "no status at all" means no answer came back.
///
/// `AgentKeyCheck` is the same split for the agent keys; this is it for the
/// token bridges, which have no check call of their own (their first read IS
/// the check). Foundation-only, compiled by `scripts/key-shape-selftest.sh`.
enum ConnectFailure: Equatable {
    case refused
    case missingAccess
    case rateLimited
    case unreachable
    case unknown

    /// `status` is the last HTTP status the provider answered this paste's
    /// read with, nil when no response came back at all.
    static func from(status: Int?) -> ConnectFailure {
        switch status {
        case nil, 0?:         return .unreachable
        case 401?:            return .refused
        case 403?:            return .missingAccess
        case 429?:            return .rateLimited
        default:              return .unknown
        }
    }

    func sentence(_ service: String) -> String {
        switch self {
        case .refused:
            String(localized: "\(service) turned that key down. Check you copied all of it, or make a new one.")
        case .missingAccess:
            String(localized: "\(service) took the key but it can't read enough. Make one with read access.")
        case .rateLimited:
            String(localized: "\(service) is busy right now. Paste the key again in a minute.")
        case .unreachable:
            String(localized: "Couldn't reach \(service). Check your connection and paste again.")
        case .unknown:
            String(localized: "That key didn't work with \(service). Check it and paste again.")
        }
    }
}
