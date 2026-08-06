import Foundation
import SwiftData

/// The token bridges (2026-07-07) — Readwise, GitHub, Todoist, Raindrop.
/// Each of these apps hands its users a personal access token in settings;
/// pasting it here is the sanctioned client-side way in — no OAuth server,
/// no secrets of ours to hold. The token goes to the Keychain (TokenVault)
/// and every fetch goes straight from this iPhone to the app's own API.
enum TokenBridge: String, CaseIterable, Identifiable {
    case readwise = "Readwise"
    case github   = "GitHub"
    case todoist  = "Todoist"
    case raindrop = "Raindrop"
    case calcom   = "Cal.com"
    case calendly = "Calendly"
    case notion   = "Notion"
    case linear   = "Linear"
    case bitrefill = "Bitrefill"
    case privacy  = "Privacy"
    case oneclaw  = "1Claw"
    case posthog  = "PostHog"
    case stripe   = "Stripe"
    case trello   = "Trello"
    case cloudflare = "Cloudflare"
    case cursor   = "Cursor"
    case sentry   = "Sentry"
    case vercel   = "Vercel"
    case pagerduty = "PagerDuty"

    var id: String { rawValue }

    /// BridgeStore id, and the connected-strip route.
    var bridgeID: String {
        switch self {
        case .readwise: "readwise"
        case .github:   "github"
        case .todoist:  "todoist"
        case .raindrop: "raindrop"
        case .calcom:   "calcom"
        case .calendly: "calendly"
        case .notion:   "notion"
        case .linear:   "linear"
        case .bitrefill: "bitrefill"
        case .privacy:  "privacy"
        case .oneclaw:  "oneclaw"
        case .posthog:  "posthog"
        case .stripe:   "stripe"
        case .trello:   "trello"
        case .cloudflare: "cloudflare"
        case .cursor:   "cursor"
        case .sentry:   "sentry"
        case .vercel:   "vercel"
        case .pagerduty: "pagerduty"
        }
    }

    var tokenKey: String { "token.\(bridgeID)" }
    var connected: Bool { TokenVault.get(tokenKey) != nil }

    /// Step one, as a door instead of a sentence (prd §218, 2026-07-25).
    ///
    /// Every one of these screens used to open with "Open &lt;url&gt;…" set in
    /// body text — an instruction to do something the app was perfectly able
    /// to do for you, and which you then retyped into Safari by hand. It's now
    /// the screen's one filled slab, and `steps` below picks up from step two.
    /// The URL is the page the copy already named, never a guess: each was
    /// checked live 2026-07-25 (`bitrefill.com` answers curl with a 403 from
    /// its bot filter, not a 404 — it's the address its own docs give).
    var setupURL: URL? {
        switch self {
        case .readwise:  URL(string: "https://readwise.io/access_token")
        case .github:    URL(string: "https://github.com/settings/tokens")
        case .todoist:   URL(string: "https://app.todoist.com/app/settings/integrations/developer")
        case .raindrop:  URL(string: "https://app.raindrop.io/settings/integrations")
        case .calcom:    URL(string: "https://app.cal.com/settings/developer/api-keys")
        case .calendly:  URL(string: "https://calendly.com/integrations/api_webhooks")
        case .notion:    URL(string: "https://www.notion.so/my-integrations")
        case .linear:    URL(string: "https://linear.app/settings/api")
        case .bitrefill: URL(string: "https://www.bitrefill.com/account/developers")
        case .privacy:   URL(string: "https://app.privacy.com/account")
        case .oneclaw:   URL(string: "https://1claw.xyz")
        case .posthog:   URL(string: "https://us.posthog.com/settings/user-api-keys")
        case .stripe:    URL(string: "https://dashboard.stripe.com/apikeys")
        // Trello's FIRST door only (the API key). Its second door — the
        // authorize page that mints the token — can't live here: it has to
        // carry the key you just pasted, so `TokenSetupScreen` builds it from
        // `TrelloAuth.authorizeURL(key:)` instead. See `TrelloAuth`.
        case .trello:    URL(string: "https://trello.com/power-ups/admin")
        case .cloudflare: URL(string: "https://dash.cloudflare.com/profile/api-tokens")
        // The dashboard ROOT, not the API-keys tab, and that is deliberate
        // imprecision: Cursor's current docs put the key at
        // `cursor.com/dashboard/api` while an older revision of the same page
        // says `/dashboard/integrations`, and this bridge has never been run
        // against a live account (see `CursorFetch`). A door that 404s is worse
        // than one that needs a tab click, so this opens the page that
        // certainly exists and `setupURLLabel` names the tab to look for.
        case .cursor:    URL(string: "https://cursor.com/dashboard")
        // The token page is per-organization and its URL carries the org slug,
        // which isn't known until after the token exists — so this is the
        // account-wide page, which is where Sentry's own docs send you and
        // works whatever your org is called.
        case .sentry:    URL(string: "https://sentry.io/settings/account/api/auth-tokens/")
        case .vercel:    URL(string: "https://vercel.com/account/settings/tokens")
        // PagerDuty's REST keys are an ACCOUNT setting, not a user one, and
        // the two live on different pages — this is the one where the
        // read-only checkbox is.
        case .pagerduty: URL(string: "https://pagerduty.com/api_keys")
        }
    }

    /// The door's words — where you're going, not what you'll do there. The
    /// host and path, so the button is checkable against the address bar it
    /// opens.
    var setupURLLabel: String {
        switch self {
        case .readwise:  "readwise.io/access_token"
        case .github:    "github.com/settings/tokens"
        case .todoist:   "Todoist → Integrations → Developer"
        case .raindrop:  "raindrop.io → For Developers"
        case .calcom:    "cal.com → API keys"
        case .calendly:  "Calendly → API & Webhooks"
        case .notion:    "notion.so/my-integrations"
        case .linear:    "linear.app → API keys"
        case .bitrefill: "bitrefill.com → Developers"
        case .privacy:   "privacy.com → account"
        case .oneclaw:   "1claw.xyz"
        case .posthog:   "posthog.com → personal API keys"
        case .stripe:    "dashboard.stripe.com → API keys"
        case .trello:    "trello.com → Power-Ups admin"
        case .cloudflare: "dash.cloudflare.com → API tokens"
        case .cursor:    "cursor.com → Dashboard → API Keys"
        case .sentry:    "sentry.io → Settings → Auth Tokens"
        case .vercel:    "vercel.com → Settings → Tokens"
        case .pagerduty: "pagerduty.com → Integrations → API Access Keys"
        }
    }

