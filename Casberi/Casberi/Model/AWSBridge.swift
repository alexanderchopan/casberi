import Foundation
import CryptoKit
import SwiftData

/// AWS (2026-08-30) — a read-only Work seat over an IAM user/role you create
/// yourself: Billing/Cost Explorer, CloudWatch alarms, CodePipeline deploys,
/// and a resource inventory (EC2/S3/RDS/Lambda).
///
/// ## Credentials, and why they aren't a `TokenBridge` case alone
///
/// AWS has no bearer token — every request is SIGNED with an access key ID
/// and a secret access key (`AWSSigV4`), plus a region this bridge's own
/// screen asks for. That's Trello's two-credential shape with a third field,
/// App Store Connect's shape exactly: all three save together, and the check
/// that follows is a real signed request, because there is no other way to
/// validate an AWS key pair.
///
/// ## Read-only is by IAM POLICY, and it is enforced HERE too
///
/// Unlike Cursor or App Store Connect, AWS genuinely HAS a read-only grade —
/// the setup screen tells the person to create an IAM user/role carrying only
/// a read-only policy (e.g. the AWS-managed `ReadOnlyAccess`, or narrower).
/// But a policy is something the PERSON configures on AWS's side, not
/// something this app can prove, and a key minted with a broader policy would
/// make this file's own conduct the last line of defense — exactly Cursor's
/// and App Store Connect's reasoning, one layer more defensible. So this file
/// still issues only actions on `AWSAction.allowed` (`Describe*`, `List*`,
/// `Get*`, and STS's `GetCallerIdentity`) and never a mutating verb.
/// `scripts/aws-selftest.sh` fails the build on any action name outside that
/// allowlist, and on any HTTP verb this file has no legitimate reason to send
/// (this bridge only ever needs GET/POST — a PUT/DELETE/PATCH literal is
/// itself the finding).
///
/// ## The module doctrine, applied to four very different kinds of read
///
///   - **CloudWatch alarms** land a `Thing` only on a STATE TRANSITION
///     (OK→ALARM, ALARM→OK) — never a standing "N alarms" tally. First sight
///     seeds the ledger silently (the Peer/Morpho/Hyperliquid cursor-seed
///     shape): an account with a year of alarm history does not land a year
///     of fake news the moment it connects.
///   - **CodePipeline** lands only TERMINAL executions (Succeeded, Failed,
///     Superseded) — never `InProgress`, which is a state, not an event
///     (Cursor's `CREATING`/`RUNNING` reasoning exactly). A failure LEADS its
///     title, `IngestSupport.titleLine`'s 80-char clamp rule.
///   - **Cost Explorer** is a STATE, redrawn each pass and never landed as a
///     Thing per day — except a genuine anomaly, which is the one event Cost
///     Explorer has. The baseline is the MEDIAN of the trailing 7–14 days,
///     not the mean: `StripeSilence.verdict` (2026-07-31) is the standing
///     lesson here — a burst drags a mean into missing the very thing it
///     exists to catch, and the fix generalizes to any trailing-window
///     baseline in this codebase, not just Stripe's payment cadence.
///   - **Resource inventory** (EC2/S3/RDS/Lambda) is pure counts and state,
///     so it NEVER lands as individual `Thing`s — it composes into
///     `AWSStanding`, the ASC/Stripe/PostHog room-head shape: written by the
///     same pass that reads it, spending nothing extra to draw.
///
/// ## UNMEASURED (2026-08-30)
///
/// No AWS credential has ever been given to this app and the build host has
/// no egress to any `*.amazonaws.com` host. Every field map and every
/// protocol shape below (which of CloudWatch/CodePipeline is JSON-1.1 vs
/// Query/XML, the exact `X-Amz-Target` operation strings) is doc-derived,
/// not measured against a live account — the App Store Connect/Cursor/Stripe
/// convention this whole file follows. Every read is a GET/POST that returns
/// nil on any non-200 or parse failure, so it fails safe: a wrong target or a
/// drifted field empties the room rather than landing a wrong reading. Run
/// `-awsProbe YES` against a real key before trusting any of it.
enum AWSAuth {

    /// The secret access key — the slot `TokenBridge.connected` reads, Cursor's
    /// reasoning (a key ID with no secret is a label, not a credential).
    static var secretVaultKey: String { TokenBridge.aws.tokenKey }
    static let accessKeyIDVaultKey = "aws.accesskeyid"
    private static let regionKey = "aws.region"
    static let defaultRegion = "us-east-1"

    static var storedSecretKey: String? { TokenVault.get(secretVaultKey) }
    static var storedAccessKeyID: String { TokenVault.get(accessKeyIDVaultKey) ?? "" }

    static var region: String {
        get {
            let stored = UserDefaults.standard.string(forKey: regionKey)
            return (stored?.isEmpty == false) ? stored! : defaultRegion
        }
        set { UserDefaults.standard.set(newValue, forKey: regionKey) }
    }

    /// Connected means both halves of the key pair. `TokenBridge.connected`
    /// only sees the secret, which is why every seat/pass check goes through
    /// this — a secret with no access key ID mints a request AWS refuses, and
    /// a bridge that reads "connected" while every call 403s is the fake
    /// status §83 bans (the `ASCAuth.configured` shape exactly).
    static var configured: Bool {
        storedSecretKey != nil && !storedAccessKeyID.isEmpty
    }

    static func setAccessKeyID(_ id: String) {
        TokenVault.set(id.trimmingCharacters(in: .whitespacesAndNewlines), for: accessKeyIDVaultKey)
    }

    /// Drops both halves of the key pair and every ledger. Called on BOTH a
    /// real Remove and a reconnect (App Store Connect's/Cloudflare's reason):
    /// a fresh key pair may name a different AWS account entirely, and
    /// diffing a new account's alarms against the old account's ledger would
    /// announce a stranger's incident as yours.
    static func clear() {
        TokenVault.delete(secretVaultKey)
        TokenVault.delete(accessKeyIDVaultKey)
        AWSState.clear()
    }
}

// MARK: - Signature Version 4

