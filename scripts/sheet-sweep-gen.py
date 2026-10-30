#!/usr/bin/env python3
"""The sheet sweep's manifest generator (prd §1308).

Writes scripts/sheet-sweep.json: the entries `CasberiUITests/SheetSweepTests.swift`
walks and the exempt rows `scripts/sheet-sweep-audit.py` holds to the code. A key
the audit lists that no entry or exempt row places goes to a PENDING exempt row,
printed, so a new sheet is never silently unswept.

Usage: scripts/sheet-sweep-gen.py [--discover]
  --discover  also writes the DISCOVER rows: walks whose anchor never appears,
              so the sweep dumps the screen's tree (`sheet-d-<id>-tree.txt`) for
              an anchor to be read, not guessed. Never commit a --discover run.

On the phone (prd §1321) Day, Notes, Sources, Markets and every Wallet tile are
PAGES under the band, and a step deeper (a setting, an app's page, What this app
reaches, the Wallet's history) PUSHES on the pager's stack: none of those is a
sheet. What a page raises (a tray, a row's sheet, a key) rises over it, so a
pull closes it and leaves the page; an app picked from the tray rises as the app
sheet (chrome.appSheet).
"""
import json, subprocess, pathlib, sys
ROOT = pathlib.Path(__file__).resolve().parent.parent
D = "demo"
# Sources is the Library tab (prd §1327, §1347); the Feed has no Sources tile.
SRC = [{"wait": 2}, {"tap": "button:=Library"}]
APPS = "button:~, Apps"                    # Sources' Apps count: on the Sources page under every sheet it raises
SEARCH = "button:=Search"                  # the band's Search: takes a touch whenever no sheet covers it
BACK = "button:=Back"
GRAB = "button:=Sheet Grabber"
WALLET = [{"tap": "button:=Wallet"}]
THING = [{"relaunch": [D, "-openThing", "Sourdough"]}]
def OPEN(prefix): return [{"relaunch": [D, "-openThing", prefix]}]
# Each app's folder in Sources' library (prd §1316); Wallet and Work stand below the fold.
FOLDER = {"Gemini": "Agents", "ENS": "Wallet", "Acorns": "Wallet", "Rocket Money": "Wallet",
          "Spotify": "Media", "Walletbeat": "Media", "Stripe": "Work"}
def APP(name):
    """A connected app's page, as a person opens it on the phone: Sources, its
    category's folder, its icon (prd §1316, §1321). The band's Search lands a
    connected app in its feed, not on its page, so the page's door is the
    folder (or the tray's long press, Settings). The page is PUSHED on the
    pager; what it raises rises over it."""
    folder = FOLDER[name]
    lift = [{"swipeUp": 1}] if folder in ("Wallet", "Work") else []
    return SRC+lift+[{"tap": f"button:^{folder}, "}, {"tap": f"button:={name}"}]
def pushed(id, covers, launch, steps, anchor, root, swipe_to, back=True, **kw):  # kw: offscreen, swipeFrom
    """A step pushed inside a sheet (prd §1238, §1315): a pull down closes the whole sheet
    (`swipe_to` is on the page under it), Back returns to the sheet's root.
    back=False: the step opens on the decimal pad, which stands over the foot's Back (§1304), so only the pull is walked."""
    d = dict(id=id, covers=covers, launch=launch, steps=steps, anchor=anchor, afterSwipe=swipe_to, **kw)
    if back: d.update(control=BACK, afterControl=root)
    return d
def rises(id, covers, launch, steps, anchor, **kw):
    """A sheet or tray that rises over a page: a pull closes it, and the control
    that raised it (else `afterSwipe`) takes a touch again."""
    return dict(id=id, covers=covers, launch=launch, steps=steps, anchor=anchor, **kw)
SH = "Screens/SettingsHome.swift:"
FS = "Screens/FeedScreen+Sheets.swift:feedSheet#"
MS = "Shell/MainSurface.swift:route.sheet#"
RS = "Shell/RootShell.swift:"
TS = "Screens/ThingSheetView.swift:"
def section(room, item):
    return [{"tap": f"button:=Add to {room}"}, {"tap": f"button:^{item}"}]
