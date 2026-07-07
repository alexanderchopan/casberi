import { useState, useRef, useEffect } from "react";
import { useLangStream, El, Els } from "./genui/engine";
import {
  House, LayoutGrid, Activity, Settings, Plus, Search, ArrowUp, X,
  Calendar, Mail, Bot, ListChecks, ChevronRight, ChevronLeft, FileText, Bell, Asterisk, Sparkle, Pin, Zap, CircleUser, Mic, Wallet, Lock, Wifi, WifiOff, Smartphone, CreditCard, LifeBuoy, Info, Signal, Moon, ArrowUpRight, ChevronDown, BarChart3,
} from "lucide-react";

const v = (name: string) => `var(--ds-${name})`;

type TabId = "home" | "apps" | "feed" | "account";
type AppsView = "list" | "detail" | "catalog";

type AppRow = {
  id: string; name: string; Icon: any;
  status: "ok" | "attention" | "paused";
  statusLine: string;
  lastActive?: number;
  can: string[];
  recent: string[];
};

const initialApps: AppRow[] = [
  { id: "cal", name: "Calendar", Icon: Calendar, status: "attention", statusLine: "Reconnect Calendar", lastActive: 3,
    can: ["Reads your calendar.", "Adds events when you ask."],
    recent: ["Dinner with Sam · added Tue", "Dentist · added Mon"] },
  { id: "gmail", name: "Gmail", Icon: Mail, status: "ok", statusLine: "Synced 2m ago", lastActive: 1,
    can: ["Reads your mail.", "Drafts replies when you ask."],
    recent: ["Flight confirmation · saved 2m ago", "Receipt from Lyft · saved 1h ago"] },
  { id: "gpt", name: "ChatGPT", Icon: Bot, status: "ok", statusLine: "Synced 1h ago", lastActive: 2,
    can: ["Brings in your chats.", "Does work when you ask."],
    recent: ["Trip plan: Lisbon · saved 1h ago", "Workout plan · saved 3d ago"] },
  { id: "rem", name: "Reminders", Icon: ListChecks, status: "paused", statusLine: "Paused", lastActive: 4,
    can: ["Reads your reminders.", "Adds reminders when you ask."],
    recent: ["Book dentist · added last week"] },
  { id: "pho", name: "Photos", Icon: FileText, status: "ok", statusLine: "Synced 1d ago", lastActive: 5,
    can: ["Reads screenshots you save."],
    recent: ["4 screenshots · yesterday"] },
  { id: "twi", name: "X", Icon: FileText, status: "ok", statusLine: "Synced 1d ago", lastActive: 6,
    can: ["Brings in threads you save."],
    recent: ["Design thread · yesterday"] },
];

const catalog = [
  { group: "Your schedule", items: [{ name: "Apple Calendar", Icon: Calendar }, { name: "Google Calendar", Icon: Calendar }] },
  { group: "Your mail", items: [{ name: "Gmail", Icon: Mail }] },
  { group: "Your notes", items: [{ name: "Apple Notes", Icon: FileText }, { name: "Apple Reminders", Icon: ListChecks }] },
  { group: "Your agent", items: [{ name: "ChatGPT", Icon: Bot }, { name: "Claude", Icon: Bot }, { name: "Gemini", Icon: Bot }] },
];

const sortRank = { attention: 0, ok: 1, paused: 2 } as const;


/* ---------- app icons: squircle tiles, brand-colored stand-ins.
   Production swaps in real app icon assets. ---------- */
function AppIcon({ name, size = 40 }: { name: string; size?: number }) {
  if (!name) name = "?";
  const r = Math.round(size * 0.2237);
  const base: React.CSSProperties = {
    width: size, height: size, borderRadius: r, flexShrink: 0,
    display: "flex", alignItems: "center", justifyContent: "center",
    overflow: "hidden",
    boxShadow: "inset 0 0 0 1px rgba(0,0,0,0.08)",
  };
  const n = name.toLowerCase();

  if (n === "calendar" || n === "apple calendar") return (
    <span style={{ ...base, background: "#fff", flexDirection: "column" }}>
      <span style={{ fontSize: size * 0.18, lineHeight: 1, color: "#FF3B30", fontWeight: 600, textTransform: "uppercase", letterSpacing: "0.02em" }}>Thu</span>
      <span style={{ fontSize: size * 0.42, lineHeight: 1.1, color: "#000", fontWeight: 400 }}>2</span>
    </span>
  );
  if (n === "google calendar") return (
    <span style={{ ...base, background: "#fff" }}>
      <span style={{ fontSize: size * 0.4, color: "#1A73E8", fontWeight: 500 }}>31</span>
    </span>
  );
  if (n === "gmail") return (
    <span style={{ ...base, background: "#fff" }}>
      <svg width={size * 0.55} height={size * 0.42} viewBox="0 0 24 18">
        <path d="M2 16V4l10 7L22 4v12" fill="none" stroke="#EA4335" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
    </span>
  );
  if (n === "chatgpt") return (
    <span style={{ ...base, background: "#000", border: "1px solid rgba(255,255,255,0.14)" }}>
      <Asterisk size={size * 0.55} color="#fff" strokeWidth={2.4} />
    </span>
  );
  if (n === "claude") return (
    <span style={{ ...base, background: "#EEECE2" }}>
      <Asterisk size={size * 0.55} color="#D97757" strokeWidth={2.6} />
    </span>
  );
  if (n === "x" || n.includes("twitter")) return (
    <span style={{ ...base, background: "#000", border: "1px solid rgba(255,255,255,0.14)" }}>
      <svg width={size * 0.5} height={size * 0.5} viewBox="0 0 24 24">
        <path d="M18.9 1.2h3.7l-8.1 9.3L24 22.8h-7.5l-5.9-7.7-6.7 7.7H.2l8.7-9.9L0 1.2h7.7l5.3 7 6-7z" fill="#fff" />
      </svg>
    </span>
  );
  if (n === "photos" || n === "apple photos") return (
    <span style={{ ...base, background: "#fff" }}>
      <svg width={size * 0.72} height={size * 0.72} viewBox="0 0 48 48">
        {[
          ["#FDB027", 0], ["#F7E12F", 45], ["#C7DB4E", 90], ["#5EC66E", 135],
          ["#54C7DC", 180], ["#5E9EE6", 225], ["#B58BE0", 270], ["#EF7BA2", 315],
        ].map(([c, deg]) => (
          <ellipse key={String(deg)} cx="24" cy="13" rx="6" ry="10" fill={String(c)} opacity="0.82"
            transform={`rotate(${deg} 24 24)`} />
        ))}
      </svg>
    </span>
  );
  if (n === "gemini") return (
    <span style={{ ...base, background: "#fff" }}>
      <Sparkle size={size * 0.5} color="#4E82EE" fill="#4E82EE" />
    </span>
  );
  if (n === "reminders" || n === "apple reminders") return (
    <span style={{ ...base, background: "#fff", flexDirection: "column", alignItems: "flex-start", gap: size * 0.07, paddingLeft: size * 0.18 }}>
      {["#FF9F0A", "#FF3B30", "#0A84FF"].map((c) => (
        <span key={c} style={{ display: "flex", alignItems: "center", gap: size * 0.07 }}>
          <span style={{ width: size * 0.1, height: size * 0.1, borderRadius: 999, background: c }} />
          <span style={{ width: size * 0.38, height: size * 0.05, borderRadius: 999, background: "#D1D1D6" }} />
        </span>
      ))}
    </span>
  );
  if (n === "photos") return (
    <span style={{ ...base, background: "#fff", position: "relative" }}>
      <span style={{ position: "relative", width: size * 0.62, height: size * 0.62 }}>
        {["#FF9F0A", "#FFD60A", "#30D158", "#64D2FF", "#0A84FF", "#BF5AF2", "#FF375F", "#FF6482"].map((c, i) => {
          const a = (i / 8) * Math.PI * 2;
          return (
            <span key={i} style={{
              position: "absolute", left: "50%", top: "50%",
              width: size * 0.34, height: size * 0.16, borderRadius: size * 0.08,
              background: c, opacity: 0.85,
              transform: `translate(-50%, -50%) rotate(${(a * 180) / Math.PI}deg) translateX(${size * 0.16}px)`,
            }} />
          );
        })}
      </span>
    </span>
  );
  if (n === "twitter" || n === "x") return (
    <span style={{ ...base, background: "#000", border: "1px solid rgba(255,255,255,0.14)" }}>
      <span style={{ color: "#fff", fontWeight: 700, fontSize: size * 0.5, fontFamily: "inherit", lineHeight: 1 }}>𝕏</span>
    </span>
  );
  if (n === "apple notes" || n === "notes") return (
    <span style={{ ...base, background: "#fff", flexDirection: "column", justifyContent: "flex-start" }}>
      <span style={{ width: "100%", height: size * 0.24, background: "linear-gradient(#FCD34D, #FBBF24)" }} />
      <span style={{ display: "flex", flexDirection: "column", gap: size * 0.08, marginTop: size * 0.12, width: "100%", alignItems: "center" }}>
        {[0.6, 0.6, 0.4].map((w, i) => (
          <span key={i} style={{ width: `${w * 100}%`, height: size * 0.045, borderRadius: 999, background: "#C7C7CC", alignSelf: "flex-start", marginLeft: size * 0.2 }} />
        ))}
      </span>
    </span>
  );
  return (
    <span style={{ ...base, background: v("gray-100"), color: v("gray-900"), fontSize: size * 0.4, fontWeight: 500 }}>
      {name[0]}
    </span>
  );
}

function Tile({ Icon }: { Icon: any }) {
  return (
    <span style={{
      width: 36, height: 36, borderRadius: v("radius-control"),
      background: v("gray-100"),
      display: "flex", alignItems: "center", justifyContent: "center",
      color: v("gray-900"), flexShrink: 0,
    }}><Icon size={16} /></span>
  );
}

function Row({ children, onClick }: { children: React.ReactNode; onClick?: () => void }) {
  return (
    <button onClick={onClick} style={{
      display: "flex", alignItems: "center", gap: v("space-3"), width: "100%",
      minHeight: 56, padding: `var(--ds-space-2) var(--ds-space-4)`,
      background: "transparent", border: "none",
      cursor: onClick ? "pointer" : "default", textAlign: "left",
      color: v("gray-1000"), fontFamily: "inherit",
    }}>{children}</button>
  );
}

function Card({ children }: { children: React.ReactNode }) {
  return (
    <div style={{
      background: v("surface-sheet"),
      borderRadius: v("radius-card"), overflow: "hidden",
    }}>{children}</div>
  );
}

function Divider() {
  return <div style={{ height: 1, background: v("gray-alpha-200"), marginLeft: 64 }} />;
}

function StatusLine({ app }: { app: AppRow }) {
  const color = app.status === "attention" ? v("amber-800") : app.status === "paused" ? v("gray-700") : v("gray-900");
  return <span className="t-copy-13" style={{ color }}>{app.statusLine}</span>;
}

/* ---------- Apps tab: list ---------- */
function StateRing({ name, status, size = 52 }: { name: string; status: AppRow["status"]; size?: number }) {
  const color = status === "ok" ? v("green-700") : status === "attention" ? v("amber-800") : v("gray-500");
  const r = Math.round((size + 12) * 0.2237) + 3;
  return (
    <span style={{
      padding: v("space-1"), borderRadius: r, border: `2.5px solid ${color}`,
      display: "inline-flex", flexShrink: 0,
    }}>
      <AppIcon name={name} size={size} />
    </span>
  );
}

function SwipeRow({ app, onOpen, onReconnect, onRemove, openId, setOpenId }: {
  app: AppRow; onOpen: () => void; onReconnect: () => void; onRemove: () => void;
  openId: string | null; setOpenId: (id: string | null) => void;
}) {
  const [dx, setDx] = useState(0);
  const startX = useRef<number | null>(null);
  const actionsW = 176;
  const open = openId === app.id;
  const offset = open ? -actionsW : dx;

  const onStart = (x: number) => { startX.current = x; };
  const onMove = (x: number) => {
    if (startX.current === null) return;
    const d = x - startX.current - (open ? actionsW : 0);
    setDx(Math.max(-actionsW, Math.min(0, d)));
  };
  const onEnd = () => {
    if (startX.current === null) return;
    startX.current = null;
    setOpenId(offset < -actionsW / 2 ? app.id : null);
    setDx(0);
  };

  return (
    <div style={{ position: "relative", overflow: "hidden" }}>
      <div style={{ position: "absolute", right: 0, top: 0, bottom: 0, display: "flex" }}>
        <button onClick={() => { setOpenId(null); onReconnect(); }} className="t-label-12" style={{
          width: 88, border: "none", background: v("tint"), color: "#fff",
          cursor: "pointer", fontFamily: "inherit",
        }}>Reconnect</button>
        <button onClick={() => { setOpenId(null); onRemove(); }} className="t-label-12" style={{
          width: 88, border: "none", background: v("red-800"), color: "#fff",
          cursor: "pointer", fontFamily: "inherit",
        }}>Remove</button>
      </div>
      <div
        onTouchStart={(e) => onStart(e.touches[0].clientX)}
        onTouchMove={(e) => onMove(e.touches[0].clientX)}
        onTouchEnd={onEnd}
        onMouseDown={(e) => onStart(e.clientX)}
        onMouseMove={(e) => e.buttons === 1 && onMove(e.clientX)}
        onMouseUp={onEnd}
        onMouseLeave={() => startX.current !== null && onEnd()}
        onClick={() => { if (open) { setOpenId(null); } else if (Math.abs(dx) < 4) { onOpen(); } }}
        style={{
          display: "flex", alignItems: "center", gap: v("space-4"), width: "100%",
          padding: `var(--ds-space-3) var(--ds-space-4)`,
          background: v("background-200"), cursor: "pointer",
          color: v("gray-1000"), fontFamily: "inherit",
          transform: `translateX(${offset}px)`,
          transition: startX.current === null ? `transform var(--ds-duration) var(--ds-ease)` : "none",
          userSelect: "none",
        }}
      >
        <StateRing name={app.name} status={app.status} size={44} />
        <span className="t-label-14" style={{ flex: 1 }}>{app.name}</span>
      </div>
    </div>
  );
}