/// AWS's request-signing algorithm, entirely Foundation + CryptoKit (no SDK).
/// Every method here is pure and independently checkable: `scripts/aws-
/// selftest.sh` compiles this WHOLE against fixed test vectors computed
/// separately by `scripts/support/aws-sigv4-vectors.py` — a second, from-spec
/// implementation in Python's stdlib `hashlib`/`hmac`, so the two agreeing is
/// evidence rather than one file quietly checking itself (`safetx-vectors.py`'s
/// shape for the Safe signer).
enum AWSSigV4 {

    /// `"20250115T120000Z"` — the format every AWS request date carries, both
    /// in the `X-Amz-Date` header and inside the string to sign.
    static func amzDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    /// The first 8 characters of an `amzDate` — `"20250115"`.
    static func dateStamp(_ amzDate: String) -> String { String(amzDate.prefix(8)) }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func hmac(key: Data, _ message: String) -> Data {
        let symmetric = SymmetricKey(data: key)
        let code = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: symmetric)
        return Data(code)
    }

    /// RFC 3986 unreserved characters are never encoded; everything else is,
    /// uppercase hex, which is what AWS's own examples show and what a lower-
    /// case percent-encoding silently fails to match (AWS compares the
    /// canonical request byte-for-byte). `encodeSlash` is false only for a
    /// canonical URI PATH segment (there is none here — every read below signs
    /// against `/`), and true everywhere else, including every query value.
    static func uriEncode(_ s: String, encodeSlash: Bool = true) -> String {
        var allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
        if !encodeSlash { allowed.insert(charactersIn: "/") }
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    /// Query parameters, percent-encoded and joined `k=v&k=v…`, sorted by the
    /// ENCODED key — AWS's canonicalization order, which for every parameter
    /// name this file ever sends (plain ASCII, no encoded characters) is the
    /// same as sorting the raw key, but stated the spec's way rather than
    /// assumed.
    static func canonicalQuery(_ params: [String: String]) -> String {
        params.map { (uriEncode($0.key), uriEncode($0.value)) }
            .sorted { $0.0 < $1.0 }
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: "&")
    }

    /// One canonical request + its signed-headers list. `headers` must be
    /// LOWERCASE keys — every caller here builds them that way, and this
    /// function trusts rather than re-lowercases them so a mismatched case
    /// between this and the actual `URLRequest` headers can be caught by
    /// reading the call site rather than silently repaired here.
    static func canonicalRequest(method: String, path: String, query: [String: String],
                                 headers: [String: String], hashedPayload: String)
        -> (canonical: String, signedHeaders: String) {
        let canonicalURI = path.isEmpty ? "/" : path
        let sortedNames = headers.keys.sorted()
        let canonicalHeaders = sortedNames
            .map { "\($0):\(headers[$0]!.trimmingCharacters(in: .whitespaces))\n" }
            .joined()
        let signedHeaders = sortedNames.joined(separator: ";")
        let canonical = [
            method, canonicalURI, canonicalQuery(query),
            canonicalHeaders, signedHeaders, hashedPayload,
        ].joined(separator: "\n")
        return (canonical, signedHeaders)
    }

    static func stringToSign(amzDate: String, credentialScope: String,
                             canonicalRequestHash: String) -> String {
        ["AWS4-HMAC-SHA256", amzDate, credentialScope, canonicalRequestHash]
            .joined(separator: "\n")
    }

    /// The HMAC chain seeded with the literal `"AWS4"` prefix — AWS's own
    /// derivation, four links deep, so a key never signs anything directly
    /// with the raw secret.
    static func signingKey(secretKey: String, dateStamp: String,
                           region: String, service: String) -> Data {
        let kDate = hmac(key: Data("AWS4\(secretKey)".utf8), dateStamp)
        let kRegion = hmac(key: kDate, region)
        let kService = hmac(key: kRegion, service)
        return hmac(key: kService, "aws4_request")
    }

    struct Signed {
        let authorization: String
        let amzDate: String
    }

    /// Sign one request. `body` is the EXACT bytes that will be sent — for a
    /// GET (every EC2/RDS/S3/STS read here) that's always empty, so there is
    /// no risk of the signed hash disagreeing with what actually goes over
    /// the wire; for the two JSON-1.1 POSTs (CloudWatch, CodePipeline) the
    /// caller must send precisely this `Data`, not re-serialize the source
    /// dictionary a second time (see `AWSFetch`'s note on this).
    static func sign(method: String, host: String, path: String, query: [String: String],
                     body: Data, service: String, region: String,
                     accessKeyID: String, secretKey: String, date: Date = .now) -> Signed {
        let amz = amzDate(date)
        let stamp = dateStamp(amz)
        var headers: [String: String] = ["host": host, "x-amz-date": amz]
        if !body.isEmpty {
            // Only the two JSON POSTs carry this — every GET below signs the
            // well-known empty-payload hash without adding the header, which
            // is legitimate (SigV4 does not require it) and matches what a
            // GET signed by the AWS CLI itself sends.
            headers["x-amz-content-sha256"] = sha256Hex(body)
        }
        let hashedPayload = sha256Hex(body)
        let (canonical, signedHeaders) = canonicalRequest(
            method: method, path: path, query: query, headers: headers,
            hashedPayload: hashedPayload)
        let credentialScope = "\(stamp)/\(region)/\(service)/aws4_request"
        let toSign = stringToSign(amzDate: amz, credentialScope: credentialScope,
                                  canonicalRequestHash: sha256Hex(Data(canonical.utf8)))
        let key = signingKey(secretKey: secretKey, dateStamp: stamp,
                             region: region, service: service)
        let signature = hmac(key: key, toSign).map { String(format: "%02x", $0) }.joined()
        let authorization = "AWS4-HMAC-SHA256 Credential=\(accessKeyID)/\(credentialScope), "
            + "SignedHeaders=\(signedHeaders), Signature=\(signature)"
        return Signed(authorization: authorization, amzDate: amz)
    }
}

// MARK: - The read-only allowlist (conduct, enforced mechanically)

