import Foundation

extension WorkStage.Row {
    /// The primitives `WorkStage` and `WorkAsk` read off a row — one spelling
    /// for the cover, the sheet and Coming up, so the state word a row wears
    /// and whether it needs you can never be read from two different
    /// snapshots (prd §1080). Every field is a light column.
    init(_ thing: Thing) {
        self.init(source: thing.source,
                  sourceRef: thing.sourceRef,
                  title: thing.title,
                  tags: thing.tags,
                  mark: thing.mark.rawValue,
                  projectField: thing.authorHandle,
                  hasPrice: thing.priceValue != nil && thing.priceCurrency != nil)
    }
}
