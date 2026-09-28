import Foundation

/// **WHAT THE AUTHORIZE SHEET SIGNS, AND WHAT IT WILL NOT** (user: "scope as
/// switches and show change before signing and rotate key").
///
/// Pure, so the arithmetic that decides a key's authority is read apart from
/// the sheet that draws it. Three facts carry it:
///
/// * **Scope zero is Admin** (`VibenetScope.isAdmin`, prd §463). A set of
///   switches with every switch off is therefore NOT "nothing": signed as-is
///   it would grant full control. `compose` answers nil for it, and the sheet
///   refuses to arm.
/// * **The editor offers four bits, never POLICY** — a gated key needs a
///   manager and a commitment this sheet does not compose (Subscriptions' own
///   build). A key being EDITED keeps every bit the editor does not offer
///   (POLICY, the reserved ones) exactly as it held them, so changing "Pay own
///   gas" can never silently drop a policy gate.
/// * **Only an admin can change an account**, so an edit or a replacement that
///   leaves the account with no admin leaves it unchangeable for good. That is
///   refused here; losing this phone's own admin while another admin remains
///   is allowed and said out loud.
enum VibenetScopeEdit {
    /// The bits the switches offer, in `Scopes.sol`'s declared order.
    static let switchable: UInt16 = VibenetScope.known & ~VibenetScope.policy

    /// The scope to sign, or nil when the switches describe no scope at all
    /// (which, signed, would be Admin).
    static func compose(admin: Bool, bits: UInt16, kept: UInt16) -> UInt16? {
        if admin { return 0 }
        let raw = (bits & switchable) | (kept & ~switchable)
        return raw == 0 ? nil : raw
    }

    /// What an edited key keeps that the switches do not show.
    static func kept(from scope: VibenetScope) -> UInt16 {
        scope.isAdmin ? 0 : scope.raw & ~switchable
    }

    /// The switches' starting state for a key being edited or replaced.
    static func bits(from scope: VibenetScope) -> UInt16 {
        scope.isAdmin ? 0 : scope.raw & switchable
    }

    enum Act: Equatable {
        /// A key that is not on the account yet.
        case add
        /// The same key, a different scope (`AuthorizeActor` is an upsert).
        case edit(before: UInt16)
        /// A new key takes the place of an old one, in one transaction.
        case replace(before: UInt16)
    }

    /// Why the sheet will not sign, in the sheet's own words; nil when it may.
    enum Refusal: Equatable {
        /// Every switch off and Admin off.
        case noScope
        /// An edit that changes nothing.
        case unchanged
        /// The edited or replaced key is the account's last admin, and the
        /// result is not an admin.
        case lastAdmin
        /// The key is limited to one contract (POLICY). Its manager and
        /// commitment ride `policyData`, which this sheet does not compose,
        /// so signing it again would sign the gate without its target.
        case policyGate
    }

    enum Warning: Equatable {
        /// This phone's own admin key becomes a limited one (or is replaced):
        /// the phone can no longer change the account afterwards.
        case thisPhoneLosesAdmin
        /// The new or edited key gets full control.
        case grantsAdmin
    }

    /// `otherAdmins` counts the account's admin keys other than the one being
    /// edited or replaced.
    static func refusal(_ act: Act, after: UInt16?, otherAdmins: Int) -> Refusal? {
        guard let after else { return .noScope }
        if after != 0, after & VibenetScope.policy != 0 { return .policyGate }
        switch act {
        case .add:
            return nil
        case .edit(let before):
            if before == after { return .unchanged }
            if before == 0, after != 0, otherAdmins == 0 { return .lastAdmin }
            return nil
        case .replace(let before):
            if before == 0, after != 0, otherAdmins == 0 { return .lastAdmin }
            return nil
        }
    }

    static func warnings(_ act: Act, after: UInt16, isThisPhone: Bool) -> [Warning] {
        var out: [Warning] = []
        switch act {
        case .add:
            break
        case .edit(let before):
            if isThisPhone, before == 0, after != 0 { out.append(.thisPhoneLosesAdmin) }
        case .replace(let before):
            if isThisPhone, before == 0 { out.append(.thisPhoneLosesAdmin) }
        }
        if after == 0, act != .edit(before: 0) { out.append(.grantsAdmin) }
        return out
    }

    /// The scope in words: "Admin", or "Send anywhere · Pay own gas".
    static func words(_ raw: UInt16) -> String {
        VibenetScope(raw: raw).grantedPlainLabels.joined(separator: " · ")
    }
}