/// Every AWS action this file may ever call, in one place — so
/// `scripts/aws-selftest.sh` can grep a COMMENT-STRIPPED copy of `AWSFetch`
/// for any `Action=` / `X-Amz-Target` value outside this list and fail the
/// build (the Cursor/App Store Connect conduct guard, applied to an action
/// NAME rather than an HTTP verb, because AWS's own verb is almost always
/// GET/POST regardless of whether the action reads or writes).
enum AWSAction {
    static let allowed: Set<String> = [
        "GetCallerIdentity",
        "DescribeAlarms", "DescribeAlarmHistory",
        "ListPipelines", "ListPipelineExecutions",
        "GetCostAndUsage",
        "DescribeInstances", "DescribeDBInstances",
        "ListBuckets", "ListFunctions",
    ]
}

// MARK: - What this device remembers

/// Resource-inventory + present-tense standing, the ASC/Stripe/PostHog shape:
/// written by the same pass that reads it, spending nothing extra to draw.
struct AWSStanding: Codable, Equatable {
    var region: String
    /// Alarms currently in ALARM state, by name — a snapshot, never landed as
    /// Things themselves (only a TRANSITION is).
    var alarmsInAlarm: [String]
    var lastFailedPipeline: String?
    var lastFailedPipelineWhen: Date?
    var costToday: Double?
    var costBaseline: Double?
    /// Set only on the day an anomaly actually fired — so the room head can
    /// tell "spend is fine" from "spend is elevated but we already said so".
    var costAnomalyDay: String?
    var ec2Count: Int
    var s3Count: Int
    var rdsCount: Int
    var lambdaCount: Int
    var lastRead: Date?

    // "us-east-1" as a literal rather than `AWSAuth.defaultRegion` — the
    // struct stays Foundation-only and self-contained (no `TokenVault`/
    // `UserDefaults` reach), which is what lets `scripts/aws-selftest.sh`
    // extract it whole beside `AWSRoom.swift`. `AWSIngest.refresh` always
    // overwrites `region` with the real value before this default is ever
    // seen by a person.
    static let empty = AWSStanding(region: "us-east-1", alarmsInAlarm: [],
                                   lastFailedPipeline: nil, lastFailedPipelineWhen: nil,
                                   costToday: nil, costBaseline: nil, costAnomalyDay: nil,
                                   ec2Count: 0, s3Count: 0, rdsCount: 0, lambdaCount: 0,
                                   lastRead: nil)
}

enum AWSState {
    private static let alarmStatesKey = "aws.alarmStates"
    private static let alarmsSeededKey = "aws.alarmsSeeded"
    private static let pipelineStatesKey = "aws.pipelineStates"
    private static let costHistoryKey = "aws.costHistory"
    private static let standingKey = "aws.standing"

    /// Alarm name → last known state, for the transition-only landing rule.
    static var alarmStates: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: alarmStatesKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: alarmStatesKey) }
    }

    static var alarmsSeeded: Bool {
        get { UserDefaults.standard.bool(forKey: alarmsSeededKey) }
        set { UserDefaults.standard.set(newValue, forKey: alarmsSeededKey) }
    }

    /// Pipeline name → the state of its NEWEST known execution, refreshed
    /// every pass whatever the answer — the version-ledger shape from
    /// `ASCIngest`: it is read for the room head's present-tense standing,
    /// not to decide whether to land a row (that's `sourceRef` dedupe).
    static var pipelineStates: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: pipelineStatesKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: pipelineStatesKey) }
    }

    /// `"yyyy-MM-dd"` → daily unblended cost, trailing ~14 days. Pure STATE
    /// (§216) — never landed as a `Thing` per day, only read for the median
    /// baseline and the room head's own small chart.
    static var costHistory: [String: Double] {
        get { UserDefaults.standard.dictionary(forKey: costHistoryKey) as? [String: Double] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: costHistoryKey) }
    }

    static var standing: AWSStanding {
        get {
            guard let data = UserDefaults.standard.data(forKey: standingKey),
                  let decoded = try? JSONDecoder().decode(AWSStanding.self, from: data)
            else { return .empty }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: standingKey)
        }
    }

    static func clear() {
        let d = UserDefaults.standard
        for key in [alarmStatesKey, alarmsSeededKey, pipelineStatesKey, costHistoryKey, standingKey] {
            d.removeObject(forKey: key)
        }
    }
}

// MARK: - The reads

enum AWSFetch {

    /// The service NAME `NetworkLedger`/the receipts screen shows — a single
    /// word rather than per-endpoint noise, PostHog's/Stripe's choice.
    static let networkService = "AWS"

    // MARK: STS — the connect-time check

    /// `sts:GetCallerIdentity` — free, keyless-of-policy, and answerable by
    /// every AWS principal regardless of what it can otherwise see, which is
    /// exactly why every AWS SDK's own "is this key any good" check uses it.
    /// STS's global endpoint signs against `us-east-1` no matter which region
    /// the person picked for their resources — an identity check is not a
    /// regional resource.
    /// `status` is 0 on a transport failure (no response at all — offline,
    /// DNS), `IngestSupport`'s convention throughout. Never optional: every
    /// outcome, reachable or not, is a real answer worth logging.
    static func callerIdentity(accessKeyID: String, secretKey: String) async
        -> (account: String, arn: String, status: Int) {
        let host = "sts.amazonaws.com"
        let query = ["Action": "GetCallerIdentity", "Version": "2011-06-15"]
        let signed = AWSSigV4.sign(method: "GET", host: host, path: "/", query: query,
                                   body: Data(), service: "sts", region: "us-east-1",
                                   accessKeyID: accessKeyID, secretKey: secretKey)
        let qs = AWSSigV4.canonicalQuery(query)
        let (text, status) = await xmlGET("https://\(host)/?\(qs)", signed: signed)
        guard let text else { return (account: "", arn: "", status: status) }
        let fields = AWSXML.textValues(in: text, tags: ["Account", "Arn"])
        return (account: fields["Account"]?.first ?? "",
                arn: fields["Arn"]?.first ?? "", status: status)
    }

