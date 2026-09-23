"""Every picture the furnished demo shows, one row per subject.

`key` is the asset: `sample-pic-<key>` unless `asset` names another (the Photos
room's screenshots keep `sample-screenshot-N`, because their `sourceRef` is
`sample:demo-shot-N` and the sheet resolves the picture from the ref).
`size` is CSS pixels, `scale` the device scale factor. `subject` is what the
picture shows — it is the brief the family module draws from, and it has to
agree with the row in `DemoSeedAll.swift` that names the key.

Families:
  ui          — screens and documents: phone screenshots, drawings, figures
  cover       — made editorial images: thumbnails, article heads, bookmark and page covers
  sleeve      — made square/capsule art: albums, podcast episodes, game headers
  scene_home  — drawn photographs of food, rooms, objects and craft
  scene_out   — drawn photographs of places, streets, weather and moments
"""

PHONE = (390, 844)
P = []


def pic(key, family, size, subject, scale=1, asset=None):
    row = {"key": key, "family": family, "size": size, "subject": subject, "scale": scale}
    if asset:
        row["asset"] = asset
    P.append(row)


# ── Photos: the camera roll's screenshots (DemoSeedAll.photos) ────────────
# Phone screenshots, so phone-shaped. The words drawn in each are the words
# the row's OCR `content` claims the screenshot holds.
shots = [
    (5, "Figma on iPhone: a spacing-tokens frame — space-1 4, space-2 8, space-3 12, space-4 16, space-6 24, space-8 32 — each a labelled bar; page title 'Spacing tokens', Design system file"),
    (6, "Xcode-style dark code editor on iPhone (Swift Playgrounds look): SwiftUI code using .scrollTransition { content, phase in content.opacity(phase.isIdentity ? 1 : 0.4) }, line numbers, title 'ScrollTransitions.swift'"),
    (7, "Apple Maps-like screen: Alfama, Lisbon; a walking route drawn in blue through winding streets from Miradouro de Santa Luzia to Sé; a card 'Alfama walking route · 18:40 · 42 min walk'"),
    (8, "Apple Notes-like screen titled 'Espresso dial-in': list — 18.0 g in / 36 g out / 28 s / grind 2.8 → 2.6 / tastes: sour, then balanced; a checklist"),
    (9, "Figma on iPhone: a colour-ramp frame — ten swatches from pale espresso-cream to deep brown with hex labels, title 'Colour ramp', Design system file"),
    (10, "Swift Playgrounds-like screen split: SwiftUI code with matchedGeometryEffect(id: \"card\", in: ns) above, a live preview of a card expanding below; title 'MatchedGeometry.swift'"),
    (11, "Transit timetable screen: 'Tram 28E · Martim Moniz → Campo Ourique', a table of departure times 08:02 08:14 08:26 …, current time highlighted, yellow tram glyph"),
    (12, "A chart screenshot titled 'Grind chart': grind setting (x) vs shot time in seconds (y), a line with dots, a shaded target band 25–30 s, espresso-brown palette"),
]
for n, subject in shots:
    pic(f"shot-{n}", "ui", PHONE, subject, scale=1.5, asset=f"sample-screenshot-{n}")
# The two WORDLESS shots — OCR found no words, so these must contain no text.
pic("shot-13", "scene_out", (600, 800), "Wordless camera photo: late sun over Lisbon terracotta rooftops, the river beyond, no text", asset="sample-screenshot-13")
pic("shot-14", "scene_home", (600, 800), "Wordless camera photo: a plant in a terracotta pot on a sunny windowsill, long shadows, no text", asset="sample-screenshot-14")

# ── X archive (DemoSeedAll.xArchive) ──────────────────────────────────────
pic("x-photo-0", "scene_out", (800, 600), "Your photo post: a Berlin canal at dusk, bridge arches, lamps coming on")
pic("x-photo-1", "scene_home", (800, 600), "Your photo post: a coffee cup on a window ledge, morning light, city blurred outside")
pic("x-photo-2", "scene_out", (800, 600), "Your photo post: a bicycle leaning on a pastel wall, bold shadow")
pic("x-video-0", "scene_out", (800, 450), "Your video post's poster frame: view from a train window, fields and pylons, motion")

