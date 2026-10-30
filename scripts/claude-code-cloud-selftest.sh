#!/bin/zsh
# Casberi Claude Code cloud self-test (prd §1625) — how a session from
# claude.ai's `/v1/code/sessions` becomes a row, compiled WHOLE and unmodified:
#
#   Casberi/Casberi/Model/ClaudeCodeCloud.swift
#
# The state is Claude's own (`status_category`, `needs_action`,
# `worker_status`), the line is what Claude says, the repo is the GitHub
# source's. Plus the drift guards: the read is read-only and runs in the
# page, and the ingest never logs.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

PURE="Casberi/Casberi/Model/ClaudeCodeCloud.swift"
INGEST="Casberi/Casberi/Model/ClaudeCodeCloudIngest.swift"
for f in "$PURE" "$INGEST"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done
code() { grep -vE '^[[:space:]]*(//|///)' "$1"; }
if code "$INGEST" | grep -qE 'NSLog|print\('; then
  echo "✗ ClaudeCodeCloudIngest logs — session titles must never reach a log"; exit 1
fi
# Read-only: the page's script makes GETs and nothing else.
if code "$INGEST" | grep -qiE "method: *'(POST|PUT|PATCH|DELETE)'"; then
  echo "✗ the Claude Code read writes to claude.ai"; exit 1
fi
grep -qF "ClaudeWeb.shared.read(readJS)" "$INGEST" \
  || { echo "✗ the read no longer runs inside claude.ai's own page"; exit 1; }
echo "claude-code-cloud-selftest: drift guards ✓"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); failures += 1 }
}
func raw(id: String = "cse_1", title: String? = "Fix the build", worker: String = "idle", bucket: String = "completed",
         category: String? = "completed", needs: String = "", detail: String = "done it", recent: String = "",
         url: String? = "https://github.com/alex/casberi", branches: [String: Any]? = ["claude/fix": NSNull()]) -> [String: Any] {
    var summary: [String: Any] = ["needs_action": needs, "status_detail": detail, "recent_action": recent]
    if let category { summary["status_category"] = category }
    var meta: [String: Any] = ["post_turn_summary": summary]
    if let branches { meta["current_branches"] = branches }
    var r: [String: Any] = ["id": id, "worker_status": worker, "status_bucket": bucket, "external_metadata": meta,
                            "created_at": "2026-10-30T19:35:47.823002Z", "updated_at": "2026-10-30T20:01:00Z",
                            "config": ["sources": url.map { [["type": "git_repository", "url": $0]] } ?? []]]
    if let title { r["title"] = title }
    return r
}
func one(_ r: [String: Any]) -> ClaudeCodeCloud.Session? { ClaudeCodeCloud.session(r) }

// ── The measured page ────────────────────────────────────────────────────
let page = ClaudeCodeCloud.sessions(["data": [raw(), raw(id: "cse_2")], "next_cursor": "x"])
check(page?.count == 2, "a page's sessions are read")
check(ClaudeCodeCloud.sessions(["error": "x"]) == nil, "a body that is not the page is nil, never empty")
check(ClaudeCodeCloud.sessions(["data": [["title": "no id"]]])?.isEmpty == true, "a session with no id is skipped")

// ── State, Claude's own ──────────────────────────────────────────────────
check(one(raw())?.state == .done, "completed is Completed")
check(one(raw(category: "need_input", needs: "Approve the push"))?.state == .needsYou, "need_input is Needs you")
check(one(raw(category: "completed", needs: "Approve the push"))?.state == .needsYou, "a needs_action sentence is Needs you on its own")
check(one(raw(bucket: "failed", category: "failed"))?.state == .failed, "failed is Failed")
check(one(raw(bucket: "failed", category: nil))?.state == .failed, "a failed bucket with no summary is Failed")
check(one(raw(worker: "running", category: "need_input", needs: "x"))?.state == .running, "a running worker is Running, whatever it last asked")
check(ClaudeCodeCloud.State.needsYou.rawValue == "Needs you", "the waiting tag reads as words")

// ── The line, what Claude says ───────────────────────────────────────────
check(one(raw(needs: "Approve the push", detail: "waiting"))?.line == "Approve the push", "what it needs leads")
check(one(raw(detail: "recommends read-only sign-in"))?.line == "recommends read-only sign-in", "else where it stands")
check(one(raw(detail: " ", recent: "opened a PR"))?.line == "opened a PR", "else what it did")
check(one(raw(detail: ""))?.line == "", "nothing said is an empty line")

// ── Repo, branch, title, address ─────────────────────────────────────────
check(one(raw())?.repo == "alex/casberi", "the repo is owner/name")
check(one(raw(url: "https://github.com/alex/casberi.git"))?.repo == "alex/casberi", "a .git ending is dropped")
check(one(raw(url: "https://gitlab.com/alex/casberi"))?.repo == nil, "only a GitHub source names the repo")
check(one(raw(url: nil))?.repo == nil, "no source, no repo")
check(one(raw())?.branch == "claude/fix", "the branch is the current branch's name")
check(one(raw(branches: nil))?.branch == nil, "no branches, no branch")
check(one(raw(title: nil))?.title == "Claude Code session", "an untitled session has a name")
check(one(raw())?.ref == "claudecode:cloud:cse_1", "the ref never collides with a folder session's")
check(one(raw())?.link == "https://claude.ai/code/cse_1", "the link opens the session")
check(one(raw())?.tags == ["Session", "Completed", "casberi"], "tags: kind, state, repo name")
check(one(raw())?.created != nil && one(raw())?.updated != nil, "both timestamp shapes read")

print(failures == 0 ? "claude-code-cloud-selftest: all checks ✓" : "claude-code-cloud-selftest: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

swiftc -O -o "$TMP/run" "$PURE" "$TMP/main.swift" 2>&1 | grep -v "^$" || true
[[ -x "$TMP/run" ]] || { echo "✗ claude-code-cloud-selftest: compile failed"; exit 1; }
"$TMP/run"