    // MARK: CloudWatch — JSON 1.1 (doc-derived, see the file's UNMEASURED note)

    private static let cloudWatchTargetPrefix = "GraniteServiceVersion20100801"

    static func alarms(region: String, accessKeyID: String, secretKey: String) async
        -> [[String: Any]]? {
        let root = await jsonCall(
            host: "monitoring.\(region).amazonaws.com", region: region, service: "monitoring",
            target: "\(cloudWatchTargetPrefix).DescribeAlarms", body: [:],
            accessKeyID: accessKeyID, secretKey: secretKey)
        return root?["MetricAlarms"] as? [[String: Any]]
    }

    /// The REASON an alarm's state changed ("Threshold Crossed: 1 datapoint
    /// [72.3] was greater than the threshold [70.0]"), off CloudWatch's own
    /// `HistoryItemType == StateUpdate` records. Deliberately NOT called from
    /// the main sweep — it costs one request PER alarm and most passes touch
    /// several alarms just to confirm nothing changed, so it is a diagnose-
    /// time-only read (`AWSIngest.diagnose`), not landed into a Thing.
    static func alarmHistory(alarm: String, region: String,
                             accessKeyID: String, secretKey: String) async
        -> [[String: Any]]? {
        let root = await jsonCall(
            host: "monitoring.\(region).amazonaws.com", region: region, service: "monitoring",
            target: "\(cloudWatchTargetPrefix).DescribeAlarmHistory",
            body: ["AlarmName": alarm], accessKeyID: accessKeyID, secretKey: secretKey)
        return root?["AlarmHistoryItems"] as? [[String: Any]]
    }

    // MARK: CodePipeline — JSON 1.1

    private static let codePipelineTargetPrefix = "CodePipeline_20150709"

    static func pipelineNames(region: String, accessKeyID: String, secretKey: String) async
        -> [String]? {
        let root = await jsonCall(
            host: "codepipeline.\(region).amazonaws.com", region: region, service: "codepipeline",
            target: "\(codePipelineTargetPrefix).ListPipelines", body: [:],
            accessKeyID: accessKeyID, secretKey: secretKey)
        let rows = root?["pipelines"] as? [[String: Any]]
        return rows?.compactMap { $0["name"] as? String }
    }

    /// One pipeline's executions, newest first — `ListPipelineExecutions`'
    /// documented order, and the assumption `AWSIngest.pipelineStanding`
    /// rests on (index 0 is the newest known status).
    static func pipelineExecutions(pipeline: String, region: String,
                                   accessKeyID: String, secretKey: String) async
        -> [[String: Any]]? {
        let root = await jsonCall(
            host: "codepipeline.\(region).amazonaws.com", region: region, service: "codepipeline",
            target: "\(codePipelineTargetPrefix).ListPipelineExecutions",
            body: ["pipelineName": pipeline],
            accessKeyID: accessKeyID, secretKey: secretKey)
        return root?["pipelineExecutionSummaries"] as? [[String: Any]]
    }

    // MARK: Cost Explorer — REGION-PINNED to us-east-1 regardless of the
    // account's chosen resource region. This is a real AWS quirk, not an
    // oversight: Cost Explorer has exactly one endpoint, in `us-east-1`, no
    // matter where the billed resources live.

    private static let costExplorerHost = "ce.us-east-1.amazonaws.com"
    private static let costExplorerTargetPrefix = "AWSInsightsIndexService"

    /// Daily unblended cost for the trailing `days` days (default 14, the
    /// baseline window). Three keys in the body (`TimePeriod` nesting two
    /// more) — the one call in this file whose JSON body isn't 0-or-1 keys;
    /// see `jsonCall`'s note on why that's still safe to sign here.
    static func dailyCosts(days: Int = 14, accessKeyID: String, secretKey: String) async
        -> [(date: String, amount: Double)]? {
        let end = Date()
        let start = Calendar(identifier: .gregorian).date(byAdding: .day, value: -days, to: end) ?? end
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(identifier: "UTC")
        let body: [String: Any] = [
            "TimePeriod": ["Start": df.string(from: start), "End": df.string(from: end)],
            "Granularity": "DAILY",
            "Metrics": ["UnblendedCost"],
        ]
        let root = await jsonCall(
            host: costExplorerHost, region: "us-east-1", service: "ce",
            target: "\(costExplorerTargetPrefix).GetCostAndUsage", body: body,
            accessKeyID: accessKeyID, secretKey: secretKey)
        guard let results = root?["ResultsByTime"] as? [[String: Any]] else { return nil }
        return results.compactMap { row -> (date: String, amount: Double)? in
            guard let period = row["TimePeriod"] as? [String: Any],
                  let start = period["Start"] as? String,
                  let total = row["Total"] as? [String: Any],
                  let unblended = total["UnblendedCost"] as? [String: Any],
                  let amountStr = unblended["Amount"] as? String,
                  let amount = Double(amountStr) else { return nil }
            return (date: start, amount: amount)
        }
    }

    // MARK: Resource inventory — EC2/RDS are Query/XML, S3 is REST/XML,
    // Lambda is REST/JSON. Only counts + a couple of identifying fields.

    static func ec2InstanceIDs(region: String, accessKeyID: String, secretKey: String) async
        -> [String]? {
        await queryXML(host: "ec2.\(region).amazonaws.com", region: region, service: "ec2",
                       query: ["Action": "DescribeInstances", "Version": "2016-11-15"],
                       tag: "instanceId", accessKeyID: accessKeyID, secretKey: secretKey)
    }

    static func rdsInstanceIDs(region: String, accessKeyID: String, secretKey: String) async
        -> [String]? {
        await queryXML(host: "rds.\(region).amazonaws.com", region: region, service: "rds",
                       query: ["Action": "DescribeDBInstances", "Version": "2014-10-31"],
                       tag: "DBInstanceIdentifier", accessKeyID: accessKeyID, secretKey: secretKey)
    }