# ── Instagram (DemoSeedAll.instagram / igNotices) ─────────────────────────
ig = (640, 800)
pic("ig-photo-0", "scene_out", ig, "Your photo: Lisbon rooftops, terracotta tiles, a church dome")
pic("ig-photo-1", "scene_home", ig, "Your photo: a pastel de nata on a small plate, cinnamon, top-down")
pic("ig-photo-2", "scene_out", ig, "Your photo: a yellow Lisbon tram climbing a steep street")
pic("ig-photo-3", "scene_home", ig, "Your photo: a sourdough loaf, scored ear, on a linen cloth")
ig_saves = [
    ("Cafe with the marble counter", "scene_home", "a cafe interior, white marble counter, espresso machine, pendant lamps"),
    ("Studio shelf, all wood", "scene_home", "a wooden studio shelf, books, a plant, ceramic pieces"),
    ("Ceramics, matte glaze", "scene_home", "three matte-glazed ceramic vases in sage, sand and charcoal"),
    ("Bakery window at six", "scene_out", "a bakery shop window at dawn, warm light inside, loaves on shelves, blue street"),
    ("Desk setup, one lamp", "scene_home", "a minimal desk, one angled lamp glowing, laptop closed, dark room"),
    ("Thirty seconds on lamination", "scene_home", "laminated dough on a floured bench, a rolling pin, butter layers visible"),
    ("The tile shop nobody posts about", "scene_out", "a wall of blue-and-white azulejo tiles in a small shop"),
    ("Two chairs, one window", "scene_home", "two chairs facing a tall window, soft daylight, bare floorboards"),
    ("Wheel-thrown, trimmed wet", "scene_home", "a pottery wheel with a wet clay bowl, hands-free, top-three-quarter view"),
    ("Blue hour over the bridge", "scene_out", "a suspension bridge over a river at blue hour, city lights"),
    ("Pastry lamination, slowly", "scene_home", "a croissant cross-section showing honeycomb layers, close up"),
    ("Kiln opening, third firing", "scene_home", "an open kiln with glowing shelves of glazed pots"),
]
for i, (caption, fam, subject) in enumerate(ig_saves):
    pic(f"ig-save-{i}", fam, ig, f"Saved post '{caption}': {subject}")
ig_likes = [
    ("Every bench in the park, ranked", "scene_out", "a park bench under a tree, autumn leaves"),
    ("One pot, forty minutes", "scene_home", "a cast-iron pot of stew on a stove, steam, wooden spoon"),
    ("Shelf brackets that aren't ugly", "scene_home", "close-up of a slim black steel shelf bracket holding an oak shelf"),
]
for i, (caption, fam, subject) in enumerate(ig_likes):
    pic(f"ig-like-{i}", fam, ig, f"Liked post '{caption}': {subject}")
# Notices are about posts NEWER than the export, so none repeats an export photo.
pic("ig-notice-0", "scene_out", ig, "Your newest photo (lena liked it): small fishing boats in a harbour, morning")
pic("ig-notice-1", "scene_home", ig, "Your photo (tomas: 'that light though'): afternoon light falling across a white wall and a chair")
pic("ig-notice-3", "scene_out", ig, "Your post (lena and 4 others liked it): steep stone stairs in Alfama, laundry lines")

# ── TikTok (DemoSeedAll.tiktok / tiktokNotices) ───────────────────────────
tt = (450, 800)
tt_posts = [
    "Two minutes on espresso ratios: espresso dripping into a cup on a scale reading 36.0 g",
    "Grinder teardown, part one: a coffee grinder opened up, burrs laid out on a mat",
    "Coffee at altitude, why it tastes flat: a mountain cabin table, a cup, peaks outside",
    "Espresso puck prep, honestly: top-down portafilter with a levelled coffee puck and a WDT tool",
]
for i, s in enumerate(tt_posts):
    pic(f"tt-post-{i}", "scene_home", tt, f"Your video's cover — {s}")
tt_saves = [
    ("Knife skills in 40 seconds", "scene_home", "a chef's knife and finely diced onion on a board"),
    ("One-pan dinner, no fuss", "scene_home", "a sheet pan of roasted vegetables and chicken, top-down"),
    ("Bike maintenance basics", "scene_out", "a bicycle on a repair stand, chain and tools, garage"),
    ("Rack organisation that lasts", "scene_home", "a pegboard wall with tools neatly hung"),
]
for i, (caption, fam, subject) in enumerate(tt_saves):
    pic(f"tt-save-{i}", fam, tt, f"Saved video '{caption}': {subject}")
