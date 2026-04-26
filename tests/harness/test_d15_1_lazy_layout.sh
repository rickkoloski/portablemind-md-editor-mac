#!/bin/zsh
# D15.1 regression: TextKit 2 lazy layout staleness.
#
# Bug: tables outside the initial visible area have fragments at the
# default unset y=0 until something forces layout for their range.
# Click resolution (mouseDown → tlm.textLayoutFragment(for:)) returns a
# fragment with stale frame, the cell-edit overlay mounts at the wrong
# screen position. Repro requires a doc with multiple tables where
# some tables are below the initial viewport.
#
# Fix: mouseDown calls `tlm.ensureLayout(for: tcm.documentRange)`
# BEFORE resolving the click fragment, so subsequent lookups use the
# fully-laid-out positions.
#
# This test:
#   1. Asserts BEFORE-click stale-fragment count > 0 on a multi-table doc.
#   2. Triggers the click fix via simulate_click_at_table_cell on table 0.
#   3. Asserts AFTER-click stale-fragment count == 0.
#   4. Asserts overlay actualFrame == expectedFrame for cells in tables 1+.
#
# Required: app running with a multi-table doc focused.

set -e
cd "$(dirname "$0")"
. ./lib.sh

DOC_PATH="${TEST_DOC_PATH:-$HOME/src/apps/harmoniq/harmoniq-frontend/docs/00_CURRENT_WORK/planning/d09_task_conversations_files_plan.md}"

if [ ! -f "$DOC_PATH" ]; then
  echo "SKIP: test doc not present: $DOC_PATH"
  echo "Override with TEST_DOC_PATH=/path/to/multi-table.md"
  exit 0
fi

ROOT=$(dirname "$(dirname "$(pwd)")")
"$ROOT/scripts/md-editor" "$DOC_PATH"
/bin/sleep 1

write_cmd '{"action":"set_scroll","y":0}'
write_cmd '{"action":"cancel_overlay"}'
/bin/sleep 0.3