    /// S3's global endpoint — `ListBuckets` is an account-wide list, not a
    /// per-bucket read, so it is signed against `us-east-1` against the
    /// classic `s3.amazonaws.com` host regardless of the person's chosen
    /// region, exactly like STS above.
    static func s3BucketNames(accessKeyID: String, secretKey: String) async -> [String]? {
        await queryXML(host: "s3.amazonaws.com", region: "us-east-1", service: "s3",
                       query: [:], tag: "Name", accessKeyID: accessKeyID, secretKey: secretKey)
    }

    static func lambdaFunctionNames(region: String, accessKeyID: String, secretKey: String) async
        -> [String]? {
        let host = "lambda.\(region).amazonaws.com"
        let path = "/2015-03-31/functions/"
        let query = ["MaxItems": "50"]
        let signed = AWSSigV4.sign(method: "GET", host: host, path: path, query: query,
                                   body: Data(), service: "lambda", region: region,
                                   accessKeyID: accessKeyID, secretKey: secretKey)
        let qs = AWSSigV4.canonicalQuery(query)
        let url = "https://\(host)\(path)?\(qs)"
        guard let root = await IngestSupport.getJSON(
            url, auth: signed.authorization,
            headers: ["X-Amz-Date": signed.amzDate], service: networkService) as? [String: Any]
        else { return nil }
        let rows = root["Functions"] as? [[String: Any]]
        return rows?.compactMap { $0["FunctionName"] as? String }
    }

    // MARK: - Transport

    /// One JSON-1.1 POST. The body is built ONCE by the caller and passed
    /// unchanged both to `AWSSigV4.sign` (which hashes it) and to
    /// `IngestSupport.postJSON` (which serializes it again to send it) —
    /// they must produce byte-identical output for the signature to verify.
    /// `JSONSerialization.data(withJSONObject:)` on the SAME `[String: Any]`
    /// value is deterministic within one process (Dictionary's hash seed is
    /// fixed per launch, and a value-copy of an unmutated dictionary keeps
    /// its storage layout), so this holds for a `let`-bound body reused
    /// as-is — every call site here does exactly that, and every body but
    /// Cost Explorer's is 0 or 1 key, where there is no ordering to disagree
    /// about at all. UNMEASURED end-to-end (no live key), so this is the
    /// engineering argument, not a live-verified guarantee.
    private static func jsonCall(host: String, region: String, service: String,
                                 target: String, body: [String: Any],
                                 accessKeyID: String, secretKey: String) async
        -> [String: Any]? {
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        let signed = AWSSigV4.sign(method: "POST", host: host, path: "/", query: [:],
                                   body: payload, service: service, region: region,
                                   accessKeyID: accessKeyID, secretKey: secretKey)
        return await IngestSupport.postJSON(
            "https://\(host)/", auth: signed.authorization, body: body,
            headers: [
                "X-Amz-Date": signed.amzDate,
                "X-Amz-Target": target,
                "Content-Type": "application/x-amz-json-1.1",
            ], service: networkService) as? [String: Any]
    }

    /// One Query-protocol GET, XML back — EC2's, RDS's and S3's shape. `tag`
    /// is the ONE element name this file needs out of the response (an
    /// instance/DB/bucket identifier) — a minimal reader by design (see
    /// `AWSXML`'s note), not a general XML→model mapper.
    private static func queryXML(host: String, region: String, service: String,
                                 query: [String: String], tag: String,
                                 accessKeyID: String, secretKey: String) async -> [String]? {
        let signed = AWSSigV4.sign(method: "GET", host: host, path: "/", query: query,
                                   body: Data(), service: service, region: region,
                                   accessKeyID: accessKeyID, secretKey: secretKey)
        let qs = AWSSigV4.canonicalQuery(query)
        let url = qs.isEmpty ? "https://\(host)/" : "https://\(host)/?\(qs)"
        let (text, _) = await xmlGET(url, signed: signed)
        guard let text else { return nil }
        return AWSXML.textValues(in: text, tags: [tag])[tag] ?? []
    }

    /// `IngestSupport` has no "GET text, with status" helper — only
    /// `getJSONStatus` (which tries to parse JSON, and every AWS XML body
    /// isn't) and `getText` (which has no status). Two requests rather than
    /// adding a new `IngestSupport` primitive for one bridge: the first
    /// (`getJSONResponse`, whose JSON parse is expected to fail on an XML
    /// body — only its `status` is read) answers whether it is worth asking
    /// again for the body via `getText`.
    private static func xmlGET(_ url: String, signed: AWSSigV4.Signed) async -> (String?, Int) {
        guard let u = URL(string: url) else { return (nil, 0) }
        let (_, status, _) = await IngestSupport.getJSONResponse(
            url, auth: signed.authorization, headers: ["X-Amz-Date": signed.amzDate],
            service: networkService)
        guard status == 200 else { return (nil, status) }
        let text = await IngestSupport.getText(
            u, headers: ["X-Amz-Date": signed.amzDate, "Authorization": signed.authorization],
            service: networkService)
        return (text, status)
    }
}

// MARK: - A minimal XML reader

/// The one thing this bridge needs from an XML body: every value of ONE
/// element name, wherever it occurs. Not a general parser — EC2/RDS/S3
/// responses are deeply nested and this only needs identifying fields, not a
/// full resource model (the task's own scope: "a couple of identifying
/// fields, not a full resource model"). Built on Foundation's `XMLParser`,
/// which is the only XML facility in this codebase (nothing else here parses
/// XML), so this is new ground and kept deliberately small.
final class AWSXML: NSObject, XMLParserDelegate {
    private var wanted: Set<String>
    private var current: String?
    private var buffer = ""
    private(set) var found: [String: [String]] = [:]

    private init(wanted: Set<String>) { self.wanted = wanted }