    /// What's left after the door — stated plainly, step by step, and numbered
    /// from TWO on screen, because opening the page really was step one.
    /// Nothing was deleted here: what the old first step said beyond "open
    /// the page" moved into the step that follows it.
    ///
    /// A step never re-types the field beneath it (§220). Cal.com's and 1Claw's
    /// steps used to spell out the key prefix — "it starts with cal_live_",
    /// "it starts with ocv_" — which is exactly what `placeholder` shows a line
    /// lower (audit, 2026-07-31).
    var steps: [String] {
        switch self {
        case .readwise: [
            "Sign in if asked — the token appears on the page.",
            "Copy it and paste it below."]
        case .github: [
            "Generate a token with read-only access to your repositories, gists, and profile — enough for every feed.",
            "Copy it and paste it below."]
        case .todoist: [
            "Copy the API token shown there.",
            "Paste it below."]
        case .raindrop: [
            "Create an app, then copy its Test token.",
            "Paste it below."]
        case .calcom: [
            "Add a new key.",
            "Copy it and paste it below."]
        case .calendly: [
            "Generate a personal access token.",
            "Copy it and paste it below."]
        case .notion: [
            "Create an internal integration and copy its Internal Integration Secret.",
            "In Notion, open each page you want here → ⋯ → Connections → add your integration. Only connected pages land."]
        case .linear: [
            "Create a key — read access is enough.",
            "Copy it and paste it below."]
        case .bitrefill: [
            "In the API Keys tab, create a key — any name works.",
            "Copy it and paste it below."]
        case .privacy: [
            "Generate an API key (a paid Privacy plan is required).",
            "Copy it and paste it below."]
        case .oneclaw: [
            "Sign in, then create an agent (or open one) and copy its API key.",
            "Paste it below."]
        // The three scopes are NOT named here — the checklist directly beneath
        // this step is the list, the same fix Stripe took the day before
        // (§220, "a step that was already on screen twice"; audit 2026-07-31).
        case .posthog: [
            "Create a personal API key and tick only these scopes:",
            "Copy it and paste it below — then pick which project to read."]
        // The six scopes are NOT named here — the checklist directly beneath
        // this step is the list, and naming them twice on one screen is §220's
        // "a step that was already on screen twice" (user, seeing the built
        // screen: "THAT IS A LOT OF TEXT ON THE STRIPE PAGE", 2026-07-31).
        // Same for the test-mode refusal, which the placeholder shows and the
        // failure sentence explains at the moment it actually matters.
        case .stripe: [
            "Create a RESTRICTED key with only these reads:",
            "Copy it and paste it below."]
        // Trello's steps are the SECOND stage only — the key stage carries its
        // own (`TokenSetupScreen.trelloKeySection`), because this bridge is the
        // one here that needs two pastes. The scope is not named in a step: the
        // authorize link above it is one Casberi builds with `scope=read`, and
        // the note under the field says so once (§220 — a step never re-types
        // what is already on screen).
        case .trello: [
            "Allow — Trello shows a token on the page.",
            "Copy it and paste it below."]
        // The permissions ARE named here, unlike PostHog's and Stripe's, and
        // that is not a §220 slip: those two own their own screens and render a
        // `DSCheckList` under the step, so naming them twice would be the thing
        // §220 forbids. A `.token` bridge renders `TokenSetupScreen`, which has
        // no checklist — so the step is the only place this can be said, and
        // leaving it unsaid means someone mints a token with the wrong reach.
        // Cloudflare's own template is named rather than four permission rows
        // spelled out, because a template is one click and cannot be mistyped.
        case .cloudflare: [
            "Create a token from the Read all resources template — or any token whose permissions are all Read.",
            "Copy it and paste it below."]
        // No scope to choose, and the steps deliberately don't pretend there
        // is one: Cursor's keys carry no permissions at all (see
        // `CursorFetch`). What that means is said once, in `canLine`, which is
        // the line about trust — not repeated here as an instruction nobody
        // can act on (§220).
        case .cursor: [
            "Create an API key — the one Cloud Agents use.",
            "Copy it and paste it below."]
        // The three scopes are NOT named here — Sentry owns its own screen and
        // renders a `DSCheckList` under this step, so naming them twice is
        // §220's "a step that was already on screen twice" (the PostHog and
        // Stripe precedent).
        case .sentry: [
            "Create a token with only these scopes:",
            "Copy it and paste it below — then pick which organization to read."]
        // No scope to choose, and no pretending otherwise: a Vercel token is
        // account-wide (see `VercelFetch`). What that means is said once, in
        // `canLine`.
        case .vercel: [
            "Create a token — scope it to the team whose deployments you want.",
            "Copy it and paste it below."]
        // The read-only box IS named here, unlike PostHog's and Stripe's
        // checklists, because a `.token` bridge renders `TokenSetupScreen`,
        // which has no checklist — so this step is the only place it can be
        // said, and leaving it unsaid means minting a key that can page
        // everyone in the company (the Cloudflare reasoning).
        case .pagerduty: [
            "Create a General Access REST API Key and tick Read-only.",
            "Copy it and paste it below."]
        }
    }

    var placeholder: String {
        switch self {
        case .readwise: "Access token"
        case .github:   "github_pat_…"
        case .todoist:  "API token"
        case .raindrop: "Test token"
        case .calcom:   "cal_live_…"
        case .calendly: "Personal access token"
        case .notion:   "ntn_…"
        case .linear:   "lin_api_…"
        case .bitrefill: "API key"
        case .privacy:  "API key"
        case .oneclaw:  "ocv_…"
        case .posthog:  "phx_…"
        case .stripe:   "rk_live_…"
        case .trello:   "Token"
        case .cloudflare: "API token"
        // No prefix shown. `crsr_` is documented for Cursor's ADMIN keys and
        // it is unverified whether a Cloud Agents key wears it — a placeholder
        // that shows the wrong prefix reads as a validation rule and would
        // have someone believing a perfectly good key is the wrong one.
        case .cursor:   "API key"
        case .sentry:   "sntryu_…"
        // No prefix. Vercel's tokens are an opaque random string with no
        // documented prefix at all, and inventing one would read as a
        // validation rule (the Cursor reasoning).
        case .vercel:   "Token"
        case .pagerduty: "API key"
        }
    }

    /// What this bridge calls the thing you pasted — for the connected
    /// state's line about how it's connected (prd §186). Each venue's own
    /// word, the way `placeholder` and `steps` already are: telling someone
    /// their "key" is stored when the site called it a secret is a small lie
    /// that costs trust on the one screen that's about trust.
    var credentialNoun: String {
        switch self {
        case .readwise: "access token"
        case .github:   "personal access token"
        case .todoist:  "API token"
        case .raindrop: "test token"
        case .calcom:   "API key"
        case .calendly: "personal access token"
        case .notion:   "integration secret"
        case .linear:   "API key"
        case .bitrefill: "API key"
        case .privacy:  "API key"
        case .oneclaw:  "agent key"
        case .posthog:  "personal API key"
        case .stripe:   "restricted key"
        case .trello:   "token"
        case .cloudflare: "API token"
        case .cursor:   "API key"
        case .sentry:   "auth token"
        case .vercel:   "token"
        case .pagerduty: "API key"
        }
    }

    /// What lands, for proof lines: "12 highlights in".
    var noun: String {
        switch self {
        case .readwise: "highlights"
        case .github:   "items"
        case .todoist:  "tasks"
        case .raindrop: "bookmarks"
        case .calcom:   "bookings"
        case .calendly: "meetings"
        case .notion:   "pages"
        case .linear:   "issues"
        case .bitrefill: "orders"
        case .privacy:  "purchases"
        case .oneclaw:  "grants"
        case .posthog:  "updates"
        case .stripe:   "updates"
        case .trello:   "cards"
        case .cloudflare: "alerts"
        case .cursor:   "runs"
        case .sentry:   "issues"
        case .vercel:   "deploys"
        case .pagerduty: "incidents"
        }
    }

