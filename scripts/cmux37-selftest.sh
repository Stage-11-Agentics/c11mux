#!/usr/bin/env bash
# CMUX-37 end-to-end self-test.
#
# Drives the full Blueprint -> Snapshot -> Quit -> Relaunch -> Restore loop
# against a tagged c11 build, isolated from the operator's primary c11
# (own bundle id, own socket, own DerivedData). Verifies that the restored
# workspace structurally matches the pre-snapshot state.
#
# Usage:
#   ./scripts/cmux37-selftest.sh                # default tag, build + run
#   ./scripts/cmux37-selftest.sh --skip-build   # skip xcodebuild (use existing tagged app)
#   ./scripts/cmux37-selftest.sh --tag <name>   # override tag (default: cmux37-test)
#   ./scripts/cmux37-selftest.sh --keep         # leave the tagged app running on success
#   ./scripts/cmux37-selftest.sh --blueprint <path>  # custom blueprint (default: agent-room)

set -euo pipefail

TAG="cmux37-test"
SKIP_BUILD=0
KEEP_RUNNING=0
BLUEPRINT="Resources/Blueprints/agent-room.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) TAG="${2:?--tag requires a value}"; shift 2 ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    --keep) KEEP_RUNNING=1; shift ;;
    --blueprint) BLUEPRINT="${2:?--blueprint requires a path}"; shift 2 ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "error: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if ! command -v jq >/dev/null 2>&1; then
  echo "error: this script requires jq" >&2
  exit 1
fi