function AppsList({ apps, empty, onOpen, onAdd, onReconnect, onRemove }: {
  apps: AppRow[]; empty: boolean; onOpen: (a: AppRow) => void; onAdd: () => void;
  onReconnect: (a: AppRow) => void; onRemove: (a: AppRow) => void;
}) {
  const [sort, setSort] = useState<"recent" | "az">("recent");
  const [openId, setOpenId] = useState<string | null>(null);
  const base = sort === "az" ? [...apps].sort((a, b) => a.name.localeCompare(b.name)) : apps;
  const sorted = [...base].sort((a, b) => (a.status === "attention" ? -1 : 0) - (b.status === "attention" ? -1 : 0));
  return (
    <div>
      <div style={{ display: "flex", alignItems: "center", gap: v("space-2"), padding: `var(--ds-space-6) var(--ds-space-4) var(--ds-space-4)` }}>
        <h1 className="t-heading-24" style={{ margin: 0, flex: 1 }}>Apps</h1>
        {!empty && (
          <button onClick={() => setSort(sort === "recent" ? "az" : "recent")} className="t-label-12" style={{
            background: v("gray-100"), border: "none", borderRadius: v("radius-pill"),
            color: v("gray-900"), padding: `var(--ds-space-1) var(--ds-space-3)`, cursor: "pointer", fontFamily: "inherit",
          }}>{sort === "recent" ? "Recent" : "A–Z"}</button>
        )}
      </div>

      {empty ? (
        <div style={{ padding: `var(--ds-space-2) var(--ds-space-4)`, display: "flex", flexDirection: "column", gap: v("space-3") }}>
          {[
            { title: "See your week", desc: "Your plans, in one place.", app: "Calendar" },
            { title: "Your mail, findable", desc: "Receipts, bookings, the thing from Tuesday.", app: "Gmail" },
            { title: "Bring your ChatGPT", desc: "Everything you made there, kept here.", app: "ChatGPT" },
          ].map((c) => (
            <button key={c.title} onClick={onAdd} className="pressable" style={{
              background: v("surface-sheet"), border: "none", borderRadius: v("radius-card"),
              padding: v("space-6"), cursor: "pointer", textAlign: "left", fontFamily: "inherit",
              display: "flex", flexDirection: "column", gap: v("space-3"), color: v("gray-1000"),
            }}>
              <AppIcon name={c.app} size={56} />
              <span>
                <span className="t-heading-20" style={{ display: "block" }}>{c.title}</span>
                <span className="t-copy-14" style={{ color: v("gray-900") }}>{c.desc}</span>
              </span>
              <span className="t-heading-16" style={{
                background: v("tint"), color: "#fff", borderRadius: v("radius-pill"),
                padding: `var(--ds-space-2) var(--ds-space-6)`,
              }}>Connect</span>
            </button>
          ))}
        </div>
      ) : (
        <div style={{ padding: `var(--ds-space-2) 0` }}>
          {sorted.map((a) => (
            <SwipeRow key={a.id} app={a} openId={openId} setOpenId={setOpenId}
              onOpen={() => onOpen(a)} onReconnect={() => onReconnect(a)} onRemove={() => onRemove(a)} />
          ))}
          <button onClick={onAdd} className="pressable" style={{
            display: "flex", alignItems: "center", gap: v("space-4"), width: "100%",
            padding: `var(--ds-space-3) var(--ds-space-4)`,
            background: "transparent", border: "none", cursor: "pointer", textAlign: "left",
            color: v("tint"), fontFamily: "inherit",
          }}>
            <span style={{
              width: 52, height: 52, borderRadius: v("radius-pill"), flexShrink: 0,
              background: v("gray-100"), display: "flex", alignItems: "center", justifyContent: "center",
            }}><Plus size={22} /></span>
            <span className="t-label-14">Add app</span>
          </button>
        </div>
      )}
    </div>
  );
}

/* ---------- Apps tab: detail ---------- */
function AppDetail({ app, onBack, onTogglePause, onRemove }: {
  app: AppRow; onBack: () => void; onTogglePause: () => void; onRemove: () => void;
}) {
  return (
    <div>
      <div style={{ display: "flex", alignItems: "center", gap: v("space-2"), padding: `var(--ds-space-4) var(--ds-space-3)` }}>
        <button onClick={onBack} aria-label="Back" style={{ background: "none", border: "none", cursor: "pointer", padding: v("space-2"), color: v("gray-900"), borderRadius: v("radius-control") }}>
          <ChevronLeft size={20} />
        </button>
        <AppIcon name={app.name} size={52} />
        <div style={{ flex: 1 }}>
          <div className="t-heading-16">{app.name}</div>
          <StatusLine app={app} />
        </div>
      </div>

      <div style={{ padding: `0 var(--ds-space-4)`, display: "flex", flexDirection: "column", gap: v("space-3") }}>
        {app.status === "attention" && (
          <button className="t-label-14" style={{
            background: v("tint"), color: "#fff", border: "none",
            borderRadius: v("radius-control"), height: 44, cursor: "pointer", fontFamily: "inherit",
          }}>Reconnect</button>
        )}

        <Card>
          <div style={{ padding: v("space-4") }}>
            <div className="t-label-12" style={{ color: v("gray-700"), marginBottom: v("space-2"), textTransform: "uppercase", letterSpacing: "0.04em" }}>What it does</div>
            {app.can.map((c) => (
              <div key={c} className="t-copy-14" style={{ marginBottom: 4 }}>{c}</div>
            ))}
          </div>
        </Card>

        <Card>
          <div style={{ padding: `var(--ds-space-4) var(--ds-space-4) var(--ds-space-2)` }}>
            <div className="t-label-12" style={{ color: v("gray-700"), textTransform: "uppercase", letterSpacing: "0.04em" }}>Recent</div>
          </div>
          {app.recent.map((r, i) => (
            <div key={r}>
              {i > 0 && <div style={{ height: 1, background: v("gray-alpha-200"), marginLeft: 16 }} />}
              <div className="t-copy-14" style={{ padding: `var(--ds-space-3) var(--ds-space-4)` }}>{r}</div>
            </div>
          ))}
        </Card>

        <Card>
          <Row onClick={onTogglePause}>
            <span className="t-label-14" style={{ flex: 1 }}>{app.status === "paused" ? "Resume" : "Pause"}</span>
          </Row>
          <div style={{ height: 1, background: v("gray-alpha-200") }} />
          <Row onClick={onRemove}>
            <span className="t-label-14" style={{ flex: 1, color: v("red-900") }}>Remove</span>
          </Row>
        </Card>
      </div>
    </div>
  );
}

/* ---------- Apps tab: picker of installed apps ---------- */
const installedApps = ["Calendar", "Gmail", "ChatGPT", "Claude", "Gemini", "Maps", "Messages", "Notes", "Photos", "Reminders", "Safari", "Spotify", "X"];

function Catalog({ connected, onBack, onConnect }: { connected: string[]; onBack: () => void; onConnect: (name: string, Icon: any) => void }) {
  const [q, setQ] = useState("");
  const list = installedApps
    .filter((a) => !connected.includes(a))
    .filter((a) => a.toLowerCase().includes(q.toLowerCase()));
  return (
    <div>
      <div style={{ display: "flex", alignItems: "center", gap: v("space-1"), padding: `var(--ds-space-4) var(--ds-space-3)` }}>
        <button onClick={onBack} aria-label="Back" style={{ background: "none", border: "none", cursor: "pointer", padding: v("space-2"), color: v("gray-900"), borderRadius: v("radius-control") }}>
          <ChevronLeft size={20} />
        </button>
        <h1 className="t-heading-20" style={{ margin: 0 }}>Add an app</h1>
      </div>
      <div style={{ padding: `0 var(--ds-space-4) var(--ds-space-2)` }}>
        <div style={{
          display: "flex", alignItems: "center", gap: v("space-2"),
          background: v("gray-100"), borderRadius: v("radius-pill"),
          padding: `0 var(--ds-space-4)`, height: 40,
        }}>
          <Search size={16} color={v("gray-700")} />
          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Search your apps"
            className="t-copy-14"
            style={{ flex: 1, border: "none", outline: "none", background: "transparent", color: v("gray-1000"), fontFamily: "inherit", minWidth: 0 }}
          />
        </div>
      </div>
      <div style={{
        background: v("surface-sheet"), borderRadius: 20,
        margin: `var(--ds-space-2) var(--ds-space-4) 0`, overflow: "hidden",
      }}>
        {list.map((name) => (
          <button key={name} onClick={() => onConnect(name, FileText)} className="pressable" style={{
            display: "flex", alignItems: "center", gap: v("space-3"), width: "100%",
            padding: `var(--ds-space-3) var(--ds-space-4)`,
            background: "transparent", border: "none", cursor: "pointer", textAlign: "left",
            color: v("gray-1000"), fontFamily: "inherit",
          }}>
            <AppIcon name={name} size={40} />
            <span className="t-label-14" style={{ flex: 1 }}>{name}</span>
            <span className="t-label-12" style={{ color: v("tint") }}>Connect</span>
          </button>
        ))}
        {list.length === 0 && (
          <div className="t-copy-14" style={{ color: v("gray-700"), padding: v("space-4") }}>No apps match.</div>
        )}
      </div>
      <p className="t-copy-13" style={{ color: v("gray-700"), padding: `var(--ds-space-3) var(--ds-space-6)` }}>
        Connecting installs the bridge for you.
      </p>
    </div>
  );
}

/* ---------- remove confirm ---------- */
function RemoveConfirm({ appName, onKeep, onRemoveAll, onCancel }: {
  appName: string; onKeep: () => void; onRemoveAll: () => void; onCancel: () => void;
}) {
  return (
    <>
      <div onClick={onCancel} style={{ position: "absolute", inset: 0, background: "var(--ds-scrim)", zIndex: 40 }} />
      <div style={{
        position: "absolute", left: 16, right: 16, bottom: 24, zIndex: 41,
        background: v("surface-sheet"), borderRadius: v("radius-sheet"),
        boxShadow: v("shadow-overlay"), padding: v("space-4"),
      }}>
        <div className="t-heading-16" style={{ marginBottom: 4 }}>Remove {appName}?</div>
        <div className="t-copy-14" style={{ color: v("gray-900"), marginBottom: v("space-4") }}>
          Access is revoked. Choose what happens to the things it brought in.
        </div>
        <div style={{ display: "flex", flexDirection: "column", gap: v("space-2") }}>
          <button onClick={onKeep} className="t-label-14" style={{
            background: v("tint"), color: "#fff", border: "none",
            borderRadius: v("radius-control"), height: 44, cursor: "pointer", fontFamily: "inherit",
          }}>Remove app, keep things</button>
          <button onClick={onRemoveAll} className="t-label-14" style={{
            background: v("gray-100"), color: v("red-900"), border: "none",
            borderRadius: v("radius-control"), height: 44, cursor: "pointer", fontFamily: "inherit",
          }}>Remove app and things</button>
          <button onClick={onCancel} className="t-label-14" style={{
            background: "transparent", color: v("tint"), border: "none",
            borderRadius: v("radius-control"), height: 44, cursor: "pointer", fontFamily: "inherit",
          }}>Cancel</button>
        </div>
      </div>
    </>
  );
}

/* ---------- quick actions ---------- */