    func parser(_ parser: XMLParser, didStartElement name: String,
               namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        if wanted.contains(name) { current = name; buffer = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard current != nil else { return }
        buffer += string
    }

    func parser(_ parser: XMLParser, didEndElement name: String,
               namespaceURI: String?, qualifiedName: String?) {
        guard let current, current == name else { return }
        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { found[current, default: []].append(value) }
        self.current = nil
        buffer = ""
    }

    /// `tag → every value of that element found in the document`, or an
    /// empty dictionary on malformed XML — never a crash, matching every
    /// other reader here (`XMLParser` itself never throws on bad input, it
    /// simply stops parsing at the point of failure and reports what it
    /// already collected, which is the fail-safe behaviour this wants).
    static func textValues(in xmlText: String, tags: [String]) -> [String: [String]] {
        guard let data = xmlText.data(using: .utf8) else { return [:] }
        let delegate = AWSXML(wanted: Set(tags))
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        _ = parser.parse()
        return delegate.found
    }
}

// MARK: - The pass

@MainActor
enum AWSIngest {

    private static var running = false
    private(set) static var lastPassAlarm: String?

    /// How many pipelines one pass walks — a bound, not a target: each costs
    /// one more request, and most accounts here have a handful.
    static let pipelineCap = 15

    /// The trailing window Cost Explorer's baseline is computed over.
    static let costBaselineDays = 14
    /// A day's spend counts as an anomaly only when it is at least this many
    /// times the trailing MEDIAN — never the mean; see the file header.
    static let costAnomalyMultiplier = 2.0
    /// Below this the baseline is too small to be meaningful — a $0.02 → $0.06
    /// day is a 3x "anomaly" that is really just AWS's free-tier noise.
    static let costAnomalyFloor = 5.0

    static func refresh(context: ModelContext) async -> Int? {
        guard !running else { return 0 }
        guard AWSAuth.configured else { return nil }
        running = true
        defer { running = false }
        lastPassAlarm = nil

        let accessKeyID = AWSAuth.storedAccessKeyID
        guard let secretKey = AWSAuth.storedSecretKey else { return nil }
        let region = AWSAuth.region

        var landed: [Thing] = []
        var alarming: Set<String> = []
        var standing = AWSStanding.empty
        standing.region = region

        // CloudWatch — transitions land, current-ALARM set is standing.
        if let rows = await AWSFetch.alarms(region: region, accessKeyID: accessKeyID, secretKey: secretKey) {
            let firstSight = !AWSState.alarmsSeeded
            var seen = AWSState.alarmStates
            var inAlarm: [String] = []
            for row in rows {
                guard let name = row["AlarmName"] as? String, !name.isEmpty,
                      let state = row["StateValue"] as? String else { continue }
                if state == "ALARM" { inAlarm.append(name) }
                let previous = seen[name]
                seen[name] = state
                guard !firstSight, previous != state, previous != nil,
                      state == "ALARM" || state == "OK" else { continue }
                let thing = alarmThing(name: name, state: state, region: region)
                landed.append(thing)
                if state == "ALARM", let ref = thing.sourceRef { alarming.insert(ref) }
            }
            AWSState.alarmStates = seen
            AWSState.alarmsSeeded = true
            standing.alarmsInAlarm = inAlarm.sorted()
        }

        // CodePipeline — terminal executions land, newest-known status is
        // standing (pipelineStates).
        if let names = await AWSFetch.pipelineNames(region: region, accessKeyID: accessKeyID, secretKey: secretKey) {
            var states = AWSState.pipelineStates
            let existing = IngestSupport.existingSourceRefs(context, source: AWSShape.source)
            for name in names.prefix(pipelineCap) {
                guard let execs = await AWSFetch.pipelineExecutions(
                    pipeline: name, region: region, accessKeyID: accessKeyID, secretKey: secretKey)
                else { continue }
                // Newest first (AWS's documented order) — index 0 is the
                // pipeline's current standing whether or not it lands a row.
                if let newest = execs.first, let status = newest["status"] as? String {
                    states[name] = status
                    if status == "Failed" {
                        standing.lastFailedPipeline = name
                        standing.lastFailedPipelineWhen =
                            IngestSupport.isoDate(newest["lastUpdateTime"])
                    }
                }
                for row in execs {
                    guard let thing = pipelineThing(row, pipeline: name, region: region),
                          let ref = thing.sourceRef, !existing.contains(ref) else { continue }
                    landed.append(thing)
                    if (row["status"] as? String) == "Failed", let ref = thing.sourceRef {
                        alarming.insert(ref)
                    }
                }
            }
            AWSState.pipelineStates = states
        }

        // Cost Explorer — STATE every pass, an EVENT only on a real anomaly.
        if let costs = await AWSFetch.dailyCosts(
            days: costBaselineDays, accessKeyID: accessKeyID, secretKey: secretKey) {
            AWSState.costHistory = Dictionary(uniqueKeysWithValues: costs)
            if let (today, amount) = costs.last {
                let baseline = AWSCost.median(costs.dropLast().map(\.amount))
                standing.costToday = amount
                standing.costBaseline = baseline
                let previousAnomalyDay = AWSState.standing.costAnomalyDay
                if AWSCost.isAnomaly(today: amount, baseline: baseline,
                                     multiplier: costAnomalyMultiplier, floor: costAnomalyFloor) {
                    // Land a Thing only the FIRST time this day crosses —
                    // every later pass the same day sees the same anomaly
                    // and must not re-alert on it (dedupe by day, not just
                    // by `sourceRef`, since the ref itself is keyed on the
                    // day and would collide anyway; this guard is what keeps
                    // `alarming` — and so the sync screen's flash — from
                    // firing again on a pass that landed nothing new).
                    if previousAnomalyDay != today {
                        let thing = costAnomalyThing(day: today, amount: amount, baseline: baseline)
                        landed.append(thing)
                        if let ref = thing.sourceRef { alarming.insert(ref) }
                    }
                    standing.costAnomalyDay = today
                } else {
                    // Preserve the flag only while it's still describing
                    // TODAY — once the day rolls over an old anomaly is
                    // history, not standing.
                    standing.costAnomalyDay = (previousAnomalyDay == today) ? today : nil
                }
            }
        }

        // Resource inventory — counts ONLY, never a `Thing`.
        async let ec2 = AWSFetch.ec2InstanceIDs(region: region, accessKeyID: accessKeyID, secretKey: secretKey)
        async let s3  = AWSFetch.s3BucketNames(accessKeyID: accessKeyID, secretKey: secretKey)
        async let rds = AWSFetch.rdsInstanceIDs(region: region, accessKeyID: accessKeyID, secretKey: secretKey)
        async let lambda = AWSFetch.lambdaFunctionNames(region: region, accessKeyID: accessKeyID, secretKey: secretKey)
        let (ec2Rows, s3Rows, rdsRows, lambdaRows) = await (ec2, s3, rds, lambda)
        standing.ec2Count = ec2Rows?.count ?? 0
        standing.s3Count = s3Rows?.count ?? 0
        standing.rdsCount = rdsRows?.count ?? 0
        standing.lambdaCount = lambdaRows?.count ?? 0
        standing.lastRead = .now

        AWSState.standing = standing

        let inserted = insert(landed, context: context)
        lastPassAlarm = inserted.first { alarming.contains($0.sourceRef ?? "") }?.title
        return inserted.count
    }