    /// The connect screen's ONE sentence (prd §315) — what pasting a token
    /// gets you, and the strongest true promise about what it can't do.
    ///
    /// It is deliberately NOT `canLine`. That sentence is the CONNECTED
    /// state's capability line, written to be read beside the things it
    /// describes, and several run to sixty words (Cursor's names four verbs;
    /// Sentry's names four kinds of data it never touches). A connect page has
    /// one sentence of prose, so this states the read-only promise in the form
    /// that is actually true for THIS bridge and stops.
    ///
    /// Three grades of promise, and the wording tracks which one applies —
    /// getting this wrong would be exactly the fake status §83 bans:
    ///   · MINTED — Casberi builds the authorize link with `scope=read`, so
    ///     the service issues a token with no write permission to give
    ///     (Trello alone).
    ///   · SCOPED — the person ticks read-only on the service's own page, and
    ///     the token cannot write whatever this app does (most of them).
    ///   · CONDUCT — the key carries no scopes at all, so the promise is kept
    ///     by what the code does and nothing else (Privacy, Cursor, Vercel).
    ///     These say "only ever reads" rather than "read-only", because the
    ///     restriction is ours, not the token's.
    var setupIntro: String {
        switch self {
        case .readwise:
            String(localized: "Paste a read-only token and every highlight you've saved becomes searchable here, arriving on its own from then on.")
        case .github:
            String(localized: "Sign in with GitHub — or paste a token — and the feeds you pick keep arriving, plus any repo you watch. Watching here is private: it never touches your GitHub account.")
        case .todoist:
            String(localized: "Paste a read-only token and your open tasks keep arriving with their due dates. Nothing here completes, edits, or adds a task.")
        case .raindrop:
            String(localized: "Paste a read-only token and your bookmarks keep arriving, searchable alongside everything else. Nothing here adds or deletes one.")
        case .calcom:
            String(localized: "Paste a read-only key and your bookings keep arriving before they happen. Nothing here books, moves, or cancels anything.")
        case .calendly:
            String(localized: "Paste a read-only token and your scheduled meetings keep arriving before they happen. Nothing here books, moves, or cancels anything.")
        case .notion:
            String(localized: "Paste an integration secret and only the pages you explicitly connect arrive — Notion decides what it can see, not us. Nothing here edits a page.")
        case .linear:
            String(localized: "Paste a read-only key and the issues assigned to you keep arriving. Nothing here comments, closes, or moves an issue.")
        case .bitrefill:
            String(localized: "Paste a read-only key and your orders and refills keep arriving, with your balance beside them. Nothing here ever buys, pays, or spends.")
        case .privacy:
            // CONDUCT. Privacy's key can issue cards and move money; the
            // promise is what this code does, so it is worded as such.
            String(localized: "Paste an API key and what you spend on your virtual cards keeps arriving. Privacy's key can't be scoped read-only, so the promise is ours to keep: Casberi only ever reads transactions, and never creates, closes, or funds a card.")
        case .oneclaw:
            String(localized: "Paste an agent key and you'll see what it can reach — which vaults, which secret paths, and when each grant expires. Names and permissions only: no secret's value is ever read.")
        case .posthog:
            String(localized: "Paste a read-only key, watch the metrics you care about, and only what's news arrives: a milestone crossed, a metric falling silent, a deploy you annotated.")
        case .stripe:
            String(localized: "Paste a read-only key and the money that needs you keeps arriving — a dispute and its deadline, a payout, a cancelled subscription, a failed payment.")
        case .trello:
            // MINTED — the strongest promise in the catalog, and the only one
            // that is structural rather than a box someone ticked.
            String(localized: "Authorize once and the cards assigned to you keep arriving with their due dates. Casberi asks Trello for a read-only token, so the one it issues has no write permission to give.")
        case .cloudflare:
            String(localized: "Paste a read-only token and you're told before a certificate, domain or token expires, and when a DNS record changes. No analytics, and nothing about your visitors.")
        case .cursor:
            // CONDUCT, and the weakest grade here: this key could start an
            // agent, which spends money AND writes a branch to a repo.
            String(localized: "Paste a key and your finished cloud agents keep arriving — what each was asked to do, what it says it did, and the pull request it opened. Cursor's key can't be scoped read-only, so the promise is ours to keep: Casberi only ever lists them.")
        case .sentry:
            String(localized: "Paste a read-only token and three things arrive: an issue that's new, one that regressed, one that escalated. Never an event, a stack trace, or anything about the person who hit it.")
        case .vercel:
            // CONDUCT.
            String(localized: "Paste a token and your deployments keep arriving — what shipped, what broke, and the commit behind it. Vercel's token can't be scoped read-only, so the promise is ours to keep: Casberi only ever lists them, and never reads your environment variables.")
        case .pagerduty:
            String(localized: "Paste a read-only key and your incidents keep arriving — what fired, how urgent, and when it was resolved. Nothing here pages anyone, acknowledges, or resolves.")
        }
    }

    var canLine: String {
        switch self {
        case .readwise: "Reads your highlights."
        // Two deletions, both because the connected GitHub screen renders this
        // sentence directly above the things it was describing (audit,
        // 2026-07-31): the seven feeds were the seven switch rows beneath it,
        // and "never touching your GitHub account" is the private-watch field's
        // own slab note verbatim. "Privately" carries what's left.
        case .github:   "Reads the GitHub feeds you pick, plus any repos you watch privately."
        case .todoist:  "Reads your open tasks."
        case .raindrop: "Reads your bookmarks."
        case .calcom:   "Reads your bookings."
        case .calendly: "Reads your scheduled meetings."
        case .notion:   "Reads the pages you connect."
        case .linear:   "Reads issues assigned to you."
        case .bitrefill: "Reads your orders, refills, and balance — nothing here ever buys, pays, or spends."
        case .privacy:  "Reads your card transactions only. Privacy's key can't be scoped read-only, so the promise is kept by conduct: Casberi never creates, closes, or funds a card."
        case .oneclaw:  "Reads which vaults and secret paths the key can reach — names and permissions only. Nothing here ever reads a secret's value, signs, or spends."
        case .posthog:  "Reads the metrics you watch and your project's annotations. The key is scoped read-only — it cannot ship a flag, edit a dashboard, or write anything back."
        case .stripe:   "Reads disputes, payouts, canceled subscriptions, failed payments, and your balance. The restricted key is read-only — it cannot refund, charge, or pay out."
        // The read-only promise here is the strongest of any bridge in this
        // file, because Casberi MINTS it rather than asking you to: the
        // authorize link is built with `scope=read`, so Trello itself issues a
        // token that has no write permission to give. Every other keyed bridge
        // depends on the person ticking the right box on someone else's page.
        case .trello:   "Reads the cards assigned to you and when they're due. Casberi asks Trello for a read-only token — it cannot move a card, comment, or write anything back."
        // What is NOT read is worth a clause here. Cloudflare's API is mostly
        // traffic numbers, and someone connecting an infrastructure account has
        // every right to wonder whether their visitors' data is about to land
        // in a feed.
        case .cloudflare: "Reads certificate, domain and token expiry dates, and tells you when a DNS record changes. No analytics, nothing about your visitors. A read-only token cannot change a record or purge cache."
        // The Privacy.com sentence, one rung stronger, because the risk is one
        // rung higher: Cursor's key carries no scopes at all, and the thing it
        // could do unasked isn't just spending — it's spending AND writing a
        // branch to your repository. Naming the four verbs Casberi doesn't use
        // is the whole promise, so they're listed rather than summarised. If a
        // write is ever added to `CursorFetch`, this line has to change in the
        // same commit.
        case .cursor:   "Reads the cloud agents you've run — what each was asked to do, what it says it did, and the pull request it opened. Cursor's key can't be scoped read-only, so the promise is kept by conduct: Casberi only ever lists your agents, and never starts one, follows one up, stops one, or deletes one."
        // What is NOT read is the load-bearing clause. Sentry holds the data
        // your users generated when something broke — anyone connecting it has
        // every right to ask whether that is about to land in a feed. It isn't:
        // this reads the ISSUE list, which is titles and code locations, and
        // never an event, a stack trace, a request body, or a user.
        case .sentry:   "Reads your unresolved issues — the error, the project, and where in your code it happened. Never an event, a stack trace, or anything about the person who hit it. The token is scoped read-only: it cannot resolve an issue, comment, or change a project."
        case .vercel:   "Reads your deployments — the project, whether each one shipped or broke, and its commit message. Vercel's token can't be scoped read-only, so the promise is kept by conduct: Casberi only ever lists deployments, and never deploys, promotes, rolls back, cancels, or deletes one. It never reads your environment variables."
        case .pagerduty: "Reads your incidents — what fired, on which service, how urgent, and when it was resolved. A read-only key cannot page anyone, acknowledge, resolve, or reassign."
        }
    }

