import SwiftData
import UIKit

/// **AN ADDRESS WEARS THE FACE OF WHOEVER HOLDS IT (prd §1964).** When
/// Contacts has joined a wallet to a contact card that carries a photo, every
/// face drawn for that address (Send's To rows, a transfer's head, an
/// Activity row) shows the card's photo, so money reads as people. It sits
/// above the address's own pictures in `WalletFace`: the card is a picture
/// YOU keep of them, a published avatar is theirs.
///
/// Filled after each index build (`ContactIndexSources.rebuild`) and, from
/// the map the last build kept, once at launch (`warm`), never in a body:
/// the map is a dictionary lookup, the photos are the cards' own thumbnails
/// (`ContactsIngest.healPhotos`), decoded off main and kept.
@MainActor
@Observable
final class HolderPhotos {
    static let shared = HolderPhotos()

    /// Lowercased address → its holder's card photo.
    private(set) var photos: [String: UIImage] = [:]
    /// The card ref each photo was decoded from, so a build that changed
    /// nothing decodes nothing.
    @ObservationIgnored private var decoded: [String: String] = [:]
    /// The last build's address → card ref, kept so the faces are right from
    /// launch instead of after the first sweep's index build.
    @ObservationIgnored private var kept: [String: String] =
        (UserDefaults.standard.data(forKey: HolderPhotos.keptKey))
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    private static let keptKey = "holderPhotos.cards.v1"

    /// The holder's photo, for a face. A lookup, nothing fetched.
    func photo(for address: String) -> UIImage? {
        photos.isEmpty ? nil : photos[address.lowercased()]
    }

    /// At launch: the photos of the map the last build kept.
    func warm(context: ModelContext) {
        #if DEBUG
        NSLog("holderPhotos| warm | kept=%d decoded=%d", kept.count, decoded.count)
        #endif
        guard decoded.isEmpty, !kept.isEmpty else { return }
        load(kept, context: context)
    }

    /// Every listed contact that carries both a card and a wallet: each of
    /// its wallets takes the card's photo. You and a wallet you follow as
    /// your own are not listed (§1392), so your own accounts keep your face.
    func update(from contacts: [Contact], context: ModelContext) {
        var wanted: [String: String] = [:]   // address → card ref
        for contact in contacts where ContactIndexSources.isListed(contact) {
            guard let card = contact.identities.first(where: { $0.kind == .contact }),
                  let ref = ContactIndexSources.cardRef(forKey: card.key) else { continue }
            for wallet in contact.identities where wallet.kind == .wallet {
                wanted[wallet.body.lowercased()] = ref
            }
        }
        if wanted != kept {
            kept = wanted
            if let data = try? JSONEncoder().encode(wanted) { DefaultsWrite.set(data, forKey: Self.keptKey) }
        }
        load(wanted, context: context)
    }

    /// Forget what no card holds any more; read and decode what is new. A
    /// card with no photo yet is asked again next time, so a photo
    /// `healPhotos` lands later still reaches the face.
    private func load(_ wanted: [String: String], context: ModelContext) {
        for address in Set(decoded.keys).subtracting(wanted.keys) {
            photos[address] = nil
            decoded[address] = nil
        }
        var cardData: [String: Data] = [:]
        for (address, ref) in wanted where decoded[address] != ref {
            if cardData[ref] == nil {
                var d = FetchDescriptor<Thing>(predicate: #Predicate { $0.sourceRef == ref && $0.source == "Contacts" })
                d.fetchLimit = 1
                guard let data = (try? context.fetch(d))?.first?.previewImageData, !data.isEmpty else { continue }
                cardData[ref] = data
            }
            guard let data = cardData[ref] else { continue }
            decoded[address] = ref
            Task {
                let image = await Task.detached(priority: .utility) { UIImage(data: data)?.preparingForDisplay() }.value
                guard let image, self.decoded[address] == ref else { return }
                self.photos[address] = image
                #if DEBUG
                NSLog("holderPhotos| face | %@", AddressTail.short(address))
                #endif
            }
        }
    }
}