pic("tt-notice-0", "scene_home", tt, "Your video 'Pouring a flat white, slowed down': milk pouring into espresso, a rosetta forming")
pic("tt-notice-1", "scene_home", tt, "Your video 'Why my shot ran in 18 seconds': a fast pale espresso stream, a timer reading 0:18")

# ── Snapchat memories (DemoSeedAll.snapchat) ──────────────────────────────
snap = [
    ("scene_out", "a beach at golden hour, long shadows, a towel"),
    ("scene_out", "concert crowd from behind, stage lights and haze"),
    ("scene_home", "birthday cake with lit candles on a dark table"),
    ("scene_out", "a snowy street at night, lamps, footprints"),
    ("scene_out", "a climbing gym wall with coloured holds and a rope"),
    ("scene_out", "a picnic in a park, blanket, fruit, trees"),
]
for i, (fam, s) in enumerate(snap):
    pic(f"snap-{i}", fam, (450, 800), f"Snapchat memory: {s}")

# ── Telegram channel pictures (DemoSeedAll.telegram) ──────────────────────
pic("tg-2", "ui", (800, 450), "Telegram Info channel graphic: a phone showing a chat with a 'Scheduled' message chip and a calendar icon, Telegram blue gradient, no Telegram logo")
pic("tg-4", "ui", (800, 450), "Telegram News channel graphic: an Apple-Watch-shaped screen showing a chat list, blue gradient, no logos")

# ── YouTube (DemoSeedAll.youtube) — thumbnails ────────────────────────────
yt = [
    ("How a compiler actually reads your code", "Computerphile", "source code turning into a token stream and a tree"),
    ("The physics of a good espresso shot", "James Hoffmann", "espresso extraction diagram, pressure arrows through a puck"),
    ("Systems that scale down", "Strange Loop", "conference-talk slide: tiny boxes and arrows, a small server"),
    ("Compilers from scratch, part four", "Computerphile", "a parse tree on graph paper, 'Part 4'"),
    ("Coffee grinders, measured", "James Hoffmann", "three grinders in a row with a particle-size chart"),
    ("Systems thinking for small teams", "Strange Loop", "talk slide: feedback loop diagram, stock and flow"),
    ("Espresso, but for filter drinkers", "James Hoffmann", "a filter cone beside an espresso cup"),
    ("A tour of modern type systems", "Strange Loop", "talk slide: type lattice / Venn of types"),
]
for i, (title, channel, s) in enumerate(yt):
    pic(f"yt-{i}", "cover", (800, 450), f"YouTube thumbnail for '{title}' ({channel}): {s}; big short thumbnail words, not the full title")

# ── Files: images in a connected folder (DemoSeedAll.files) ───────────────
files = [
    ("Kitchen plan v3", "ui", "architectural floor plan of a small kitchen, pencil on white, dimensions, 'v3'"),
    ("Hallway measurements", "ui", "hand sketch of a hallway on squared paper with measurements in cm"),
    ("Shelf bracket spec", "ui", "technical drawing of an L-shaped shelf bracket, orthographic views, dimensions"),
    ("Kitchen tile samples", "scene_home", "photo of tile samples laid on a counter, green and white glazes"),
    ("Plans — lighting run", "ui", "electrical plan: room outline with light fittings and a dashed cable run, legend"),
    ("Tiles, second batch", "scene_home", "photo of a stack of square green tiles in a cardboard box"),
]
for i, (name, fam, s) in enumerate(files):
    pic(f"file-{i}", fam, (800, 600), f"'{name}': {s}")

# ── Reading: Substack and RSS heroes (DemoSeedAll.reading) ────────────────
substack = [
    "The case for small software", "What a good changelog says", "Notes on interface latency",
    "Latency is a feature", "Writing for people who skim", "The end of the settings screen",
]
for i, t in enumerate(substack):
    pic(f"substack-{i}", "cover", (800, 420), f"Substack post header illustration for '{t}' — editorial, abstract, no words")
rss = [
    ("A quieter approach to notifications", "The Verge"), ("Inside a very small compiler", "Hacker News"),
    ("The return of local-first", "The Verge"), ("Type systems, plainly", "Hacker News"),
    ("Why your app feels slow", "TechCrunch"), ("The cost of a background sync", "TechCrunch"),
    ("Local-first, one year on", "The Verge"),
]
for i, (t, pub) in enumerate(rss):
    pic(f"rss-{i}", "cover", (800, 450), f"News article lead image for '{t}' ({pub}) — editorial illustration, no words, no publisher logo")