    // MARK: Shaping

    private static func alarmThing(name: String, state: String, region: String) -> Thing {
        let title = state == "ALARM"
            ? String(localized: "Alarm · \(name)")
            : String(localized: "Cleared · \(name)")
        let thing = Thing(
            kind: .link,
            title: IngestSupport.titleLine(title),
            // The literal host FIRST, region as a query param — never
            // `\(region).console…`, which `network-reach-audit.sh`'s
            // built-at-runtime check would read as a fetched host family
            // rather than the permalink this is (opened in the browser,
            // never called by the app).
            content: "https://console.aws.amazon.com/cloudwatch/home?region=\(region)#alarmsV2:alarm/\(name)",
            source: AWSShape.source,
            capturedAt: .now,
            tags: [String(localized: "Alarm")],
            // The STATE rides the ref, so an alarm that flaps ALARM→OK→ALARM
            // keeps every transition as its own row rather than one that
            // silently rewrites (the ASC version-ref shape).
            sourceRef: "aws:alarm:\(name):\(state):\(Int(Date().timeIntervalSince1970))"
        )
        return thing
    }

    private static func pipelineThing(_ row: [String: Any], pipeline: String, region: String) -> Thing? {
        guard let id = row["pipelineExecutionId"] as? String, !id.isEmpty,
              let status = row["status"] as? String,
              status == "Succeeded" || status == "Failed" || status == "Superseded"
        else { return nil }
        // The outcome LEADS on a failure — `IngestSupport.titleLine`'s 80-char
        // clamp eats whatever is at the END of a title, and a failed deploy
        // reading as a success is the fake status §83 bans (Cursor's/ASC's
        // rule, restated here rather than shared, since the three bridges
        // have no common status type to hang one function off).
        let title = status == "Failed"
            ? String(localized: "Failed · \(pipeline)")
            : (status == "Superseded"
               ? String(localized: "Superseded · \(pipeline)")
               : pipeline)
        let thing = Thing(
            kind: .link,
            title: IngestSupport.titleLine(title),
            content: "https://console.aws.amazon.com/codesuite/codepipeline/pipelines/\(pipeline)/executions/\(id)/timeline?region=\(region)",
            source: AWSShape.source,
            capturedAt: IngestSupport.isoDate(row["lastUpdateTime"]) ?? .now,
            // `status` is a RUNTIME value from CodePipeline's own API
            // (Succeeded/Failed/Superseded), not a compile-time literal, so
            // it rides as-is rather than through `String(localized:)` — a
            // stable, unlocalized tag, the Cursor `facetTag` shape.
            tags: [String(localized: "Deploy"), status],
            sourceRef: "aws:pipeline:\(id)"
        )
        thing.authorHandle = pipeline
        return thing
    }

    private static func costAnomalyThing(day: String, amount: Double, baseline: Double) -> Thing {
        let thing = Thing(
            kind: .reminder,
            title: IngestSupport.titleLine(
                String(localized: "Spend anomaly · \(AWSCost.dollars(amount))")),
            content: "https://console.aws.amazon.com/cost-management/home#/cost-explorer",
            source: AWSShape.source,
            capturedAt: .now,
            tags: [String(localized: "Cost")],
            sourceRef: "aws:costanomaly:\(day)"
        )
        thing.summary = String(localized:
            "\(AWSCost.dollars(amount)) on \(day), against a typical \(AWSCost.dollars(baseline)).")
        return thing
    }

    @MainActor
    private static func insert(_ incoming: [Thing], context: ModelContext) -> [Thing] {
        let existing = IngestSupport.existingSourceRefs(context, source: AWSShape.source)
        var added: [Thing] = []
        var landedRefs: Set<String> = []
        for item in incoming {
            guard let ref = item.sourceRef,
                  !existing.contains(ref), landedRefs.insert(ref).inserted else { continue }
            context.insert(item)
            SpotlightIndex.index([item])
            added.append(item)
        }
        if !added.isEmpty { context.saveHonestly() }
        return added
    }

    // MARK: - Probe

