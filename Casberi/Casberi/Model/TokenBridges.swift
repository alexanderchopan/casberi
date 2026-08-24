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
    case gitlab   = "GitLab"
    /// The only bridge here that takes THREE credentials and signs its own
    /// requests — see `ASCAuth`. It rides `TokenBridge` for the vault slot and
    /// the seat id, and routes to its own `Destination`.
    case appStoreConnect = "App Store Connect"
    /// Jira takes THREE credentials too, Trello's shape rather than App Store
    /// Connect's: a site and an email are stored beside the token (see
    /// `JiraAuth`), but nothing is SIGNED — Basic auth over the token is
    /// enough, so unlike ASC this still rides the generic dedupe-and-land
    /// loop in `TokenIngest.refresh` and needs no `Destination` of its own.
    case jira     = "Jira"

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
        case .gitlab:   "gitlab"
        case .appStoreConnect: "appstoreconnect"
        case .jira:      "jira"
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
        // certainly exists and the first STEP names the tab to look for.
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
        case .gitlab:    URL(string: "https://gitlab.com/-/user_settings/personal_access_tokens")
        // The Integrations tab, which is where the key, the key ID and the
        // issuer ID all live on one page — the three things this screen asks
        // for, in the order it asks for them.
        case .appStoreConnect:
            URL(string: "https://appstoreconnect.apple.com/access/integrations/api")
        // Where a token is MINTED, tied to the Atlassian account's email —
        // not a per-site page, because the site itself is the OTHER two
        // fields this bridge asks for (see `JiraAuth`), entered in the stage
        // before this door (`TokenSetupScreen.jiraSiteSection`, Trello's
        // two-stage shape).
        case .jira:      URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")
        }
    }

    /// The door's VERB — what you're going to get, in words short enough that
    /// no translation wraps them. This replaced `setupURLLabel` ("Open
    /// dashboard.stripe.com → API keys"), whose one line tried to be both the
    /// verb and the route map and ran edge to edge inside the slab (reported
    /// 2026-08-14 as "the words barely fit in the CTA"). The address renders
    /// beneath the verb (`doorHost`), and a tab trail lives in the step that
    /// follows — or nowhere, when the URL lands on the tab directly.
    var doorTitle: String {
        switch self {
        // Notion is the one door here that doesn't hand back a credential on
        // arrival — you make an integration first, and its secret is the paste.
        case .notion: String(localized: "Create your integration")
        case .readwise, .github, .todoist, .raindrop, .calendly, .gitlab,
             .vercel, .sentry, .jira, .cloudflare:
            String(localized: "Get your token")
        case .calcom, .linear, .bitrefill, .privacy, .oneclaw, .posthog,
             .stripe, .trello, .cursor, .pagerduty, .appStoreConnect:
            String(localized: "Get your API key")
        }
    }

    /// The address under the verb — DERIVED from `setupURL`, never a second
    /// table, so the button stays checkable against the address bar it opens
    /// and can't drift from where the door actually goes.
    var doorHost: String {
        guard let host = setupURL?.host else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// What's left after the door — stated plainly, step by step. Rendered
    /// UNNUMBERED on screen (ruling 2026-08-14): the door does step one
    /// itself, so numerals starting at 2 sent the eye hunting for a missing 1;
    /// two short lines in reading order need no numbers at all.
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
        // The tab IS named here — raindrop's door lands on Integrations, and
        // the token hides one tab over (the trail used to live in the door's
        // own label, which is a route map no button should carry).
        case .raindrop: [
            "Under For Developers, create an app and copy its Test token.",
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
            "In the API Keys tab, create a key — the one Cloud Agents use.",
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
        // The scope IS named here, for the Cloudflare/pagerduty reason: a
        // `.token` bridge renders the generic `TokenSetupScreen`, which has
        // no checklist, so this step is the only place it can be said.
        // `read_api` alone covers everything this bridge reads — issues and
        // merge requests assigned to you — and nothing it doesn't.
        case .gitlab: [
            "Create a token with only the read_api scope.",
            "Copy it and paste it below."]
        // FOUR steps, not two, and this is the only bridge here that needs
        // them — Apple hands back three separate values and a downloadable
        // file, and the download happens ONCE (the `.p8` can never be
        // re-downloaded, which is worth its own step). The role is named
        // because it is the only lever a person has over reach, and because
        // App Store Connect owns its own screen the checklist beneath step 2
        // carries the reads rather than this step naming them twice (§220,
        // the PostHog/Stripe precedent).
        // THREE steps, not four — the fourth was "Paste all three below", which
        // is §220's own example of a step re-typing what is already on screen
        // (three labelled fields sit directly beneath it). The role is named
        // because it is the only lever anyone has over reach; the checklist
        // under it says what that role lets Casberi see, so this step doesn't.
        case .appStoreConnect: [
            "Generate a key with the Developer role — the narrowest that works.",
            "Download the .p8. Apple only offers it once.",
            "The Key ID and Issuer ID are on the same page."]
        // Jira's steps are the SECOND stage only — the site stage carries its
        // own (`TokenSetupScreen.jiraSiteSection`), Trello's exact reason:
        // this is the one bridge here besides Trello that needs two pastes.
        // No scope to name: a Jira API token carries the same access as your
        // account (see `canLine`), so there is no box to tick the way
        // Cloudflare's or Sentry's steps name one.
        case .jira: [
            "Create an API token — name it Casberi.",
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
        case .gitlab:   "glpat-…"
        // WAS `-----BEGIN PRIVATE KEY-----`, Apple's own marker, on the theory
        // that showing the file's first line hinted the whole file goes in. It
        // did the opposite (report, 2026-08-14): a field whose placeholder is a
        // PEM header reads as a LABEL for something already there, not as an
        // empty box waiting for a paste, and the one person who worked it out
        // had to open the `.p8` in a desktop text editor to find out what to
        // copy. The screen reads the file directly now, so this field is the
        // fallback and says so in words.
        case .appStoreConnect: "Or paste the .p8 contents"
        case .jira:      "API token"
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
        case .gitlab:   "personal access token"
        case .appStoreConnect: "private key"
        case .jira:      "API token"
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
        case .gitlab:   "issues & MRs"
        // Four shapes with no shared noun — "verdicts, reviews and builds"
        // would be a list, and "items" says nothing. "updates" is Stripe's
        // and PostHog's answer to the same problem.
        case .appStoreConnect: "updates"
        case .jira:      "issues"
        }
    }

    /// The `Thing.source` this bridge stamps on every row it lands — i.e. the
    /// room `ChipLiveNote`'s door opens (2026-08-24).
    ///
    /// It is `rawValue` for all twenty-two, VERIFIED case by case against each
    /// bridge's own `source:` literal rather than assumed from the fact that
    /// the names match today. The assumption is the dangerous half: a seat
    /// whose bridge stamps something else gets a door onto a room that does
    /// not exist, which renders as a tap that quietly lands you in an empty
    /// feed — the §83 fault the door was built to fix, one step later. Guarded
    /// mechanically by `setup-copy-audit.py` check 6, so this cannot drift
    /// silently the day a case is added.
    ///
    /// Deliberately NOT `BridgeCatalog.offer(forSource:)` run backwards: that
    /// function matches an offer whose name merely ENDS with the source
    /// ("0xBow Privacy Pools" for "Privacy Pools"), which has no inverse.
    var source: String { rawValue }

    /// The rest of the door's sentence — "See Todoist **for your tasks.**"
    ///
    /// Derived from `noun` rather than spelled out a second time, so a bridge
    /// cannot end up calling the same rows two different things one screen
    /// apart. GitHub is the one override: its noun is deliberately "items"
    /// (four feeds with no shared word), and "for your items" says nothing.
    var roomVerb: String {
        switch self {
        case .github: String(localized: "for what's landed.")
        default:      String(localized: "for your \(noun).")
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
            String(localized: "Sign in with GitHub — or paste a token — and the feeds you pick keep arriving, plus any repo you watch. Watching here is private.")
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
            String(localized: "Paste an API key and what you spend on your virtual cards keeps arriving. Privacy's key can't be scoped read-only, so nothing here creates, closes, or funds a card.")
        case .oneclaw:
            String(localized: "Paste an agent key and you'll see what it can reach — which vaults, which paths, when each grant expires. No secret's value is ever read.")
        case .posthog:
            String(localized: "Paste a read-only key, watch the metrics you care about, and only what's news arrives: a milestone crossed, a metric falling silent, a deploy you annotated.")
        case .stripe:
            String(localized: "Paste a read-only key and the money that needs you keeps arriving — a dispute and its deadline, a payout, a cancelled subscription, a failed payment.")
        case .trello:
            // MINTED — the strongest promise in the catalog, and the only one
            // that is structural rather than a box someone ticked.
            String(localized: "Authorize once and the cards assigned to you keep arriving with their due dates. Trello is asked for a read-only token, so it has no write permission to give.")
        case .cloudflare:
            String(localized: "Paste a read-only token and you're told before a certificate, domain or token expires, and when a DNS record changes. No analytics, and nothing about your visitors.")
        case .cursor:
            // CONDUCT, and the weakest grade here: this key could start an
            // agent, which spends money AND writes a branch to a repo.
            String(localized: "Paste a key and your finished cloud agents keep arriving. Cursor's key can't be scoped read-only, so this only ever lists them.")
        case .sentry:
            String(localized: "Paste a read-only token and three things arrive: a new issue, a regression, an escalation. Never an event, a stack trace, or anything about the person who hit it.")
        case .vercel:
            // CONDUCT.
            String(localized: "Paste a token and your deployments keep arriving — what shipped and what broke. Vercel's token can't be scoped read-only, and your environment variables are never read.")
        case .pagerduty:
            String(localized: "Paste a read-only key and your incidents keep arriving — what fired, how urgent, and when it was resolved. Nothing here pages anyone, acknowledges, or resolves.")
        case .gitlab:
            String(localized: "Paste a read-only token and the issues and merge requests assigned to you keep arriving. Nothing here comments, merges, or closes anything.")
        case .appStoreConnect:
            // CONDUCT, and the weakest grade in the catalog: an App Store
            // Connect key carries a ROLE, and no role is read-only for what
            // this reads — the same key could submit a version.
            String(localized: "Add a key and Apple's verdicts, your customer reviews and expiring builds keep arriving. Apple has no read-only role, so this only ever reads.")
        case .jira:
            // CONDUCT. A Jira API token carries the same access as the
            // account it's minted for — Atlassian has no read-only token —
            // so the promise, like Privacy's and Cursor's, is what this code
            // does rather than what the token can't.
            String(localized: "Paste a token and the issues assigned to you keep arriving with their due dates. Jira has no read-only token, so this only ever reads.")
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
        case .privacy:  "Reads your card transactions only. Privacy's key can't be scoped read-only, so nothing here creates, closes, or funds a card."
        case .oneclaw:  "Reads which vaults and secret paths the key can reach — names and permissions only. Nothing here ever reads a secret's value, signs, or spends."
        case .posthog:  "Reads the metrics you watch and your project's annotations. The key is scoped read-only — it cannot ship a flag, edit a dashboard, or write anything back."
        case .stripe:   "Reads disputes, payouts, canceled subscriptions, failed payments, and your balance. The restricted key is read-only — it cannot refund, charge, or pay out."
        // The read-only promise here is the strongest of any bridge in this
        // file, because Casberi MINTS it rather than asking you to: the
        // authorize link is built with `scope=read`, so Trello itself issues a
        // token that has no write permission to give. Every other keyed bridge
        // depends on the person ticking the right box on someone else's page.
        case .trello:   "Reads the cards assigned to you and when they're due. The token is minted read-only, so it cannot move a card, comment, or write anything back."
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
        case .cursor:   "Reads the cloud agents you've run — what each was asked to do, what it says it did, and the pull request it opened. Cursor's key can't be scoped read-only, so this only lists them: never starts, follows up, stops, or deletes one."
        // What is NOT read is the load-bearing clause. Sentry holds the data
        // your users generated when something broke — anyone connecting it has
        // every right to ask whether that is about to land in a feed. It isn't:
        // this reads the ISSUE list, which is titles and code locations, and
        // never an event, a stack trace, a request body, or a user.
        case .sentry:   "Reads your unresolved issues — the error, the project, and where in your code it happened. Never an event, a stack trace, or anything about the person who hit it. The token is scoped read-only: it cannot resolve an issue, comment, or change a project."
        case .vercel:   "Reads your deployments — the project, whether each one shipped or broke, and its commit message. Vercel's token can't be scoped read-only, so this only lists them: never deploys, promotes, rolls back, cancels, or deletes one, and never reads your environment variables."
        case .pagerduty: "Reads your incidents — what fired, on which service, how urgent, and when it was resolved. A read-only key cannot page anyone, acknowledge, resolve, or reassign."
        case .gitlab:   "Reads the issues and merge requests assigned to you, across every project. The read_api token cannot comment, merge, close, or write anything back."
        // The Cursor sentence, one rung stronger, because the risk is one rung
        // higher: an App Store Connect key carries a ROLE rather than scopes,
        // and the narrowest role that can read all four of these can also ship
        // software to the public under your name. Naming the six verbs Casberi
        // doesn't use IS the promise, so they are listed rather than
        // summarised — and if a write is ever added to `AppStoreConnectBridge`,
        // this line has to change in the same commit
        // (`scripts/appstoreconnect-selftest.sh` fails the build if it isn't).
        case .appStoreConnect: "Reads your apps' review status, your customer reviews, and your builds. Apple has no read-only role, so this only reads: it never submits, releases, removes an app from sale, replies to a review, or uploads a build — and never touches your sales, proceeds, or anything about the people who use your apps."
        // The Privacy.com/Cursor sentence: a Jira API token carries no scopes
        // and no read-only grade at all, so the promise is kept the same way
        // — by naming the verbs this code doesn't use. If a write is ever
        // added to `jira()`, this line has to change in the same commit.
        case .jira:      "Reads the issues assigned to you — the project, the status, and when each is due. A Jira token has the same access as your account, so this only ever reads: never transitions, comments on, or edits an issue."
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
            String(localized: "Trello answered — no cards are assigned to you. Only cards you're a member of are read, so add yourself to one and sync again.")
        // Cloudflare earns one for the opposite reason to Trello's: here empty
        // is the GOOD outcome and by far the most common one, and it is exactly
        // as silent as a refused token. Nothing lands until something is close
        // to expiring, so a healthy account reads as a broken connection
        // forever without this sentence.
        case .cloudflare:
            String(localized: "Cloudflare answered — nothing needs attention. Only certificates, domains and tokens close to expiring land, so an empty read means everything is current.")
        // Cursor earns one for the plainest reason of the three: most people
        // who use Cursor have never launched a CLOUD agent — they use the
        // editor, which this cannot see and does not claim to. So a perfectly
        // good key legitimately reads empty forever, and without this sentence
        // that is indistinguishable from a key Cursor refused.
        case .cursor:
            String(localized: "Cursor answered — no finished cloud agents yet. Only the background agents you launch are read, not the edits you make yourself, so run one and sync again.")
        // Cloudflare's case exactly: here empty is the GOOD outcome and the
        // common one, and it is precisely as silent as a refused key. Nothing
        // lands until something fires, so a quiet week reads as a broken
        // connection without this sentence.
        case .pagerduty:
            String(localized: "PagerDuty answered — nothing is on fire. Incidents land as they trigger and resolve, so an empty read means your services are quiet.")
        // Sentry's empty is ambiguous in the way Trello's is, and the cause is
        // actionable: this reads UNRESOLVED issues only, so an org whose
        // backlog is entirely resolved or archived legitimately lands nothing
        // forever, and so does an org that simply isn't the one you meant.
        case .sentry:
            String(localized: "Sentry answered — nothing unresolved. Open issues only, so an empty read means your backlog is clear. If that's a surprise, check which organization is selected above.")
        // Vercel's is a WRONG-SCOPE hint rather than a quiet-is-fine one: a
        // personal token reads your personal account, and someone whose
        // projects live under a team will otherwise see a working connection
        // that never lands anything, with nothing anywhere saying why.
        case .vercel:
            String(localized: "Vercel answered — no deployments found. A token scoped to your personal account can't see a team's projects, so if your work lives under a team, make the token for that team.")
        // Cloudflare's and PagerDuty's case, with an extra cause of its own.
        // Nothing lands until something HAPPENS to an app, so a shipped app in
        // a quiet week legitimately reads empty — AND a first sync deliberately
        // records where every version and build already stands without saying
        // anything, so that a decade of shipped releases doesn't land as
        // today's news. Both are the healthy answer, and both are exactly as
        // silent as a key Apple refused.
        case .appStoreConnect:
            String(localized: "Apple answered — nothing has changed. A first sync notes where everything stands, then stays quiet until a verdict, a review, or a build expiry actually arrives.")
        // Trello's exact ambiguity, on a different filter: `jiraJQL` asks for
        // issues assigned to you specifically, so a working token can read a
        // busy site and still land nothing if nothing is assigned to you.
        case .jira:
            String(localized: "Jira answered — no issues are assigned to you. Only issues where you're the assignee are read, so check that against the site and project you meant.")
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
        // Cleared on BOTH callers — a fresh token may belong to a different
        // account with a different budget, and the stale bucket must not
        // suppress a real crossing on the new one.
        case .github:    GitHubRateLimit.clear()
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
        // Cleared on BOTH callers, unlike Trello's API key: a re-paste here
        // replaces the key AND its two identifiers together (the screen asks
        // for all three), and a fresh key may name a different Apple account.
        // Diffing a new account's versions against the old account's ledger
        // would announce a stranger's rejection as yours.
        case .appStoreConnect: ASCAuth.clear()
        // Cleared on a real Remove only, Trello's key reasoning exactly: the
        // site and email name the ACCOUNT the token is minted for, and a
        // fresh token pasted over an expired one is minted for the same
        // account, so clearing them on a reconnect would delete what the very
        // next line depends on.
        case .jira:      if !reconnecting { JiraAuth.clear() }
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

/// Jira Cloud's credentials — a site, an email, and an API token minted
/// against that email (2026-08-08). Three values because Jira's REST API has
/// no single bearer secret the way Readwise's or Todoist's do: a token minted
/// at `id.atlassian.com` names an ATLASSIAN ACCOUNT, and that account can sit
/// on any number of sites (`<name>.atlassian.net`), so the token alone names
/// neither which site to read nor whose issues "assigned to you" means.
///
/// The TOKEN itself rides `TokenBridge.jira.tokenKey` — the vault slot the
/// generic dispatch in `TokenIngest.refresh` already checks for `connected`,
/// Trello's exact shape. The site and email are two more Keychain slots,
/// stored beside it for Trello's own reason: each is useless apart from the
/// token it authenticates, so cleartext UserDefaults would scatter one
/// credential across two storage tiers for no reason.
///
/// Auth is HTTP Basic — `email:token`, base64 — Jira Cloud's documented
/// scheme for every REST call (the `ZerionAPI`/`RedditBridge` shape here,
/// not Trello's OAuth-flavoured header, since Jira issues no authorize link
/// this app could build for you).
///
/// UNMEASURED (2026-08-08): authored against Atlassian's published REST API
/// v3 reference, no live site, no egress to any `*.atlassian.net` host from
/// this build host. Every read fails to nil rather than guessing, so it
/// fails safe — verify with `-jiraDomain` + `-jiraEmail` +
/// `-tokenBridge "Jira:<token>"` + `-jiraProbe YES` before trusting it.
enum JiraAuth {
    /// The site, e.g. "yourteam.atlassian.net" — WITHOUT a scheme. Stored
    /// normalized (see `normalizedDomain`) so a pasted address-bar URL — the
    /// likeliest paste, and a paste Trello's Power-Up key never had to guard
    /// against — can't corrupt every request built from it.
    static let domainVaultKey = "jira.domain"
    /// The Atlassian account email the token was minted for. Not the bearer
    /// secret, but Basic auth needs it on every request, so it travels with
    /// the token rather than being retyped each launch.
    static let emailVaultKey = "jira.email"

    static var storedDomain: String? { TokenVault.get(domainVaultKey) }
    static var storedEmail: String? { TokenVault.get(emailVaultKey) }

    /// Strips a scheme and anything after the host — the address-bar paste
    /// Trello's key field never had to worry about, since a Power-Up key has
    /// no plausible "looks like a URL" paste.
    static func normalizedDomain(_ raw: String) -> String {
        var d = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://"] where d.hasPrefix(prefix) {
            d.removeFirst(prefix.count)
        }
        if let slash = d.firstIndex(of: "/") { d = String(d[..<slash]) }
        return d
    }

    static func setDomain(_ raw: String) { TokenVault.set(normalizedDomain(raw), for: domainVaultKey) }
    static func setEmail(_ raw: String) {
        TokenVault.set(raw.trimmingCharacters(in: .whitespacesAndNewlines), for: emailVaultKey)
    }
    static func clear() {
        TokenVault.delete(domainVaultKey)
        TokenVault.delete(emailVaultKey)
    }

    /// `email:token`, base64 — Jira Cloud's documented Basic-auth scheme. A
    /// credential in a URL is a credential in every log that ever holds it
    /// (Trello's reasoning for its own header), so this rides the
    /// Authorization header like everything else in this file.
    static func header(email: String, token: String) -> String? {
        guard let data = "\(email):\(token)".data(using: .utf8) else { return nil }
        return "Basic \(data.base64EncodedString())"
    }

    /// Every issue assigned to you, newest-updated first — no status filter,
    /// `linear()`'s shape rather than Trello's `filter=open`: Jira's
    /// `statusCategory` is a FIXED three-value field regardless of a
    /// project's custom workflow names (see `TokenIngest.jiraMark`), so
    /// filtering server-side would only cost this bridge the ability to see
    /// an issue move to Done — `TokenIngest.reconcileJira` needs to see it
    /// arrive to close it here.
    static let jql = "assignee = currentUser() ORDER BY updated DESC"
    /// The selection is the ceiling (the Linear/App-Store-Connect lesson): a
    /// field not asked for here can never reach the corpus, no matter what
    /// `TokenIngest.jira` tries to read off it. `description` is deliberately
    /// NOT here — Jira v3 renders it as Atlassian Document Format, a JSON
    /// node tree rather than a markdown string like Linear's, so a card-back
    /// summary needs a tree walk this bridge doesn't do yet; asking for a
    /// field nothing reads would cost a request for nothing.
    static let fields = "summary,status,duedate,priority,project,updated,labels"

    static func searchURL(domain: String) -> String {
        var c = URLComponents()
        c.scheme = "https"
        c.host = domain
        c.path = "/rest/api/3/search"
        c.queryItems = [
            URLQueryItem(name: "jql", value: jql),
            URLQueryItem(name: "fields", value: fields),
            URLQueryItem(name: "maxResults", value: "50"),
        ]
        // Falls back to a hand-built string only if URLComponents somehow
        // can't encode the JQL (it always can) — never silently drops the
        // query and hits the bare search root, which would read as "no
        // issues" rather than "couldn't build the request".
        return c.url?.absoluteString
            ?? "https://\(domain)/rest/api/3/search?jql=\(jql)&fields=\(fields)&maxResults=50"
    }

    /// The measure tool for a bridge built from docs and never run (see the
    /// UNMEASURED note above). Reports the RAW shape, phase by phase: an
    /// empty Jira room has causes that all render as the same sentence — no
    /// site stored, no email, a token Jira refuses (401), a site name that
    /// isn't a real Jira Cloud host (unreachable), or a perfectly good read
    /// of an account with nothing assigned. One NSLog per line — a joined
    /// multi-line message gets truncated by the log reader (the
    /// `-todayProbe` lesson).
    @MainActor
    static func diagnose() async {
        guard let domain = storedDomain, !domain.isEmpty else {
            NSLog("[Casberi] jira| no site stored — paste one first (-jiraDomain <site>.atlassian.net)")
            return
        }
        guard let email = storedEmail, !email.isEmpty else {
            NSLog("[Casberi] jira| site stored, no email — paste one (-jiraEmail you@company.com)")
            return
        }
        guard let token = TokenVault.get(TokenBridge.jira.tokenKey) else {
            NSLog("[Casberi] jira| site and email stored, no token — mint one at id.atlassian.com and paste it (-tokenBridge \"Jira:<token>\")")
            return
        }
        guard let auth = header(email: email, token: token) else {
            NSLog("[Casberi] jira| couldn't build the auth header")
            return
        }
        let myself = await IngestSupport.getJSONStatus(
            "https://\(domain)/rest/api/3/myself", auth: auth, service: "Jira")
        NSLog("[Casberi] jira| GET /myself HTTP %d", myself.status)
        guard myself.status != 401 else {
            NSLog("[Casberi] jira| 401 — Jira refused the token. Check the email matches the account the token was minted for.")
            return
        }
        guard myself.status == 200 else {
            NSLog("[Casberi] jira| couldn't reach %@ — check the site name (no https://, no trailing slash)", domain)
            return
        }
        if let me = myself.json as? [String: Any] {
            NSLog("[Casberi] jira| signed in as %@ (%@)",
                  (me["displayName"] as? String) ?? "—", (me["emailAddress"] as? String) ?? "—")
        }
        let search = await IngestSupport.getJSONStatus(searchURL(domain: domain), auth: auth, service: "Jira")
        NSLog("[Casberi] jira| GET /search HTTP %d", search.status)
        guard let root = search.json as? [String: Any],
              let issues = root["issues"] as? [[String: Any]] else {
            NSLog("[Casberi] jira| issues payload missing — shape drift, or the JQL was refused")
            return
        }
        NSLog("[Casberi] jira| %d issues assigned to you", issues.count)
        // The decisive lines: which fields are ACTUALLY on the wire. Every
        // shaping decision in `TokenIngest.jira` rests on these, and a
        // rename empties the room with no error anywhere.
        for issue in issues.prefix(10) {
            let fields = (issue["fields"] as? [String: Any]) ?? [:]
            let status = fields["status"] as? [String: Any]
            let category = (status?["statusCategory"] as? [String: Any])?["key"] as? String
            NSLog("[Casberi] jiraIssue| key=%@ summary=%@ status=%@ category=%@ due=%@ project=%@",
                  (issue["key"] as? String) ?? "MISSING",
                  (fields["summary"] as? String) ?? "—",
                  (status?["name"] as? String) ?? "MISSING",
                  category ?? "MISSING",
                  (fields["duedate"] as? String) ?? "nil",
                  ((fields["project"] as? [String: Any])?["name"] as? String) ?? "MISSING")
        }
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
        // App Store Connect owns its whole pass for PostHog's reason and one
        // of its own. It DERIVES its news by diffing per-version and per-build
        // state ledgers rather than mirroring a list, so the generic dedupe
        // below would be re-deriving what those ledgers already answered — and
        // its credential isn't a token at all but three values and a signed
        // JWT, so `TokenVault.get(bridge.tokenKey)` alone can't establish that
        // it is really connected (see `ASCAuth.configured`).
        if bridge == .appStoreConnect { return await ASCIngest.refresh(context: context) }
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
        // An issue's status is the one field here that CHANGES after landing,
        // Trello's/Linear's exact shape — dedupe never revisits a known ref.
        if bridge == .jira { reconcileJira(incoming, context: context) }
        // Cloudflare needs BOTH halves — its rows are states wearing a date,
        // so a landed row's due date has to keep moving as the date approaches
        // (the dedupe below never revisits a known ref), and a row whose
        // condition has cleared has to close. See `reconcileCloudflare`.
        if bridge == .cloudflare { reconcileCloudflare(incoming, context: context) }
        // The Linear shape exactly — an issue closed or an MR merged/closed
        // in GitLab must stop reading as open in the feed.
        if bridge == .gitlab { reconcileGitlab(incoming, context: context) }

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
                // The face rides the same patch (2026-08-14). Dedupe never
                // revisits a known ref, so without this a bridge that starts
                // stamping an avatar reaches only rows landed from that day
                // on — and GitHub's stars and watched repos are the same
                // thirty rows for months, so it would have reached none of
                // them until you starred something new.
                backfill.patch(ref, image: item.previewImageURL,
                               face: item.authorAvatarURL, handle: item.authorHandle)
                continue
            }
            context.insert(item)
            existing.insert(ref)
            SpotlightIndex.index([item])
            added += 1
        }
        if added > 0 || backfills.values.contains(where: \.any) { context.saveHonestly() }
        // Notion's search response carries no page body, so the words are a
        // second read per page (see `notionBodies`). It runs AFTER the landing
        // loop on purpose: a page that arrived in this very pass can then gain
        // its body in the same pass rather than the next one. Nothing above is
        // read after this await.
        if bridge == .notion { await notionBodies(token, context: context) }
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
        case .gitlab:   await gitlab(token)
        // Only runs that are OVER land, so — unlike Linear/Trello/Cloudflare
        // above — there is no `reconcile…` call for this bridge at the top of
        // `refresh`. A finished agent run is finished forever. See
        // `CursorFetch`.
        //
        // Note what that does and does not cover (2026-08-08, prd §340): the
        // RUN is final, and the PULL REQUEST it opened is not. That second
        // half is reconciled by `CursorPullRequests`, which runs from the
        // foreground sweep rather than here, because it spends the GitHub
        // token rather than this bridge's own.
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
        case .appStoreConnect: ownSweepUnreachable(.appStoreConnect)
        case .jira:     await jira(token)
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
            // The book's own shelf words, shared by every highlight under it:
            // the tags you put on the BOOK, and Readwise's own category — the
            // one fixed word that tells a book from an article, a tweet and a
            // podcast in a room where every row is a paragraph of prose.
            let bookTags = names(in: book["book_tags"])
            let category = readwiseCategory(book["category"] as? String)
            let sourceURL = httpLink(book["source_url"])
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
                // WHERE IT CAME FROM (2026-08-06). Until now a highlight
                // carried no address anywhere: `content` holds "Book — Author",
                // which is prose and what groups a book's highlights visually,
                // so the sheet had nothing to open even though the payload
                // carries three links. It rides `externalLink` rather than
                // `content` for exactly that reason — moving a URL into
                // `content` would replace the book line on every row and take
                // the grouping with it.
                //
                // `readwise_url` leads because it names THIS highlight and
                // every highlight has one; the highlight's own `url` and the
                // book's `source_url` exist only for things that were on the
                // web, and are the better answer when they do.
                thing.externalLink = httpLink(h["readwise_url"])
                    ?? httpLink(h["url"]) ?? sourceURL
                // Readwise's category, then your own tags on the highlight,
                // then the book's — see `tagList` for why that order.
                thing.tags = tagList(category + names(in: h["tags"]) + bookTags)
                all.append((when, thing))
            }
        }
        return all.sorted { $0.0 > $1.0 }.prefix(30).map(\.1)
    }

    /// Readwise's own `category` → one word for the tag rail, or none.
    ///
    /// The values are Readwise's fixed vocabulary rather than anything a person
    /// types, which is what makes a fixed map safe here in a way that reading a
    /// Trello list name never is (see `trelloMark`). An unrecognized value
    /// lands NOTHING rather than a machine plural: Readwise adding a sixth kind
    /// should read as a highlight with no category, not as a tag whose spelling
    /// we invented.
    private static func readwiseCategory(_ raw: String?) -> [String] {
        switch raw {
        case "books":         ["Book"]
        case "articles":      ["Article"]
        case "tweets":        ["Tweet"]
        case "podcasts":      ["Podcast"]
        case "supplementals": ["Supplemental"]
        default:              []
        }
    }

    /// GitHub — the feeds the person turned on (Stars, New releases, Gists,
    /// Contributions, Watched repos, Notifications, and the original Issues &
    /// PRs), plus any repos watched directly (`GitHubRepoWatch`). Each is a
    /// GET or two against GitHub's own API; `GitHubFeedFetch` builds the things.
    @MainActor
    private static func github(_ token: String, context: ModelContext) async -> [Thing]? {
        await GitHubFeedFetch.all(token: token, context: context)
    }

    /// Todoist — open tasks, newest 30. Two GETs (the Trello shape): the
    /// tasks, then the project names, so a task can say which list it came
    /// from.
    private static func todoist(_ token: String) async -> [Thing]? {
        // The unified v1 API (2026-07-13: REST v2 answers 410 Gone for
        // everything now — the write probe caught it). v1 wraps lists in
        // `results`, renamed `created_at` → `added_at`, and dropped the
        // task `url` field (built from the id instead).
        guard let root = await IngestSupport.getJSON("https://api.todoist.com/api/v1/tasks",
                                    auth: "Bearer \(token)") as? [String: Any],
              let tasks = root["results"] as? [[String: Any]]
        else { return nil }
        // Project names, id → name (2026-08-06). A second GET, the Trello
        // board-name shape and for its reason: a task's project is context the
        // task itself doesn't carry. A failure here is NOT a failure of the
        // pass — the tasks already read fine, and a task without its project is
        // worse-labelled, not wrong; only the first page is read, so a project
        // past it leaves its tasks untagged rather than mistagged.
        //
        // The name lands as a TAG rather than leading the title the way a
        // Trello board does, and that is a difference in the data, not a
        // preference: a Trello card name is a fragment written against a board
        // you were looking at ("Ship v1"), while a Todoist task is a whole
        // instruction that stands on its own — and every task in the default
        // project would otherwise read "Inbox · …", spending the title's
        // 80-character clamp on the least informative word on the row.
        var projects: [String: String] = [:]
        if let list = (await IngestSupport.getJSON("https://api.todoist.com/api/v1/projects",
                                                  auth: "Bearer \(token)")
                       as? [String: Any])?["results"] as? [[String: Any]] {
            for project in list {
                guard let id = project["id"] as? String,
                      let name = (project["name"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                      !name.isEmpty else { continue }
                projects[id] = name
            }
        }
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
            // YOUR LABELS (2026-08-06) — plain strings in Todoist, and the one
            // field here already spelled in the corpus's own vocabulary.
            //
            // The priority tag is ONE level, and it is Todoist's own word for
            // it. The API numbers priority the OPPOSITE way round to the app:
            // `4` is what every Todoist screen calls **P1**, and `1` is the
            // default no-priority level — so a tag reading "Priority 4" would
            // be exactly backwards to the person who set it (§83), and only the
            // service's own label is safe to show. Only the top level lands:
            // p2 and p3 are ordinary, and four priority words would put one on
            // nearly every task, which is a tag that no longer narrows
            // anything.
            let priority: [String] = (task["priority"] as? Int) == 4 ? ["P1"] : []
            let project = (task["project_id"] as? String).flatMap { projects[$0] }
            thing.tags = tagList(priority + ((task["labels"] as? [String]) ?? [])
                                 + [project].compactMap { $0 })
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
            // THE JOIN LINK (2026-08-06) — the one actionable thing on a
            // booking, and it was being dropped. `content` holds the Cal.com
            // booking page, which is where you go to reschedule, not where the
            // meeting is. `meetingUrl` first (Cal.com's own resolved link),
            // then `location`, which carries a URL for a room you host
            // yourself and a machine slug ("integrations:daily") otherwise —
            // `httpLink` refuses the slug rather than landing a link that
            // opens nothing.
            thing.externalLink = httpLink(booking["meetingUrl"])
                ?? httpLink(booking["location"])
            // WHO IS COMING, as retrieval text only (2026-08-06). "the call
            // with Priya" is how a booking actually gets looked up, and the
            // names were nowhere in the corpus.
            //
            // NOT `summary`: that field is the source's own abstract — text the
            // service AUTHORED, which is what the booking description above
            // is — and a "With: …" line we composed ourselves is not that.
            // NAMES ONLY: an attendee's email address is their contact
            // details, not a fact about this meeting, and it would ride into
            // Spotlight and every agent grounding payload for a search nobody
            // types.
            let attendees = ((booking["attendees"] as? [[String: Any]]) ?? [])
                .compactMap { ($0["name"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !attendees.isEmpty {
                thing.enrichedText = attendees.joined(separator: ", ")
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
            let location = event["location"] as? [String: Any]
            let join = location?["join_url"] as? String
            let thing = Thing(
                kind: .event,
                title: name,
                content: join ?? "",
                source: "Calendly",
                capturedAt: IngestSupport.isoDate(event["start_time"]) ?? .now,
                sourceRef: "calendly:\(id)"
            )
            // Calendly's own notes on the meeting (2026-08-06) — written by
            // whoever set the event type up, so display copy, the Todoist
            // description rule. The plain-text field only: the HTML twin is
            // markup, not copy.
            if let notes = (event["meeting_notes_plain"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                thing.summary = notes
            }
            // THE HOST. `event_memberships` is whose booking page this is —
            // yourself on a personal account, and the teammate whose calendar
            // it was on a team one, which is the case worth having. It rides
            // `authorHandle`, the field every "whose" room is keyed by and the
            // one `Retriever` now scores like a tag, so "the call Dana hosted"
            // can find it. No surface draws it for an event row today; it is a
            // stored fact, not a claim on screen.
            thing.authorHandle = ((event["event_memberships"] as? [[String: Any]]) ?? [])
                .compactMap { ($0["user_name"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            // WHERE, when it is a place rather than a link — retrieval only.
            // `content` above already carries the join URL for a video call;
            // an in-person booking's address is a real fact about it, but
            // composing "Location: …" into `summary` would be putting our own
            // sentence in the field that means "what the source wrote" (the
            // Cal.com attendee reasoning).
            //
            // `invitees_counter` is deliberately unread: it is a tally, and a
            // tally is never a thing.
            if join == nil, let place = (location?["location"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !place.isEmpty {
                thing.enrichedText = place
            }
            return thing
        }
    }

    /// Notion — the pages connected to your integration, newest edits first.
    /// Pages only, by ruling — databases stay behind.
    ///
    /// This is the LISTING: titles, properties and covers, which is everything
    /// `/v1/search` answers with. A page's own words are a second read per page
    /// and live in `notionBodies`, which `refresh` runs after the landing loop.
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
            // Everything the page files itself under, and the deadline it
            // names if it names one (2026-08-06) — until now every property
            // but the title was read past. See both helpers for what is
            // deliberately not read: a status never becomes a `mark`, and a
            // date property is only a deadline when it says so.
            thing.tags = tagList(notionTags(props))
            thing.dueAt = notionDue(props)
            return thing
        }
    }

    /// The words a Notion page files itself under — its `select`, `status` and
    /// `multi_select` properties, which are the only ones whose values come
    /// from a fixed list somebody picked from rather than being typed fresh
    /// each time.
    ///
    /// A `status` lands as a TAG and never as a `mark`. Notion's statuses are
    /// user-created and user-named ("Shipped", "Icebox", "Done ✅"), so reading
    /// completion out of one would be `trelloMark`'s ruling in a third product:
    /// pattern-matching somebody's private vocabulary, and wrong for anyone
    /// whose board isn't in English or doesn't use the word.
    ///
    /// Property ORDER is Notion's, which is a dictionary's, which is to say
    /// none — so the names are sorted before the values are read. Without that,
    /// a page with more than `tagLimit` options would keep a different dozen on
    /// every sync.
    private static func notionTags(_ props: [String: Any]) -> [String] {
        var out: [String] = []
        for key in props.keys.sorted() {
            guard let prop = props[key] as? [String: Any],
                  let type = prop["type"] as? String else { continue }
            switch type {
            case "select", "status":
                if let name = (prop[type] as? [String: Any])?["name"] as? String {
                    out.append(name)
                }
            case "multi_select":
                out += names(in: prop["multi_select"])
            default:
                continue
            }
        }
        return out
    }

    /// The property names this reads as a deadline. Tiny and English on
    /// purpose — see `notionDue`.
    private static let notionDueNames: Set<String> = [
        "due", "due date", "duedate", "deadline",
    ]

    /// A Notion page's DEADLINE, when it names one — and nil the rest of the
    /// time, which is most of the time.
    ///
    /// Notion gives a `date` property no meaning of its own: "Created",
    /// "Reviewed on", "Published" and "Due" are all the same type, so the only
    /// thing separating a deadline from a stamp is what somebody called it.
    /// That is one step from `trelloMark`'s ruling, and only one — the
    /// difference is which way each fails. Trello's inference would MARK a card
    /// done off a list name; this one either recognizes a name or sets nothing,
    /// so a page whose vocabulary this doesn't know keeps its date to itself
    /// and the row reads exactly as it did before. `dueAt` is loud (Coming up,
    /// the overdue ask, the sheet's due row, "Add to Reminders"), which is why
    /// the list names deadlines only: no "date", no "when", nothing that could
    /// as easily be a start.
    ///
    /// The EARLIEST match wins when a page carries two. Not a judgement about
    /// which is the real deadline — a rule that makes the answer the same on
    /// every sync, since property order is a dictionary's and picking "the
    /// first" would flip between runs.
    private static func notionDue(_ props: [String: Any]) -> Date? {
        var found: [Date] = []
        for (key, value) in props {
            guard notionDueNames.contains(key.lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)),
                  let prop = value as? [String: Any],
                  prop["type"] as? String == "date",
                  let start = (prop["date"] as? [String: Any])?["start"] as? String
            else { continue }
            // A Notion date is either a full timestamp or a bare calendar day,
            // the same fork Todoist's `due` takes.
            if let when = IngestSupport.isoDate(start) ?? Self.allDayDate(start) {
                found.append(when)
            }
        }
        return found.min()
    }

    /// The retrieval clamp on a page body — `ObsidianNote.retrievalLimit`'s
    /// number, for its reason: long enough that a real page arrives whole,
    /// bounded enough that one pathological page can't put a megabyte into a
    /// column every `@Query` may fault.
    private static let notionBodyLimit = 8_000
    /// How many pages may have their body read in one sync.
    private static let notionBodyCap = 6
    private static let notionAskedKey = "notion.body.asked"
    /// A bound on the ledger itself, so a huge workspace can't grow a
    /// UserDefaults array without end. Trimming re-opens a page to being asked
    /// once more, which costs one request and lands the same text — the safe
    /// direction for a bound to be wrong in.
    private static let notionAskedLimit = 2_000

    /// The page's own WORDS (2026-08-06) — the half of Notion this bridge
    /// never read.
    ///
    /// `/v1/search` answers with a page's properties and no body at all, so a
    /// connected Notion was a list of titles: a page called "Q3 planning" could
    /// be found by those two words and by nothing written inside it. The body
    /// costs one request per page (`/v1/blocks/{id}/children`), which is why
    /// this is a separate bounded pass rather than part of the fetch.
    ///
    /// It lands on `enrichedText`, retrieval-only by the 2026-07-15 ruling —
    /// nothing draws it. That is the right field twice over: the text is ours,
    /// assembled out of Notion's block tree, not an abstract Notion authored
    /// and handed over (which is what `summary` means); and a page body is
    /// exactly what the retriever and the answer path were missing.
    ///
    /// Bounded three ways, each a real ceiling rather than a precaution:
    ///   · TOP-LEVEL BLOCKS ONLY. A nested block's children are their own
    ///     request, so a page written inside toggles arrives as its outline.
    ///   · ONE PAGE OF BLOCKS (Notion's own 100 maximum), clamped to
    ///     `notionBodyLimit`.
    ///   · ASKED ONCE, ever. A page that answered is never asked again, so an
    ///     empty one — a heading and a picture, no text — can't cost a request
    ///     every sync forever. The price is the honest one: a page edited after
    ///     it landed keeps the body it had. Only an ANSWER spends the ask; a
    ///     read that never reached Notion is left to try again.
    ///
    /// **UNMEASURED**, like the rest of this bridge's newer reads. Every failure
    /// path leaves the row exactly as it is, so it fails safe.
    @MainActor
    private static func notionBodies(_ token: String, context: ModelContext) async {
        var asked = Set(UserDefaults.standard.stringArray(forKey: notionAskedKey) ?? [])
        // Refs as plain STRINGS before the first await — nothing below holds a
        // `Thing` across a suspension (the corollary-6 rule); the rows are
        // re-fetched after the reads are done.
        let wanted = IngestSupport.thingsByRef(context, source: "Notion")
            .filter { $0.value.enrichedText == nil && !asked.contains($0.key) }
            .keys.sorted().prefix(notionBodyCap)
        guard !wanted.isEmpty else { return }

        var bodies: [String: String] = [:]
        for ref in wanted {
            let read = await notionPageText(String(ref.dropFirst("notion:".count)),
                                            token: token)
            guard read.answered else { continue }
            asked.insert(ref)
            if !read.text.isEmpty { bodies[ref] = read.text }
        }
        UserDefaults.standard.set(Array(asked.prefix(notionAskedLimit)),
                                  forKey: notionAskedKey)
        guard !bodies.isEmpty else { return }

        let landed = IngestSupport.thingsByRef(context, source: "Notion")
        var changed = false
        for (ref, text) in bodies {
            guard let thing = landed[ref], thing.enrichedText == nil else { continue }
            thing.enrichedText = text
            // The richer text is what the index should read (see
            // `Thing.enrichedText`), so the vector written from the title alone
            // is dropped rather than left standing.
            thing.embedding = nil
            changed = true
        }
        if changed { context.saveHonestly() }
    }

    /// One page's top-level blocks as plain text.
    ///
    /// `answered` separates "Notion says this page has no words" from "the read
    /// never reached Notion" — only the first may spend the page's one ask.
    private static func notionPageText(_ id: String,
                                       token: String) async -> (answered: Bool, text: String) {
        guard let root = await IngestSupport.getJSON(
            "https://api.notion.com/v1/blocks/\(id)/children?page_size=100",
            auth: "Bearer \(token)",
            headers: ["Notion-Version": "2022-06-28"]) as? [String: Any],
              let blocks = root["results"] as? [[String: Any]] else { return (false, "") }
        var lines: [String] = []
        for block in blocks {
            // Every text block in Notion's tree keeps its words in the same
            // place — a `rich_text` array under a key named after the block's
            // own type — so this needs no list of block types to maintain, and
            // a type Notion ships tomorrow reads correctly on the day.
            guard let type = block["type"] as? String,
                  let body = block[type] as? [String: Any],
                  let rich = body["rich_text"] as? [[String: Any]] else { continue }
            let line = rich.compactMap { $0["plain_text"] as? String }.joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty { lines.append(line) }
        }
        return (true, String(lines.joined(separator: "\n").prefix(notionBodyLimit)))
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
        //
        // `priority`, `priorityLabel`, `labels` and `project` ride along
        // (2026-08-06): the SELECTION is the ceiling for this bridge, so a
        // field nobody asks for isn't dropped downstream, it was never on the
        // wire — which is why none of these four could reach the corpus before.
        // Note the cliff they share with the App Store Connect bridge's
        // projections: a field name Linear doesn't serve is a 400 for the WHOLE
        // query, so the room empties rather than losing one column. All four
        // are core `Issue` fields; introspect before adding a fifth.
        let query = """
        { viewer { assignedIssues(first: 30, orderBy: updatedAt) \
        { nodes { id identifier title url updatedAt dueDate description \
        priority priorityLabel state { type } labels { nodes { name } } \
        project { name } } } } }
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
            // The four fields the selection above added (2026-08-06).
            //
            // The priority tag is ONE level and it is Linear's own word for it
            // (`priorityLabel` — "Urgent"), never a number: Linear counts
            // priority UP from 1 = Urgent while Todoist counts it DOWN to
            // 4 = P1 (see `todoist`), so any shared numeric scale in this file
            // would be exactly backwards for one of the two. `0` means "no
            // priority", which is why the test is `== 1` and not `<= 1`.
            let priority: String? = (node["priority"] as? Double) == 1
                ? (node["priorityLabel"] as? String) : nil
            let project = (node["project"] as? [String: Any])?["name"] as? String
            thing.tags = tagList([priority].compactMap { $0 }
                                 + names(in: (node["labels"] as? [String: Any])?["nodes"])
                                 + [project].compactMap { $0 })
            return thing
        }
    }

    // MARK: - Payload helpers (shared by the bridges above)

    /// How many of a service's own tags one thing may bring — the
    /// `ObsidianNote.tagLimit` number, for its reason: a service with a
    /// tag-per-thought habit would otherwise put hundreds of one-use words on
    /// the feed's filter surface, where the useful dozen become unfindable.
    private static let tagLimit = 12

    /// A service's own tags, normalized for the corpus's tag rail.
    ///
    /// Every app in this file lets you name your own tags and hands them over
    /// as free text: blank strings, a stray `#`, the same word twice in two
    /// cases, fifty on one item. `ObsidianNote.normalize` learned those lessons
    /// for the vault; these are the same rules for the keyed bridges,
    /// deliberately kept here rather than shared, so a change to how a vault
    /// reads its frontmatter can never quietly re-tag every bookmark.
    ///
    /// ORDER IS THE CONTRACT, because the cap truncates: a caller passes the
    /// service's own FIXED words first (a Readwise category, a Todoist P1, a
    /// Raindrop type — words nobody typed, meaning the same thing on every
    /// account), then the person's own tags, then the container the thing sits
    /// in (a project, a shelf). A pathological item loses its container name,
    /// never the word that says what it is.
    private static func tagList(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for candidate in raw {
            var tag = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            while tag.hasPrefix("#") { tag.removeFirst() }
            tag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty, tag.count <= 40,
                  tag.rangeOfCharacter(from: .letters) != nil,
                  seen.insert(tag.lowercased()).inserted else { continue }
            out.append(tag)
            if out.count == tagLimit { break }
        }
        return out
    }

    /// The `name` field out of a list of objects — the shape four of these
    /// services hand tags over in (Readwise's `{id, name}`, a Trello label, a
    /// Notion multi-select option, a Linear label node). An entry with no name
    /// yields nothing rather than a placeholder.
    private static func names(in raw: Any?) -> [String] {
        ((raw as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }
    }

    /// A link a payload handed us, or nil. `IngestSupport.imageURL` does this
    /// for pictures; a permalink needs the same guard and must not be told it
    /// is one. Anything that isn't a parseable http(s) address — an empty
    /// string, a Cal.com `location` reading "integrations:daily" — comes back
    /// nil rather than as something a tap would fail on.
    private static func httpLink(_ raw: Any?) -> String? {
        guard let s = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty, s.hasPrefix("https://") || s.hasPrefix("http://"),
              URL(string: s) != nil else { return nil }
        return s
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
            guard let ref = thing.sourceRef, let now = byRef[ref] else { continue }
            // Tags MERGE, never replace (2026-08-06) — the same reasoning in
            // both reconcilers. Dedupe skips a known ref, so without this an
            // issue that landed before labels were read would never get them;
            // and a tag on a landed row is not necessarily ours (a project in
            // this app IS a tag), so assigning the fresh list wholesale would
            // delete somebody's filing. A label removed in Linear therefore
            // stays here, which is the safe direction to be wrong in.
            let missing = now.tags.filter { !thing.tags.contains($0) }
            if !missing.isEmpty {
                thing.tags += missing
                changed = true
            }
            guard now.mark != thing.mark else { continue }
            thing.mark = now.mark
            changed = true
        }
        if changed { context.saveHonestly() }
    }

    /// GitLab — issues AND merge requests assigned to you, across every
    /// project on GitLab.com, via its REST API v4. Personal access tokens
    /// ride the `PRIVATE-TOKEN` header, GitLab's own scheme, never Bearer.
    ///
    /// Self-hosted GitLab is out of scope — this reads `gitlab.com` only,
    /// same simplification `linear`/`trello`/every token bridge here makes
    /// for the SaaS-hosted product rather than a self-hosted install with an
    /// arbitrary base URL.
    ///
    /// Neither read is filtered to `state=opened`: an unfiltered
    /// `scope=assigned_to_me` ordered by `updated_at` mirrors `linear`'s own
    /// choice exactly — a row recently closed or merged is still one of the
    /// 30 most recently updated, which is what lets `reconcileGitlab` below
    /// catch the transition into done rather than needing a second read.
    ///
    /// Issues are required (a failure there means a broken connection);
    /// merge requests are read the same way but a failure there doesn't fail
    /// the whole pass — the Trello `boards`-optional shape, generalized to a
    /// second primary content stream rather than a decorative lookup.
    private static func gitlab(_ token: String) async -> [Thing]? {
        guard let issues = await IngestSupport.getJSON(
            "https://gitlab.com/api/v4/issues?scope=assigned_to_me&per_page=30&order_by=updated_at",
            headers: ["PRIVATE-TOKEN": token]) as? [[String: Any]] else { return nil }
        let mergeRequests = await IngestSupport.getJSON(
            "https://gitlab.com/api/v4/merge_requests?scope=assigned_to_me&per_page=30&order_by=updated_at",
            headers: ["PRIVATE-TOKEN": token]) as? [[String: Any]] ?? []
        return issues.compactMap { gitlabThing($0, refPrefix: "issue") }
            + mergeRequests.compactMap { gitlabThing($0, refPrefix: "mr") }
    }

    /// One GitLab issue or merge request → a `Thing`. Both payloads share
    /// every field this reads, so one function covers both — the split is
    /// only in `refPrefix`, which keeps an issue's id and an MR's id from
    /// colliding in `sourceRef` (the two are separate integer sequences and
    /// GitLab can hand back the same number for both).
    private static func gitlabThing(_ node: [String: Any], refPrefix: String) -> Thing? {
        guard let id = node["id"] as? Int,
              let title = (node["title"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
              let url = node["web_url"] as? String else { return nil }
        // `references.full` is GitLab's own identifier string — e.g.
        // "group/project#123" for an issue, "group/project!45" for an MR —
        // so the `#`/`!` already says which this is; no separate label is
        // needed the way Linear's `identifier` needed one.
        let ref = (node["references"] as? [String: Any])?["full"] as? String
        let thing = Thing(
            kind: .link,
            title: ref.map { "\($0) · \(title)" } ?? title,
            content: url,
            source: "GitLab",
            capturedAt: IngestSupport.isoDate(node["updated_at"]) ?? .now,
            sourceRef: "gitlab:\(refPrefix):\(id)"
        )
        thing.mark = gitlabMark(node["state"] as? String)
        // Only an issue carries `due_date` (an all-day date) — a merge
        // request has none, and stays honestly nil rather than guessing one
        // from `target_branch` or a milestone.
        if let due = node["due_date"] as? String {
            thing.dueAt = allDayDate(due)
        }
        if let body = (node["description"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
            thing.summary = body
        }
        // GitLab's own labels ride the REST payload as a plain array of
        // strings already — unlike Linear's/Trello's `{name: …}` objects,
        // there's no `names(in:)` unwrap needed.
        thing.tags = tagList((node["labels"] as? [String]) ?? [])
        return thing
    }

    /// GitLab's own state vocabulary → the corpus's mark. `opened` is the
    /// only state this bridge should ever call `.todo`; every other value —
    /// `closed` (an issue closed or an MR declined), `merged`, `locked` — is
    /// treated as done, the Trello two-state simplification (`trelloMark`)
    /// rather than Linear's seven-way table, because GitLab's REST state
    /// field carries no equivalent breakdown to introspect against.
    private static func gitlabMark(_ state: String?) -> Mark {
        state == "opened" ? .todo : .done
    }

    /// Re-marks GitLab issues/MRs already in the corpus on every sync — the
    /// `reconcileLinear` shape exactly, including the loop-closer moment: an
    /// issue or MR you were carrying getting closed/merged is real news, a
    /// plain field edit isn't.
    @MainActor
    static func reconcileGitlab(_ fresh: [Thing], context: ModelContext) {
        let byRef = Dictionary(fresh.map { ($0.sourceRef ?? "", $0) },
                               uniquingKeysWith: { a, _ in a })
        guard !byRef.isEmpty else { return }
        let existing = (try? context.fetch(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "GitLab" }))) ?? []
        var changed = false
        for thing in existing {
            guard let ref = thing.sourceRef, let now = byRef[ref] else { continue }
            let missing = now.tags.filter { !thing.tags.contains($0) }
            if !missing.isEmpty {
                thing.tags += missing
                changed = true
            }
            guard now.mark != thing.mark else { continue }
            thing.mark = now.mark
            changed = true
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
    ///
    /// `badges` is deliberately unread: its checklist, comment and attachment
    /// numbers are tallies, and a tally is never a thing (module doctrine).
    /// "3 of 7 done" would also be a state that goes stale the moment somebody
    /// ticks the next box, on a row nothing re-reads.
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
            // YOUR LABELS (2026-08-06). A label with no name is skipped, and
            // that is not tidiness: a colour-only label is ordinary on a Trello
            // board and means whatever its members agreed it means, so filing
            // one as "green" would be inventing the single thing the card
            // doesn't say.
            thing.tags = tagList(names(in: card["labels"]))
            // The card's COVER, when it is a picture that can actually be
            // loaded. Only a SHARED-SOURCE cover lands — an Unsplash picture,
            // whose URL is public. A cover backed by an ATTACHMENT is
            // deliberately skipped: Trello serves attachment bytes only to an
            // authenticated request, and the loader that draws a row's thumb
            // sends no Authorization header, so landing one would paint a hole
            // where a picture was claimed.
            //
            // UNMEASURED like the rest of this bridge: `sharedSourceUrl` is
            // documented as the cover's own source. If it turns out to name a
            // page rather than a picture, the row shows what it shows today —
            // nothing — rather than something wrong.
            thing.previewImageURL = IngestSupport.imageURL(
                (card["cover"] as? [String: Any])?["sharedSourceUrl"] as? String)
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
            guard let ref = thing.sourceRef, let now = byRef[ref] else { continue }
            // Additive, for `reconcileLinear`'s reasons exactly — a card that
            // landed before labels were read gains them, and nothing this app
            // or the person filed on the row is taken away.
            let missing = now.tags.filter { !thing.tags.contains($0) }
            if !missing.isEmpty {
                thing.tags += missing
                changed = true
            }
            guard now.mark != thing.mark else { continue }
            thing.mark = now.mark
            changed = true
        }
        if changed { context.saveHonestly() }
    }

    /// Jira — the issues assigned to you, across every project, newest-
    /// updated 50 (`JiraAuth.jql`'s own note on why nothing is filtered
    /// server-side). No key, no email, no requests: the honest nil `refresh`
    /// words as "check the token" — Trello's rule, and right for the same
    /// reason: two missing credentials out of three is a broken connection,
    /// not a partial one.
    private static func jira(_ token: String) async -> [Thing]? {
        guard let domain = JiraAuth.storedDomain, !domain.isEmpty,
              let email = JiraAuth.storedEmail, !email.isEmpty,
              let auth = JiraAuth.header(email: email, token: token) else { return nil }
        guard let root = await IngestSupport.getJSON(
            JiraAuth.searchURL(domain: domain), auth: auth, service: "Jira") as? [String: Any],
              let issues = root["issues"] as? [[String: Any]] else { return nil }
        return issues.compactMap { issue in
            guard let key = issue["key"] as? String,
                  let fields = issue["fields"] as? [String: Any],
                  let summary = (fields["summary"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty
            else { return nil }
            // The key LEADS, the Linear-identifier/Trello-board rule — but
            // unlike either, nothing else needs joining in front of it: a
            // Jira key already carries its project's own short code
            // ("PROJ-123"), so it is legible on its own the way a bare Trello
            // card name or a bare Linear title isn't.
            let thing = Thing(
                kind: .reminder,
                title: "\(key) · \(summary)",
                content: "https://\(domain)/browse/\(key)",
                source: "Jira",
                capturedAt: jiraDate(fields["updated"]) ?? .now,
                sourceRef: "jira:\(domain):\(key)"
            )
            let status = fields["status"] as? [String: Any]
            let category = (status?["statusCategory"] as? [String: Any])?["key"] as? String
            thing.mark = jiraMark(category)
            // `duedate` is a bare calendar day ("2026-08-20"), Todoist's and
            // Linear's shape — noon local, never midnight (`allDayDate`'s own
            // reasoning). Trello's `due` needs none of this because it's
            // already a full timestamp; Jira's isn't.
            thing.dueAt = (fields["duedate"] as? String).flatMap(Self.allDayDate)
            // YOUR LABELS, Trello's exact ruling and for the same reason: a
            // project's workflow STATUS name is user-renamed per project
            // (`jiraMark`'s own note), so pattern-matching it into a tag would
            // mean tagging with arbitrary per-project vocabulary and getting
            // it wrong for any project that isn't in English or doesn't use
            // the word. Priority is the same shape one field over — Jira's
            // default five levels can be renamed or replaced per instance, so
            // there is no fixed "Urgent" this file can safely assume the way
            // `linearMark` can. Labels and the project name are the only two
            // fields here nobody can rename out from under this bridge.
            thing.tags = tagList(names(in: fields["labels"])
                                 + [(fields["project"] as? [String: Any])?["name"] as? String]
                                    .compactMap { $0 })
            return thing
        }
    }

    /// Jira's own status-category vocabulary → the corpus's mark. FIXED
    /// across every project regardless of a workflow's custom status names —
    /// Jira ships exactly three categories ("new", "indeterminate", "done")
    /// and every custom status belongs to one of them, the `state { type }`
    /// shape `linearMark` already leans on for the identical reason.
    /// Unrecognized reads `.none` — `linearMark`'s own ruling: a mark we
    /// can't justify is worse than no mark.
    private static func jiraMark(_ category: String?) -> Mark {
        switch category {
        case "new":           return .todo
        case "indeterminate": return .doing
        case "done":          return .done
        default:              return .none
        }
    }

    /// Jira's own timestamp shape — a millisecond offset with NO colon
    /// ("2026-08-06T10:15:30.000+0000", Atlassian's documented example) —
    /// which `IngestSupport.isoDate`'s `ISO8601DateFormatter` does not parse:
    /// `.withInternetDateTime` expects a colon-separated zone ("+00:00") or a
    /// bare "Z", and Jira's format has neither. A dedicated `DateFormatter`
    /// reads it instead, `allDayDate`'s own precedent for a field
    /// `ISO8601DateFormatter` can't. UNMEASURED like the rest of this bridge
    /// — re-verify against a real `updated` value before trusting it.
    private static func jiraDate(_ raw: Any?) -> Date? {
        guard let s = raw as? String else { return nil }
        return jiraDateFormatter.date(from: s)
    }
    private static let jiraDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return f
    }()

    /// Re-marks Jira issues already in the corpus on every sync — an issue
    /// closed in Jira has to stop reading as open here (`reconcileTrello`'s
    /// own shape, and the same loop-closer moment). Scoped to issues this
    /// pass actually SAW, `reconcileLinear`'s reasoning rather than Trello's
    /// own caveat: `JiraAuth.jql` carries no status filter at all (unlike
    /// Trello's `filter=open`), so an issue that stops arriving really did
    /// fall out of the newest-50 window rather than close, and one that DID
    /// arrive carries a mark that's fresh as of this very pass.
    @MainActor
    static func reconcileJira(_ fresh: [Thing], context: ModelContext) {
        let byRef = Dictionary(fresh.map { ($0.sourceRef ?? "", $0) },
                               uniquingKeysWith: { a, _ in a })
        guard !byRef.isEmpty else { return }
        let existing = (try? context.fetch(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == "Jira" }))) ?? []
        var changed = false
        for thing in existing {
            guard let ref = thing.sourceRef, let now = byRef[ref] else { continue }
            let missing = now.tags.filter { !thing.tags.contains($0) }
            if !missing.isEmpty {
                thing.tags += missing
                changed = true
            }
            guard now.mark != thing.mark else { continue }
            thing.mark = now.mark
            changed = true
        }
        if changed { context.saveHonestly() }
    }

    /// Raindrop — newest 30 bookmarks across all collections, then the
    /// collections themselves (two more GETs) so a bookmark can name the shelf
    /// it sits on.
    private static func raindrop(_ token: String) async -> [Thing]? {
        guard let root = await IngestSupport.getJSON("https://api.raindrop.io/rest/v1/raindrops/0?perpage=30",
                                   auth: "Bearer \(token)") as? [String: Any],
              let items = root["items"] as? [[String: Any]] else { return nil }
        // Shelf names, id → title (2026-08-06). Two more GETs — Raindrop serves
        // top-level collections and nested ones on separate endpoints — in the
        // Trello board-name shape and for its reason: a failure leaves a
        // bookmark without its shelf, which is worse-labelled, not wrong.
        //
        // System collections are skipped by their own sign: Raindrop numbers
        // "Unsorted" -1 and "Trash" -99, and neither is a shelf anyone chose.
        var collections: [Int: String] = [:]
        for path in ["collections", "collections/childrens"] {
            guard let list = (await IngestSupport.getJSON(
                "https://api.raindrop.io/rest/v1/\(path)",
                auth: "Bearer \(token)") as? [String: Any])?["items"] as? [[String: Any]]
            else { continue }
            for collection in list {
                guard let id = collection["_id"] as? Int, id > 0,
                      let title = (collection["title"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                      !title.isEmpty else { continue }
                collections[id] = title
            }
        }
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
            // YOUR TAGS (2026-08-06). Raindrop's are first-class — the field
            // its whole interface is organized around, and the plainest thing
            // this bridge was dropping. Raindrop's own `type` leads them (a
            // fixed word nobody typed) and the shelf trails; see `tagList`.
            let shelf = (((item["collection"] as? [String: Any])?["$id"] as? Int)
                         ?? (item["collectionId"] as? Int)).flatMap { collections[$0] }
            thing.tags = tagList(raindropType(item["type"] as? String)
                                 + ((item["tags"] as? [String]) ?? [])
                                 + [shelf].compactMap { $0 })
            // Every picture Raindrop found on the page, not just the cover
            // (`media` is its own extraction, and the cover is usually its
            // first entry). `previewImageURL` above stays the row's single
            // thumb — this is the set a bigger surface would lay out, the way
            // a social post's has since 2026-07-16. An entry that names a type
            // other than an image is skipped rather than filed as one.
            var images: [String] = []
            for entry in (item["media"] as? [[String: Any]]) ?? [] {
                let type = entry["type"] as? String
                guard type == nil || type == "image",
                      let url = IngestSupport.imageURL(entry["link"] as? String),
                      !images.contains(url) else { continue }
                images.append(url)
            }
            thing.imageURLs = images
            return thing
        }
    }

    /// Raindrop's own `type` → one word for the tag rail, or none.
    ///
    /// Six fixed values, not free text, so a fixed map is safe here the way
    /// `readwiseCategory`'s is. "link" lands NOTHING on purpose: every Raindrop
    /// row is already a `.link` kind, so the tag would separate nothing from
    /// nothing. An unrecognized value lands nothing either — Raindrop adding a
    /// seventh kind should read as a bookmark with no type, never as a word
    /// whose spelling we guessed.
    private static func raindropType(_ raw: String?) -> [String] {
        switch raw {
        case "article":  ["Article"]
        case "image":    ["Image"]
        case "video":    ["Video"]
        case "document": ["Document"]
        case "audio":    ["Audio"]
        default:         []
        }
    }
}