    /// What an EMPTY but SUCCESSFUL read means, for the bridges where empty is
    /// a state worth explaining rather than good news (2026-08-03, prd §291).
    ///
    /// "Up to date" is perfectly true of a Trello account with nothing assigned
    /// to you, and perfectly useless: the token worked, the read worked, and
    /// the screen is indistinguishable from a broken connection. Trello earns
    /// this because its emptiness has a CAUSE the person can act on —
    /// `/members/me/cards` returns only cards you are a member of, and plenty
    /// of boards never use member assignment at all, so a working connection
    /// really can land nothing.
    ///
    /// Nil for every other bridge on purpose. An empty Todoist means you have
    /// no open tasks, which is self-evident and arguably the point; a sentence
    /// there would be explaining nothing. Add a case only when empty is
    /// genuinely ambiguous.
    var emptyReadNote: String? {
        switch self {
        case .trello:
            String(localized: "Trello answered — no cards are assigned to you. Casberi reads cards you're a member of, so add yourself to one and sync again.")
        // Cloudflare earns one for the opposite reason to Trello's: here empty
        // is the GOOD outcome and by far the most common one, and it is exactly
        // as silent as a refused token. Nothing lands until something is close
        // to expiring, so a healthy account reads as a broken connection
        // forever without this sentence.
        case .cloudflare:
            String(localized: "Cloudflare answered — nothing needs attention. Casberi only lands certificates, domains and tokens that are close to expiring, so an empty read means everything is current.")
        // Cursor earns one for the plainest reason of the three: most people
        // who use Cursor have never launched a CLOUD agent — they use the
        // editor, which this cannot see and does not claim to. So a perfectly
        // good key legitimately reads empty forever, and without this sentence
        // that is indistinguishable from a key Cursor refused.
        case .cursor:
            String(localized: "Cursor answered — no finished cloud agents yet. Casberi reads the background agents you launch from Cursor's dashboard or editor, not the edits you make yourself, so run one and sync again.")
        // Cloudflare's case exactly: here empty is the GOOD outcome and the
        // common one, and it is precisely as silent as a refused key. Nothing
        // lands until something fires, so a quiet week reads as a broken
        // connection without this sentence.
        case .pagerduty:
            String(localized: "PagerDuty answered — nothing is on fire. Casberi only lands incidents as they trigger and resolve, so an empty read means your services are quiet.")
        // Sentry's empty is ambiguous in the way Trello's is, and the cause is
        // actionable: this reads UNRESOLVED issues only, so an org whose
        // backlog is entirely resolved or archived legitimately lands nothing
        // forever, and so does an org that simply isn't the one you meant.
        case .sentry:
            String(localized: "Sentry answered — nothing unresolved. Casberi reads open issues only, so an empty read means your backlog is clear. If that's a surprise, check which organization is selected above.")
        // Vercel's is a WRONG-SCOPE hint rather than a quiet-is-fine one: a
        // personal token reads your personal account, and someone whose
        // projects live under a team will otherwise see a working connection
        // that never lands anything, with nothing anywhere saying why.
        case .vercel:
            String(localized: "Vercel answered — no deployments found. A token scoped to your personal account can't see a team's projects, so if your work lives under a team, make the token for that team.")
        default:
            nil
        }
    }

    /// Bridge-specific teardown beyond the token itself — a hook the remove
    /// path calls so a bridge that caches non-thing state (a reading, not a
    /// Thing) drops it when disconnected, and a reconnected DIFFERENT account
    /// never wears the prior one's cache. Most bridges hold nothing extra.
    ///
    /// `reconnecting` distinguishes the two callers, which until Trello landed
    /// wanted exactly the same thing (2026-08-03). Pasting a fresh token calls
    /// this FIRST, to drop the old key's cached readings before the new one is
    /// stored — but Trello's API key is not a per-token reading, it identifies
    /// the Power-Up the token is minted against, and the paste that follows is
    /// worthless without it. Clearing it on a reconnect would delete the
    /// credential the very next line depends on. An explicit Remove still
    /// takes both.
    func onRemove(reconnecting: Bool = false) {
        switch self {
        case .bitrefill: BitrefillBalance.clear()
        case .oneclaw:   OneClawAccess.clear()
        case .posthog:   PostHogAccount.clear()
        case .stripe:    StripeAccount.clear()
        case .trello:    if !reconnecting { TrelloAuth.clear() }
        // Cleared on BOTH callers, unlike Trello's key: this is a cached
        // reading, which is exactly what this hook is for, and a fresh token
        // may name a different Cloudflare account. Diffing a new account's DNS
        // against the old one's snapshot would report a stranger's records as
        // yours, added and removed.
        case .cloudflare:
            CloudflareDNSLedger.clear()
            // Same reasoning one surface up: the runway would otherwise name a
            // new account's certificate rows after the old account's zones.
            CloudflareEstateStore.clear()
        // Cleared on BOTH callers, Cloudflare's reasoning: the host, the org
        // and the substatus ledger are all readings against one account, and a
        // fresh token may name a different one. Diffing a new org's issues
        // against the old org's ledger would announce a stranger's regressions
        // as yours.
        case .sentry:    SentryAccount.clear()
        case .pagerduty: PagerDutyCursor.clear()
        default:         break
        }
    }
}

/// Trello's two credentials, and the read-only mint (2026-08-03).
///
/// Every other bridge in this file is one paste. Trello's REST API takes TWO
/// values on every request — an API key identifying a Power-Up, and a token
/// identifying you — and neither works alone. That shapes the setup screen
/// into two stages, and it is also what makes the read-only promise here
/// STRUCTURAL rather than an instruction: because Casberi holds the key, it
/// builds the authorize URL itself and pins `scope=read`, so Trello mints a
/// token that has no write permission to give. Ask a person to pick read-only
/// on someone else's settings page and the promise is only as good as the box
/// they ticked.
///
/// The key is PUBLIC by design — it ships in the client-side JavaScript of
/// every Trello Power-Up, exactly like the Reown project id and the Dropbox
/// app key already in this tree. It lives in the Keychain anyway, beside the
/// token it is useless without, rather than in cleartext UserDefaults.
///
/// **UNMEASURED (2026-08-03)**: authored against Atlassian's published REST
/// docs with no Trello key stored and no egress to `api.trello.com` from this
/// host. Every read is a GET and every failure path returns nil, so it fails
/// safe — a wrong field name finds nothing rather than landing something
/// wrong. Verify with `-trelloKey` + `-tokenBridge "Trello:<token>"` before
/// trusting it.
enum TrelloAuth {
    /// The Keychain slot for the API key. The TOKEN rides `TokenBridge.trello.
    /// tokenKey` ("token.trello"), so this deliberately does NOT sit under
    /// that prefix as a suffix that could collide with it.
    static let keyVaultKey = "trello.apikey"

    static var storedKey: String? { TokenVault.get(keyVaultKey) }

    static func setKey(_ key: String) { TokenVault.set(key, for: keyVaultKey) }
    static func clear() { TokenVault.delete(keyVaultKey) }

    /// Trello's documented header form. The alternative — `?key=…&token=…` on
    /// the query string — is what most of its examples show and is avoided on
    /// purpose: a credential in a URL is a credential in every log, cache key
    /// and crash report that ever holds that URL.
    static func header(key: String, token: String) -> String {
        "OAuth oauth_consumer_key=\"\(key)\", oauth_token=\"\(token)\""
    }

