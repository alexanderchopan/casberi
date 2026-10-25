import SwiftUI

/// **WHAT THE CO-SIGNER SEES BEFORE FACE ID (prd §1509 item 3, §1514,
/// canvas figure 11).** Under the call words of the Safe sign block: a red
/// line for each unlimited approval, in words, then "Details", which opens
/// the nonce and the three hashes Safe's app and hardware wallets show,
/// labelled in ERC-8213's own terms, and Raw transaction in place.
struct SafeSignDetails: View {
    let chainId: Int
    let safe: String
    let tx: SafeTransaction
    /// Each call the transaction makes, as the block reads it: its target and
    /// its calldata (a batch's entries, or the one call).
    let calls: [(to: String, data: String)]
    /// The calls in the block's words, for Raw transaction.
    let words: [String]
    /// Opened at mount (`-safeSignPreview`).
    var opened = false

    @State private var open = false
    @State private var rawOpen = false
    /// The unlimited approvals' lines, once the token's name is read.
    @State private var unlimited: [String] = []

    private var hashes: SafeSignChecks.Hashes? { SafeSignChecks.hashes(chainId: chainId, safe: safe, tx: tx) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ForEach(unlimited, id: \.self) { line in
                Text(verbatim: line).dsText(.body17).foregroundStyle(DS.destructiveInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                withAnimation(DS.Motion.standard) { open.toggle(); if !open { rawOpen = false } }
                DSHaptic.selection()
            } label: {
                (Text("Details") + Text(verbatim: " ") + Text(Image(systemName: open ? "chevron.up" : "chevron.down")))
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(RowPress())
            if open, let hashes {
                VStack(alignment: .leading, spacing: 0) {
                    fact(String(localized: "Nonce"), String(tx.nonce), mono: false)
                    fact(String(localized: "EIP-712 Digest"), YourAccountPreview.hex(hashes.digest), sub: String(localized: "Safe's safeTxHash"))
                    fact(String(localized: "Domain Hash"), YourAccountPreview.hex(hashes.domain))
                    fact(String(localized: "Message Hash"), YourAccountPreview.hex(hashes.message))
                    DSCopyRow(value: YourAccountPreview.hex(hashes.digest), label: "Copy digest", sensitive: false)
                    DSPushRow(title: Text("Raw transaction"), action: {
                        withAnimation(DS.Motion.standard) { rawOpen.toggle() }
                        DSHaptic.selection()
                    }) { EmptyView() }
                    if rawOpen {
                        MoveRawPage(raw: RawTransaction(words: words.map { YourAccountPreview.Step(words: $0) },
                                                        hash: hashes.digest, hashKind: .eip712,
                                                        callData: SafeABI.hexBytes(tx.data) ?? []))
                            .padding(.top, DS.Space.s2)
                    }
                }
                .transition(.opacity)
            }
        }
        .task(id: tx.nonce) {
            if opened { open = true }
            await readUnlimited()
        }
    }

    /// A hash, whole and selectable, under its name.
    private func fact(_ label: String, _ value: String, sub: String? = nil, mono: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: label).dsText(.body17).foregroundStyle(DS.textSecondary)
                if let sub { Text(verbatim: sub).dsText(.subhead12).foregroundStyle(DS.textTertiary) }
            }
            Text(verbatim: value)
                .dsText(mono ? .mono12 : .body17).foregroundStyle(DS.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DS.Space.s2)
    }

    /// Each unlimited approval in words, naming the spender as the book does
    /// and the token as its own contract does (`symbol()`, a collection's
    /// `name()`), read from the Safe's chain; else its address.
    private func readUnlimited() async {
        let found = calls.compactMap { call -> SafeSignChecks.Unlimited? in
            guard let data = SafeABI.hexBytes(call.data) else { return nil }
            return SafeSignChecks.unlimited(to: call.to, data: data)
        }
        func spender(_ u: SafeSignChecks.Unlimited) -> String {
            AddressBook.shared.name(for: u.spender) ?? YourAccountPreview.short(EIP55.checksum(u.spender))
        }
        // Drawn at once with the token's address; its own name follows when
        // the chain answers, so a slow read never hides the warning.
        unlimited = found.map { SafeSignChecks.line($0, spender: spender($0), token: YourAccountPreview.short(EIP55.checksum($0.token))) }
        #if DEBUG
        NSLog("safeSignChecks| unlimited=%d of %d calls", found.count, calls.count)
        #endif
        var named: [String] = []
        for u in found {
            let selector = u.collection ? "0x06fdde03" : "0x95d89b41"
            let token = await SafeSigner.ethCall(chainId: chainId, to: u.token, data: selector)
                .flatMap(YourAccountOp.abiString) ?? YourAccountPreview.short(EIP55.checksum(u.token))
            named.append(SafeSignChecks.line(u, spender: spender(u), token: token))
        }
        guard !Task.isCancelled else { return }
        unlimited = named
    }
}
