# App Store submission — Casberi

Everything needed to turn the current TestFlight build into a live App Store release.
TestFlight beta approval does **not** carry to the App Store — Apple re-reviews the build
against the full App Store Review Guidelines. This doc is the prep; the steps marked
**[you, in App Store Connect]** can only be done by you in the ASC web UI.

---

## 0. Prerequisites

- [x] Apple Developer Program membership **active** (confirmed by user, 2026-07-17).
- [ ] The build you want to ship is uploaded and shows in App Store Connect → TestFlight.
      (Reuse the exact build public testers are on — no rebuild needed.)

---

## 1. Store listing copy (paste-ready)

Character limits are Apple's hard caps. Counts shown are for the text as written.

### App Name  *(≤30)*
```
Casberi
```
*(7)*

### Subtitle  *(≤30)*
```
One home for your things
```
*(24)* — Alternatives: `Everything you make, one home` (29) · `Your things, private, on-device` (30)

### Promotional text  *(≤170 — editable anytime without review)*
```
Screenshots, links, notes, events, chats — everything you capture lands in one private home on your iPhone. Ask it anything. Nothing leaves your phone.
```
*(150)*

### Keywords  *(≤100, comma-separated, NO spaces — spaces waste the budget)*
```
second brain,capture,screenshots,notes,organizer,private,on-device,bookmarks,save,links,feed,memory
```
*(99)*
- **Do not** put competitor/trademarked names (ChatGPT, Notion, etc.) in keywords — Apple rejects them.
- Don't repeat the app name or subtitle words here; they're already indexed.

### Description  *(≤4000)*
```
Casberi is one private home for everything you make.

Every screenshot you take, link you save, note you jot, event on your calendar, voice memo, and chat becomes a "thing" — captured in one gesture, with no folder to pick and no title to write. It all lands in one place, on your iPhone.

CAPTURE WITHOUT FRICTION
• Share anything from any app — it lands instantly, no filing.
• Screenshots flow in on their own once Photos is connected.
• Tap the mic for a voice note; it's transcribed and stays findable.
• Paste a link and Casberi reads the page so you don't have to.

FIND BY WHAT IT IS
One search across everything you've kept. Ask in plain words — "what did I save about the trip" — and get the actual things back, most relevant first. No remembering which app it was in.

ANSWERS ON YOUR DEVICE
On iPhones with Apple Intelligence, Casberi writes answers from your things using Apple's on-device model. Your data isn't sent to us, to Apple's servers, or to anyone. Casberi can only answer from things you actually saved — it never invents.

CONNECT YOUR APPS, KEEP THE DATA YOURS
Bring in what you already use — RSS feeds, Bluesky, Farcaster, Apple Health workouts, your calendar and reminders, GitHub, Todoist, Notion, Linear, and more. Casberi talks to each service directly from your iPhone. Tokens and keys live in your device Keychain and are never uploaded.

BUILT SO YOUR THINGS STAY YOURS
• No account. No sign-up. No password to give us.
• No analytics, no tracking, no ads.
• No Casberi server holds your things — there's no backend at all.
• Optional iCloud sync through your own private iCloud account (off by default).
• Export everything to a single file, any time. Delete everything for real.

Casberi isn't another chatbot to configure. It's an organizer that happens to be smart — one home, on your phone, that stays yours.
```
*(~1,760 — well under the cap; room to expand if you like)*

### What's New (version notes)  *(≤4000)*
For a first public release, keep it simple:
```
Casberi's first public release. One private home on your iPhone for everything you capture — screenshots, links, notes, events, voice memos, and more. Ask it anything; nothing leaves your phone.
```

### Support URL  *(required)*
```
https://casberi.app
```
(or a dedicated `https://casberi.app/support` if you add one)

### Marketing URL  *(optional)*
```
https://casberi.app
```

### Privacy Policy URL  *(required — verified live)*
```
https://casberi.app/privacy.html
```
✅ Reachable, effective July 8, 2026, and covers on-device storage, iCloud, third-party
connections, BYOK keys, no-tracking, TestFlight, and children. This is a strong asset.

### Category
- Primary: **Productivity**
- Secondary: **Utilities** (optional)

### Copyright
```
2026 Casberi
```
(Apple wants `YEAR Entity` — adjust to your legal entity/name.)

---

## 2. Screenshots  **[you — must be produced]**

This is the one remaining *asset* gap. Apple requires screenshots for:
- **6.9" iPhone** (iPhone 16/17 Pro Max class) — **required**, 1320×2868 or 2868×1320.
- 6.5" is accepted as a fallback for older sizes but 6.9" is the current requirement.
- 2–10 images. First 2–3 are what most people see — make them count.

Suggested set (all capturable on the iPhone 17 Pro sim per CLAUDE.md hooks):
1. **Home** — the synthesis surface with cover + tag map ("What's going on").
2. **Feed** — the record, source chips, a few real rows.
3. **Composer answering** — a plain-language question with real things returned.
4. **A thing sheet** — screenshot thing with its image + spec table.
5. **Apps store** — the catalog, showing the breadth of connectors.
6. **Settings → Data** — the trust surface (on-device, iCloud off by default, export/delete).