function QuickActions({ onClose }: { onClose: () => void }) {
  return (
    <>
      <div onClick={onClose} style={{ position: "absolute", inset: 0, background: "var(--ds-scrim)", zIndex: 40 }} />
      <div style={{
        position: "absolute", left: 0, right: 0, bottom: 0, zIndex: 41,
        background: v("surface-sheet"),
        borderTopLeftRadius: v("radius-sheet"), borderTopRightRadius: v("radius-sheet"),
        boxShadow: v("shadow-overlay"), paddingBottom: v("space-4"),
        animation: "sheetUp var(--ds-duration) var(--ds-ease)",
      }}>
        <div style={{ display: "flex", alignItems: "center", padding: `var(--ds-space-4) var(--ds-space-4) var(--ds-space-2)` }}>
          <span className="t-heading-16" style={{ flex: 1 }}>Quick actions</span>
          <button onClick={onClose} aria-label="Close" style={{ background: "none", border: "none", cursor: "pointer", padding: v("space-2"), borderRadius: v("radius-control") }}>
            <X size={18} color={v("gray-900")} />
          </button>
        </div>
        <div className="t-copy-14" style={{ color: v("gray-700"), padding: `var(--ds-space-2) var(--ds-space-4) var(--ds-space-4)` }}>
          Not defined yet.
        </div>
      </div>
      <style>{`@keyframes sheetUp { from { transform: translateY(24px); opacity: 0 } to { transform: translateY(0); opacity: 1 } }`}</style>
    </>
  );
}


/* ---------- streaming parse (OpenUI-style progressive render) ---------- */
type Parse = { kind: string; Icon: any; meta: string | null };

function classify(d: string): Parse {
  const s = d.trim();
  if (/^https?:\/\//i.test(s)) return { kind: "Link", Icon: FileText, meta: "Save to Home" };
  if (/\?$/.test(s) || /^(find|where|search|show|who|what|when)\b/i.test(s))
    return { kind: "Search", Icon: Search, meta: "Search your things" };
  const time = s.match(/\b(mon|tue|wed|thu|fri|sat|sun)[a-z]*\b|\btomorrow\b|\btonight\b|\btoday\b|\b\d{1,2}\s?(am|pm)\b/gi);
  if (time) {
    const isTask = /^(book|call|buy|pick|pay|email|text|remind|renew|return)\b/i.test(s);
    return { kind: isTask ? "Reminder" : "Event", Icon: isTask ? Bell : Calendar, meta: time.join(" · ") };
  }
  if (s.length > 0) return { kind: "Note", Icon: FileText, meta: null };
  return { kind: "", Icon: FileText, meta: null };
}

function ParsePreview({ draft }: { draft: string }) {
  const p = classify(draft);
  if (!p.kind || p.kind === "Search") return null;
  const row = (delay: number): React.CSSProperties => ({
    animation: `parseIn 240ms var(--ds-ease) ${delay}ms both`,
  });
  return (
    <div key={p.kind + (p.meta ?? "")} style={{
      margin: `0 var(--ds-space-4) var(--ds-space-2)`,
      background: v("surface-sheet"), borderRadius: v("radius-card"),
      padding: v("space-3"), display: "flex", flexDirection: "column", gap: 6,
      animation: "parseIn 240ms var(--ds-ease) both",
    }}>
      <div style={{ display: "flex", alignItems: "center", gap: v("space-2"), ...row(0) }}>
        <span style={{
          display: "inline-flex", alignItems: "center", gap: v("space-1"),
          background: v("tint-dim"), color: v("tint"),
          borderRadius: v("radius-pill"), padding: `var(--ds-space-1) var(--ds-space-2)`,
        }} className="t-label-12"><p.Icon size={12} /> {p.kind}</span>
      </div>
      <div className="t-label-14" style={row(90)}>{draft.trim()}</div>
      {p.meta && (
        <div className="t-copy-13" style={{ color: v("gray-900"), ...row(180) }}>{p.meta}</div>
      )}
      <style>{`@keyframes parseIn { from { opacity: 0; transform: translateY(4px) } to { opacity: 1; transform: translateY(0) } }`}</style>
    </div>
  );
}


/* ---------- composer: one unit, pill expands in place ---------- */
function ComposerUnit({ open, draft, setDraft, onOpen, onClose, onCommit }: {
  open: boolean; draft: string; setDraft: (s: string) => void;
  onOpen: () => void; onClose: () => void; onCommit: () => void;
}) {
  const [answerFor, setAnswerFor] = useState<string | null>(null);
  useEffect(() => { if (!open) { setAnswerFor(null); setDraft(""); } // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open]);
  const handle = () => {
    const p = classify(draft);
    if (p.kind === "Search") setAnswerFor(draft);
    else onCommit();
  };
  const chips = ["Lisbon trip", "Mobile app", "lisbon", "File"];
  return (
    <div style={{
      background: v("glass-bg"),
      backdropFilter: "var(--ds-glass-blur)", WebkitBackdropFilter: "var(--ds-glass-blur)",
      boxShadow: `inset 0 0 0 1px var(--ds-glass-stroke), 0 8px 24px rgba(0,0,0,0.4)`,
      borderRadius: open ? "24px 24px 10px 24px" : v("radius-pill"),
      maxHeight: open ? 420 : 48,
      display: "flex", flexDirection: "column", overflow: "hidden",
      transformOrigin: "100% 100%",
      animation: open ? "bubbleIn 260ms var(--ds-ease)" : "none",
    }}>
      <style>{`@keyframes bubbleIn { from { transform: scale(0.3); opacity: 0 } to { transform: scale(1); opacity: 1 } }`}</style>
      {!open ? (
        <div onClick={onOpen} style={{ display: "flex", alignItems: "center", gap: v("space-2"), height: 48, padding: `0 var(--ds-space-2) 0 var(--ds-space-3)`, cursor: "text" }}>
          <Search size={16} color={v("gray-700")} style={{ flexShrink: 0 }} />
          <div style={{ flex: 1, display: "flex", gap: v("space-2"), minWidth: 0, overflowX: "auto" }}>
            <button onClick={(e) => { e.stopPropagation(); onOpen(); }} className="t-label-12" style={{
              background: v("tint-dim"), color: v("tint"), border: "none",
              borderRadius: v("radius-pill"), padding: `var(--ds-space-1) var(--ds-space-3)`, height: 28, flexShrink: 0,
              cursor: "pointer", fontFamily: "inherit",
            }}>Ask</button>
            {["Open app", "Open shortcut"].map((a) => (
              <button key={a} onClick={(e) => { e.stopPropagation(); parseAction.fn?.(a); }} className="t-label-12" style={{
                background: v("gray-100"), color: v("gray-900"), border: "none",
                borderRadius: v("radius-pill"), padding: `var(--ds-space-1) var(--ds-space-3)`, height: 28, flexShrink: 0,
                cursor: "pointer", fontFamily: "inherit",
              }}>{a}</button>
            ))}
          </div>
          <button aria-label="Voice" onClick={(e) => e.stopPropagation()} style={{
            background: "none", border: "none", cursor: "pointer", padding: v("space-1"),
            color: v("gray-700"), display: "flex", flexShrink: 0,
          }}><Mic size={18} /></button>
        </div>
      ) : (
        <>
          <div style={{ flex: 1, overflowY: "auto", minHeight: 0 }}>
            <div style={{ display: "flex", alignItems: "flex-start", gap: v("space-2"), padding: `var(--ds-space-3) var(--ds-space-3) 0 var(--ds-space-4)` }}>
              <textarea
                autoFocus
                value={draft}
                onChange={(e) => setDraft(e.target.value)}
                placeholder="Ask anything. Organize everything."
                rows={2}
                className="t-heading-20"
                style={{
                  flex: 1, border: "none", outline: "none", boxShadow: "none", resize: "none",
                  background: "transparent", color: v("gray-1000"),
                  fontFamily: "inherit", caretColor: v("tint"), minWidth: 0,
                }}
              />
              <button onClick={onClose} aria-label="Close" style={{
                width: 28, height: 28, borderRadius: v("radius-pill"), border: "none",
                background: v("gray-100"), color: v("gray-900"), cursor: "pointer",
                display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0,
              }}><ChevronDown size={16} /></button>
            </div>

            {!answerFor && (
              <div style={{ display: "flex", gap: v("space-2"), padding: `var(--ds-space-1) var(--ds-space-4) 0` }}>
                {["Open app", "Open shortcut"].map((a) => (
                  <button key={a} onClick={() => parseAction.fn?.(a)} className="t-label-12" style={{
                    display: "flex", alignItems: "center", gap: v("space-1"),
                    background: v("tint-dim"), color: v("tint"), border: "none",
                    borderRadius: v("radius-pill"), padding: `var(--ds-space-1) var(--ds-space-3)`, height: 28, flexShrink: 0,
                    cursor: "pointer", fontFamily: "inherit",
                  }}><Zap size={12} /> {a}</button>
                ))}
              </div>
            )}
            {!draft.trim() && !answerFor && (
              <div style={{ display: "flex", gap: v("space-2"), overflowX: "auto", padding: `var(--ds-space-1) var(--ds-space-4) var(--ds-space-3)` }}>
                {chips.map((c) => (
                  <button key={c} onClick={() => setDraft(c)} className="t-label-12" style={{
                    background: v("gray-100"), color: v("gray-900"), border: "none",
                    borderRadius: v("radius-pill"), padding: `var(--ds-space-1) var(--ds-space-3)`, height: 28, flexShrink: 0,
                    cursor: "pointer", fontFamily: "inherit",
                  }}>{c}</button>
                ))}
              </div>
            )}

            {draft.trim() && !answerFor && <ParsePreview draft={draft} />}
            {answerFor && <AnswerStream q={answerFor} />}
          </div>

          <div style={{ display: "flex", alignItems: "center", gap: v("space-2"), padding: `var(--ds-space-2) var(--ds-space-3) var(--ds-space-3)`, flexShrink: 0 }}>
            <button aria-label="Voice" style={{
              background: "none", border: "none", cursor: "pointer", padding: v("space-1"),
              color: v("gray-700"), display: "flex", flexShrink: 0,
            }}><Mic size={18} /></button>
            <button onClick={handle} disabled={!draft.trim()} className="t-label-14" style={{
              flex: 1, height: 40, border: "none", borderRadius: v("radius-pill"),
              background: draft.trim() ? v("tint") : v("gray-100"),
              color: draft.trim() ? "#fff" : v("gray-700"),
              cursor: draft.trim() ? "pointer" : "not-allowed", fontFamily: "inherit",
              transition: `background var(--ds-duration) var(--ds-ease)`,
            }}>{classify(draft).kind === "Search" ? "Search" : "Save"}</button>
          </div>
        </>
      )}
    </div>
  );
}

/* ---------- Home: thing model + streamed widgets ---------- */
type Thing = {
  id: string; title: string; tag: string; source: string;
  time: string; status?: "todo" | "doing" | "done" | "saved" | "suggested" | "none";
};

const todayThings: Thing[] = [
  { id: "e1", title: "Team standup", tag: "Event", source: "Calendar", time: "9:30 AM" },
  { id: "e2", title: "Dinner with Sam", tag: "Event", source: "Calendar", time: "7:00 PM" },
];

const initialTasks: Thing[] = [
  { id: "t1", title: "Book dentist", tag: "Reminder", source: "Reminders", time: "Today", status: "todo" },
  { id: "t2", title: "Pay July invoice", tag: "Task", source: "Gmail", time: "Fri", status: "doing" },
  { id: "t3", title: "Send Lisbon dates to Sam", tag: "Task", source: "ChatGPT", time: "—", status: "todo" },
];

const savedThings: Thing[] = [
  { id: "s1", title: "Trip plan: Lisbon", tag: "Session", source: "ChatGPT", time: "1h", status: "saved" },
  { id: "s2", title: "Workout plan", tag: "Note", source: "ChatGPT", time: "3d", status: "saved" },
];

const fileThings: Thing[] = [
  { id: "f1", title: "TAP-1147-confirmation.pdf", tag: "File", source: "Gmail", time: "2h", status: "saved" },
  { id: "f2", title: "receipt-lyft-0630.png", tag: "File", source: "You", time: "2d", status: "saved" },
];

const appPulse = [
  { source: "Gmail", line: "3 new" },
  { source: "ChatGPT", line: "1 session" },
  { source: "Calendar", line: "2 events" },
];

function Tag({ label }: { label: string }) {
  return (
    <span className="t-label-12" style={{
      background: v("gray-100"), color: v("gray-900"),
      padding: `0 var(--ds-space-2)`, borderRadius: v("radius-pill"),
      lineHeight: "18px", flexShrink: 0,
    }}>{label}</span>
  );
}

function ThingRow({ t }: { t: Thing }) {
  const done = t.status === "done";
  return (
    <div className="mount" style={{ display: "flex", alignItems: "center", gap: v("space-3"), padding: `var(--ds-space-3) var(--ds-space-4)` }}>
      <AppIcon name={t.source} size={24} />
      <span className="t-label-14" style={{
        flex: 1, minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
        color: done ? v("gray-700") : v("gray-1000"),
        textDecoration: done ? "line-through" : "none",
      }}>{t.title}</span>
      <Tag label={t.tag} />
      <span className="t-copy-13" style={{ color: v("gray-700"), flexShrink: 0 }}>{t.time}</span>
    </div>
  );
}

function Streamed({ i, children }: { i: number; children: React.ReactNode }) {
  return (
    <div style={{ animation: `parseIn 320ms var(--ds-ease) ${i * 180}ms both` }}>
      {children}
      <style>{`@keyframes parseIn { from { opacity: 0; transform: translateY(8px) } to { opacity: 1; transform: translateY(0) } }`}</style>
    </div>
  );
}

function WidgetHeader({ label, count }: { label: string; count?: string }) {
  return (
    <div style={{ display: "flex", alignItems: "baseline", gap: v("space-2"), padding: `var(--ds-space-3) var(--ds-space-4) var(--ds-space-1)` }}>
      <span className="t-heading-16">{label}</span>
      {count && <span className="t-copy-13" style={{ color: v("gray-700") }}>{count}</span>}
    </div>
  );
}

function SuggestRow({ onAdd }: { onAdd: () => void }) {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: v("space-3"), padding: `var(--ds-space-3) var(--ds-space-4)` }}>
      <span className="t-copy-13" style={{ color: v("gray-900"), flex: 1 }}>2 tasks found in mail</span>
      <button onClick={onAdd} className="t-label-12" style={{
        background: v("tint-dim"), color: v("tint"), border: "none",
        borderRadius: v("radius-pill"), padding: `var(--ds-space-1) var(--ds-space-3)`,
        cursor: "pointer", fontFamily: "inherit",
      }}>Review</button>
    </div>
  );
}