MARKETS = WALLET+[{"tap": "button:^Markets, What"}]
PIVOT = [{"wait": 2}, {"tap": SEARCH}, {"focus": "field:?Search"}, {"type": "Telegram"}, {"tap": "button:^Everything from Telegram"}]
HISTORY = WALLET+[{"tap": "button:^Home, The line"}, {"swipeUp": 5}, {"tap": "button:^See all "}]
ENTRIES = [
  # ---- Library, a page (prd §1321). Its counts box and the lists and trays it
  # raised are deleted (2026-10-30); Contacts and Calendars are their apps' pages,
  # pushed from Social's and Day's folders, and what those pages raise rises over them ----
  rises("sources-new-contact", ["Screens/ContactsPage.swift:sheet#newContact"], [D],
        SRC+[{"tap": "button:^Social, "}, {"tap": "button:=Contacts"}, {"tap": "button:=New contact"}],
        "button:=Save", afterSwipe="button:=New contact"),
  rises("sources-subscribe-calendar", ["Screens/CalendarsPage.swift:subscribing&&route.sheet"], [D],
        SRC+[{"tap": "button:^Day, "}, {"tap": "button:=Calendar"}, {"tap": "button:=Subscribe by link"}],
        GRAB, afterSwipe="button:=Subscribe by link"),
  rises("sources-contact", ["Screens/AddressesScreen.swift:opened"], [D],
        SRC+[{"tap": "button:^Social, "}, {"tap": "button:=Contacts"}, {"tap": "button:^Ana Kovač, "}],
        "button:=ana@studio.com"),
  # A step from a row's sheet pushes inside it (prd §1315): a pull closes the whole sheet.
  pushed("plan-edit", ["Screens/SubscriptionSheets.swift:editing"], [D, "-subscriptionTrack", "Hulu:15.99"],
         [{"wait": 2}]+WALLET+[{"tap": "button:^Spending, "}, {"tap": "button:^Subscriptions. "}, {"tap": "button:^Hulu, "}, {"tap": "button:^Edit"}],
         "button:=Save", "button:^Edit", swipe_to="button:^Hulu, "),
  pushed("addresses-thing", ["Screens/AddressesScreen.swift:openedThing"], [D, "-openAddresses", "YES"], [{"wait": 2}, {"tap": "button:^Sam, "}, {"tap": "button:^Sent 0.15 ETH"}],
         "button:=Share, Share", "button:^Sent 0.15 ETH", swipe_to="button:^Sam, "),
  # ---- Apps' pages: found through the band's Search, a page pushed on the pager (prd §1321) ----
  dict(id="app-page", covers=[MS+"connect"], launch=[D, "-openRoom", "Life"], steps=section("Life", "Gmail, A sender"), anchor=GRAB, afterSwipe="button:=Add to Life"),
  rises("app-key", ["Screens/AccountPage.swift:sheet#key"], [D], APP("Gemini")+[{"tap": "button:^Add your Google key"}], "text:=Your Gemini key"),
  dict(id="app-key-door", covers=["Screens/AccountDoorHost.swift:web"], launch=[D], steps=APP("Gemini")+[{"tap": "button:^Add your Google key"}, {"tap": "button:^Get your API key"}],
       anchor="button:=Done", control="button:=Done", afterSwipe="text:=Your Gemini key", afterControl="text:=Your Gemini key"),
  dict(id="app-website", covers=["Screens/AccountPage.swift:sheet#web"], launch=[D], steps=APP("Stripe")+[{"tap": "button:^Website"}],
       anchor="button:=Open in Safari"),
  rises("app-thing", ["Screens/AccountPage.swift:sheet#thing"], [D], APP("ENS")+[{"swipeUp": 1}, {"tap": "button:^nick.eth, "}], "button:^Share, Share"),
  rises("app-track", ["Screens/AccountPage.swift:sheet#track"], [D], APP("Acorns")+[{"tap": "button:^Track a subscription, Free"}], "button:=Track Acorns"),
  rises("app-card", ["Screens/AccountPage.swift:sheet#card"], [D], APP("Walletbeat")+[{"swipeUp": 2}, {"tap": "button:^Ledger Wallet, "}], "link:=Full review on Walletbeat",
        offscreen=True),
  dict(id="acorns-login", covers=["Screens/AcornsScreen.swift:showLogin"], launch=[D], steps=APP("Acorns")+[{"tap": "button:^Sign in"}],
       anchor="text:=Log in to Acorns", swipe=False, control="button:=Done", afterControl="button:^Sign in"),
  dict(id="rocket-login", covers=["Screens/RocketMoneyScreen.swift:showLogin"], launch=[D], steps=APP("Rocket Money")+[{"tap": "button:^Sign in"}],
       anchor="button:=Done", swipe=False, control="button:=Done", afterControl="button:^Sign in"),
  dict(id="spotify-login", covers=["Screens/SpotifyScreen.swift:showLogin"], launch=[D], steps=APP("Spotify")+[{"tap": "button:^Sign in"}],
       anchor="button:=Done", swipe=False, control="button:=Done", afterControl="button:^Sign in"),
  # An app picked from the rooms tray rises as the app sheet (prd §1321, `routeIntoFeed`).
  rises("tray-app", [RS+"chrome.appSheet"], [D, "-openTray", "YES"], [{"tap": "button:=GitHub"}], "button:^Share this week", afterSwipe=SEARCH),
  dict(id="room-share", covers=["Screens/FeedScreen.swift:roomShare"], launch=[D, "-openTray", "YES"],
       steps=[{"tap": "button:=GitHub"}, {"tap": "button:^Share this week"}], anchor="button:=Close"),
  # ---- The Feed ----
  dict(id="feed-thing", covers=[FS+"thing"], launch=[D], steps=WALLET+[{"tap": "button:^Needs you. "}, {"tap": "button:~Needs attention · £200"}],
       anchor="button:=Wise, Wise"),
  dict(id="thing-by-link", covers=[RS+"deepLinkThing"], launch=[D], steps=THING, anchor="text:^From your Telegram archive", afterSwipe=SEARCH),
  # Share rises as the system share sheet, a system picker (prd §1370).
  rises("share-tray", ["Screens/ThingStage.swift:sharing"], [D], THING+[{"tap": "button:^Share"}], "button:=Close",
        control="button:=Close", afterSwipe="button:^Share", afterControl="button:^Share"),
  dict(id="media-follow-site", covers=[FS+"followingAdd"], launch=[D, "-openRoom", "Media"], steps=section("Media", "RSS, A site"), anchor=GRAB, afterSwipe="button:=Add to Media"),
  dict(id="social-follow", covers=[FS+"socialFollow"], launch=[D, "-openRoom", "Social"], steps=section("Social", "Bluesky, A person"), anchor=GRAB, afterSwipe="button:=Add to Social"),
  dict(id="work-watch", covers=[FS+"githubWatch"], launch=[D, "-openRoom", "Work"], steps=section("Work", "GitHub, A person"), anchor=GRAB, afterSwipe="button:=Add to Work"),
  dict(id="life-track-mail-list", covers=[FS+"mailSubscriptionAdd"], launch=[D, "-openRoom", "Life"], steps=section("Life", "Gmail, A sender"), anchor="text:=Uma Patel", afterSwipe="button:=Add to Life"),
  # An app's directory pushes inside its app sheet: a pull closes the sheet, Back returns to the app.
  pushed("l2beat-directory", [], [D, "-openRoom", "Media"], section("Media", "L2BEAT, A chain")+[{"tap": "button:^Browse every chain"}],
         BACK, "button:^Browse every chain", swipe_to="button:=Add to Media"),
  pushed("walletbeat-directory", [], [D, "-openRoom", "Media"], section("Media", "Walletbeat, A wallet")+[{"tap": "button:^Browse every wallet"}],
         BACK, "button:^Browse every wallet", swipe_to="button:=Add to Media"),
  # Calendar is Day's since prd §1347: its subscribe door is Day's section +.
  dict(id="day-calendar-link", covers=[FS+"calendarSubscribe"], launch=[D, "-openRoom", "Day"], steps=section("Day", "Calendar"), anchor=GRAB, afterSwipe="button:=Add to Day"),
  # The Feed's Reorder tile (prd §1345).
  dict(id="feed-reorder", covers=[FS+"feedOrder"], launch=[D], steps=[{"wait": 2}, {"tap": "button:^Reorder,"}], anchor="text:=Feed order"),
  dict(id="person-by-link", covers=[RS+"deepLinkPerson"], launch=[D, "-deeplink", "casberi://person/Bluesky/uma"], steps=[{"wait": 3}], anchor=GRAB, afterSwipe=SEARCH),
  # Find's pivot page: since prd §1326 a thing's From card no longer opens it; the band's Search does.
  dict(id="pivot", covers=[RS+"chrome.pivot"], launch=[D], steps=PIVOT, anchor=GRAB, afterSwipe=SEARCH),
  # ---- The thing sheet's own steps (prd §1315: they push inside it) ----
  pushed("thing-track", [TS+"faceTarget#track"], [D], OPEN("Spotify · $11.99")+[{"tap": "button:^Track"}], "button:=Track Spotify", "button:^Track",
         swipe_to=SEARCH, back=False),
  pushed("thing-alert-new", ["Screens/MarketsViews.swift:tray#new"], [D], OPEN("Ethereum")+[{"tap": "button:=Alert, Alert"}], "text:=New alert", "button:=Alert, Alert",
         swipe_to=SEARCH, back=False),
  pushed("pivot-thing", ["Screens/PivotPage.swift:opened"], [D],
         PIVOT+[{"tap": "button:^Kettlebell complexes for cyclists, "}], "text:^From your Telegram archive",
         "button:^Kettlebell complexes for cyclists, ", swipe_to=SEARCH),
  pushed("thing-reply-to", [TS+"walkingTo"], [D], OPEN("Critique day")+[{"tap": "button:^Replying to you"}], "button:=@you", "button:^Replying to you",
         swipe_to=SEARCH),
  dict(id="thing-photo", covers=[TS+"zoomingPhoto"], launch=[D], steps=OPEN("Figma")+[{"tap": "button:=Figma"}], anchor="button:=Close", swipe=False, control="button:=Close"),
  pushed("social-post", ["Screens/SocialPostViews.swift:walking"], [D], OPEN("Local-first")+[{"tap": "button:^@nils, "}], "button:=@nils", "button:^@nils, ",
         swipe_to=SEARCH),
  pushed("walletbeat-wallet", ["Screens/WalletbeatDirectoryScreen.swift:opened"], [D, "-openRoom", "Media"],
         section("Media", "Walletbeat, A wallet")+[{"tap": "button:^Browse every wallet"}, {"tap": "text:=Ambire"}], "link:=Full review on Walletbeat",
         "text:=Ambire", swipe_to="button:=Add to Media", offscreen=True),
  pushed("l2beat-chain", ["Screens/L2beatDirectoryScreen.swift:opened"], [D, "-openRoom", "Media"],
         section("Media", "L2BEAT, A chain")+[{"tap": "button:^Browse every chain"}, {"tap": "text:=Abstract"}], "link:=Full assessment on L2BEAT",
         "text:=Abstract", swipe_to="button:=Add to Media", offscreen=True),
  pushed("thing-walletbeat", ["Screens/WalletbeatSheetViews.swift:openedWallet"], [D],
         OPEN("Customer Data Exposed")+[{"tap": "button:^What Walletbeat says about Trezor"}], "link:=Full review on Walletbeat",
         "button:^What Walletbeat says about Trezor", swipe_to=SEARCH, offscreen=True),
  pushed("social-post-author", ["Screens/SocialPostViews.swift:profile"], [D], OPEN("Local-first")+[{"tap": "button:^@nils, "}, {"tap": "button:=@nils"}],
         "button:=Follow", "button:=@nils", swipe_to=SEARCH),
  # A thing names where it came from (prd §1326): its From card's followed feed pushes inside the sheet.
  pushed("thing-from-follow", [TS+"faceTarget#followed"], [D], OPEN("A quieter approach")+[{"tap": "button:^The Verge"}],
         "text:=Through", "button:^The Verge", swipe_to=SEARCH),
  pushed("following-recent", ["Screens/FollowingViews.swift:opened"], [D],
         OPEN("A quieter approach")+[{"tap": "button:^The Verge"}, {"tap": "button:^The return of local-first"}],
         "text:=From", "button:^The return of local-first", swipe_to=SEARCH),
  pushed("thing-follow-site", [TS+"faceTarget#followSite"], [D], OPEN("Bauhaus")+[{"tap": "button:^Follow, Follow"}],
         "field:?A site's address", "button:^Follow, Follow", swipe_to=SEARCH),
  pushed("alert-edit", ["Screens/MarketsViews.swift:tray#edit"], [D],
         OPEN("Ethereum")+[{"tap": "button:=Alert, Alert"}, {"tap": "button:=+10%"}, {"tap": "button:=Set alert"}, {"tap": "button:^Rises to "}],
         "text:=Edit alert", "button:^Rises to ", swipe_to=SEARCH),
  # ---- The Wallet: every tile is the Wallet's page (prd §1321); what a tile raises rises over it ----
  rises("wallet-worth-a-look", [FS+"worthALook"], [D],
        WALLET+[{"tap": "button:^Security, Who"}, {"tap": "button:=1, Poisoning"}, {"tap": "button:^1 lookalike address, "}], "text:=Worth a look"),
  rises("wallet-subscription", [FS+"subscription"], [D], WALLET+[{"tap": "button:^Subscriptions. "}, {"tap": "button:^Netflix, $12.99"}], "text:=Paid so far"),
  rises("wallet-track-subscription", [FS+"subscriptionAdd"], [D], WALLET+[{"tap": "button:^Subscriptions. "}, {"tap": "button:=Track a subscription"}],
        "field:?Search, or type any name"),
  # Home's Follow an account row (prd §1480), the tray Library's Wallet plus raised until 2026-10-30.
  rises("wallet-follow", [FS+"walletFollow"], [D], [{"wait": 2}]+WALLET+[{"tap": "button:^Follow an account"}], "field:?An address or a name"),
  # The history is a page pushed on the pager; a row's thing rises over it.
  rises("wallet-history-thing", ["Screens/WalletHistoryScreen.swift:sheetThing"], [D], HISTORY+[{"tap": "button:^Sent to Savings, "}], "button:=Share, Share"),
  rises("markets-follow-company", [FS+"watchAdd"], [D], MARKETS+[{"tap": "button:=Follow"}], GRAB),
  rises("markets-company", [FS+"company"], [D], MARKETS+[{"tap": "button:=Work"}, {"tap": "button:^Amazon, AMZN"}], GRAB),
  # ---- Notes, a page (prd §1321) ----
  dict(id="notes-trash", covers=["Screens/FeedScreen.swift:open"], launch=[D, "-openRoom", "Your notes"],
       steps=[{"hold": "button:^Note, Composer grammar notes"}, {"tap": "button:=Delete"}, {"tap": "button:=Delete note"},
              {"tap": "button:^Folders, What you filed"}, {"tap": "button:^Recently deleted"}], anchor="text:=Composer grammar notes"),
  dict(id="note-page", covers=["Shell/NoteCaptureSheet.swift:hosted&&chrome.noteOpen"], launch=[D, "-openRoom", "Your notes"], steps=[{"tap": "button:^New, Write"}],
       anchor="button:=Format", swipe=False, control="button:=All notes"),
  dict(id="note-link", covers=["Shell/NoteCaptureSheet.swift:linkPickerOpen"], launch=[D, "-openRoom", "Your notes"],
       steps=[{"tap": "button:^New, Write"}, {"tap": "button:=Attach"}, {"tap": "button:^Link"}], anchor="text:=Link something",
       afterSwipe="button:=Format"),
  dict(id="note-sketch", covers=["Shell/NoteCaptureSheet.swift:sketchOpen"], launch=[D, "-openRoom", "Your notes"],
       steps=[{"tap": "button:^New, Write"}, {"tap": "button:=Attach"}, {"tap": "button:^Sketch"}], anchor=GRAB, swipeFrom=GRAB,
       afterSwipe="button:=Format"),
]
PENDING = []
PHONE_PAGE = "on the phone a page since prd §1321 (HomeRoute.present/stack push it on the pager's stack while no sheet is up); this root rises only on the iPad"
EXEMPT = [
  dict(covers=[TS+"faceTarget#followChannel"],
       why="the Follow tile draws only for a video or podcast whose channel you do not follow, and every demo channel is followed (measured 2026-10-15 after prd §1326: Computerphile, Strange Loop and Signals and Threads each read Following in the From card, no Follow tile)"),
  dict(covers=[MS+"node.casberi", MS+"node.settingsPage", MS+"node.reach", MS+"node.bridge",
               MS+"node.l2beatDirectory", MS+"node.walletbeatDirectory", MS+"node.notes", MS+"node.settingsFolder",
               MS+"node.contacts", MS+"node.calendars"],
       why=PHONE_PAGE + " (Sources, a setting, What this app reaches, an app's page or the Wallet's history, a directory, the Notes page Library's Notes folder opens, prd §1347, and the Contacts and Calendars pages its Contacts and Calendar apps open)"),
  dict(covers=[FS+"mailSubscription", FS+"following"],
       why="NOT WALKED: on the phone Life and Media are Feed sections, so these rise only through a service door (ShellChrome.open, a sheet's Writes/Following row) by an item's id; Library's rows that swept the same sheets (sources-mail-list, sources-followed) were deleted with its box (2026-10-30)"),
  dict(covers=["Screens/ContactsPage.swift:sheet#plan"],
       why="NOT WALKED: a contact's biller row raises the Wallet's plan sheet; no demo contact is a biller with a plan (unmeasured). The same SubscriptionSheet is swept from the Wallet (wallet-subscription)"),
  dict(covers=[SH+"trackPick"],
       why="NOT WALKED since Library's box was deleted (2026-10-30): the Track tray rises when a folder's app that needs only a name is not yet yours, or a door names one (route.openOffer); the walk that reached it went through the box's Follow something. Needs a demo app that is not added"),
  dict(covers=["Screens/AccountScreen.swift:detail#data", "Screens/AccountScreen.swift:detail#notifications", "Screens/AccountScreen.swift:languageOpen"],
       why="on the phone a setting is a page pushed beside Sources (AccountScreen.open, SettingsHome.bandSearches, prd §1321), never a sheet; these rise only on the iPad outside a sheet"),
  dict(covers=[MS+"node.project"], why="its one door is a circle on Find's source map (`genProjectTap`), which the sweep does not search; the composer's `show <topic>` cannot reach it, since it parses with no tags"),
  dict(covers=[FS+"nftPicks"], why="both Choose collections controls hide while DemoMode.isActive, and the sweep runs in the demo"),
  dict(covers=[FS+"socialFaces", "Shell/MainSurface.swift:allFacesShown"], why="the More face needs more than eight people (the demo has two); allFacesShown is also iPad/Mac only (showsRail)"),
  dict(covers=[FS+"walletTokens"], why="the More tokens row draws only when Holdings folds two or more small tokens; the demo's four tokens each stand on their own row (measured 2026-10-14)"),
  dict(covers=["Screens/AddressesScreen.swift:asked"], why="Same person? rises only for a pair ContactSuggest proposes; the demo's addresses propose none"),
  dict(covers=["Screens/AccountPage.swift:sheet#profile", "Screens/StarterPackImportSheet.swift:open"],
       why="the demo's Bluesky page draws no followed people and no Follow a starter pack door (measured 2026-10-15: Open, Website, Pause, Disconnect only); a profile is swept through a post instead"),
  dict(covers=[FS+"token"], why="the demo's holdings carry no token route (`position.route` is nil), so a token row's tap returns before it raises this; in the demo that row is a dead tap"),
  dict(covers=["Screens/PersonRoomScreen.swift:sheetThing"], why="a person's room by link shows no rows for any demo person (measured @uma and @sam, 2026-10-15), so there is no row to open"),
  dict(covers=[TS+"faceTarget#person", TS+"faceTarget#address", TS+"walkingToNote"],
       why="NOT WALKED YET: no demo thing found that draws Open profile, Every transfer with, or a linked-note row (-openThing on the transfer titles lands on nothing)"),
  dict(covers=[FS+"person"], why="the Social page draws no faces in the demo (measured 2026-10-15: Feed · Social lists notices only), so there is no face to tap twice"),
  dict(covers=["Screens/ThingSheetView.swift:faceTarget#remind"],
       why="the thing sheet's Remind me needs a kept note shown as a thing sheet, and on the phone a note of yours always opens as its page (FeedScreen.opensAsPage, prd §1099), whose own hold raises NoteRemindTray"),
  dict(covers=["Screens/SocialPostViews.swift:followImport"], why="Who they follow draws only for a watched person; the demo's profile pages show Follow alone (measured @nils, @uma, @sam, 2026-10-15)"),
  dict(covers=["Screens/FeedScreen.swift:folderShare", "Screens/ThingSheetView.swift:sharingHighlight"],
       why="NOT WALKED YET: a hold on a Notes folder opened it rather than raising its menu, and no demo thing has a readable body to keep a highlight from (measured 2026-10-15)"),
  dict(covers=[FS+"logosSend", FS+"logosChat"], why="Send needs a Logos key made on this phone and chats need a paired Observer node; the demo has neither"),
  dict(covers=[FS+"subscriptionTrack"], why="raised once after an app's first real connect (SubscriptionPlans.shouldAsk); the demo's apps are poured, never connected"),
  dict(covers=["Screens/SocialPostViews.swift:profile@2"], why="reply avatars come from a live thread fetch; the demo has no replies to tap"),
  dict(covers=[MS+"node.apps"], why="present(.apps) is rewritten to .casberi (HomeRoute.present, prd §1234), so this sheet is node.casberi's, which on the phone is the Sources page (prd §1321) and rises only on the iPad"),
  dict(covers=["Screens/AddressesScreen.swift:composer#messages", "Screens/AddressesScreen.swift:composer#mail"],
       why="MessageCompose.canText and canMail are false on the simulator (no Messages or Mail account), so the rows that raise Apple's composers never draw there"),
  dict(covers=["Shell/NoteCaptureSheet.swift:scanOpen"], why="the document camera needs a camera; the simulator has none, so Attach offers no Scan there"),
  dict(covers=["Screens/ThingContent.swift:tray#new", "Screens/ThingContent.swift:tray#edit"],
       why="NOT WALKED YET: a watched chart's Alert tile (prd §1363) raises the same price-alert tray Markets does; the journey to a demo chart sheet is not written (2026-10-16)"),
  dict(covers=["Screens/FileverseDocPage.swift:webDoor", "Shell/NoteCaptureSheet.swift:hosted&&chrome.docToRead"],
       why="NOT WALKED YET: a dDoc's page (prd §1355) and a link inside it; the journey to a demo Fileverse doc is not written (2026-10-16)"),
  dict(covers=[RS+"safeAsk", "Screens/SafeScreen.swift:pastedAsk"], why="raised by a live Safe pairing (SafePeer) or a pasted ask from it; there is no Safe on the simulator to ask"),
  dict(covers=[RS+"aztecSign", "Screens/AztecScreen.swift:pastedSign"], why="raised by a signing link from the Aztec wallet; there is no peer on the simulator to make one"),
  dict(covers=[RS+"observerOffer", "Screens/LogosScreen.swift:pairOffer"], why="raised by a logos-observer pairing offer from a Logos node; there is no node on the simulator"),
]
X = "text:=__never__"
def d(id, launch, steps): return dict(id="d-"+id, covers=[], launch=launch, steps=steps+[{"wait": 2}], anchor=X)
DISCOVER = [
]
UNSETTLED = {
  "note-sketch": "a pull from the grabber left it open twice (the canvas takes the drag); prd §1023 says a pull keeps the drawing and closes, so a person should check it",
}
# Ids are unique; a later definition of one would replace the earlier.
_last = {e["id"]: e for e in ENTRIES}
ENTRIES = [e for i, e in enumerate(ENTRIES) if _last[e["id"]] is e]
moved = [e for e in ENTRIES if e["id"] in UNSETTLED]
ENTRIES = [e for e in ENTRIES if e["id"] not in UNSETTLED]
EXEMPT += [dict(covers=e["covers"], why=f"NOT WALKED YET ({e['id']}): {UNSETTLED[e['id']]}") for e in moved if e["covers"]]
inv = subprocess.run([str(ROOT/"scripts/sheet-sweep-audit.py"), "--list"], capture_output=True, text=True).stdout.split()
placed = {k for e in ENTRIES for k in e["covers"]} | {k for x in EXEMPT for k in x["covers"]}
pending = [k for k in inv if k not in placed and ":?line" not in k]
ex = list(EXEMPT) + ([{"covers": pending, "why": "PENDING: not walked yet"}] if pending else [])
for d in DISCOVER: d["covers"] = []
out = {"_doc": "The sheet sweep's list (prd §1308): scripts/sheet-sweep-audit.py holds it to the code; CasberiUITests/SheetSweepTests.swift walks it.",
       "entries": ENTRIES + (DISCOVER if "--discover" in sys.argv else []), "exempt": ex}
(ROOT/"scripts/sheet-sweep.json").write_text(json.dumps(out, indent=1, ensure_ascii=False) + "\n")
print(f"{len(ENTRIES)} entries, {len(pending)} pending")
print("\n".join(pending))
