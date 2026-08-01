#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=""
QS_PID=""
MOCK_PID=""

cleanup() {
  if [[ -n $MOCK_PID ]] && kill -0 "$MOCK_PID" 2>/dev/null; then
    kill "$MOCK_PID" 2>/dev/null || true
    wait "$MOCK_PID" 2>/dev/null || true
  fi
  if [[ -n $QS_PID ]] && kill -0 "$QS_PID" 2>/dev/null; then
    kill "$QS_PID" 2>/dev/null || true
    wait "$QS_PID" 2>/dev/null || true
  fi
  [[ -n $TMPDIR && -d $TMPDIR ]] && rm -rf "$TMPDIR"
  return 0
}
trap cleanup EXIT

if [[ -z ${WAYLAND_DISPLAY:-} ]]; then
  pass "no Wayland compositor; skipping tray menu activation test"
  exit 0
fi

if ! command -v quickshell >/dev/null 2>&1; then
  pass "quickshell not installed; skipping tray menu activation test"
  exit 0
fi

require_command jq
require_command node
require_command python

python - <<'PY' || {
import dbus
import gi
PY
  pass "python DBus bindings unavailable; skipping tray menu activation test"
  exit 0
}

TMPDIR=$(mktemp -d)
config_dir="$TMPDIR/tray-menu-activation"
result="$TMPDIR/result.json"
event_log="$TMPDIR/events"
query_log="$TMPDIR/queries"
command_file="$TMPDIR/command"
ready="$TMPDIR/ready"
qs_log="$TMPDIR/quickshell.log"
mock_log="$TMPDIR/mock-sni.log"
mkdir -p "$config_dir" "$TMPDIR/home"
cp "$SHELL_TEST_DIR/fixtures/tray-menu-activation/shell.qml" "$config_dir/shell.qml"
ln -s "$ROOT/shell/Ui" "$config_dir/Ui"
ln -s "$ROOT/shell/Commons" "$config_dir/Commons"

OMARCHY_PATH="$ROOT" \
OMARCHY_QML_TEST_RESULT="$result" \
OMARCHY_TRAY_MENU_COMMAND="$command_file" \
HOME="$TMPDIR/home" \
QML2_IMPORT_PATH="$ROOT/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
QML_IMPORT_PATH="$ROOT/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
PATH="$ROOT/bin:$PATH" \
  quickshell -p "$config_dir" --no-color >"$qs_log" 2>&1 &
QS_PID=$!

OMARCHY_TRAY_MENU_EVENT_LOG="$event_log" \
OMARCHY_TRAY_MENU_QUERY_LOG="$query_log" \
OMARCHY_TRAY_MENU_COMMAND="$command_file" \
OMARCHY_TRAY_MENU_READY="$ready" \
  python "$SHELL_TEST_DIR/fixtures/tray-menu-activation/mock-sni.py" >"$mock_log" 2>&1 &
MOCK_PID=$!

for _ in {1..160}; do
  [[ -s $result ]] && break

  if ! kill -0 "$QS_PID" 2>/dev/null; then
    sed -n '1,220p' "$qs_log" >&2
    fail "actual Tray.qml fixture exited before completing menu navigation"
  fi

  if ! kill -0 "$MOCK_PID" 2>/dev/null; then
    sed -n '1,220p' "$mock_log" >&2
    fail "mock StatusNotifierItem exited before menu navigation completed"
  fi

  sleep 0.1
done

if [[ ! -s $result ]]; then
  printf 'Quickshell log:\n' >&2
  sed -n '1,220p' "$qs_log" >&2
  printf 'Mock SNI log:\n' >&2
  sed -n '1,220p' "$mock_log" >&2
  fail "actual Tray.qml fixture completes menu navigation"
fi

if [[ $(jq -r '.ok' "$result") != "true" ]]; then
  jq . "$result" >&2
  printf 'Quickshell log:\n' >&2
  sed -n '1,220p' "$qs_log" >&2
  printf 'Mock SNI log:\n' >&2
  sed -n '1,220p' "$mock_log" >&2
  fail "actual Tray.qml behavior passes runtime assertions"
fi

OMARCHY_TRAY_MENU_EVENT_LOG="$event_log" \
OMARCHY_TRAY_MENU_QUERY_LOG="$query_log" \
run_node_test <<'JS'
const fs = require('fs')

const events = fs.readFileSync(process.env.OMARCHY_TRAY_MENU_EVENT_LOG, 'utf8').trim().split(/\n+/)
const queries = fs.readFileSync(process.env.OMARCHY_TRAY_MENU_QUERY_LOG, 'utf8').trim().split(/\n+/)

function containsSequence(values, sequence) {
  let offset = 0
  for (const value of values) {
    if (value === sequence[offset]) offset++
    if (offset === sequence.length) return true
  }
  return false
}

const sessions = []
let session = null
for (const event of events) {
  if (event === 'opened 0') session = []
  if (session) session.push(event)
  if (event === 'closed 0' && session) {
    sessions.push(session)
    session = null
  }
}

assert(
  sessions.some(values => containsSequence(values, ['opened 0', 'clicked 1', 'closed 0'])),
  'tray menu preserves flat root action activation',
  events.join('\n')
)

assert(
  sessions.some(values => containsSequence(values, ['opened 0', 'opened 3', 'opened 4', 'clicked 7', 'closed 4', 'closed 3', 'closed 0'])),
  'tray menu keeps ancestors open and closes them deepest-first',
  events.join('\n')
)

assert(
  queries.includes('0 -1') && queries.includes('3 -1'),
  'mock menu honors root and parent layout queries',
  queries.join('\n')
)
JS

pass "actual Tray.qml handles nested navigation and layout invalidation"