/* Declarative generative UI: the "model" authors a composition per moment
   from our component library. A parser renders complete lines as they stream.
   Unresolved refs drop from arrays. */

const KNOWN_SOURCES = ["Gmail", "ChatGPT", "Calendar", "Photos", "X", "Reminders", "Notes"];

function filterDoc(doc: string[], connected: string[]): string[] {
  return doc.filter((line) => {
    if (!/= (Row|Chip)\(/.test(line)) return true;
    const hit = KNOWN_SOURCES.find((s) => line.includes(`"${s}"`));
    return !hit || connected.includes(hit);
  });
}

function docConnect(name: string): string[] {
  const n = name.toLowerCase();
  let rows: string[];
  if (/calendar/.test(n)) rows = [
    `g1 = Row("Team standup", "Event", "${name}", "9:30 AM")`,
    `g2 = Row("Dinner with Sam", "Event", "${name}", "7:00 PM")`,
    `g3 = Row("Flight LIS 1147", "Event", "${name}", "Jul 12")`,
  ];
  else if (/mail/.test(n)) rows = [
    `g1 = Row("Flight confirmation — TAP 1147", "File", "${name}", "2h")`,
    `g2 = Row("Re: July invoice", "Mail", "${name}", "2h")`,
    `g3 = Row("Your table for Friday", "Mail", "${name}", "3h")`,
  ];
  else if (/chatgpt|claude|gemini/.test(n)) rows = [
    `g1 = Row("Trip plan: Lisbon", "Session", "${name}", "1h")`,
    `g2 = Row("Workout plan", "Session", "${name}", "3d")`,
    `g3 = Row("Packing list", "Session", "${name}", "1w")`,
  ];
  else rows = [
    `g1 = Row("Imported thing", "Item", "${name}", "now")`,
    `g2 = Row("Imported thing", "Item", "${name}", "now")`,
    `g3 = Row("Imported thing", "Item", "${name}", "now")`,
  ];
  return [
    'root = Stack([hero, insight, projects, incoming])',
    `hero = Hero("Connected", "${name} is in", "3 things found")`,
    'insight = Insight("New things joined your projects where they fit.")',
    'projects = Bento([p1])',
    `p1 = ProjectTile("1", "Lisbon trip", "ChatGPT,Calendar,${name}", "Now spans more of your apps", "11 things", blue)`,
    `incoming = Widget("From ${name}", "3", [g1, g2, g3])`,
    ...rows,
  ];
}

const ANSWER_DOC = [
  'root = Stack([res])',
  'res = Widget("Found", "3", [r1, r2, r3])',
  'r1 = Row("Workout plan", "Note", "ChatGPT", "3d")',
  'r2 = Row("workout-plan.md", "File", "ChatGPT", "3d")',
  'r3 = Row("Gym schedule", "Event", "Calendar", "Mon")',
];

const DOCS: Record<string, string[]> = {
  morning: [
    'root = Stack([hero, insight, projects, themes, stats])',
    'hero = Hero("This week", "Lisbon and design fill your week", "9 things across 5 apps")',
    'insight = Insight("Two of your screenshots match hotels from the Lisbon session.")',
    'projects = Bento([p1, p2, p3, p4])',
    'p1 = ProjectTile("1", "Lisbon trip", "ChatGPT,Calendar,Gmail", "Plans, photos, mail", "9 things", blue)',
    'p2 = ProjectTile("1", "Mobile app", "ChatGPT,Notes", "Sessions and notes", "12 things", purple)',
    'p3 = ProjectTile("1", "Home gym", "ChatGPT,Photos", "A plan and a rack photo", "5 things", green)',
    'p4 = ProjectTile("1", "Design reading", "X,Files", "Threads and papers", "7 things", pink)',
    'themes = Widget("Threads across apps", null, [t1, t2])',
    't1 = Row("Lisbon: 2 screenshots look like hotel options", "Photos", "Photos", "1d")',
    't2 = Row("The @rauno thread ties to your design notes", "Link", "X", "1d")',
    'stats = Bento([sv1, sv2])',
    'sv1 = StatTile("1", "23", "Things this week", "From 5 apps")',
    'sv2 = StatTile("1", "9", "In Lisbon trip", "Your largest project")',
  ],
  evening: [
    'root = Stack([map, projects])',
    'map = TagMap("This week", "What your things are about", [Lisbon 9, Design 7, Mobile app 5, Home gym 3, Money 2, Reading 2])',
    'projects = Bento([p1, p2, p3])',
    'p1 = ProjectTile("1", "Lisbon trip", "ChatGPT,Calendar,Gmail", "Plans, photos, mail", "9 things", blue)',
    'p2 = ProjectTile("1", "Mobile app", "ChatGPT,Notes", "Sessions and notes", "12 things", purple)',
    'p3 = ProjectTile("1", "Design reading", "X,Files", "Threads and papers", "7 things", pink)',
  ],
  connect: [
    'root = Stack([hero, insight, projects, incoming])',
    'hero = Hero("Connected", "Gmail is in", "3 things found")',
    'insight = Insight("A flight confirmation joined Lisbon trip. One invoice matches a reminder.")',
    'projects = Bento([p1])',
    'p1 = ProjectTile("1", "Lisbon trip", "ChatGPT,Calendar,Gmail", "Now spans 3 apps", "11 things", blue)',
    'incoming = Widget("From Gmail", "3", [g1, g2, g3])',
    'g1 = Row("Flight confirmation — TAP 1147", "File", "Gmail", "2h")',
    'g2 = Row("Re: July invoice", "Mail", "Gmail", "2h")',
    'g3 = Row("TAP-1147-confirmation.pdf", "File", "Gmail", "2h")',
  ],
  empty: [
    'root = Stack([hero, projects])',
    'hero = Hero("Now", "Your context goes here", "Connect an app or capture a thing.")',
    'projects = Bento([k1, k2, k3])',
    'k1 = ProjectTile("1", "Projects appear here", "", "Grouped from what you make", "")',
    'k2 = ProjectTile("1", "", "", "", "")',
    'k3 = ProjectTile("1", "", "", "", "")',
  ],
};

function SkeletonRow() {
  return (
    <div className="mount" style={{ display: "flex", alignItems: "center", gap: v("space-3"), padding: `var(--ds-space-3) var(--ds-space-4)` }}>
      <span style={{ width: 24, height: 24, borderRadius: 7, background: v("gray-100"), flexShrink: 0 }} />
      <span style={{ flex: 1, height: 12, borderRadius: v("radius-pill"), background: v("gray-100") }} />
      <span style={{ width: 40, height: 12, borderRadius: v("radius-pill"), background: v("gray-100"), flexShrink: 0 }} />
    </div>
  );
}

const WASH: Record<string, string> = {
  blue: "rgba(10,132,255,0.14)",
  green: "rgba(48,209,88,0.12)",
  amber: "rgba(255,159,10,0.12)",
  pink: "rgba(255,55,95,0.12)",
  purple: "rgba(191,90,242,0.12)",
  teal: "rgba(64,200,224,0.12)",
};

function RenderEl({ id, els, slot }: { id: string; els: Els; slot?: "row" }) {
  const el = els[id];
  if (!el) {
    if (slot === "row") return <SkeletonRow />;
    if (slot === "tile") return <div className="mount" style={{ gridColumn: "span 1", minHeight: 96, background: v("surface-sheet"), borderRadius: 20 }} />;
    return null;
  } // declared ref: skeleton until its line arrives
  const widgetStyle: React.CSSProperties = {
    background: v("surface-sheet"), borderRadius: 20,
    margin: `var(--ds-space-4) var(--ds-space-4) 0`,
    paddingBottom: v("space-2"), overflow: "hidden",
  };
  switch (el.comp) {
    case "Stack":
      return <>{(Array.isArray(el.args[0]) ? el.args[0] : []).map((c: string) => <RenderEl key={c} id={c} els={els} />)}</>;
    case "Hero":
      return (
        <div className="mount" style={{ padding: `var(--ds-space-8) var(--ds-space-4) var(--ds-space-6)` }}>
          <div className="t-label-12" style={{ color: v("tint"), textTransform: "uppercase", letterSpacing: "0.08em" }}>{el.args[0] ?? ""}</div>
          <div className="t-heading-24" style={{ margin: `var(--ds-space-2) 0 var(--ds-space-1)` }}>{el.args[1] ?? ""}</div>
          <div className="t-copy-14" style={{ color: v("gray-900") }}>{el.args[2] ?? ""}</div>
        </div>
      );
    case "Shelf":
      return (
        <div style={{ display: "flex", gap: v("space-2"), overflowX: "auto", padding: `0 var(--ds-space-4)` }}>
          {(Array.isArray(el.args[0]) ? el.args[0] : []).map((c: string) => <RenderEl key={c} id={c} els={els} />)}
        </div>
      );
    case "Chip":
      return (
        <span className="mount" style={{
          display: "flex", alignItems: "center", gap: v("space-2"),
          background: v("gray-100"), borderRadius: v("radius-pill"),
          padding: `var(--ds-space-2) var(--ds-space-3)`, flexShrink: 0,
        }}>
          <AppIcon name={el.args[0] ?? "?"} size={20} />
          <span className="t-copy-13" style={{ color: v("gray-900") }}>{el.args[1] ?? ""}</span>
        </span>
      );
    case "Widget":
      return (
        <div className="mount" style={widgetStyle}>
          <div style={{ display: "flex", alignItems: "baseline", gap: v("space-2"), padding: `var(--ds-space-4) var(--ds-space-4) var(--ds-space-1)` }}>
            <span className="t-heading-20">{el.args[0] ?? ""}</span>
            {el.args[1] && <span className="t-copy-14" style={{ color: v("gray-700") }}>{el.args[1]}</span>}
          </div>
          {(Array.isArray(el.args[2]) ? el.args[2] : []).map((c: string) => <RenderEl key={c} id={c} els={els} slot="row" />)}
        </div>
      );
    case "Row":
      return <ThingRow t={{ id, title: el.args[0] ?? "", tag: el.args[1] ?? "", source: el.args[2] ?? "?", time: el.args[3] ?? "" }} />;
    case "Suggest":
      return <SuggestRow onAdd={() => {}} />;
    case "Insight":
      return (
        <div className="mount" style={{
          background: v("tint-dim"), borderRadius: v("radius-card"),
          margin: `var(--ds-space-4) var(--ds-space-4) 0`, padding: v("space-4"),
        }}>
          <div className="t-label-12" style={{ color: v("tint"), textTransform: "uppercase", letterSpacing: "0.08em", marginBottom: v("space-1") }}>Noticed</div>
          <div className="t-copy-14">{el.args[0] ?? ""}</div>
        </div>
      );
    case "Bento":
      return (
        <div style={{
          display: "grid", gridTemplateColumns: "1fr 1fr", gap: v("space-3"),
          padding: `var(--ds-space-4) var(--ds-space-4) 0`, gridAutoFlow: "dense",
        }}>
          {(Array.isArray(el.args[0]) ? el.args[0] : []).map((c: string) => <RenderEl key={c} id={c} els={els} slot="tile" />)}
        </div>
      );
    case "Tile":
      return (
        <div className="mount" style={{
          gridColumn: el.args[0] === "2" ? "span 2" : "span 1",
          background: v("surface-sheet"), borderRadius: 20,
          padding: v("space-4"), display: "flex", flexDirection: "column", gap: v("space-2"),
          minHeight: 96,
        }}>
          <AppIcon name={el.args[1] ?? "?"} size={24} />
          <div style={{ marginTop: "auto" }}>
            <div className="t-heading-16">{el.args[2] ?? ""}</div>
            <div className="t-copy-13" style={{ color: v("gray-900") }}>{el.args[3] ?? ""}</div>
          </div>
        </div>
      );
    case "ProjectTile": {
      const span2 = el.args[0] === "2";
      const wash = WASH[el.args[5] as string] ?? "transparent";
      return (
        <div className="mount pressable"
          onClick={() => projectTap.fn?.(el.args[1] ?? "", el.args[3] ?? "", el.args[4] ?? "", wash)}
          style={{
          gridColumn: span2 ? "span 2" : "span 1",
          background: v("surface-sheet"),
          borderRadius: 20,
          padding: v("space-4"), display: "flex", flexDirection: "column", gap: v("space-2"),
          minHeight: span2 ? 132 : 120, cursor: "pointer",
        }}>
          <div style={{ display: "flex", alignItems: "center" }}>
            <div style={{ display: "flex" }}>
              {String(el.args[2] ?? "").split(",").filter(Boolean).map((s: string, i: number) => (
                <span key={s} style={{ marginLeft: i === 0 ? 0 : -6, borderRadius: 6, outline: `2px solid ${v("background-200")}` }}>
                  <AppIcon name={s.trim()} size={20} />
                </span>
              ))}
            </div>
            {el.args[4] && (
              <span className="t-label-12" style={{
                color: v("gray-900"), marginLeft: "auto",
                background: v("gray-alpha-100"), borderRadius: v("radius-pill"),
                padding: `var(--ds-space-1) var(--ds-space-2)`,
              }}>{el.args[4]}</span>
            )}
          </div>
          <div style={{ marginTop: "auto", minWidth: 0 }}>
            <div className="t-heading-16" style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{el.args[1] ?? ""}</div>
            <div className="t-copy-13" style={{ color: v("gray-900"), overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{el.args[3] ?? ""}</div>
          </div>
        </div>
      );
    }
    case "TagMap": {
      const items = (Array.isArray(el.args[2]) ? el.args[2] : []).map((s: string) => {
        const m = String(s).trim().match(/^(.+?)\s+(\d+)$/);
        return m ? { tag: m[1], n: parseInt(m[2]) } : { tag: String(s), n: 1 };
      });
      const max = Math.max(1, ...items.map((x: any) => x.n));
      const areas = ["a", "b", "c", "d", "e", "f"];
      return (
        <div className="mount" style={{ padding: `var(--ds-space-4) var(--ds-space-4) 0` }}>
          {el.args[0] && <div className="t-label-12" style={{ color: v("tint"), textTransform: "uppercase", letterSpacing: "0.08em" }}>{el.args[0]}</div>}
          {el.args[1] && <div className="t-copy-14" style={{ color: v("gray-900"), margin: `var(--ds-space-1) 0 var(--ds-space-3)` }}>{el.args[1]}</div>}
          <div style={{
            display: "grid", gap: v("space-2"), height: 220,
            gridTemplateColumns: "1fr 1fr 1fr 1fr",
            gridTemplateRows: "1fr 1fr 1fr",
            gridTemplateAreas: '"a a b b" "a a c d" "e e f d"',
          }}>
            {items.slice(0, 6).map((it: any, i: number) => (
              <button key={it.tag} onClick={() => tagTap.fn?.(it.tag)} className="pressable" style={{
                gridArea: areas[i], border: "none", cursor: "pointer", textAlign: "left",
                background: `color-mix(in srgb, var(--ds-tint) ${Math.round(6 + 22 * (it.n / max))}%, transparent)`, borderRadius: v("radius-card"),
                padding: v("space-3"), display: "flex", flexDirection: "column",
                color: v("gray-1000"), fontFamily: "inherit", minWidth: 0, overflow: "hidden",
              }}>
                <span className="t-label-14">{it.tag}</span>
              </button>
            ))}
          </div>
        </div>
      );
    }
    case "StatTile":
      return (
        <div className="mount" style={{
          gridColumn: el.args[0] === "2" ? "span 2" : "span 1",
          background: v("surface-sheet"), borderRadius: 20,
          padding: v("space-4"), display: "flex", flexDirection: "column", gap: v("space-1"),
          minHeight: 96,
        }}>
          <div className="t-heading-24">{el.args[1] ?? ""}</div>
          <div style={{ marginTop: "auto", minWidth: 0 }}>
            <div className="t-label-14">{el.args[2] ?? ""}</div>
            <div className="t-copy-13" style={{ color: v("gray-900"), overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{el.args[3] ?? ""}</div>
          </div>
        </div>
      );
    case "PhotoTile":
      return (
        <div className="mount" style={{
          gridColumn: el.args[0] === "2" ? "span 2" : "span 1",
          background: v("surface-sheet"), borderRadius: 20,
          padding: v("space-4"), display: "flex", flexDirection: "column", gap: v("space-3"),
        }}>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: v("space-2") }}>
            {[0, 1, 2, 3].map((i) => (
              <div key={i} style={{
                aspectRatio: "1", borderRadius: v("radius-control"),
                background: `linear-gradient(135deg, ${["#3a3a3c", "#48484a", "#2c2c2e", "#414144"][i]}, #1c1c1e)`,
              }} />
            ))}
          </div>
          <div>
            <div className="t-heading-16">{el.args[1] ?? ""}</div>
            <div className="t-copy-13" style={{ color: v("gray-900") }}>{el.args[2] ?? ""}</div>
          </div>
        </div>
      );
    case "VoiceTile":
      return (
        <div className="mount" style={{
          gridColumn: el.args[0] === "2" ? "span 2" : "span 1",
          background: v("surface-sheet"), borderRadius: 20,
          padding: v("space-4"), display: "flex", flexDirection: "column", gap: v("space-3"),
          minHeight: 96,
        }}>
          <div style={{ display: "flex", alignItems: "center", gap: 2, height: 24 }}>
            {[8, 14, 20, 12, 18, 8, 16, 22, 10, 14, 6, 12].map((h, i) => (
              <span key={i} style={{ width: 3, height: h, borderRadius: v("radius-pill"), background: v("tint") }} />
            ))}
          </div>
          <div style={{ marginTop: "auto" }}>
            <div className="t-heading-16">{el.args[1] ?? ""}</div>
            <div className="t-copy-13" style={{ color: v("gray-900") }}>{el.args[2] ?? ""}</div>
          </div>
        </div>
      );
    case "Skeleton":
      return <SkeletonRow />;
    default:
      return null;
  }
}

function AnswerStream({ q }: { q: string }) {
  const { els } = useLangStream(ANSWER_DOC, [q]);
  return <RenderEl id="root" els={els} />;
}

function HomeScreen({ empty, pendingConnect, onConsumed, connected }: {
  empty: boolean; pendingConnect: string | null; onConsumed: () => void; connected: string[];
}) {
  const [connectName, setConnectName] = useState<string | null>(null);
  useEffect(() => {
    if (pendingConnect) { setConnectName(pendingConnect); onConsumed(); }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pendingConnect]);

  const hour = new Date().getHours();
  const doc = empty ? DOCS.empty
    : connectName ? docConnect(connectName)
    : filterDoc(hour < 15 ? DOCS.morning : DOCS.evening, connected);
  const { els } = useLangStream(doc, [empty, connectName, connected.join(",")]);

  return (
    <div>
      <div style={{ padding: `var(--ds-space-6) var(--ds-space-4) 0` }}>
        <h1 className="t-heading-24" style={{ margin: 0 }}>Home</h1>
      </div>
      <RenderEl id="root" els={els} />
    </div>
  );
}

/* ---------- Feed: the record. Filters live here. Marks ride swipe. ---------- */
type FeedItem = {
  id: string; title: string; tag: string; source: string; time: string;
  day: string; verb: string; kind?: "approval";
};

const feedData: FeedItem[] = [
  { id: "fd1", title: "Trip plan: Lisbon", tag: "Session", source: "ChatGPT", time: "1h", day: "Today", verb: "saved from a session" },
  { id: "fd2", title: "Flight confirmation — TAP 1147", tag: "File", source: "Gmail", time: "2h", day: "Today", verb: "found in mail" },
  { id: "fd3", title: "File 3 receipts", tag: "Approval", source: "Gmail", time: "2h", day: "Today", verb: "wants to run", kind: "approval" },
  { id: "fd4", title: "Dinner with Sam", tag: "Event", source: "Calendar", time: "5h", day: "Today", verb: "added to calendar" },
  { id: "fd5", title: "4 screenshots", tag: "Photos", source: "Photos", time: "1d", day: "Yesterday", verb: "imported" },
  { id: "fd6", title: "Design thread by @rauno", tag: "Bookmark", source: "X", time: "1d", day: "Yesterday", verb: "saved" },
  { id: "fd7", title: "Voice note", tag: "Voice", source: "You", time: "1d", day: "Yesterday", verb: "captured · 0:42" },
];

const sourceFilters = ["All", "Gmail", "ChatGPT", "Calendar", "Photos", "X", "You"];
const tagFilters = ["All", "File", "Mail", "Session", "Event", "Photo", "Bookmark", "Voice"];

function FeedSwipe({ item, openId, setOpenId, onMark, unread, pinned, onPin, onOpen }: {
  item: FeedItem; openId: string | null; setOpenId: (id: string | null) => void;
  onMark: (item: FeedItem, mark: string) => void; unread?: boolean;
  pinned?: boolean; onPin?: (item: FeedItem) => void; onOpen?: (item: FeedItem) => void;
}) {
  const isOpen = openId === item.id;
  const actionsW = 176;
  const startX = useRef(0);
  const [drag, setDrag] = useState(0);
  const dx = isOpen ? -actionsW + drag : Math.min(0, drag);

  const down = (e: React.PointerEvent) => {
    startX.current = e.clientX;
    (e.currentTarget as HTMLElement).setPointerCapture?.(e.pointerId);
  };
  const move = (e: React.PointerEvent) => {
    if (e.buttons !== 1) return;
    setDrag(e.clientX - startX.current);
  };
  const up = () => {
    if (Math.abs(drag) < 6) {
      setDrag(0);
      if (isOpen) { setOpenId(null); return; }
      onOpen?.(item);
      return;
    }
    const settled = dx < -actionsW / 2;
    setOpenId(settled ? item.id : null);
    setDrag(0);
  };

  return (
    <div style={{ position: "relative", overflow: "hidden" }}>
      <div style={{ position: "absolute", top: 0, right: 0, bottom: 0, display: "flex" }}>
        <button onClick={() => { setOpenId(null); onMark(item, "To do"); }} className="t-label-12" style={{
          width: 88, border: "none", background: v("tint"), color: "#fff", cursor: "pointer", fontFamily: "inherit",
        }}>To do</button>
        <button onClick={() => { setOpenId(null); onMark(item, "Doing"); }} className="t-label-12" style={{
          width: 88, border: "none", background: v("green-700"), color: "#fff", cursor: "pointer", fontFamily: "inherit",
        }}>Doing</button>
      </div>
      <div
        onPointerDown={down} onPointerMove={move} onPointerUp={up} onPointerCancel={up}
        style={{
          transform: `translateX(${Math.max(-actionsW, Math.min(0, dx))}px)`,
          transition: drag === 0 ? `transform var(--ds-duration) var(--ds-ease)` : "none",
          background: v("surface-sheet"), touchAction: "pan-y", userSelect: "none",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: v("space-3"), padding: `var(--ds-space-3) var(--ds-space-4)` }}>
          {unread !== undefined && (
            <span style={{ width: 8, height: 8, borderRadius: v("radius-pill"), background: unread ? v("tint") : "transparent", flexShrink: 0 }} />
          )}
          <AppIcon name={item.source} size={32} />
          <span style={{ flex: 1, minWidth: 0 }}>
            <span className="t-label-14" style={{ display: "block", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", color: unread === false ? v("gray-900") : v("gray-1000") }}>{item.title}</span>
          </span>
          <Tag label={item.tag} />
          {onPin && (
            <button onClick={(e) => { e.stopPropagation(); onPin(item); }} aria-label="Pin" style={{
              background: "none", border: "none", cursor: "pointer", padding: v("space-1"),
              color: pinned ? v("tint") : v("gray-600"), display: "flex", flexShrink: 0,
            }}>
              <Pin size={16} fill={pinned ? "currentColor" : "none"} />
            </button>
          )}
          <span className="t-copy-13" style={{ color: v("gray-700"), flexShrink: 0 }}>{item.time}</span>
        </div>
        {item.kind === "approval" && (
          <div style={{ display: "flex", gap: v("space-2"), padding: `0 var(--ds-space-4) var(--ds-space-3) 60px` }}>
            <button className="t-label-14" style={{
              background: v("tint"), color: "#fff", border: "none",
              borderRadius: v("radius-control"), padding: `var(--ds-space-1) var(--ds-space-3)`, height: 32,
              cursor: "pointer", fontFamily: "inherit",
            }}>Approve</button>
            <button className="t-label-14" style={{
              background: v("gray-100"), color: v("gray-1000"), border: "none",
              borderRadius: v("radius-control"), padding: `var(--ds-space-1) var(--ds-space-3)`, height: 32,
              cursor: "pointer", fontFamily: "inherit",
            }}>Review</button>
          </div>
        )}
      </div>
    </div>
  );
}

type Burst = {
  id: string; source: string; verb: string; time: string; day: string;
  items: { title: string; tag: string; time: string }[];
  kind?: "approval";
};

const bursts: Burst[] = [
  { id: "b1", source: "Gmail", verb: "brought 3 things", time: "2h", day: "Today", items: [
    { title: "Flight confirmation — TAP 1147", tag: "File", time: "2h" },
    { title: "Re: July invoice", tag: "Mail", time: "2h" },
    { title: "Your table for Friday", tag: "Mail", time: "3h" },
  ]},
  { id: "b3", source: "ChatGPT", verb: "saved 1 session", time: "1h", day: "Today", items: [
    { title: "Trip plan: Lisbon", tag: "Session", time: "1h" },
  ]},
  { id: "b4", source: "Calendar", verb: "added 1 event", time: "5h", day: "Today", items: [
    { title: "Dinner with Sam", tag: "Event", time: "5h" },
  ]},
  { id: "b5", source: "Photos", verb: "imported 4 screenshots", time: "1d", day: "Yesterday", items: [
    { title: "Screenshot · hotel option", tag: "Photo", time: "1d" },
    { title: "Screenshot · hotel option", tag: "Photo", time: "1d" },
  ]},
  { id: "b6", source: "X", verb: "saved 1 thread", time: "1d", day: "Yesterday", items: [
    { title: "Design thread by @rauno", tag: "Bookmark", time: "1d" },
  ]},
  { id: "b7", source: "You", verb: "captured a voice note", time: "1d", day: "Yesterday", items: [
    { title: "Voice note · 0:42", tag: "Voice", time: "1d" },
  ]},
];

const VERB_BY_TAG: Record<string, string> = {
  Mail: "in your inbox",
  File: "in your inbox",
  Session: "from your session",
  Event: "on your calendar",
  Photo: "in your photos",
  Bookmark: "saved by you",
  Voice: "recorded by you",
};

const flatItems = bursts.flatMap((b) =>
  b.kind === "approval"
    ? [{ id: b.id, title: "File 3 receipts", tag: "Approval", source: b.source, time: b.time, day: b.day, verb: b.verb, kind: "approval" as const }]
    : b.items.map((it, i) => ({ id: b.id + i, title: it.title, tag: it.tag, source: b.source, time: it.time, day: b.day, verb: VERB_BY_TAG[it.tag] ?? b.verb }))
);

function ApprovalCard({ compact }: { compact?: boolean }) {
  return (
    <div className="mount" style={{
      background: v("tint-dim"), borderRadius: 20,
      margin: compact ? `var(--ds-space-2) var(--ds-space-4)` : `var(--ds-space-3) var(--ds-space-4)`,
      padding: v("space-4"),
    }}>
      <div style={{ display: "flex", alignItems: "center", gap: v("space-3") }}>
        <AppIcon name="Gmail" size={32} />
        <span style={{ flex: 1 }}>
          <span className="t-label-14" style={{ display: "block" }}>File 3 receipts</span>
          <span className="t-copy-13" style={{ color: v("gray-900") }}>Gmail · needs your OK</span>
        </span>
      </div>
      <div style={{ display: "flex", gap: v("space-2"), marginTop: v("space-3") }}>
        <button className="t-label-14" style={{
          background: v("tint"), color: "#fff", border: "none", flex: 1,
          borderRadius: v("radius-control"), height: 36, cursor: "pointer", fontFamily: "inherit",
        }}>Approve</button>
        <button className="t-label-14" style={{
          background: v("gray-100"), color: v("gray-1000"), border: "none", flex: 1,
          borderRadius: v("radius-control"), height: 36, cursor: "pointer", fontFamily: "inherit",
        }}>Review</button>
      </div>
    </div>
  );
}


/* ---------- thing detail: the thing, then its verbs ---------- */
const TYPE_VERB: Record<string, string> = {
  Event: "Get directions",
  Reminder: "Mark done",
  Mail: "Reply",
  Session: "Continue session",
  File: "Share",
  Photo: "View",
  Bookmark: "Open link",
  Voice: "Play",
  Task: "Mark done",
};

function ThingSheet({ item, tags, allTags, onAdd, onRemove, onClose, onAction }: {
  item: FeedItem; tags: string[]; allTags: string[];
  onAdd: (t: string) => void; onRemove: (t: string) => void; onClose: () => void;
  onAction: (label: string) => void;
}) {
  const [draft, setDraft] = useState("");
  const add = (t: string) => { const c = t.trim(); if (c) onAdd(c); setDraft(""); };
  const verb = TYPE_VERB[item.tag];

  const actionRow = (label: string, icon: React.ReactNode) => (
    <button key={label} onClick={() => onAction(label)} className="pressable" style={{
      display: "flex", alignItems: "center", gap: v("space-3"), width: "100%",
      padding: `var(--ds-space-3) var(--ds-space-4)`,
      background: "transparent", border: "none", cursor: "pointer", textAlign: "left",
      color: v("gray-1000"), fontFamily: "inherit",
    }}>
      {icon}
      <span className="t-label-14" style={{ flex: 1 }}>{label}</span>
      <ArrowUpRight size={16} color={v("gray-600")} />
    </button>
  );

  return (
    <>
      <div onClick={onClose} style={{ position: "absolute", inset: 0, background: "var(--ds-scrim)", zIndex: 40 }} />
      <div style={{
        position: "absolute", left: 0, right: 0, bottom: 0, zIndex: 41, maxHeight: "80%",
        overflowY: "auto",
        background: v("surface-sheet"),
        borderTopLeftRadius: v("radius-sheet"), borderTopRightRadius: v("radius-sheet"),
        boxShadow: v("shadow-overlay"), padding: `var(--ds-space-2) 0 var(--ds-space-6)`,
        animation: "sheetUp var(--ds-duration) var(--ds-ease)",
      }}>
        <div style={{ width: 36, height: 5, borderRadius: v("radius-pill"), background: v("gray-300"), margin: "0 auto" }} />

        <div style={{ display: "flex", alignItems: "center", gap: v("space-3"), padding: `var(--ds-space-4)` }}>
          <AppIcon name={item.source} size={40} />
          <span style={{ flex: 1, minWidth: 0 }}>
            <span className="t-heading-16" style={{ display: "block" }}>{item.title}</span>
            <span className="t-copy-13" style={{ color: v("gray-900") }}>{item.verb} · {item.time}</span>
          </span>
        </div>

        {/* verbs: open app, open shortcut, type verb */}
        <div style={{
          background: v("gray-alpha-100"), borderRadius: v("radius-card"),
          margin: `0 var(--ds-space-4) var(--ds-space-3)`, overflow: "hidden",
        }}>
          {actionRow(`Open in ${item.source}`, <AppIcon name={item.source} size={28} />)}
          {actionRow("Open shortcut", <span style={{
            width: 28, height: 28, borderRadius: Math.round(28 * 0.2237),
            background: v("tint-dim"), display: "flex", alignItems: "center", justifyContent: "center",
            color: v("tint"), flexShrink: 0,
          }}><Zap size={14} /></span>)}
          {verb && actionRow(verb, <span style={{
            width: 28, height: 28, borderRadius: Math.round(28 * 0.2237),
            background: v("gray-100"), display: "flex", alignItems: "center", justifyContent: "center",
            color: v("gray-900"), flexShrink: 0,
          }}><ArrowUpRight size={14} /></span>)}
        </div>

        <div style={{ padding: `0 var(--ds-space-4)` }}>
          <div className="t-label-12" style={{ color: v("gray-700"), textTransform: "uppercase", letterSpacing: "0.06em", marginBottom: v("space-2") }}>Tags</div>
          <div style={{ display: "flex", flexWrap: "wrap", gap: v("space-2"), marginBottom: v("space-3") }}>
            {tags.map((t) => (
              <button key={t} onClick={() => onRemove(t)} className="t-label-12" style={{
                background: v("tint-dim"), color: v("tint"), border: "none",
                borderRadius: v("radius-pill"), padding: `var(--ds-space-1) var(--ds-space-3)`, height: 28,
                cursor: "pointer", fontFamily: "inherit",
              }}>{t}</button>
            ))}
            {[...allTags, "Lisbon trip", "Mobile app", "Home gym", "Design reading"]
              .filter((t, i, a) => a.indexOf(t) === i && !tags.includes(t))
              .map((t) => (
              <button key={t} onClick={() => onAdd(t)} className="t-label-12" style={{
                background: v("gray-100"), color: v("gray-900"), border: "none",
                borderRadius: v("radius-pill"), padding: `var(--ds-space-1) var(--ds-space-3)`, height: 28,
                cursor: "pointer", fontFamily: "inherit",
              }}>{t}</button>
            ))}
          </div>
          <div style={{
            display: "flex", alignItems: "center", gap: v("space-2"),
            background: v("gray-100"), borderRadius: v("radius-pill"),
            padding: `0 var(--ds-space-2) 0 var(--ds-space-4)`, height: 40,
          }}>
            <input
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && add(draft)}
              placeholder="Add a tag"
              className="t-copy-14"
              style={{ flex: 1, border: "none", outline: "none", background: "transparent", color: v("gray-1000"), fontFamily: "inherit", minWidth: 0 }}
            />
            <button onClick={() => add(draft)} disabled={!draft.trim()} className="t-label-12" style={{
              background: draft.trim() ? v("tint") : v("gray-200"),
              color: draft.trim() ? "#fff" : v("gray-700"),
              border: "none", borderRadius: v("radius-pill"), height: 28, padding: `0 var(--ds-space-3)`,
              cursor: draft.trim() ? "pointer" : "not-allowed", fontFamily: "inherit",
            }}>Add</button>
          </div>
        </div>
      </div>
      <style>{`@keyframes sheetUp { from { transform: translateY(24px); opacity: 0 } to { transform: translateY(0); opacity: 1 } }`}</style>
    </>
  );
}

function FeedTagMap({ counts, onTag }: { counts: [string, number][]; onTag: (t: string) => void }) {
  if (counts.length < 3) return null;
  const max = Math.max(1, ...counts.map(([, n]) => n));
  const areas = ["a", "b", "c", "d", "e", "f"];
  return (
    <div style={{ padding: `var(--ds-space-2) var(--ds-space-4) 0` }}>
      <div style={{
        display: "grid", gap: v("space-2"), height: 140,
        gridTemplateColumns: "1fr 1fr 1fr 1fr",
        gridTemplateRows: "1fr 1fr",
        gridTemplateAreas: '"a a b c" "a a d e"',
      }}>
        {counts.slice(0, 5).map(([tag, n], i) => (
          <button key={tag} onClick={() => onTag(tag)} className="pressable" style={{
            gridArea: areas[i], border: "none", cursor: "pointer", textAlign: "left",
            background: `color-mix(in srgb, var(--ds-tint) ${Math.round(6 + 22 * (n / max))}%, transparent)`,
            borderRadius: v("radius-card"),
            padding: v("space-3"), display: "flex", flexDirection: "column",
            color: v("gray-1000"), fontFamily: "inherit", minWidth: 0, overflow: "hidden",
          }}>
            <span className="t-label-14">{tag}</span>
          </button>
        ))}
      </div>
    </div>
  );
}

function FeedScreen({ onToast, connected, seedTag, onSeedUsed, onBack }: {
  onToast: (s: string) => void; connected: string[];
  seedTag?: string | null; onSeedUsed?: () => void; onBack?: () => void;
}) {
  const [source, setSource] = useState("All");
  const [tag, setTag] = useState("All");
  useEffect(() => {
    if (seedTag) { setTag(seedTag); onSeedUsed?.(); }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [seedTag]);
  const [openId, setOpenId] = useState<string | null>(null);
  const [pinned, setPinned] = useState<string[]>([]);
  const [sheetItem, setSheetItem] = useState<FeedItem | null>(null);
  const [tagsById, setTagsById] = useState<Record<string, string[]>>(
    Object.fromEntries(flatItems.map((i) => [i.id, [i.tag]])));

  const customTags = [...new Set(Object.values(tagsById).flat())].filter((t) => !tagFilters.includes(t));
  const allTagChips = [...tagFilters, ...customTags];

  const live = (i: any) => connected.includes(i.source) || i.source === "You";
  const match = (i: any) =>
    live(i) && (source === "All" || i.source === source) && (tag === "All" || (tagsById[i.id] ?? [i.tag]).includes(tag));
  const items = flatItems.filter(match);
  const days = [...new Set(items.map((i) => i.day))];
  const pinnedItems = flatItems.filter((i) => pinned.includes(i.id));
  const filtered = source !== "All" || tag !== "All";
  const filterLabel = [source !== "All" ? source : null, tag !== "All" ? tag : null].filter(Boolean).join(" · ");

  const mark = (it: any, m: string) => onToast(`${m}: ${it.title}`);
  const togglePin = (it: any) => {
    const on = pinned.includes(it.id);
    setPinned(on ? pinned.filter((p) => p !== it.id) : [...pinned, it.id]);
    onToast(on ? `Unpinned: ${it.title}` : `Pinned: ${it.title}`);
  };

  const chip = (label: string, active: boolean, onTap: () => void, icon?: boolean) => (
    <button key={label} onClick={onTap} className="t-label-12" style={{
      display: "flex", alignItems: "center", gap: v("space-1"),
      border: "none", borderRadius: v("radius-pill"),
      background: active ? v("gray-1000") : v("gray-100"),
      color: active ? v("background-200") : v("gray-900"),
      padding: `var(--ds-space-1) var(--ds-space-3)`, height: 28, flexShrink: 0,
      cursor: "pointer", fontFamily: "inherit",
    }}>
      {icon && label !== "All" && <AppIcon name={label} size={16} />}
      {label}
    </button>
  );

  const groupCard = (label: string, count: number, rows: React.ReactNode) => (
    <div key={label} style={{
      background: v("surface-sheet"), borderRadius: 20,
      margin: `var(--ds-space-3) var(--ds-space-4) 0`, overflow: "hidden",
      paddingBottom: v("space-2"),
    }}>
      <div style={{ display: "flex", alignItems: "baseline", gap: v("space-2"), padding: `var(--ds-space-4) var(--ds-space-4) var(--ds-space-1)` }}>
        <span className="t-heading-16">{label}</span>
        <span className="t-copy-13" style={{ color: v("gray-700") }}>{count}</span>
      </div>
      {rows}
    </div>
  );

  const rowsOf = (list: any[], keyPrefix = "") => list.map((i) => (
    <FeedSwipe key={keyPrefix + i.id} item={i} openId={openId} setOpenId={setOpenId}
      onMark={mark} pinned={pinned.includes(i.id)} onPin={togglePin} onOpen={setSheetItem} />
  ));

  return (
    <div>
      <div style={{ padding: `var(--ds-space-6) var(--ds-space-4) var(--ds-space-2)` }}>
        {onBack && (
          <button onClick={onBack} aria-label="Back" style={{
            background: "none", border: "none", cursor: "pointer", padding: 0,
            color: v("gray-900"), display: "flex", alignItems: "center", gap: v("space-1"),
            fontFamily: "inherit", marginBottom: v("space-2"),
          }}><ChevronLeft size={18} /><span className="t-copy-13">Home</span></button>
        )}
        <h1 className="t-heading-24" style={{ margin: 0 }}>Feed</h1>
      </div>
      <div style={{ display: "flex", gap: v("space-2"), overflowX: "auto", padding: `0 var(--ds-space-4)` }}>
        {["All", ...connected.filter((c) => flatItems.some((i) => i.source === c)).sort(), "You"].map((f) => chip(f, source === f, () => setSource(f), true))}
      </div>
      <div style={{ display: "flex", gap: v("space-2"), overflowX: "auto", padding: `var(--ds-space-2) var(--ds-space-4)` }}>
        {["All", ...allTagChips.filter((t) => t !== "All").sort()].map((f) => chip(f, tag === f, () => setTag(f)))}
      </div>

      {!filtered && (
        <div style={{ margin: `0 0 var(--ds-space-1)` }}>
          <FeedTagMap counts={
            Object.entries(items.reduce((m: Record<string, number>, i: any) => {
              const t = (tagsById[i.id] ?? [i.tag])[0];
              m[t] = (m[t] ?? 0) + 1; return m;
            }, {})).sort((a, b) => b[1] - a[1]).slice(0, 6)
          } onTag={(t) => setTag(t)} />
        </div>
      )}
      {pinnedItems.length > 0 && groupCard("Pinned", pinnedItems.length, rowsOf(pinnedItems, "pin-"))}

      {items.length === 0 && pinnedItems.length === 0 && (
        <p className="t-copy-14" style={{ color: v("gray-700"), padding: `var(--ds-space-4) var(--ds-space-6)` }}>
          Connect apps to fill your feed.
        </p>
      )}
      {filtered
        ? groupCard(filterLabel, items.length, rowsOf(items))
        : days.map((d) => groupCard(d, items.filter((i) => i.day === d).length, rowsOf(items.filter((i) => i.day === d))))}

      {sheetItem && (
        <ThingSheet
          item={sheetItem}
          tags={tagsById[sheetItem.id] ?? [sheetItem.tag]}
          allTags={allTagChips.filter((t) => t !== "All")}
          onAdd={(t) => setTagsById({ ...tagsById, [sheetItem.id]: [...new Set([...(tagsById[sheetItem.id] ?? [sheetItem.tag]), t])] })}
          onRemove={(t) => setTagsById({ ...tagsById, [sheetItem.id]: (tagsById[sheetItem.id] ?? [sheetItem.tag]).filter((x) => x !== t) })}
          onClose={() => setSheetItem(null)}
          onAction={(a) => onToast(a)}
        />
      )}
    </div>
  );
}



/* ---------- theme ---------- */
const TINTS: { name: string; hex: string; dim: string }[] = [
  { name: "Blue", hex: "#0a84ff", dim: "rgba(10,132,255,0.16)" },
  { name: "Purple", hex: "#bf5af2", dim: "rgba(191,90,242,0.16)" },
  { name: "Pink", hex: "#ff375f", dim: "rgba(255,55,95,0.16)" },
  { name: "Green", hex: "#30d158", dim: "rgba(48,209,88,0.16)" },
  { name: "Orange", hex: "#ff9f0a", dim: "rgba(255,159,10,0.16)" },
];

function applyBgImage(dataUrl: string | null) {
  const root = document.documentElement;
  if (dataUrl) root.style.setProperty("--ds-bg-image", `linear-gradient(rgba(0,0,0,0.5), rgba(0,0,0,0.72)), url(${dataUrl})`);
  else root.style.removeProperty("--ds-bg-image");
}

function applyTheme(mode: "dark" | "light", tint: typeof TINTS[number]) {
  const root = document.documentElement;
  root.setAttribute("data-theme", mode);
  root.style.setProperty("--ds-tint", tint.hex);
  root.style.setProperty("--ds-tint-dim", tint.dim);
  root.style.setProperty("--ds-blue-700", tint.hex);
  root.style.setProperty("--ds-blue-900", tint.hex);
}

function ThemeSheet({ mode, tint, onMode, onTint, onClose, hasPhoto, onPhoto }: {
  mode: "dark" | "light"; tint: number;
  onMode: (m: "dark" | "light") => void; onTint: (i: number) => void; onClose: () => void;
  hasPhoto: boolean; onPhoto: (b: boolean) => void;
}) {
  return (
    <>
      <div onClick={onClose} style={{ position: "absolute", inset: 0, background: "var(--ds-scrim)", zIndex: 40 }} />
      <div style={{
        position: "absolute", left: 0, right: 0, bottom: 0, zIndex: 41,
        background: v("surface-sheet"),
        borderTopLeftRadius: v("radius-sheet"), borderTopRightRadius: v("radius-sheet"),
        boxShadow: v("shadow-overlay"), padding: `var(--ds-space-2) var(--ds-space-4) var(--ds-space-6)`,
        animation: "sheetUp var(--ds-duration) var(--ds-ease)",
      }}>
        <div style={{ width: 36, height: 5, borderRadius: v("radius-pill"), background: v("gray-300"), margin: "0 auto" }} />
        <div className="t-heading-16" style={{ padding: `var(--ds-space-4) 0 var(--ds-space-2)` }}>Theme</div>

        <div className="t-label-12" style={{ color: v("gray-700"), textTransform: "uppercase", letterSpacing: "0.06em", marginBottom: v("space-2") }}>Color</div>
        <div style={{ display: "flex", gap: v("space-3"), marginBottom: v("space-4") }}>
          {TINTS.map((t, i) => (
            <button key={t.name} onClick={() => onTint(i)} aria-label={t.name} style={{
              width: 40, height: 40, borderRadius: v("radius-pill"),
              background: t.hex, border: "none", cursor: "pointer",
              boxShadow: tint === i ? `0 0 0 2px var(--ds-background-100), 0 0 0 4px ${t.hex}` : "none",
            }} />
          ))}
        </div>

        <div className="t-label-12" style={{ color: v("gray-700"), textTransform: "uppercase", letterSpacing: "0.06em", marginBottom: v("space-2") }}>Background</div>
        <div style={{
          display: "flex", gap: v("space-1"), background: v("gray-100"),
          borderRadius: v("radius-pill"), padding: v("space-1"), marginBottom: v("space-3"),
        }}>
          {(["dark", "light"] as const).map((m) => (
            <button key={m} onClick={() => onMode(m)} className="t-label-12" style={{
              flex: 1, height: 28, border: "none", borderRadius: v("radius-pill"),
              background: mode === m ? v("gray-300") : "transparent",
              color: mode === m ? v("gray-1000") : v("gray-900"),
              cursor: "pointer", fontFamily: "inherit", textTransform: "capitalize",
            }}>{m}</button>
          ))}
        </div>
        <div style={{ display: "flex", gap: v("space-2"), marginBottom: v("space-3") }}>
          <label className="t-label-12" style={{
            background: v("gray-100"), color: v("gray-1000"),
            borderRadius: v("radius-pill"), padding: `var(--ds-space-1) var(--ds-space-3)`, height: 28,
            display: "inline-flex", alignItems: "center", cursor: "pointer",
          }}>
            Add photo
            <input type="file" accept="image/*" style={{ display: "none" }}
              onChange={(e) => {
                const f = e.target.files?.[0];
                if (!f) return;
                const r = new FileReader();
                r.onload = () => { applyBgImage(String(r.result)); onPhoto(true); };
                r.readAsDataURL(f);
              }} />
          </label>
          {hasPhoto && (
            <button onClick={() => { applyBgImage(null); onPhoto(false); }} className="t-label-12" style={{
              background: v("gray-100"), color: v("red-900"), border: "none",
              borderRadius: v("radius-pill"), padding: `var(--ds-space-1) var(--ds-space-3)`, height: 28,
              cursor: "pointer", fontFamily: "inherit",
            }}>Remove photo</button>
          )}
        </div>
        <div className="t-copy-13" style={{ color: v("gray-700") }}>Cards follow the background.</div>
      </div>
      <style>{`@keyframes sheetUp { from { transform: translateY(24px); opacity: 0 } to { transform: translateY(0); opacity: 1 } }`}</style>
    </>
  );
}


/* ---------- project detail ---------- */
const tagTap: { fn: ((tag: string) => void) | null } = { fn: null };
const parseAction: { fn: ((label: string) => void) | null } = { fn: null };

const projectTap: { fn: ((name: string, sub: string, count: string, wash: string) => void) | null } = { fn: null };

const PROJECT_DOCS: Record<string, string[]> = {
  "Lisbon trip": [
    'root = Stack([ins, booked, deciding, trail])',
    'ins = Insight("Hotel needs a pick. 2 screenshots hold options.")',
    'booked = Widget("Booked", null, [b1, b2])',
    'b1 = Row("Flight TAP 1147", "Event", "Calendar", "Jul 12")',
    'b2 = Row("TAP-1147-confirmation.pdf", "File", "Gmail", "2h")',
    'deciding = Widget("Deciding", null, [d1, d2, d3])',
    'd1 = Row("Screenshot · hotel option", "Photo", "Photos", "1d")',
    'd2 = Row("Screenshot · hotel option", "Photo", "Photos", "1d")',
    'd3 = Row("Trip plan: Lisbon", "Session", "ChatGPT", "1h")',
    'trail = Widget("Trail", null, [t1, t2])',
    't1 = Row("Flight confirmation arrived", "Mail", "Gmail", "2h")',
    't2 = Row("Session saved", "Session", "ChatGPT", "1h")',
  ],
  "Mobile app": [
    'root = Stack([ins, work, trail])',
    'ins = Insight("4 sessions this week. The tab bar landed.")',
    'work = Widget("Work", null, [w1, w2, w3])',
    'w1 = Row("Tab bar options", "Session", "ChatGPT", "1d")',
    'w2 = Row("Design principles", "Note", "Notes", "2d")',
    'w3 = Row("Home screen synthesis", "Session", "ChatGPT", "3d")',
    'trail = Widget("Trail", null, [t1])',
    't1 = Row("2 notes edited", "Note", "Notes", "2d")',
  ],
  "Home gym": [
    'root = Stack([ins, saved])',
    'ins = Insight("Plan saved. Nothing started.")',
    'saved = Widget("Saved", null, [s1, s2])',
    's1 = Row("Workout plan", "Session", "ChatGPT", "3d")',
    's2 = Row("Screenshot · rack option", "Photo", "Photos", "1w")',
  ],
  "Design reading": [
    'root = Stack([ins, list])',
    'ins = Insight("5 threads saved. 2 papers wait.")',
    'list = Widget("Saved", null, [l1, l2, l3])',
    'l1 = Row("Design thread by @rauno", "Bookmark", "X", "1d")',
    'l2 = Row("Interfaces paper.pdf", "File", "You", "1w")',
    'l3 = Row("Type scale thread", "Bookmark", "X", "2w")',
  ],
};

function ProjectScreen({ name, sub, count, wash, onBack }: {
  name: string; sub: string; count: string; wash: string; onBack: () => void;
}) {
  const doc = PROJECT_DOCS[name] ?? ['root = Stack([ins])', 'ins = Insight("Nothing here yet.")'];
  const { els } = useLangStream(doc, [name]);
  return (
    <div>
      <div className="mount" style={{
        background: v("surface-sheet"),
        borderRadius: 20, margin: `var(--ds-space-4)`, padding: v("space-4"),
      }}>
        <button onClick={onBack} aria-label="Back" style={{
          background: "none", border: "none", cursor: "pointer", padding: 0,
          color: v("gray-900"), display: "flex", alignItems: "center", gap: v("space-1"),
          fontFamily: "inherit", marginBottom: v("space-3"),
        }}><ChevronLeft size={18} /><span className="t-copy-13">Home</span></button>
        <div className="t-heading-24">{name}</div>
        <div className="t-copy-14" style={{ color: v("gray-900"), marginTop: v("space-1") }}>{sub}</div>
        <div className="t-copy-13" style={{ color: v("gray-700"), marginTop: v("space-1") }}>{count}</div>
      </div>
      <RenderEl id="root" els={els} />
    </div>
  );
}

/* ---------- Account ---------- */
function AccountScreen() {
  const [conn, setConn] = useState<"wifi" | "cell" | "off">("wifi");
  const [themeOpen, setThemeOpen] = useState(false);
  const [mode, setMode] = useState<"dark" | "light">("dark");
  const [tintIdx, setTintIdx] = useState(0);
  const [hasPhoto, setHasPhoto] = useState(false);
  const rows: { label: string; sub: string; Icon: any; ring?: string; onTap?: () => void }[] = [
        { label: "Avatar", sub: "Add your name and photo", Icon: CircleUser },
    { label: "Balance", sub: "$0.00", Icon: Wallet },
    { label: "Connection",
      sub: conn === "wifi" ? "Online · Wi-Fi · synced just now"
        : conn === "cell" ? "Online · Cellular · synced just now"
        : "Offline · everything still works",
      Icon: conn === "wifi" ? Wifi : conn === "cell" ? Signal : WifiOff,
      ring: conn === "off" ? v("gray-500") : v("green-700"),
      onTap: () => setConn(conn === "wifi" ? "cell" : conn === "cell" ? "off" : "wifi") },
    { label: "Data", sub: "On device · iCloud sync on", Icon: Smartphone },
    { label: "Theme", sub: `${mode === "dark" ? "Dark" : "Light"} · ${TINTS[tintIdx].name}${hasPhoto ? " · Photo" : ""}`, Icon: Moon, onTap: () => setThemeOpen(true) },
    { label: "Privacy", sub: "End-to-end encrypted", Icon: Lock },
    { label: "Subscription", sub: "Free plan", Icon: CreditCard },
    { label: "Support", sub: "Get help", Icon: LifeBuoy },
    { label: "Updates", sub: "Version 0.1", Icon: Info },
    { label: "Usage", sub: "23 things this week · most from ChatGPT", Icon: BarChart3 },
  ];
  return (
    <div>
      <div style={{ padding: `var(--ds-space-6) var(--ds-space-4) var(--ds-space-4)` }}>
        <h1 className="t-heading-24" style={{ margin: 0 }}>Account</h1>
      </div>
      <div style={{ padding: `var(--ds-space-2) 0` }}>
        {rows.map((r) => (
          <button key={r.label} onClick={r.onTap} className="pressable" style={{
            display: "flex", alignItems: "center", gap: v("space-4"), width: "100%",
            padding: `var(--ds-space-3) var(--ds-space-4)`,
            background: "transparent", border: "none", cursor: "pointer", textAlign: "left",
            color: v("gray-1000"), fontFamily: "inherit",
          }}>
            <span style={{
              padding: v("space-1"),
              borderRadius: Math.round(56 * 0.2237) + 3,
              border: `2.5px solid ${r.ring ?? "transparent"}`,
              display: "inline-flex", flexShrink: 0,
            }}>
              <span style={{
                width: 44, height: 44, borderRadius: Math.round(44 * 0.2237),
                background: v("gray-100"), display: "flex", alignItems: "center", justifyContent: "center",
                color: v("tint"),
              }}><r.Icon size={20} /></span>
            </span>
            <span style={{ flex: 1, minWidth: 0 }}>
              <span className="t-label-14" style={{ display: "block" }}>{r.label}</span>
              <span className="t-copy-13" style={{ color: v("gray-900") }}>{r.sub}</span>
            </span>
          </button>
        ))}
      </div>
      {themeOpen && (
        <ThemeSheet mode={mode} tint={tintIdx} hasPhoto={hasPhoto} onPhoto={setHasPhoto}
          onMode={(m) => { setMode(m); applyTheme(m, TINTS[tintIdx]); }}
          onTint={(i) => { setTintIdx(i); applyTheme(mode, TINTS[i]); }}
          onClose={() => setThemeOpen(false)} />
      )}
    </div>
  );
}

/* ---------- shell ---------- */
const tabs: { id: TabId; label: string; Icon: any }[] = [
  { id: "account", label: "Account", Icon: CircleUser },
  { id: "home", label: "Home", Icon: House },
  { id: "feed", label: "Feed", Icon: Activity },
  { id: "apps", label: "Apps", Icon: LayoutGrid },
];

export default function App() {
  const [tab, setTab] = useState<TabId>("home");
  const [apps, setApps] = useState<AppRow[]>(initialApps);
  const [view, setView] = useState<AppsView>("list");
  const [selected, setSelected] = useState<AppRow | null>(null);
  const [confirmRemove, setConfirmRemove] = useState(false);
  const [sheet, setSheet] = useState(false);
  const [draft, setDraft] = useState("");
  const [toast, setToast] = useState<string | null>(null);
  const [composerOpen, setComposerOpen] = useState(false);

  const commit = () => {
    setComposerOpen(false);
    setDraft("");
    setToast("Saved");
    setTimeout(() => setToast(null), 2000);
  };

  const openApp = (a: AppRow) => { setSelected(a); setView("detail"); };

  const reconnect = (a: AppRow) => {
    setApps(apps.map((x) => x.id === a.id ? { ...x, status: "ok" as const, statusLine: "Synced just now" } : x));
    setToast(`${a.name} reconnected`);
    setTimeout(() => setToast(null), 2000);
  };

  const removeRequest = (a: AppRow) => { setSelected(a); setConfirmRemove(true); };

  const togglePause = () => {
    if (!selected) return;
    const next = apps.map((a) => a.id === selected.id
      ? { ...a, status: a.status === "paused" ? "ok" as const : "paused" as const,
          statusLine: a.status === "paused" ? "Synced just now" : "Paused" }
      : a);
    setApps(next);
    setSelected(next.find((a) => a.id === selected.id) ?? null);
  };

  const removeApp = () => {
    if (!selected) return;
    setApps(apps.filter((a) => a.id !== selected.id));
    setConfirmRemove(false);
    setSelected(null);
    setView("list");
    setToast("App removed");
    setTimeout(() => setToast(null), 2000);
  };

  const [pendingConnect, setPendingConnect] = useState<string | null>(null);
  const [project, setProject] = useState<{ name: string; sub: string; count: string; wash: string } | null>(null);
  const [feedSeed, setFeedSeed] = useState<string | null>(null);
  const [feedBack, setFeedBack] = useState(false);
  useEffect(() => {
    projectTap.fn = (name, sub, count, wash) => setProject({ name, sub, count, wash });
    tagTap.fn = (t) => { setTab("feed"); setFeedSeed(t); setFeedBack(true); };
    parseAction.fn = (a) => { setToast(a); setTimeout(() => setToast(null), 2000); };
    return () => { projectTap.fn = null; tagTap.fn = null; parseAction.fn = null; };
  }, []);

  const connect = (name: string, Icon: any) => {
    setPendingConnect(name);
    const id = name.toLowerCase().replace(/\s/g, "-") + "-" + Date.now();
    setApps([...apps, { id, name, Icon, status: "ok", statusLine: "Synced just now", lastActive: 0,
      can: ["Connected."], recent: [] }]);
    setView("list");
    setToast(`${name} connected`);
    setTimeout(() => setToast(null), 2000);
  };

  return (
    <div style={{ height: "100dvh", display: "flex", alignItems: "center", justifyContent: "center", padding: v("space-4") }}>
      {/* phone frame */}
      <div style={{
        position: "relative",
        padding: v("space-3"),
        background: "#1a1a1c",
        borderRadius: 64,
        boxShadow: "inset 0 0 0 2px rgba(255,255,255,0.08), 0 24px 64px rgba(0,0,0,0.6)",
        width: "100%", maxWidth: 426, height: "100%", maxHeight: 898,
        boxSizing: "border-box",
      }}>
      {/* dynamic island */}
      <div style={{
        position: "absolute", top: 26, left: "50%", transform: "translateX(-50%)",
        width: 118, height: 34, borderRadius: v("radius-pill"),
        background: "#000", zIndex: 50,
      }} />
      <div style={{
        position: "relative", width: "100%", height: "100%",
        background: v("background-200"), overflow: "hidden",
        backgroundImage: "var(--ds-bg-image, none)",
        backgroundSize: "cover", backgroundPosition: "center",
        borderRadius: 52,
        display: "flex", flexDirection: "column",
      }}>
        <div style={{ flex: 1, overflowY: "auto", paddingBottom: 176, paddingTop: 56 }}>
          {tab === "apps" && view === "list" && (
            <AppsList apps={apps} empty={apps.length === 0} onOpen={openApp}
              onAdd={() => setView("catalog")}
              onReconnect={(a) => {
                const next = apps.map((x) => x.id === a.id ? { ...x, status: "ok" as const, statusLine: "Synced just now" } : x);
                setApps(next);
                setToast("Calendar reconnected");
                setTimeout(() => setToast(null), 2000);
              }}
              onRemove={(a) => { setSelected(a); setConfirmRemove(true); }} />
          )}
          {tab === "apps" && view === "detail" && selected && (
            <AppDetail app={selected} onBack={() => { setView("list"); setSelected(null); }}
              onTogglePause={togglePause} onRemove={() => setConfirmRemove(true)} />
          )}
          {tab === "apps" && view === "catalog" && (
            <Catalog connected={apps.map((a) => a.name)} onBack={() => setView("list")} onConnect={connect} />
          )}
          {tab === "home" && project && <ProjectScreen {...project} onBack={() => setProject(null)} />}
          {tab === "home" && !project && <HomeScreen empty={apps.length === 0} connected={apps.map((a) => a.name)} pendingConnect={pendingConnect} onConsumed={() => setPendingConnect(null)} />}
          {tab === "feed" && <FeedScreen seedTag={feedSeed} onSeedUsed={() => setFeedSeed(null)} onBack={feedBack ? () => { setTab("home"); setFeedBack(false); } : undefined} connected={apps.map((a) => a.name)} onToast={(s) => { setToast(s); setTimeout(() => setToast(null), 2000); }} />}
          {tab === "account" && <AccountScreen />}
        </div>

        {toast && (
          <div className="t-label-14" style={{
            position: "absolute", left: "50%", transform: "translateX(-50%)", bottom: 176, zIndex: 30,
            background: v("gray-100"), color: v("gray-1000"),
            borderRadius: v("radius-pill"), padding: `var(--ds-space-2) var(--ds-space-4)`, boxShadow: v("shadow-overlay"),
          }}>{toast}</div>
        )}

        {composerOpen && (
          <div onClick={() => setComposerOpen(false)}
            style={{ position: "absolute", inset: 0, background: "var(--ds-scrim)", zIndex: 19 }} />
        )}
        {/* floating bottom stack: composer + tab bar, liquid glass */}
        <div style={{
          position: "absolute", left: 0, right: 0, bottom: 0, zIndex: 20,
          padding: v("space-4"), display: "flex", flexDirection: "column", gap: v("space-3"),
        }}>
        <ComposerUnit open={composerOpen} draft={draft} setDraft={setDraft}
          onOpen={() => setComposerOpen(true)} onClose={() => setComposerOpen(false)} onCommit={commit} />

        {/* tab bar */}
        <nav style={{
          display: "flex", background: v("glass-bg"),
          backdropFilter: "var(--ds-glass-blur)", WebkitBackdropFilter: "var(--ds-glass-blur)",
          boxShadow: `inset 0 0 0 1px var(--ds-glass-stroke), 0 8px 24px rgba(0,0,0,0.4)`,
          borderRadius: v("radius-pill"), padding: `var(--ds-space-1) var(--ds-space-2)`,
        }}>
          {tabs.map((t) => {
            const active = tab === t.id;
            return (
              <button key={t.id} onClick={() => { setTab(t.id); setView("list"); setSelected(null); setProject(null); setFeedBack(false); }} aria-label={t.label} style={{
                flex: 1, minHeight: 48, background: "none", border: "none", cursor: "pointer",
                display: "flex", flexDirection: "column", alignItems: "center", gap: v("space-1"),
                color: active ? v("tint") : v("gray-700"),
                transition: `color var(--ds-duration) var(--ds-ease)`,
                fontFamily: "inherit", padding: `var(--ds-space-1) 0`,
              }}>
                <t.Icon size={20} strokeWidth={active ? 2.2 : 1.8} />
                <span className="t-tab-10">{t.label}</span>
              </button>
            );
          })}
        </nav>
        </div>

        {confirmRemove && selected && (
          <RemoveConfirm appName={selected.name}
            onKeep={removeApp} onRemoveAll={removeApp} onCancel={() => setConfirmRemove(false)} />
        )}
        {sheet && <QuickActions onClose={() => setSheet(false)} />}
      </div>
      </div>
    </div>
  );
}