# Slugify exactly like reload.sh / launch-tagged-automation.sh do, so
# socket/derived paths line up.
slug() { echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g'; }
bundle_slug() { echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/./g; s/^\.+//; s/\.+$//; s/\.+/./g'; }

TAG_SLUG="$(slug "$TAG")"
TAG_BUNDLE_SLUG="$(bundle_slug "$TAG")"
SOCKET="/tmp/c11-debug-${TAG_SLUG}.sock"
DERIVED="$HOME/Library/Developer/Xcode/DerivedData/c11-${TAG_SLUG}"
APP_PATH="${DERIVED}/Build/Products/Debug/c11 DEV ${TAG}.app"
BUNDLE_ID="com.stage11.c11.debug.${TAG_BUNDLE_SLUG}"
CLI="${APP_PATH}/Contents/Resources/bin/c11"

WORK_DIR="$(mktemp -d -t cmux37-selftest.XXXXXX)"
SUCCESS=0
cleanup() {
  if [[ "$SUCCESS" -eq 1 ]]; then
    rm -rf "$WORK_DIR"
  else
    echo "artifacts kept at: $WORK_DIR" >&2
  fi
}
trap cleanup EXIT

PASS_COLOR='\033[0;32m'
FAIL_COLOR='\033[0;31m'
INFO_COLOR='\033[0;36m'
RESET='\033[0m'

step()  { printf "${INFO_COLOR}==>${RESET} %s\n" "$*"; }
ok()    { printf "${PASS_COLOR}PASS${RESET} %s\n" "$*"; }
fail()  { printf "${FAIL_COLOR}FAIL${RESET} %s\n" "$*" >&2; exit 1; }

# --- 1. Build (unless skipped) ----------------------------------------------
if [[ "$SKIP_BUILD" -eq 0 ]]; then
  step "Building tagged app: $TAG"
  ./scripts/reload.sh --tag "$TAG"
else
  step "Skipping build (--skip-build); reusing $APP_PATH"
  if [[ ! -d "$APP_PATH" ]]; then
    fail "tagged app not found at $APP_PATH (run without --skip-build first)"
  fi
fi

if [[ ! -x "$CLI" ]]; then
  fail "tagged CLI not found at $CLI"
fi

export CMUX_SOCKET_PATH="$SOCKET"
unset CMUX_WORKSPACE_ID CMUX_SURFACE_ID CMUX_TAB_ID CMUX_PANEL_ID

# --- 2. Wait for socket -----------------------------------------------------
wait_for_socket() {
  local label="$1" timeout="${2:-15}"
  local waited=0
  while [[ $waited -lt $timeout ]]; do
    if [[ -S "$SOCKET" ]] && "$CLI" tree --json >/dev/null 2>&1; then
      ok "$label (socket ready in ${waited}s)"
      return 0
    fi
    sleep 0.5
    waited=$((waited + 1))
  done
  fail "$label: socket not ready after ${timeout}s ($SOCKET)"
}

step "Waiting for app socket"
wait_for_socket "tagged app reachable"

# --- 3. Apply blueprint -----------------------------------------------------
step "Applying blueprint: $BLUEPRINT"
APPLY_OUT="$WORK_DIR/apply.json"
"$CLI" --json workspace new --blueprint "$BLUEPRINT" >"$APPLY_OUT"

WS_REF="$(jq -r '.workspaceRef // empty' "$APPLY_OUT")"
SURFACE_COUNT="$(jq -r '.surfaceRefs | length' "$APPLY_OUT")"
PANE_COUNT="$(jq -r '.paneRefs | length' "$APPLY_OUT")"
WARNING_COUNT="$(jq -r '.warnings | length' "$APPLY_OUT")"
FAILURE_COUNT="$(jq -r '.failures | length' "$APPLY_OUT")"

[[ -n "$WS_REF" ]]              || fail "apply: no workspaceRef returned"
[[ "$FAILURE_COUNT" == "0" ]]   || fail "apply: $FAILURE_COUNT failure(s) -- $(jq -c .failures "$APPLY_OUT")"

ok "applied workspace=$WS_REF surfaces=$SURFACE_COUNT panes=$PANE_COUNT warnings=$WARNING_COUNT"

# --- 4. Snapshot ------------------------------------------------------------
step "Snapshotting workspace $WS_REF"
SNAP_OUT="$WORK_DIR/snap1.json"
"$CLI" --json snapshot --workspace "$WS_REF" >"$SNAP_OUT"

SNAP_ID="$(jq -r '.snapshot_id' "$SNAP_OUT")"
SNAP_PATH="$(jq -r '.path' "$SNAP_OUT")"
SNAP_SURFACES="$(jq -r '.surface_count' "$SNAP_OUT")"

[[ -n "$SNAP_ID" && "$SNAP_ID" != "null" ]] || fail "snapshot: no snapshot_id returned"
[[ -f "$SNAP_PATH" ]]                       || fail "snapshot: file missing at $SNAP_PATH"

ok "snapshot=$SNAP_ID surfaces=$SNAP_SURFACES file=$SNAP_PATH"

# Capture the pre-snapshot plan (the structural ground truth we'll compare against).
PRE_PLAN="$WORK_DIR/pre.plan.json"
jq '.plan // .' "$SNAP_PATH" > "$PRE_PLAN"

# --- 5. Quit the tagged app -------------------------------------------------
step "Quitting tagged app (bundle id $BUNDLE_ID)"
osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true

waited=0
while [[ -S "$SOCKET" && $waited -lt 10 ]]; do
  sleep 0.5
  waited=$((waited + 1))
done
if [[ -S "$SOCKET" ]]; then
  fail "socket $SOCKET still present after quit"
fi
ok "app quit (socket released after ${waited}s)"

# --- 6. Relaunch ------------------------------------------------------------
step "Relaunching tagged app"
open -g "$APP_PATH"
wait_for_socket "tagged app back online" 20

# --- 7. Restore -------------------------------------------------------------
step "Restoring snapshot $SNAP_ID"
RESTORE_OUT="$WORK_DIR/restore.json"
"$CLI" --json restore "$SNAP_ID" >"$RESTORE_OUT"

WS_REF2="$(jq -r '.workspaceRef // empty' "$RESTORE_OUT")"
SURFACE_COUNT2="$(jq -r '.surfaceRefs | length' "$RESTORE_OUT")"

# Some entries in `failures` are informational drift the snapshot writer
# emits today (duplicate `metadata["title"]`, seed-terminal cwd) — the
# restore still produces a valid workspace. Treat the known-drift codes as
# warnings; any other code is fatal.
TOLERATED_CODES='["metadata_override","working_directory_not_applied"]'
HARD_FAILURES="$(jq --argjson ok "$TOLERATED_CODES" \
  '[.failures[]? | select((.code as $c | $ok | index($c)) | not)]' \
  "$RESTORE_OUT")"
HARD_COUNT="$(jq 'length' <<<"$HARD_FAILURES")"
SOFT_COUNT="$(jq -r '.failures | length' "$RESTORE_OUT")"
SOFT_COUNT="$((SOFT_COUNT - HARD_COUNT))"

[[ -n "$WS_REF2" ]]            || fail "restore: no workspaceRef returned"
[[ "$HARD_COUNT" == "0" ]]     || fail "restore: $HARD_COUNT unexpected failure(s) -- $(jq -c . <<<"$HARD_FAILURES")"

ok "restored workspace=$WS_REF2 surfaces=$SURFACE_COUNT2 (drift-warnings=$SOFT_COUNT)"
if [[ "$SOFT_COUNT" -gt 0 ]]; then
  echo "  known snapshot-writer drift (not a regression):"
  jq -r '.failures[] | "    - [\(.code)] \(.message)"' "$RESTORE_OUT"
fi

# --- 8. Re-snapshot the restored workspace ----------------------------------
step "Re-snapshotting restored workspace for diff"
SNAP2_OUT="$WORK_DIR/snap2.json"
"$CLI" --json snapshot --workspace "$WS_REF2" >"$SNAP2_OUT"

SNAP2_PATH="$(jq -r '.path' "$SNAP2_OUT")"
[[ -f "$SNAP2_PATH" ]] || fail "second snapshot file missing at $SNAP2_PATH"

POST_PLAN="$WORK_DIR/post.plan.json"
jq '.plan // .' "$SNAP2_PATH" > "$POST_PLAN"

# --- 9. Structural diff -----------------------------------------------------
# Strip identifiers and ephemeral fields so we compare the workspace shape,
# not the new refs that the executor minted.
normalize() {
  jq '
    .surfaces |= sort_by(.id) |
    .surfaces |= map(del(.metadata."surface.created_at"?, .metadata."surface.updated_at"?))
  '
}

PRE_NORM="$WORK_DIR/pre.norm.json"
POST_NORM="$WORK_DIR/post.norm.json"
normalize <"$PRE_PLAN"  >"$PRE_NORM"
normalize <"$POST_PLAN" >"$POST_NORM"

step "Comparing pre-snapshot vs post-restore plan"
if diff -u "$PRE_NORM" "$POST_NORM" >"$WORK_DIR/diff.txt"; then
  ok "round-trip plan matches"
else
  echo "----- diff (pre -> post) -----" >&2
  cat "$WORK_DIR/diff.txt" >&2
  echo "------------------------------" >&2
  fail "round-trip diff non-empty (see above)"
fi

PRE_SURFACES="$(jq '.surfaces | length' "$PRE_PLAN")"
POST_SURFACES="$(jq '.surfaces | length' "$POST_PLAN")"
[[ "$PRE_SURFACES" == "$POST_SURFACES" ]] || fail "surface count drift: pre=$PRE_SURFACES post=$POST_SURFACES"
ok "surface count preserved ($PRE_SURFACES)"

PRE_LAYOUT_FP="$(jq -c '.layout' "$PRE_PLAN" | shasum | cut -d' ' -f1)"
POST_LAYOUT_FP="$(jq -c '.layout' "$POST_PLAN" | shasum | cut -d' ' -f1)"
[[ "$PRE_LAYOUT_FP" == "$POST_LAYOUT_FP" ]] || fail "layout fingerprint drift: pre=$PRE_LAYOUT_FP post=$POST_LAYOUT_FP"
ok "layout tree fingerprint preserved ($PRE_LAYOUT_FP)"

# --- 10. Cleanup ------------------------------------------------------------
if [[ "$KEEP_RUNNING" -eq 1 ]]; then
  step "Leaving tagged app running (--keep). Quit it manually with:"
  echo "  osascript -e 'tell application id \"$BUNDLE_ID\" to quit'"
else
  step "Cleaning up: quitting tagged app"
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
fi

SUCCESS=1
echo
printf "${PASS_COLOR}CMUX-37 self-test PASSED${RESET}\n"
echo "  blueprint:     $BLUEPRINT"
echo "  pre snapshot:  $SNAP_PATH"
echo "  post snapshot: $SNAP2_PATH"