    /// The mint. `scope=read` is the whole point (see above);
    /// `expiration=never` matches every other bridge here, which store a
    /// credential that keeps working until it's removed — the alternative is
    /// a connection that silently dies after 30 days and reads as a bug.
    /// `response_type=token` prints the token on the page for copying, which
    /// is the only option without a server to receive a redirect.
    /// The measure tool for a bridge built from docs and never run (see the
    /// UNMEASURED note above). Reports the RAW shape, phase by phase, because
    /// an empty Trello room has causes that all render as the same sentence:
    /// no key stored, a token Trello rejects (401), a key/token pair minted
    /// against different Power-Ups, or a perfectly good read of an account
    /// whose cards are simply not assigned to anyone. One NSLog per line — a
    /// joined multi-line message gets truncated by the log reader (the
    /// `-todayProbe` lesson).
    @MainActor
    static func diagnose() async {
        guard let key = storedKey else {
            NSLog("[Casberi] trello| no API key stored — paste one first (-trelloKey <key>)")
            return
        }
        guard let token = TokenVault.get(TokenBridge.trello.tokenKey) else {
            NSLog("[Casberi] trello| key stored, no token — authorize first (-tokenBridge \"Trello:<token>\")")
            NSLog("[Casberi] trello| authorize: %@",
                  authorizeURL(key: key)?.absoluteString ?? "(couldn't build)")
            return
        }
        let auth = header(key: key, token: token)
        let cards = await IngestSupport.getJSONStatus(
            "https://api.trello.com/1/members/me/cards?filter=open", auth: auth)
        NSLog("[Casberi] trello| cards HTTP %d", cards.status)
        guard let list = cards.json as? [[String: Any]] else {
            NSLog("[Casberi] trello| cards payload was not an array — shape drift, or the token was refused")
            return
        }
        NSLog("[Casberi] trello| %d open cards assigned to you", list.count)
        let boards = await IngestSupport.getJSONStatus(
            "https://api.trello.com/1/members/me/boards", auth: auth)
        NSLog("[Casberi] trello| boards HTTP %d, %d boards", boards.status,
              (boards.json as? [[String: Any]])?.count ?? -1)
        // The decisive line: which fields are ACTUALLY on the wire. Every
        // shaping decision in `trello()` rests on five of them, and a rename
        // empties the room with no error anywhere.
        for card in list.prefix(10) {
            NSLog("[Casberi] trelloCard| name=%@ due=%@ dueComplete=%@ closed=%@ board=%@ url=%@",
                  (card["name"] as? String) ?? "—",
                  (card["due"] as? String) ?? "nil",
                  String(describing: card["dueComplete"] ?? "MISSING"),
                  String(describing: card["closed"] ?? "MISSING"),
                  (card["idBoard"] as? String) ?? "MISSING",
                  (card["shortUrl"] as? String) ?? "MISSING")
        }
    }

    static func authorizeURL(key: String) -> URL? {
        var c = URLComponents(string: "https://trello.com/1/authorize")
        c?.queryItems = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "scope", value: "read"),
            URLQueryItem(name: "expiration", value: "never"),
            URLQueryItem(name: "response_type", value: "token"),
        ]
        return c?.url
    }
}

enum TokenIngest {

    @MainActor private static var running: Set<TokenBridge> = []

    /// Fetches with the stored token and lands new things. Returns the new
    /// count, or nil when there's no token, the token is rejected, or the
    /// network fails — callers word that as "check the token".
    @MainActor
    static func refresh(_ bridge: TokenBridge, context: ModelContext) async -> Int? {
        // PostHog owns its whole pass. It isn't a fetch-a-list-and-land bridge:
        // it reads each watched metric behind a freshness window (§216 — a
        // curve is a STATE), then DERIVES its news (milestones, silences) from
        // readings rather than mirroring rows. Routed here so the shared
        // foreground loop still drives it, without the dedupe machinery below
        // that assumes an incoming list.
        if bridge == .posthog { return await PostHogIngest.refresh(context: context) }
        // Stripe owns its whole pass for the same reason, from the other
        // direction: it isn't a fetch-a-list-and-land bridge either. It reads a
        // CURSORED event page (so the dedupe machinery below, which re-derives
        // every known ref each pass, would be doing work the cursor already
        // did) plus a balance behind a freshness window (§216 — a balance is a
        // STATE), and it sets `dueAt` on two of its shapes, which the generic
        // path has no notion of.
        if bridge == .stripe { return await StripeIngest.refresh(context: context) }
        // Sentry owns its whole pass for PostHog's reason: it doesn't mirror a
        // list, it DERIVES its news from a per-issue substatus ledger, so the
        // generic dedupe below — which re-derives every known ref each pass —
        // would be answering a question this bridge has already answered more
        // precisely. It also needs a resolved organization before it can read
        // anything at all.
        if bridge == .sentry { return await SentryIngest.refresh(context: context) }
        // PagerDuty owns its whole pass for Stripe's reason: it reads a
        // CURSORED window (`since` the last incident it saw) rather than a
        // page, and it lands both halves of an incident's life, the second of
        // which is dated from the app's own record of the first.
        if bridge == .pagerduty { return await PagerDutyIngest.refresh(context: context) }
        guard let token = TokenVault.get(bridge.tokenKey), !running.contains(bridge) else {
            return running.contains(bridge) ? 0 : nil
        }
        running.insert(bridge)
        defer { running.remove(bridge) }

        guard let incoming = await fetch(bridge, token: token, context: context) else { return nil }

        // Linear's issue state is the one field here that CHANGES after
        // landing (2026-07-22) — an issue closed in Linear must stop reading
        // as open in the feed. Runs before the dedupe below, which by design
        // never revisits a known ref.
        if bridge == .linear { reconcileLinear(incoming, context: context) }
        // Same shape for GitHub's involved issues/PRs (delight pass
        // 2026-07-28) — the loop-closer moment.
        if bridge == .github { GitHubFeedFetch.reconcileGitHubIssues(incoming, context: context) }
        // Todoist has no state field to reconcile — `/tasks` above only ever
        // returns OPEN tasks, so a completed one simply stops appearing
        // rather than arriving marked done. A separate completed-tasks read,
        // same loop-closer shape (delight pass 2026-07-28).
        if bridge == .todoist { await todoistCompletions(token, context: context) }
        // A card's due-checkbox is the one field here that CHANGES after
        // landing, the Linear shape exactly — dedupe never revisits a known
        // ref, so without this the state stamped at first sight is frozen.
        if bridge == .trello { reconcileTrello(incoming, context: context) }
        // Cloudflare needs BOTH halves — its rows are states wearing a date,
        // so a landed row's due date has to keep moving as the date approaches
        // (the dedupe below never revisits a known ref), and a row whose
        // condition has cleared has to close. See `reconcileCloudflare`.
        if bridge == .cloudflare { reconcileCloudflare(incoming, context: context) }

        var existing = IngestSupport.existingSourceRefs(context)
        // One backfill per source string the items actually carry — no
        // assumption that a fetch is single-source, and the lazy artless
        // fetch never runs for the bridges that don't set images.
        var backfills: [String: ArtlessBackfill] = [:]
        var added = 0
        for item in incoming {
            guard let ref = item.sourceRef else { continue }
            if existing.contains(ref) {
                let backfill = backfills[item.source]
                    ?? ArtlessBackfill(context, source: item.source)
                backfills[item.source] = backfill
                backfill.patch(ref, image: item.previewImageURL)
                continue
            }
            context.insert(item)
            existing.insert(ref)
            SpotlightIndex.index([item])
            added += 1
        }
        if added > 0 || backfills.values.contains(where: \.any) { context.saveHonestly() }
        return added
    }

    // MARK: - Per-app fetches (each is one or two GETs against the app's own API)

    @MainActor
    private static func fetch(_ bridge: TokenBridge, token: String, context: ModelContext) async -> [Thing]? {
        switch bridge {
        case .readwise: await readwise(token)
        case .github:   await github(token, context: context)
        case .todoist:  await todoist(token)
        case .raindrop: await raindrop(token)
        case .calcom:   await calcom(token)
        case .calendly: await calendly(token)
        case .notion:   await notion(token)
        case .linear:   await linear(token)
        case .bitrefill: await BitrefillFetch.things(token: token)
        case .privacy:  await PrivacyFetch.things(token: token)
        case .oneclaw:  await OneClawFetch.things(token: token, context: context)
        case .trello:   await trello(token)
        case .cloudflare: await CloudflareFetch.things(token: token)
        // Only runs that are OVER land, so — unlike Linear/Trello/Cloudflare
        // above — there is no `reconcile…` call for this bridge at the top of
        // `refresh`. A finished agent run is finished forever. See
        // `CursorFetch`.
        case .cursor:   await CursorFetch.things(token: token)
        // A deployment that is OVER is over forever, so — like Cursor and
        // unlike Linear/Trello/Cloudflare — there is no `reconcile…` call for
        // this bridge at the top of `refresh`. See `VercelFetch`.
        case .vercel:   await VercelFetch.things(token: token)
        // Unreachable — `refresh` routes these two to their own sweeps above.
        // Present so the switch stays exhaustive rather than defaulted, which
        // is what makes a future bridge impossible to add without deciding.
        case .posthog:  ownSweepUnreachable(.posthog)
        case .stripe:   ownSweepUnreachable(.stripe)
        case .sentry:   ownSweepUnreachable(.sentry)
        case .pagerduty: ownSweepUnreachable(.pagerduty)
        }
    }