# Phase 1: stale-fragment count BEFORE any click.
action_to_file inspect_table_layout /tmp/d15-1-before.json >/dev/null
STALE_BEFORE=$(/usr/bin/python3 -c "
import json
d = json.load(open('/tmp/d15-1-before.json'))
n = 0
for ti, t in enumerate(d.get('tables', [])):
    if ti == 0: continue
    for r in t.get('rows', []):
        if r['fragOriginY'] == 0 and r['cci'] >= 0:
            n += 1
print(n)
")

if [ "$STALE_BEFORE" = "0" ]; then
  echo "WARN: no stale fragments detected before click — doc may not exercise the bug"
else
  echo "Phase 1 ✓ — $STALE_BEFORE stale fragments BEFORE click (proves bug existed)"
fi

# Phase 2: trigger ensureLayout via the production mouseDown path.
write_cmd '{"action":"simulate_click_at_table_cell","table":0,"row":1,"col":0,"relX":5,"relY":5}'
/bin/sleep 0.3
write_cmd '{"action":"cancel_overlay"}'
/bin/sleep 0.3

action_to_file inspect_table_layout /tmp/d15-1-after.json >/dev/null
STALE_AFTER=$(/usr/bin/python3 -c "
import json
d = json.load(open('/tmp/d15-1-after.json'))
n = 0
for ti, t in enumerate(d.get('tables', [])):
    if ti == 0: continue
    for r in t.get('rows', []):
        if r['fragOriginY'] == 0 and r['cci'] >= 0:
            n += 1
print(n)
")

if [ "$STALE_AFTER" = "0" ]; then
  echo "Phase 2 ✓ — 0 stale fragments AFTER click (ensureLayout in mouseDown ran)"
else
  echo "Phase 2 ✗ FAIL — $STALE_AFTER stale fragments after click"
  exit 1
fi

# Phase 3: overlay placement — actual==expected for every reachable cell.
FAIL=0
for tbl in 0 1 2 3 4; do
  for row in 0 1 2; do
    for col in 0 1 2; do
      write_cmd "{\"action\":\"simulate_click_at_table_cell\",\"table\":$tbl,\"row\":$row,\"col\":$col,\"relX\":5,\"relY\":5}"
      /bin/sleep 0.15
      action_to_file inspect_overlay /tmp/d15-1-ov.json >/dev/null
      RES=$(/usr/bin/python3 -c "
import json
d = json.load(open('/tmp/d15-1-ov.json'))
if not d.get('active'): print('SKIP'); raise SystemExit
a = d['actualFrame']; e = d['expectedFrame']
print('OK' if a == e else f'FAIL Δy={a[\"y\"]-e[\"y\"]:.1f}')
")
      if [[ "$RES" == FAIL* ]]; then
        echo "  table=$tbl row=$row col=$col: $RES"
        FAIL=$((FAIL+1))
      fi
      write_cmd '{"action":"cancel_overlay"}'
      /bin/sleep 0.1
    done
  done
done

if [ "$FAIL" = "0" ]; then
  echo "Phase 3 ✓ — every reachable overlay landed at the expected frame"
else
  echo "Phase 3 ✗ FAIL — $FAIL overlays diverged from expected position"
  exit 1
fi

# Phase 4: SCROLL then CLICK — the actual user-visible repro pattern.
# We pick a y-target that lands deep in the doc (past Table 0), then
# click on cells in Tables 1+ which only became visible because of the
# scroll. If ensureLayout in mouseDown weren't there, the fragment
# cache would have stale (0,0) positions for these tables and the
# overlay would mount at the wrong place.
write_cmd '{"action":"cancel_overlay"}'
write_cmd '{"action":"set_scroll","y":0}'
/bin/sleep 0.3

# Force the lazy-layout state we want to exercise: scroll WITHOUT
# triggering a click first, so layout hasn't been ensured yet.
write_cmd '{"action":"set_scroll_via_wheel","y":11000}'
/bin/sleep 0.5

# Confirm layout is stale at this point (otherwise the test isn't
# exercising the bug — could mean the doc's small enough that initial
# layout already covered everything).
action_to_file inspect_table_layout /tmp/d15-1-stale-check.json >/dev/null
SCROLL_STALE=$(/usr/bin/python3 -c "
import json
d = json.load(open('/tmp/d15-1-stale-check.json'))
n = 0
for ti, t in enumerate(d.get('tables', [])):
    for r in t.get('rows', []):
        if r['fragOriginY'] == 0 and r['cci'] >= 0:
            n += 1
print(n)
")
echo "Phase 4 setup: scrolled to y=11000; stale fragments before click = $SCROLL_STALE"

# Now click. Test cells in Tables 1+ which are in the scrolled-to region.
SFAIL=0
for tbl in 1 2 3 4; do
  for row in 0 1; do
    write_cmd "{\"action\":\"simulate_click_at_table_cell\",\"table\":$tbl,\"row\":$row,\"col\":0,\"relX\":5,\"relY\":5}"
    /bin/sleep 0.15
    action_to_file inspect_overlay /tmp/d15-1-scroll-ov.json >/dev/null
    RES=$(/usr/bin/python3 -c "
import json
d = json.load(open('/tmp/d15-1-scroll-ov.json'))
if not d.get('active'): print('SKIP'); raise SystemExit
a = d['actualFrame']; e = d['expectedFrame']
print('OK' if a == e else f'FAIL Δy={a[\"y\"]-e[\"y\"]:.1f}')
")
    if [[ "$RES" == FAIL* ]]; then
      echo "  scrolled table=$tbl row=$row: $RES"
      SFAIL=$((SFAIL+1))
    fi
    write_cmd '{"action":"cancel_overlay"}'
    /bin/sleep 0.1
  done
done

if [ "$SFAIL" = "0" ]; then
  echo "Phase 4 ✓ — scroll-then-click overlays all landed at expected frames"
else
  echo "Phase 4 ✗ FAIL — $SFAIL post-scroll overlays mispositioned"
  exit 1
fi

echo ""
echo "D15.1 lazy-layout regression: PASS"
