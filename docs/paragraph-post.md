# Casberi: your apps, one feed

I built an iPhone app called Casberi. The short version: connect your apps and everything lands in one private feed on your phone — no account, ever. Pin what matters, tag what's yours, act on things in the apps they came from. One button asks, organizes, and jumps to your tools. And because there's no server, your stuff never leaves your phone unless you send it somewhere yourself.

That's the elevator pitch. Here's the actual tour, and then the thinking behind it — the problems I kept hitting, and what I decided a fix actually needs to do.

## What it does

**Just connect.** There's no account and no sign-in — the app works the moment it's installed. You connect your apps: Mail, Photos, Calendar, wallets, GitHub, Farcaster, Bluesky, RSS, and dozens more. Everything they produce lands in one feed, newest first — one screen, no tabs. Filter with a chip row up top: everything together, or one app at a time. Screenshots get their text read on your iPhone, so you can search them and ask about them. And fresh finds land on their own — trending tokens and just-launched NFT drops show up in your feed without you hunting for them.

**Keep tabs.** Pin your favorites to a board arranged your way — a wallet's balance, a trip's plans, your recent casts. The board leads with what's coming up: events and due reminders, soonest first. Come back after a day away and one chip sums up what landed while you were gone. Each app's feed takes its own shape — Calendar reads like an agenda, Photos becomes a grid, a wallet leads with its balance. Watch a few wallets and see them as one combined view over everything you hold. Watch a token and it lands back in your feed when the price moves. Tags group things without folders — one thing can carry many.

**Take action.** One round button in the corner is where everything you do lives. Ask a question and it's answered from your own things, on your phone — "what did I save this week?" Tell it to organize — "tag these as Trip," "rename Work to Projects" — and it shows you exactly what will change before you tap Apply. Bring your own key and any answer can re-run on a bigger model — Claude, ChatGPT, Gemini, or Venice — but only when you tap, straight from your iPhone. Finish things at the source: complete a Todoist task or close a GitHub issue right from the thing, and it asks first, every time. Search Casberi and Ask Casberi ride Shortcuts and Siri. Paste something to save it, or tap the mic and talk.

**Make it yours.** Your photo up top, a color or picture of yours behind the board, five languages. Your data lives on your phone and syncs only if you turn it on — export it, import it, and when you want out, two clear wipes: your things, or Casberi's access. Wallets are read-only everywhere; Casberi can never trade or move funds.

## Why I built it

Everything you do creates something — a note, a link, a screenshot, a plan — and each one lands in a different app. The more apps you use, the more places you have to look, and the harder it gets to find and use your own stuff. AI assistants were supposed to help, but each one is another app with its own history and its own settings. That just adds to the pile.

This isn't abstract for me. I saved a recipe in Notes with no title and never found it again. My travel plan sat 40 messages deep in a chat; at the airport I asked again, and the new answer was missing the hotel address. I copied a dinner plan by hand into Calendar, Messages, and Safari, and the guest list never left the chat. And on the agent side: a run finished at 11pm, I found out at 8am, and the follow-up started a day late. A scheduled job died quietly and I noticed a week later — from the silence.

Sit with enough of those and they sort into a pattern. Eight problems, really:

1. **Everything takes copy-paste.** To finish anything, you copy, switch apps, and paste. And if agents do your work, your phone can't reach them at all.
2. **Saving scatters your stuff.** Where something ends up depends on how you saved it — and you're stuck with that choice.
3. **Organizing never ends.** Keeping things tidy means doing the same filing in every app, forever.
4. **Finding means remembering.** You have to recall which app holds the thing — and you find out it's lost right when you need it.
5. **Nothing gets finished.** An assistant's answer still has to be moved into the real app by hand. That's where it stalls.
6. **Setup doesn't stick.** Casual users skip it. Power users redo it for every machine and agent. Either way, none of it carries forward.
7. **Every AI app starts from zero.** A new assistant brings its own history, memory, and settings. Nothing is shared with the last one.
8. **You don't find out.** What you saved doesn't speak up when it matters, and your agents finish or fail in silence.

## What a fix actually needs

Once I had the problems written down, I stopped asking "what features should this have" and started asking what any real fix would *need* to be true. This is the list I held myself to:

**One home for your things.** Everything lands in one place. Notes, links, screenshots, events, chats, voice notes — they all become things in one feed. For power users, one job — its prompt, its output, its approval — is one thing, not four scattered pieces.

**Find by what it is.** One search covers everything, and you get the thing itself — not the chat it was buried in. Not "which app did I put that in," just "the flight confirmation."

**Capture in one gesture.** Save from anywhere in one step — no folder to pick, no title to type. Connected apps send their things in on their own, so most capture is zero gestures.

**Captures become outcomes.** A saved thing carries its next step. An event can go on your calendar, a task can become a reminder — right from the thing. The gap between "saved it" and "did it" is where everything dies, so the fix has to close it.

**Setup adds up.** It has to be useful before you set up anything, and ask for permissions only when they unlock something. What you set up once is kept — secrets live only in the Keychain — so nothing gets redone.

**Not another AI app.** It has to look and feel like an organizer, not a chatbot. No model picker in your face, no memory panel, no persona. Results, not a character.

**Feels like it came with your phone.** iOS type, iOS motion, iOS touch. The moment it feels like a web app in a trenchcoat, casual users bounce.

**Apps are bridges, and honest about it.** Connecting an app builds a bridge. Apple apps connect through iOS itself. Services connect with a login or a pasted token. Every app's page tells you which kind it is and exactly what shows up in your feed.

**Approvals carry context.** When something asks to act, the request shows you what you need to judge it — what exactly, who's asking, what it touches. Approve or deny with one tap. "It asks first" only counts if the ask is informative.

**Status arrives in your feed.** Run finished, run failed, scheduled job died — each shows up as a row. Even the thing that should have arrived but didn't. Silence is a bug.

## Yours, meaning yours

Casberi is a native iPhone app. Your things live in a database on your phone — no Casberi server holds them, because there is no Casberi server. iCloud sync is off until you turn it on. Reading and saving work offline. No analytics, no trackers. Answers are written on your own phone, and when you bring your own key for a bigger model, the call goes straight from your device to your provider.

Some things are missing on purpose. No note editor — Casberi collects and connects; your apps stay the editors. No separate to-do tab — you act on a thing where the thing is. No streaks, goals, or guilt mechanics. And no trading, ever.

Casberi is free on TestFlight while it heads to the App Store. If any of those eight problems felt personal, I'd love for you to try it and tell me where it breaks: https://casberi.app