    /// `-awsProbe YES` — the read, phase by phase, with the STORED
    /// credentials. An empty AWS room has several causes that render as one
    /// nothing: no key pair, a refused key pair, an IAM policy that can see
    /// some services and not others (each read here is independent — a role
    /// that can't see CodePipeline still lands CloudWatch and the inventory),
    /// a genuinely quiet account, or shape drift in a doc-derived field map.
    /// Only the last is a bug.
    static func diagnose() async {
        guard AWSAuth.configured else {
            NSLog("[Casberi] aws| no key pair stored — set both first (-awsKey / -awsSecret)")
            return
        }
        let accessKeyID = AWSAuth.storedAccessKeyID
        guard let secretKey = AWSAuth.storedSecretKey else { return }
        let region = AWSAuth.region
        NSLog("[Casberi] aws| region=%@ accessKeyID=%@…", region, String(accessKeyID.prefix(4)))

        let identity = await AWSFetch.callerIdentity(accessKeyID: accessKeyID, secretKey: secretKey)
        NSLog("[Casberi] aws| GetCallerIdentity HTTP %d account=%@ arn=%@",
              identity.status, identity.account.isEmpty ? "—" : identity.account,
              identity.arn.isEmpty ? "—" : identity.arn)
        guard identity.status == 200 else {
            if identity.status == 0 {
                NSLog("[Casberi] aws| unreachable — offline, or DNS")
            } else {
                NSLog("[Casberi] aws| the key pair was refused (HTTP %d) — check both values and that the IAM user is active",
                      identity.status)
            }
            return
        }

        let alarms = await AWSFetch.alarms(region: region, accessKeyID: accessKeyID, secretKey: secretKey)
        NSLog("[Casberi] aws| CloudWatch alarms=%@", alarms.map { String($0.count) } ?? "READ FAILED (permission?)")
        for row in (alarms ?? []).prefix(10) {
            let name = (row["AlarmName"] as? String) ?? "—"
            NSLog("[Casberi] awsAlarm| %@ state=%@", name, (row["StateValue"] as? String) ?? "—")
        }
        // DescribeAlarmHistory, for the FIRST alarm only — one extra request,
        // exercised here rather than in the sweep (see the function's note).
        if let firstAlarm = (alarms ?? []).first?["AlarmName"] as? String {
            let history = await AWSFetch.alarmHistory(
                alarm: firstAlarm, region: region, accessKeyID: accessKeyID, secretKey: secretKey)
            NSLog("[Casberi] aws| DescribeAlarmHistory(%@) items=%@", firstAlarm,
                  history.map { String($0.count) } ?? "READ FAILED")
            if let summary = history?.first?["HistorySummary"] as? String {
                NSLog("[Casberi] aws| most recent: %@", summary)
            }
        }

        let pipelines = await AWSFetch.pipelineNames(region: region, accessKeyID: accessKeyID, secretKey: secretKey)
        NSLog("[Casberi] aws| CodePipeline pipelines=%@", pipelines.map { String($0.count) } ?? "READ FAILED (permission?)")
        for name in (pipelines ?? []).prefix(5) {
            let execs = await AWSFetch.pipelineExecutions(
                pipeline: name, region: region, accessKeyID: accessKeyID, secretKey: secretKey)
            NSLog("[Casberi] awsPipeline| %@ executions=%@", name,
                  execs.map { String($0.count) } ?? "READ FAILED")
            for row in (execs ?? []).prefix(3) {
                NSLog("[Casberi] awsExecution| %@ status=%@ id=%@", name,
                      (row["status"] as? String) ?? "—",
                      (row["pipelineExecutionId"] as? String) ?? "—")
            }
        }

        let costs = await AWSFetch.dailyCosts(accessKeyID: accessKeyID, secretKey: secretKey)
        if let costs {
            NSLog("[Casberi] aws| Cost Explorer days=%d", costs.count)
            for (date, amount) in costs.suffix(7) {
                NSLog("[Casberi] awsCost| %@ %@", date, AWSCost.dollars(amount))
            }
            if let (today, amount) = costs.last {
                let baseline = AWSCost.median(costs.dropLast().map(\.amount))
                NSLog("[Casberi] aws| today=%@ baseline=%@ anomaly=%@", today,
                      AWSCost.dollars(baseline),
                      AWSCost.isAnomaly(today: amount, baseline: baseline,
                                        multiplier: costAnomalyMultiplier,
                                        floor: costAnomalyFloor) ? "YES" : "no")
            }
        } else {
            NSLog("[Casberi] aws| Cost Explorer READ FAILED (permission? Cost Explorer must be enabled once in the console)")
        }

        async let ec2 = AWSFetch.ec2InstanceIDs(region: region, accessKeyID: accessKeyID, secretKey: secretKey)
        async let s3  = AWSFetch.s3BucketNames(accessKeyID: accessKeyID, secretKey: secretKey)
        async let rds = AWSFetch.rdsInstanceIDs(region: region, accessKeyID: accessKeyID, secretKey: secretKey)
        async let lambda = AWSFetch.lambdaFunctionNames(region: region, accessKeyID: accessKeyID, secretKey: secretKey)
        let (ec2Rows, s3Rows, rdsRows, lambdaRows) = await (ec2, s3, rds, lambda)
        NSLog("[Casberi] aws| inventory EC2=%@ S3=%@ RDS=%@ Lambda=%@",
              ec2Rows.map { String($0.count) } ?? "READ FAILED",
              s3Rows.map { String($0.count) } ?? "READ FAILED",
              rdsRows.map { String($0.count) } ?? "READ FAILED",
              lambdaRows.map { String($0.count) } ?? "READ FAILED")
    }
}

// MARK: - Cost arithmetic (pure)

enum AWSCost {
    /// The trailing baseline — MEDIAN, never the mean. `StripeSilence.verdict`
    /// is the standing lesson: a burst (one very expensive day) drags a mean
    /// up and hides the next real anomaly against it, where the median stays
    /// put. Even count averages the two middle values; empty returns 0.
    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// True only when today's spend is BOTH a real multiple of the baseline
    /// AND large enough in absolute terms to matter — the floor exists so a
    /// $0.02 → $0.06 day (real, on a near-empty account) never reads as an
    /// anomaly, the same over-eager-signal problem `StripeSilence` solved by
    /// requiring a minimum payment count before trusting a gap.
    static func isAnomaly(today: Double, baseline: Double, multiplier: Double, floor: Double) -> Bool {
        guard today >= floor else { return false }
        guard baseline > 0 else { return today >= floor }
        return today >= baseline * multiplier
    }

    static func dollars(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }
}

// MARK: - Shaping constants

enum AWSShape {
    static let source = "AWS"
}

// MARK: - The seat

enum AWSWatch {
    @MainActor
    static func registerBridge(store: BridgeStore) {
        guard AWSAuth.configured else {
            store.remove(TokenBridge.aws.bridgeID)
            return
        }
        let standing = AWSState.standing
        let proof = standing.region
        store.registerConnected(
            id: TokenBridge.aws.bridgeID, name: AWSShape.source,
            proof: proof,
            can: [TokenBridge.aws.canLine])
    }
}