> I can drive the sim and produce these — just say the word and I'll capture a candidate set
> at the right resolution (light or dark). Screenshots are marketing assets, so you approve them.

---

## 3. App Privacy "nutrition label"  **[you, in App Store Connect]**

Answer the App Privacy questionnaire. Based on the code and privacy policy, the honest answers:

- **Does the app collect data?**
  - Casberi itself: **No** — no backend, no analytics, no tracking, no ads.
  - **Caveat:** the questionnaire asks about *all* data collection including third parties.
    Your privacy policy already discloses:
    - **Connected services** (GitHub, Bluesky, Notion, market APIs, etc.) receive requests
      directly from the device. That's the *user's* data going to *their* service, not you
      collecting it — but be ready to explain it if asked. It does **not** make you a data
      collector for the label.
    - **BYOK AI providers** (Anthropic/OpenAI/Google/Venice) — only when the user taps
      "Try with your key," their query + matched things go to that provider. Again the user's
      choice, direct from device; you don't collect it.
    - **Apple TestFlight** diagnostics are Apple's collection, not yours.
  - Recommended label answer: **"Data Not Collected."** This is defensible given there is no
    Casberi backend. If you want to be maximally conservative you could declare nothing, since
    all outbound data goes to the user's own chosen services, not to Casberi.

- **Tracking (ATT):** **No tracking.** No IDFA, no ad networks, no cross-app tracking. Do not
  add the ATT prompt — you don't need it.

---

## 4. Info.plist permission strings  ✅ audited

All present and specifically worded (Apple rejects vague ones). Current set:
Apple Music, Camera, Calendars (full + write-only), Contacts, Health (share + update),
Microphone, Photo Library, Reminders, Speech Recognition. All read clean.

---

## 5. Review-risk areas specific to Casberi (pre-empt these)

Reviewers scrutinize these; none are blockers if handled honestly (your design law already is):
- **BYOK AI keys** — apps that let users plug in external LLM keys occasionally draw questions.
  Your privacy policy explains it well; be ready to point the reviewer there.
- **Crypto token/wallet watching** — read-only is fine; the app never trades. Make sure the
  review notes say so (see §6) so a reviewer doesn't assume a trading surface.
- **Third-party account connections** — every listed connector must actually work and not be a
  dead/"Soon" control (your honesty rule + catalog-sync already enforce this).
- **Onboarding permission prompts** — must fire only on real user intent, in-context. They do.

---

## 6. Submit for review  **[you, in App Store Connect]**

1. App Store Connect → your app → **(+) Version or Platform** → create the `1.0` iOS version
   (if not already created).
2. Fill in all the §1 metadata + §2 screenshots + §3 privacy answers.
3. **Build:** select the uploaded TestFlight build as the release build.
4. **Export Compliance:** the app makes standard HTTPS calls (no custom/proprietary crypto).
   Answer the encryption question → typically **exempt**. You can pre-set
   `ITSAppUsesNonExemptEncryption = NO` in the Info.plist to skip the prompt each upload.
5. **App Review notes** (free-text to the reviewer) — recommend including:
   ```
   Casberi is a personal, on-device organizer. No account or login is required — the app is
   fully usable immediately. Everything is stored locally; there is no Casberi server.
   Crypto token/wallet features are READ-ONLY price/holdings watching — the app never trades
   or moves funds. Optional "bring your own AI key" sends a query only to the provider the
   user chose, only when they tap it, directly from the device.
   No demo account needed.
   ```
6. **Release option:** Manual, Automatic, or Phased release. For a first launch, **Manual**
   (you press "Release" after approval) gives you the most control.
7. Submit → App Review (typically ~24–48h).

---

## 7. Website follow-up (after approval)

`website/index.html` currently has two CTAs pointing at TestFlight
(`testflight.apple.com/join/xBD4tYZh`) and the note *"App Store release to follow."* Once
approved, swap those to the `apps.apple.com/...` link and update the note. (I can do this in
one pass when the URL exists — then rebuild the deploy zip + bump `?v=` cache-busters per the
website deploy rule.)

---

## Status summary

| Item | State |
|---|---|
| Privacy policy (live, complete) | ✅ done |
| Permission usage strings | ✅ clean |
| Store copy (name/subtitle/promo/keywords/description) | ✅ drafted above |
| Category, copyright, URLs | ✅ specified |
| App Privacy label answers | ✅ guidance ready — you enter in ASC |
| Export compliance answer | ✅ guidance ready |
| Review notes | ✅ drafted |
| **Screenshots (6.9")** | 🟡 candidate set captured 2026-07-17 (`~/Desktop/casberi-appstore-shots/`, 6 shots, all 1320×2868, dark): 1-home, 2-feed, 3-answer (keyboard-free), 4-thing, 5-apps, 6-data (the on-device/iCloud-off/export-delete trust tray) — awaiting your approval; a light-mode set is available on request |
| Membership active | ✅ confirmed 2026-07-17 |
| Submit in App Store Connect | ⬜ you (I can't submit) |
