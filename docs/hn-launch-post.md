# Show HN: Casberi — your apps in one feed, no account, everything on-device

I've spent the last while building an iPhone app called Casberi, and I want to explain what it is and why I bothered, because the pitch sounds like a hundred other apps until you get to the part where there's no server.

## The itch

Everything I do creates something — a note, a link, a screenshot, a plan — and every one of those lands in a different app. The recipe with no title in Notes that I never found again. The travel plan buried 40 messages deep in a chat, so at the airport I asked the assistant again and the new answer was missing the hotel address. The dinner plan I copied by hand into Calendar, Messages, and Safari, while the guest list never left the group chat.

AI assistants were supposed to fix this, and instead each one is just another app with its own history and its own settings. I tried a second assistant once, ended up with two of everything, and deleted it within a week. If you run agents it's worse — a job leaves its prompt on one machine, its output on another, and the approval in a dashboard, and reassembling the story is your problem. A scheduled job of mine died quietly once and I noticed a week later, from the silence.

The underlying problem is that where something ends up depends on how you happened to save it, and you're stuck with that choice forever. Finding things means remembering which app holds them. And nothing ever gets *finished* — an assistant's answer still has to be moved into the real app by hand, which is exactly where everything stalls.

## What I built

Casberi is one screen. You connect your apps — Mail, Photos, Calendar, wallets, GitHub, RSS, Farcaster, Bluesky, a few dozen others — and everything they produce lands in one feed as "things." A row of chips along the top filters by app; tap one and the feed takes that app's shape (Calendar reads like an agenda, Photos becomes a grid, a wallet leads with its balance). Pin what matters to a board you arrange yourself. That's most of the app.

There's one round button in the corner. Tap it and you can ask a question, and it gets answered from your own stuff — "what did I save this week?" By default that runs entirely on the phone with the on-device model: nothing sent anywhere, nothing billed. If you want a bigger model, you can bring your own key — Claude, ChatGPT, Gemini, or Venice — and re-run any answer on it. That *does* send the relevant things to that provider, but only when you explicitly tap, straight from your phone to their API, on your own key. No middleman, and never by default. You can also tell it to organize ("tag these as Trip", "rename Work to Projects") and it shows you the exact diff before you tap Apply.

Screenshots get OCR'd on-device, so the text in them is searchable and askable. Search Casberi and Ask Casberi ride Shortcuts and Siri, so you can pipe your corpus into automations. Come back after a day away and one chip sums up what landed while you were gone.

## The part I actually care about

There is no account. Not "sign in with Apple" — nothing. The app works the moment it's installed. Your things live in a database on your phone; no Casberi server holds them, because there is no Casberi server. iCloud sync exists but stays off until you turn it on. No analytics, no trackers. Reading and saving work offline.

The bridges are read-only wherever they can be. Connected wallets can never trade or move funds — that's not a setting, it's just not in the app. Where a bridge *can* write (complete a Todoist task, close a GitHub issue from the thing itself), it asks first, every time. GitHub connects over the device flow: a short code, one tap to github.com, read-only scope, revocable anytime. No token hunting.

Deleting is two separate verbs, because they're two separate promises: **Delete things** wipes your data (phone and iCloud), and **Delete access** removes every token and key the app holds. Each screen tells you what goes and what stays.

## What's deliberately missing

Some absences are on purpose, and I've defended them against my own feature-brain more than once. There's no chatbot persona, and no model picker in your face — the bring-your-own-key stuff lives in settings, and the main path is just: ask, get an answer. Casberi shows results, not a character. No note editor: it collects and connects, your apps stay the editors. No separate to-do tab — you act on a thing where the thing is. No streaks, no goals, no guilt mechanics. Typed text in the composer never saves silently; things only enter through deliberate capture. And no trading, ever.

## Honest caveats

It's iPhone-only and leans on iOS 26 for the on-device model. It's free on TestFlight while it heads to the App Store. I'm one person, so the bridge catalog grows at the speed of one person — though the keyless ones (Farcaster over Snapchain, Bluesky over the public AppView) have been a pleasant surprise in how far you can get without asking anyone for an API key.

I built this because I wanted my phone to be the place where my own stuff is findable and finishable, without renting that ability from anyone's server. If that itch sounds familiar, I'd genuinely like to hear where it breaks for you.

Docs and TestFlight link: https://casberi.app
