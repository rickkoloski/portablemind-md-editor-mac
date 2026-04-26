# Shared helpers for harness-driven regression tests.
# Source this from each test script.

export PATH=/usr/bin:/bin:/usr/sbin:/sbin:$PATH

CMD=${CMD:-/tmp/mdeditor-command.json}
TMPDIR=${TMPDIR:-/tmp}

# Write a JSON command, wait for the harness to process it (file
# disappears = dispatched + result file written). Required for
# back-to-back commands; omitting the wait races against the 200ms
# poller and silently drops earlier commands.
write_cmd() {
  /bin/rm -f "$CMD"
  printf '%s' "$1" > "$CMD.tmp"
  /bin/mv "$CMD.tmp" "$CMD"
  while [ -f "$CMD" ]; do /bin/sleep 0.05; done
}

# Run an action that writes its result to "path", wait for that file to
# appear, return its path so the caller can read it.
action_to_file() {
  local action="$1"
  local outpath="$2"
  /bin/rm -f "$outpath"
  write_cmd "{\"action\":\"$action\",\"path\":\"$outpath\"}"
  while [ ! -f "$outpath" ]; do /bin/sleep 0.05; done
  printf '%s' "$outpath"
}

read_scrollY() {
  action_to_file scroll_info "$TMPDIR/scroll.json" >/dev/null
  /usr/bin/python3 -c "import json; print(json.load(open('$TMPDIR/scroll.json')).get('scrollY',-1))"
}

# Best-effort focus-doc check. Caller can grep its output to assert.
focused_doc_url() {
  action_to_file focused_doc_info "$TMPDIR/focused.json" >/dev/null
  /usr/bin/python3 -c "import json; print(json.load(open('$TMPDIR/focused.json')).get('url',''))"
}