# ── Listening (DemoSeedAll.listening) ─────────────────────────────────────
# Album art is DRAWN, never a copy of the real sleeve, and one album per
# track so two rows can never share a cover.
music = [
    "Reckoner — Radiohead (In Rainbows)", "Pyramid Song — Radiohead (Amnesiac)",
    "Teardrop — Massive Attack (Mezzanine)", "Unfinished Sympathy — Massive Attack (Blue Lines)",
    "Svefn-g-englar — Sigur Rós (Ágætis byrjun)", "Hoppípolla — Sigur Rós (Takk...)",
]
for i, t in enumerate(music):
    pic(f"music-{i}", "sleeve", (600, 600), f"Abstract album art for {t} — a made cover, NOT the real sleeve, no words")
spotify = [
    "Dayvan Cowboy — Boards of Canada (The Campfire Headphase)",
    "Roygbiv — Boards of Canada (Music Has the Right to Children)",
    "Kid for Today — Boards of Canada (In a Beautiful Place Out in the Country)",
    "Avril 14th — Aphex Twin (Drukqs)",
    "Xtal — Aphex Twin (Selected Ambient Works 85-92)",
    "Lianne — Bibio (Ambivalence Avenue)",
]
for i, t in enumerate(spotify):
    pic(f"spotify-{i}", "sleeve", (600, 600), f"Abstract album art for {t} — a made cover, NOT the real sleeve, no words")
podcasts = [
    ("The one about compilers", "Signals and Threads"), ("Latency, end to end", "Signals and Threads"),
    ("Making things for two people", "Design Details"), ("The shape of a good demo", "Design Details"),
    ("Coffee, measured", "Filter Stories"), ("Roasting at altitude", "Filter Stories"),
]
for i, (ep, show) in enumerate(podcasts):
    pic(f"podcast-{i}", "sleeve", (600, 600), f"Podcast EPISODE art: show '{show}', episode '{ep}' — the show's look, with this episode's own motif and title")
steam = ["Factorio", "Balatro", "Outer Wilds", "Slay the Spire", "Tunic"]
for i, g in enumerate(steam):
    pic(f"steam-{i}", "sleeve", (736, 344), f"Steam library header for '{g}' — a made capsule evoking the game's world with its name in type, NOT the real key art or logo")

# ── Saves: Reddit, Raindrop, Pinterest (DemoSeedAll.saves) ────────────────
reddit = [
    ("The espresso machine that lasted 20 years", "scene_home", "an old chrome lever espresso machine on a counter"),
    ("Puck prep, settled", "scene_home", "top-down: a portafilter, a tamper and a distribution tool on a mat"),
    ("What I learned rewriting our sync layer", "ui", "a whiteboard-style sequence diagram: client, queue, server, arrows"),
    ("A small compiler in 400 lines", "ui", "a code editor screenshot: a tiny tokenizer function, dark theme"),
    ("Lisbon in three days — what worked", "scene_out", "a Lisbon viewpoint (miradouro) over the city and river"),
    ("Tram 28 is a trap (kind of)", "scene_out", "a crowded yellow tram stop with a queue, tram approaching"),
]
for i, (t, fam, s) in enumerate(reddit):
    pic(f"reddit-{i}", fam, (800, 600), f"Reddit post image for '{t}': {s}")
raindrop = [
    "Human Interface Guidelines — a documentation cover: soft UI shapes, layered panels",
    "SwiftUI documentation — a cover: stacked view rectangles and a layout grid",
    "swift-evolution — a repository cover: proposals as cards with status chips",
    "Swift README — a repository cover: a terminal building a toolchain",
    "CSS scroll-driven animations (MDN) — a cover: a scroll bar driving a progress animation",
    "SwiftData — a cover: model boxes linked to a database cylinder",
]
for i, s in enumerate(raindrop):
    pic(f"raindrop-{i}", "cover", (800, 420), f"Bookmark cover image: {s}; no Apple or MDN logos")
