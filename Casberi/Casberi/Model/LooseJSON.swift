import Foundation

/// Reading a shape nobody has documented (2026-09-15, prd §780b).
///
/// The finance seats promoted in §780b — Acorns and Rocket Money — read APIs
/// that publish no schema and that this repo cannot exercise without somebody's
/// real account. Their endpoints are confirmed to EXIST (Acorns' 401/404 split;
/// Rocket Money's own bundle names its operations), but the JSON they hand back
/// on a good session has never been seen here.
///
/// **The honest way to ship that is a tolerant reader plus a loud failure, not
/// a confident parser.** A parser written against a guessed shape fails the
/// same way whether the guess was wrong or the account is simply empty — and
/// §83 forbids a seat that says "Synced" over either. So this finds the parts
/// every plausible shape has in common (a list of records, each with a name and
/// a number), and when it finds nothing it reports the KEY NAMES it did see, so
/// the miss is diagnosable from the person's own screen rather than from a
/// debugger nobody has attached.
///
/// It is deliberately small and deliberately dumb. It is not a schema, and the
/// day either shape is actually observed, the seat should read it directly and
/// this becomes the fallback rather than the path.
enum LooseJSON {

    /// The keys a list of records hides behind, in the order worth trying.
    /// Every one of these is a convention, not an observation.
    private static let listKeys = ["data", "results", "items", "records",
                                   "accounts", "subscriptions", "transactions",
                                   "edges", "nodes", "list"]

    /// Finds the most plausible array of records in a decoded body — the body
    /// itself when it is already an array, else the first array of objects
    /// under a conventional key, at any depth (these APIs wrap deeply:
    /// `data.viewer.subscriptions.edges`).
    static func records(in json: Any?) -> [[String: Any]] {
        guard let json else { return [] }
        if let array = json as? [Any] {
            let objects = array.compactMap { $0 as? [String: Any] }
            if !objects.isEmpty { return objects }
        }
        guard let object = json as? [String: Any] else { return [] }

        // Conventional keys first, at this level, so a wrapper's own metadata
        // array (`errors`, `warnings`) never wins over the payload.
        for key in listKeys {
            if let found = object[key] {
                let here = records(in: found)
                if !here.isEmpty { return here }
            }
        }
        // Then anything else, deepest-last so the outermost real list wins.
        for (_, value) in object where value is [Any] || value is [String: Any] {
            let here = records(in: value)
            if !here.isEmpty { return here }
        }
        return []
    }

    /// A record's human name. `nil` when none of the conventions match, which
    /// the caller must treat as "not readable" rather than inventing one.
    static func name(in record: [String: Any]) -> String? {
        let keys = ["name", "displayName", "nickname", "title", "label",
                    "merchantName", "description", "productName", "accountName",
                    "type", "subType"]
        for key in keys {
            if let s = record[key] as? String,
               !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return s.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // A nested `{ name: { text: … } }`, which GraphQL wrappers do.
            if let nested = record[key] as? [String: Any],
               let s = name(in: nested) { return s }
        }
        return nil
    }

    /// A record's amount, as a `Double`, whatever it was spelled as — a number,
    /// a numeric string, or `{ amount: …, currency: … }`. Money APIs also ship
    /// MINOR units (cents) under `*Cents`/`*Minor`, which this converts, since
    /// reporting a $12.99 subscription as $1,299 is worse than reporting none.
    static func amount(in record: [String: Any]) -> Double? {
        let minorKeys = ["amountCents", "balanceCents", "valueCents",
                         "amountMinor", "amountInCents"]
        for key in minorKeys {
            if let n = number(record[key]) { return n / 100 }
        }
        let keys = ["amount", "balance", "value", "total", "currentValue",
                    "price", "cost", "monthlyCost", "currentBalance"]
        for key in keys {
            if let n = number(record[key]) { return n }
            if let nested = record[key] as? [String: Any],
               let n = amount(in: nested) { return n }
        }
        return nil
    }

    /// A record's currency code, when it names one. Defaults are the caller's
    /// business — this returns only what was actually stated.
    static func currency(in record: [String: Any]) -> String? {
        for key in ["currency", "currencyCode", "isoCurrencyCode"] {
            if let s = record[key] as? String, s.count == 3 { return s.uppercased() }
            if let nested = record[key] as? [String: Any],
               let s = currency(in: nested) { return s }
        }
        for key in ["amount", "balance", "value"] {
            if let nested = record[key] as? [String: Any],
               let s = currency(in: nested) { return s }
        }
        return nil
    }

    /// A record's own id, for a stable `sourceRef`. Falls back to nil so the
    /// caller can key on the name instead — never on an index, which would
    /// re-land every row the moment the list reorders.
    static func id(in record: [String: Any]) -> String? {
        for key in ["id", "uuid", "guid", "_id", "accountId", "subscriptionId"] {
            if let s = record[key] as? String, !s.isEmpty { return s }
            if let n = record[key] as? Int { return String(n) }
        }
        return nil
    }

    /// A record's date, from the conventions these APIs use.
    static func date(in record: [String: Any]) -> Date? {
        let keys = ["date", "createdAt", "updatedAt", "occurredAt", "postedAt",
                    "nextRenewalDate", "dueDate", "nextPaymentDate"]
        for key in keys {
            if let raw = record[key] {
                if let d = IngestSupport.isoDate(raw) { return d }
                if let seconds = number(raw), seconds > 1_000_000_000 {
                    // Epoch seconds or milliseconds — both appear in the wild.
                    return Date(timeIntervalSince1970: seconds > 1e12 ? seconds / 1000 : seconds)
                }
            }
        }
        return nil
    }

    /// Every key name present in a body's first record, for the honest failure
    /// line. Names only — never a value, which on these seats is somebody's
    /// balance (prd §780).
    static func keyNames(in json: Any?) -> [String] {
        if let first = records(in: json).first { return first.keys.sorted() }
        if let object = json as? [String: Any] { return object.keys.sorted() }
        return []
    }

    private static func number(_ raw: Any?) -> Double? {
        if let d = raw as? Double { return d }
        if let i = raw as? Int { return Double(i) }
        if let s = raw as? String { return Double(s) }
        return nil
    }

    /// `$1,234.56` — the one place these seats format money, so a row and a
    /// status line can never disagree about it.
    static func money(_ value: Double, currency: String?) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency ?? "USD"
        formatter.maximumFractionDigits = abs(value) < 1000 ? 2 : 0
        return formatter.string(from: NSNumber(value: value))
            ?? String(format: "%.2f", value)
    }
}
