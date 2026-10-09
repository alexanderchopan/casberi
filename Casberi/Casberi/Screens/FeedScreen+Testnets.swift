import SwiftUI

// THE TESTNETS ROOM (prd §1050, built §1050k). The testnets fold into one
// room, and the room shows one network's own screen at a time — its tiles,
// its verbs (rows since prd §1108: New account in the menu, Send in
// Holdings) and its accounts — because two networks' test coins add up to
// nothing, so no view across them could say one thing about both. Logos is
// its one network since Hegotá Frames was deleted (prd §1206). `MainSurface`
// mounts the picked network's screen with the room as its `hostRoom`; the
// account menu is how you cross to the other network.
extension FeedScreen {
    /// The room's other networks, as the account menu's last section. Empty
    /// outside a merged room, and while only one network is connected — the
    /// room is then just that network.
    var hostedNetworkSlots: [DSAccountSlot] {
        guard let hostRoom else { return [] }
        let networks = RoomAccounts.connected(in: hostRoom, names: connectedSeatNames)
            .filter(\.ownScreen)
        guard networks.count > 1 else { return [] }
        return networks.filter { $0.source != source }.map { seat in
            DSAccountSlot(id: RoomAccounts.scopeID(seat), name: seat.name, sub: nil,
                          faces: [.mark(url: nil, source: seat.mark)], group: seat.group)
        }
    }

    /// A pick of another network switches the screen the room shows, and
    /// answers true; an account pick answers false and is the network's own.
    func pickHostedNetwork(_ picked: String?) -> Bool {
        guard let hostRoom, let picked, RoomAccounts.isSeat(picked) else { return false }
        withAnimation(DS.Motion.standard) { chrome.mergedScope[hostRoom] = picked }
        return true
    }
}