pic("raindrop-0b", "cover", (800, 420), "Second image of the HIG bookmark: a colour and typography specimen page")
pic("raindrop-3b", "cover", (800, 420), "Second image of the Swift README bookmark: a build log with a green success line")
pinterest = [
    ("Kitchen — open shelving", "open kitchen shelves with jars, plates and a plant"),
    ("Studio — one lamp", "a studio corner lit by a single floor lamp, armchair"),
    ("Ceramics — matte glaze", "a row of matte ceramic cups on a wooden plank"),
    ("Hallway — narrow bench", "a narrow hallway with a slim wooden bench and coat hooks"),
    ("Kitchen — tile grid", "a kitchen wall of square white tiles with dark grout, a shelf"),
    ("Studio — cork board", "a cork board covered in pinned sketches and swatches"),
]
for i, (t, s) in enumerate(pinterest):
    pic(f"pin-{i}", "scene_home", (540, 810), f"Pin '{t}': {s}")

# ── Social posts' own pictures (DemoSeedAll.social) ───────────────────────
pic("fc-0", "ui", (800, 600), "Photo attached to 'Shipped the panel today. Every room's figure in one place.': a laptop-screen photo of a dashboard of small charts and a treemap, dark")
pic("fc-5a", "scene_home", (800, 600), "Photo attached to 'Books that changed how I plan.': a stack of books on a desk")
pic("fc-5b", "scene_home", (800, 600), "Second photo on 'Books that changed how I plan.': an open book with pencil notes and a coffee")
pic("bsky-2", "scene_home", (800, 600), "Photo on 'Espresso and compilers, the eternal pairing.': an espresso cup beside a laptop showing code")
pic("bsky-4a", "scene_home", (800, 600), "Photo on 'Notes from a quiet week.': an open notebook and pen on a table")
pic("bsky-4b", "scene_out", (800, 600), "Second photo on 'Notes from a quiet week.': an empty park path in the rain")
pic("bsky-link-0", "cover", (800, 420), "Link card image for the article 'The quiet case for local-first software' — editorial illustration: a laptop holding its own data, calm, no words")
pic("nostr-0", "scene_out", (800, 600), "Photo on 'Relays are just people who agreed to keep talking.': radio masts on a hill at dusk")
pic("nostr-2a", "scene_out", (800, 600), "Photo on 'A quiet week on the relays, which is the good kind.': a calm lake at dawn, mist")
pic("nostr-2b", "scene_home", (800, 600), "Second photo on that note: a mug and a paperback on a windowsill")

# ── Work (DemoSeedAll.work) ───────────────────────────────────────────────
pic("trello-0", "scene_home", (640, 360), "Trello card cover for 'Kitchen · Order the tiles': green glazed tiles fanned out")
pic("trello-2", "scene_out", (640, 360), "Trello card cover for 'Trip · Book the Lisbon flat': a Lisbon street of tiled facades and balconies")
pic("hf-paper-1", "ui", (800, 600), "Figure 1 from the paper 'Scaling laws for retrieval': log-log plot, recall vs corpus size, three model sizes as lines, legend, axis labels — a paper figure")

# ── Writing: journals and Notion (DemoSeedAll.writing) ────────────────────
dayone = [
    (0, "scene_out", "'Slow morning, long walk': a Berlin canal path at early morning, mist, nobody around"),
    (11, "scene_out", "'Back from Lisbon': an airplane window view over the Tagus and the red bridge"),
    (14, "scene_home", "'Sam's birthday': a long crowded dinner table from above, plates, glasses, candles"),
    (18, "scene_out", "'Long walk, no route': an unfamiliar residential street at dusk, lit windows"),
]
for i, fam, s in dayone:
    pic(f"dayone-{i}", fam, (800, 600), f"Day One journal photo for {s}")
pic("journal-1", "scene_out", (800, 600), "Apple Journal photo for 'Notes on the trip': Lisbon in autumn light, a café table on a square")
pic("journal-11", "scene_out", (800, 600), "Apple Journal photo for 'Berlin in the rain': a rainy Berlin street, umbrellas, reflections")
notion = [
    (0, "Roadmap — abstract cover: horizontal lanes with rounded milestone bars, calm gradient"),
    (3, "Trip plan — cover: a stylised map of Lisbon's river edge, pastel"),
    (6, "Hiring loop — cover: a loop of connected circles, soft colours"),
    (9, "Recipes — cover: a flat-lay pattern of herbs, lemons and a bowl"),
]
for i, s in notion:
    pic(f"notion-{i}", "cover", (900, 360), f"Notion page cover, {s}; no words")

PICTURES = P

# The keys must be unique — the whole point of this table.
_seen = set()
for _p in P:
    assert _p["key"] not in _seen, f"duplicate key {_p['key']}"
    _seen.add(_p["key"])