    /// A bridge that owns its own sweep can only arrive here if the routing at
    /// the top of `refresh` was removed. It ASSERTS rather than just returning
    /// nil because in this switch's vocabulary nil means "couldn't read", which
    /// `refresh` reports to the user as "check the token" — so the silent
    /// failure would blame the credential for a wiring mistake (review,
    /// 2026-07-27). A function rather than an inline case body so the switch
    /// stays an expression.
    private static func ownSweepUnreachable(_ bridge: TokenBridge) -> [Thing]? {
        assertionFailure("\(bridge.rawValue) owns its own sweep — refresh should have routed it")
        return nil
    }

    /// Readwise export API — books with nested highlights. Newest 30 land.
    private static func readwise(_ token: String) async -> [Thing]? {
        guard let root = await IngestSupport.getJSON("https://readwise.io/api/v2/export/",
                                   auth: "Token \(token)") as? [String: Any],
              let books = root["results"] as? [[String: Any]] else { return nil }
        var all: [(Date, Thing)] = []
        for book in books {
            let source = [book["title"] as? String, book["author"] as? String]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
            // The book's cover leads every one of its highlights — scrolling
            // groups them visually by what you were reading.
            let cover = IngestSupport.imageURL(book["cover_image_url"] as? String)
            for h in (book["highlights"] as? [[String: Any]]) ?? [] {
                guard let id = h["id"], let text = h["text"] as? String, !text.isEmpty
                else { continue }
                let when = IngestSupport.isoDate(h["highlighted_at"]) ?? .now
                let thing = Thing(
                    kind: .note,
                    title: IngestSupport.titleLine(text),
                    content: source,
                    source: "Readwise",
                    capturedAt: when,
                    sourceRef: "readwise:\(id)"
                )
                thing.previewImageURL = cover
                // The WHOLE highlight, and your own note on it (2026-07-22).
                // `title` is `titleLine`'s 80-character clamp, so until now a
                // long highlight was truncated at ingest and the rest was
                // simply lost — the one thing a highlight archive exists to
                // keep. Only carried when the clamp actually cut something.
                let full = text.trimmingCharacters(in: .whitespacesAndNewlines)
                let note = (h["note"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                var parts: [String] = []
                if full.count > thing.title.count { parts.append(full) }
                if !note.isEmpty { parts.append(note) }
                if !parts.isEmpty { thing.summary = parts.joined(separator: "\n\n") }
                all.append((when, thing))
            }
        }
        return all.sorted { $0.0 > $1.0 }.prefix(30).map(\.1)
    }

    /// GitHub — the feeds the person turned on (Stars, New releases, Gists,
    /// Contributions, Watched repos, Notifications, and the original Issues &
    /// PRs), plus any repos watched directly (`GitHubRepoWatch`). Each is a
    /// GET or two against GitHub's own API; `GitHubFeedFetch` builds the things.
    @MainActor
    private static func github(_ token: String, context: ModelContext) async -> [Thing]? {
        await GitHubFeedFetch.all(token: token, context: context)
    }

    /// Todoist — open tasks, newest 30.
    private static func todoist(_ token: String) async -> [Thing]? {
        // The unified v1 API (2026-07-13: REST v2 answers 410 Gone for
        // everything now — the write probe caught it). v1 wraps lists in
        // `results`, renamed `created_at` → `added_at`, and dropped the
        // task `url` field (built from the id instead).
        guard let root = await IngestSupport.getJSON("https://api.todoist.com/api/v1/tasks",
                                    auth: "Bearer \(token)") as? [String: Any],
              let tasks = root["results"] as? [[String: Any]]
        else { return nil }
        let sorted = tasks.sorted {
            (($0["added_at"] as? String) ?? "") > (($1["added_at"] as? String) ?? "")
        }
        return sorted.prefix(30).compactMap { task in
            guard let id = task["id"] as? String,
                  let content = task["content"] as? String, !content.isEmpty
            else { return nil }
            let thing = Thing(
                kind: .reminder,
                title: content,
                content: "https://app.todoist.com/app/task/\(id)",
                source: "Todoist",
                capturedAt: IngestSupport.isoDate(task["added_at"] ?? task["created_at"]) ?? .now,
                sourceRef: "todoist:\(id)"
            )
            // The DEADLINE (2026-07-22). A Todoist task landed as a `.reminder`
            // but never carried its due date, so every feature that reads
            // `dueAt` skipped Todoist in silence: the overdue kept-ask, Coming
            // up, the Today brief's open items, the sheet's due row, and the
            // real date on "Add to Reminders". `datetime` when the task is
            // timed, else the all-day `date`; a task with no due date stays
            // honestly nil.
            let due = task["due"] as? [String: Any]
            thing.dueAt = IngestSupport.isoDate(due?["datetime"])
                ?? (due?["date"] as? String).flatMap(Self.allDayDate)
            // The task's own notes — publisher-authored, so display copy.
            if let notes = (task["description"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                thing.summary = notes
            }
            return thing
        }
    }

    /// A task you were carrying, completed elsewhere — the loop-closer
    /// moment (delight pass 2026-07-28). `/tasks` above only ever returns
    /// OPEN tasks (confirmed by the `todoist()` doc comment: "open tasks"),
    /// so a completed one doesn't arrive marked done, it just stops arriving
    /// — this is a SEPARATE read against Todoist's completed-tasks endpoint,
    /// scoped to a rolling window (the timestamp of the last successful
    /// check, defaulting to 24h back on first run) so a busy list doesn't
    /// need a full historical walk every refresh.
    ///
    /// UNMEASURED against the live API — built from Todoist's documented v1
    /// `tasks/completed/by_completion_date` shape, matching the same-file
    /// precedent set by `todoist()`'s own v1 migration note. Fails CLOSED:
    /// any shape mismatch (a wrong field name, an unexpected type) simply
    /// finds nothing rather than guessing — same honesty rule as every other
    /// unmeasured bridge in this app (PostHog, 1Claw, Privacy).
    @MainActor
    private static func todoistCompletions(_ token: String, context: ModelContext) async {
        let sinceKey = "todoist.completions.since"
        let since = UserDefaults.standard.string(forKey: sinceKey)
            ?? ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(-86400))
        let until = ISO8601DateFormatter().string(from: .now)
        guard let root = await IngestSupport.getJSON(
            "https://api.todoist.com/api/v1/tasks/completed/by_completion_date?since=\(since)&until=\(until)",
            auth: "Bearer \(token)") as? [String: Any],
              let items = root["items"] as? [[String: Any]]
        else { return }   // unreachable or the shape didn't match — try again next pass, since stays put
        UserDefaults.standard.set(until, forKey: sinceKey)
        guard !items.isEmpty else { return }

        let existing = IngestSupport.thingsByRef(context, source: "Todoist")
        var changed = false
        for item in items {
            // The task reference can arrive as either a JSON string or number
            // depending on which field the shape actually carries — accept
            // both rather than assume.
            let rawID = item["task_id"] ?? item["id"]
            let taskID = (rawID as? String) ?? (rawID as? Int).map(String.init)
            guard let taskID, let thing = existing["todoist:\(taskID)"], thing.mark != .done
            else { continue }
            thing.mark = .done
            changed = true
            SourceMoments.shared.fire(String(localized: "Done: \(thing.title)"), source: "Todoist")
        }
        if changed { context.saveHonestly() }
    }

    /// Cal.com — your bookings, newest first. The v2 API dates its schema
    /// with a required header.
    private static func calcom(_ token: String) async -> [Thing]? {
        guard let root = await IngestSupport.getJSON("https://api.cal.com/v2/bookings?sortStart=desc&limit=30",
                                   auth: "Bearer \(token)",
                                   headers: ["cal-api-version": "2026-05-01"]) as? [String: Any],
              let bookings = root["data"] as? [[String: Any]] else { return nil }
        return bookings.compactMap { booking in
            guard let uid = booking["uid"] as? String,
                  let title = booking["title"] as? String,
                  (booking["status"] as? String) != "cancelled" else { return nil }
            let thing = Thing(
                kind: .event,
                title: title,
                content: "https://app.cal.com/booking/\(uid)",
                source: "Cal.com",
                // The START rides capturedAt — an event's deadline IS its
                // capture time by the `dueAt` convention, so `dueAt` stays
                // nil here on purpose (unlike a Todoist reminder, whose
                // capturedAt is its creation time).
                capturedAt: IngestSupport.isoDate(booking["start"]) ?? .now,
                sourceRef: "calcom:\(uid)"
            )
            // What the booking is actually about (2026-07-22) — the sheet
            // otherwise had only the URL to show.
            if let notes = (booking["description"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                thing.summary = notes
            }
            return thing
        }
    }

    /// Calendly — who you are first, then your scheduled meetings.
    private static func calendly(_ token: String) async -> [Thing]? {
        guard let me = await IngestSupport.getJSON("https://api.calendly.com/users/me",
                                 auth: "Bearer \(token)") as? [String: Any],
              let userURI = (me["resource"] as? [String: Any])?["uri"] as? String
        else { return nil }
        guard let root = await IngestSupport.getJSON(
            "https://api.calendly.com/scheduled_events?user=\(userURI)&count=30&sort=start_time:desc",
            auth: "Bearer \(token)") as? [String: Any],
              let events = root["collection"] as? [[String: Any]] else { return nil }
        return events.compactMap { event in
            guard let uri = event["uri"] as? String,
                  let name = event["name"] as? String,
                  (event["status"] as? String) != "canceled" else { return nil }
            let id = uri.split(separator: "/").last.map(String.init) ?? uri
            let join = (event["location"] as? [String: Any])?["join_url"] as? String
            return Thing(
                kind: .event,
                title: name,
                content: join ?? "",
                source: "Calendly",
                capturedAt: IngestSupport.isoDate(event["start_time"]) ?? .now,
                sourceRef: "calendly:\(id)"
            )
        }
    }

    /// Notion — the pages connected to your integration, newest edits first.
    /// Pages only, by ruling — databases stay behind.
    private static func notion(_ token: String) async -> [Thing]? {
        guard let root = await IngestSupport.postJSON("https://api.notion.com/v1/search",
                                    auth: "Bearer \(token)",
                                    body: ["filter": ["value": "page", "property": "object"],
                                           "sort": ["direction": "descending",
                                                    "timestamp": "last_edited_time"],
                                           "page_size": 30],
                                    headers: ["Notion-Version": "2022-06-28"]) as? [String: Any],
              let results = root["results"] as? [[String: Any]] else { return nil }
        return results.compactMap { page in
            guard page["object"] as? String == "page",
                  (page["archived"] as? Bool) != true,
                  (page["in_trash"] as? Bool) != true,
                  let id = page["id"] as? String,
                  let url = page["url"] as? String else { return nil }
            // The title lives in whichever property carries the title type.
            let props = (page["properties"] as? [String: Any]) ?? [:]
            var title = ""
            for prop in props.values {
                guard let p = prop as? [String: Any], p["type"] as? String == "title",
                      let parts = p["title"] as? [[String: Any]] else { continue }
                title = parts.compactMap { $0["plain_text"] as? String }.joined()
                break
            }
            guard !title.isEmpty else { return nil }
            let thing = Thing(
                kind: .note,
                title: title,
                content: url,
                source: "Notion",
                capturedAt: IngestSupport.isoDate(page["last_edited_time"]) ?? .now,
                sourceRef: "notion:\(id)"
            )
            // The page's cover art (2026-07-22) — external or Notion-hosted;
            // a Notion-hosted file URL is signed and expires, but the
            // ArtlessBackfill patch re-reads it on each sync, the same way
            // every other hosted-image bridge stays fresh.
            let cover = page["cover"] as? [String: Any]
            thing.previewImageURL = IngestSupport.imageURL(
                ((cover?["external"] as? [String: Any])?["url"] as? String)
                    ?? ((cover?["file"] as? [String: Any])?["url"] as? String))
            return thing
        }
    }

    /// Linear — issues assigned to you, via its GraphQL API. Personal keys
    /// ride the Authorization header bare, no Bearer.
    private static func linear(_ token: String) async -> [Thing]? {
        // `state { type }` rides along (2026-07-22) so a Linear row can SHOW
        // whether it's open — until now a closed issue looked identical to an
        // active one — and so the feed head can state where the work sits.
        // `type` not `name`: names are per-team and user-renameable ("In
        // Review", "Shipping"), the type enum is Linear's own fixed
        // vocabulary, so the mapping can't drift with someone's workflow.
        // `description` (the issue body) and `dueDate` ride along too
        // (2026-07-22) — a Linear URL needs auth, so the sheet's link preview
        // resolves to nothing and the body was all it could have shown. Field
        // names confirmed against the live schema by introspection, same trick
        // that caught `duplicate` below.
        let query = """
        { viewer { assignedIssues(first: 30, orderBy: updatedAt) \
        { nodes { id identifier title url updatedAt dueDate description \
        state { type } } } } }
        """
        guard let root = await IngestSupport.postJSON("https://api.linear.app/graphql",
                                    auth: token,
                                    body: ["query": query]) as? [String: Any],
              let data = root["data"] as? [String: Any],
              let viewer = data["viewer"] as? [String: Any],
              let assigned = viewer["assignedIssues"] as? [String: Any],
              let nodes = assigned["nodes"] as? [[String: Any]] else { return nil }
        return nodes.compactMap { node in
            guard let id = node["id"] as? String,
                  let title = node["title"] as? String,
                  let url = node["url"] as? String else { return nil }
            let ident = node["identifier"] as? String
            let thing = Thing(
                kind: .link,
                title: ident.map { "\($0) · \(title)" } ?? title,
                content: url,
                source: "Linear",
                capturedAt: IngestSupport.isoDate(node["updatedAt"]) ?? .now,
                sourceRef: "linear:\(id)"
            )
            thing.mark = linearMark((node["state"] as? [String: Any])?["type"] as? String)
            // A Linear issue IS a task with a deadline, and unlike an event
            // its capturedAt is `updatedAt` — so the deadline needs its own
            // field, same as a Todoist task. `dueDate` is an all-day
            // calendar day.
            thing.dueAt = (node["dueDate"] as? String).flatMap(Self.allDayDate)
            if let body = (node["description"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
                thing.summary = body
            }
            return thing
        }
    }

    /// An all-day date ("2026-07-25") → noon local. `IngestSupport.isoDate`
    /// parses full timestamps only, and these fields carry a bare calendar
    /// day (Todoist's `due.date`, Linear's `dueDate`). NOON, not midnight:
    /// midnight local is the previous day in a westward timezone, which would
    /// make an all-day task read as overdue a day early.
    private static func allDayDate(_ s: String) -> Date? {
        guard let day = allDayFormatter.date(from: s) else { return nil }
        return Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }
    private static let allDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")   // never the user's calendar
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Linear's own state vocabulary → the corpus's mark. An unknown type
    /// (Linear adding one, or the field absent on an older sync) stays
    /// `.none` — a mark we can't justify is worse than no mark, and the row
    /// simply reads as it did before.
    ///
    /// The seven types are not guessed: Linear's schema states them on the
    /// field itself, read by introspection 2026-07-22 — "One of triage,
    /// backlog, unstarted, started, completed, canceled, duplicate". That
    /// read is what caught `duplicate`, which an intuition-written table
    /// would have dropped into `.none` and left reading as open forever.
    ///
    /// `canceled` and `duplicate` map to `.done` deliberately: all three
    /// closing types mean the issue left your plate, which is what the row's
    /// strikethrough and the "Done" segment claim. Calling either "todo"
    /// would keep it in your open count for good.
    private static func linearMark(_ type: String?) -> Mark {
        switch type {
        case "backlog", "unstarted", "triage":       return .todo
        case "started":                              return .doing
        case "completed", "canceled", "duplicate":   return .done
        default:                                     return .none
        }
    }

    /// Re-marks Linear things already in the corpus on every sync — an issue
    /// you closed elsewhere has to stop reading as open here. Dedupe skips
    /// re-landing a known `sourceRef`, so without this the state stamped at
    /// first sight would be frozen forever (the same reconciliation
    /// `ScheduleIngest` does for a reminder completed in the Reminders app).
    @MainActor
    static func reconcileLinear(_ fresh: [Thing], context: ModelContext) {
        let byRef = Dictionary(fresh.map { ($0.sourceRef ?? "", $0) },
                               uniquingKeysWith: { a, _ in a })
        guard !byRef.isEmpty else { return }
        let existing = (try? context.fetch(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Linear" }))) ?? []
        var changed = false
        for thing in existing {
            guard let ref = thing.sourceRef, let now = byRef[ref],
                  now.mark != thing.mark else { continue }
            // The loop-closer moment (delight pass 2026-07-28) — an issue
            // you were carrying resolving is real news; a plain state EDIT
            // (todo → doing) isn't, so this only fires on the genuine
            // transition INTO done, never on every mark change.
            let justClosed = now.mark == .done && thing.mark != .done
            thing.mark = now.mark
            changed = true
            if justClosed {
                SourceMoments.shared.fire(
                    String(localized: "Done: \(thing.title)"), source: "Linear")
            }
        }
        if changed { context.saveHonestly() }
    }

    /// Trello — the cards assigned to you, across every board, newest 30 by
    /// last activity. Two GETs (the Calendly shape): the cards, then the board
    /// names, so a card can say WHICH board it came from — a Trello card name
    /// on its own is usually a fragment ("Ship v1") that means nothing in a
    /// feed beside everything else.
    ///
    /// `filter=open` is the whole read: cards you are carrying. An ARCHIVED
    /// card simply stops arriving, and `reconcileTrello` deliberately does not
    /// mark those done — see its own note.
    private static func trello(_ token: String) async -> [Thing]? {
        // No key, no requests. This is the honest nil: `refresh` words it as
        // "check the token", which is right — half a credential is a broken
        // connection, and the setup screen can't reach the token stage without
        // the key anyway.
        guard let key = TrelloAuth.storedKey else { return nil }
        let auth = TrelloAuth.header(key: key, token: token)
        guard let cards = await IngestSupport.getJSON(
            "https://api.trello.com/1/members/me/cards?filter=open",
            auth: auth) as? [[String: Any]] else { return nil }

        // Board names, id → name. A failure here is NOT a failure of the pass:
        // the cards already read fine, and a card without its board prefix is
        // worse-labelled, not wrong. Landing nothing because a second,
        // decorative request blipped would be the wrong trade.
        var boards: [String: String] = [:]
        if let list = await IngestSupport.getJSON(
            "https://api.trello.com/1/members/me/boards", auth: auth) as? [[String: Any]] {
            for board in list {
                guard let id = board["id"] as? String,
                      let name = (board["name"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                      !name.isEmpty else { continue }
                boards[id] = name
            }
        }

        let sorted = cards.sorted {
            (($0["dateLastActivity"] as? String) ?? "") > (($1["dateLastActivity"] as? String) ?? "")
        }
        return sorted.prefix(30).compactMap { card in
            guard let id = card["id"] as? String,
                  let name = (card["name"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty
            else { return nil }
            // The board leads the title, the way a Linear issue's identifier
            // does — same separator, same reason: it is the context that makes
            // the rest of the line legible.
            let board = (card["idBoard"] as? String).flatMap { boards[$0] }
            let thing = Thing(
                kind: .reminder,
                title: board.map { "\($0) · \(name)" } ?? name,
                content: (card["shortUrl"] as? String) ?? (card["url"] as? String) ?? "",
                source: "Trello",
                capturedAt: IngestSupport.isoDate(card["dateLastActivity"]) ?? .now,
                sourceRef: "trello:\(id)"
            )
            // Trello's `due` is a full timestamp, so it needs none of the
            // all-day handling Todoist's `due.date` and Linear's `dueDate` do.
            // A card with no due date stays honestly nil.
            thing.dueAt = IngestSupport.isoDate(card["due"])
            thing.mark = trelloMark(card)
            if let desc = (card["desc"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
                thing.summary = desc
            }
            return thing
        }
    }

    /// A Trello card's state, from the only two fields Trello itself owns.
    ///
    /// **The list a card sits in is NOT read, on purpose** — this is the Linear
    /// `state { type }` ruling in a product that has no such enum. Trello lists
    /// are user-named and user-created ("Doing", "In review", "Shipped",
    /// "Icebox", "Done ✅"), so inferring completion from a list name would
    /// mean pattern-matching somebody's private vocabulary and getting it
    /// wrong for anyone whose board isn't in English or doesn't use the word.
    /// `dueComplete` is Trello's own fixed field — the checkbox beside the due
    /// date — and `closed` is its archive flag. Neither can drift with a
    /// workflow.
    ///
    /// A card with no due date and no archive is `.todo`, not `.none`: it is
    /// on your board and assigned to you, which is what todo means here.
    private static func trelloMark(_ card: [String: Any]) -> Mark {
        if (card["dueComplete"] as? Bool) == true { return .done }
        if (card["closed"] as? Bool) == true { return .done }
        return .todo
    }

    /// Re-marks Trello cards already in the corpus on every sync — a card you
    /// ticked off in Trello has to stop reading as open here (the
    /// `reconcileLinear` shape, and the same loop-closer moment).
    ///
    /// Scoped to the cards this pass actually SAW. A card that stopped arriving
    /// is left exactly as it was, which is the deliberately conservative call:
    /// `filter=open` drops a card for three different reasons — you archived
    /// it, someone unassigned you, or it fell past the newest 30 — and only one
    /// of those means done. Marking on absence would quietly retire cards
    /// somebody is still carrying, and per Linear's own note a mark we can't
    /// justify is worse than no mark.
    @MainActor
    static func reconcileTrello(_ fresh: [Thing], context: ModelContext) {
        let byRef = Dictionary(fresh.map { ($0.sourceRef ?? "", $0) },
                               uniquingKeysWith: { a, _ in a })
        guard !byRef.isEmpty else { return }
        let existing = (try? context.fetch(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Trello" }))) ?? []
        var changed = false
        for thing in existing {
            guard let ref = thing.sourceRef, let now = byRef[ref],
                  now.mark != thing.mark else { continue }
            let justClosed = now.mark == .done && thing.mark != .done
            thing.mark = now.mark
            changed = true
            if justClosed {
                SourceMoments.shared.fire(
                    String(localized: "Done: \(thing.title)"), source: "Trello")
            }
        }
        if changed { context.saveHonestly() }
    }

    /// Raindrop — newest 30 bookmarks across all collections.
    private static func raindrop(_ token: String) async -> [Thing]? {
        guard let root = await IngestSupport.getJSON("https://api.raindrop.io/rest/v1/raindrops/0?perpage=30",
                                   auth: "Bearer \(token)") as? [String: Any],
              let items = root["items"] as? [[String: Any]] else { return nil }
        return items.compactMap { item in
            guard let id = item["_id"], let link = item["link"] as? String else { return nil }
            let title = (item["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? link
            let thing = Thing(
                kind: .link,
                title: title,
                content: link,
                source: "Raindrop",
                capturedAt: IngestSupport.isoDate(item["created"]) ?? .now,
                sourceRef: "raindrop:\(id)"
            )
            // Raindrop's cover is the bookmark's og:image — the pin pattern.
            thing.previewImageURL = IngestSupport.imageURL(item["cover"] as? String)
            // The bookmark's excerpt — Raindrop's own description of the page,
            // plus whatever note you left on it (2026-07-22).
            let excerpt = (item["excerpt"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let note = (item["note"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let both = [note, excerpt].filter { !$0.isEmpty }.joined(separator: "\n\n")
            if !both.isEmpty { thing.summary = both }
            return thing
        }
    }
}
