#!/usr/bin/env bash
# Select by source-check capability, not CLI version or schema support alone. The compiler writes no
# bytecode files; test.sh checks the v6 header and schema hash on the program files the host receives.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/lmphysics-compiler-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
# A native (mingw) python cannot see MSYS /tmp paths: hand it drive-letter paths when cygpath exists.
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi; }
candidate="${LMSCRIPT_BIN:-$(command -v lmscript || true)}"
printf '%s\n' '{"dsl.schema":2,"name":"compiler_probe","types":{},"functions":{},"context":{}}' > "$WORK/probe.schema.json"
# JSON string quoting also supports checkouts whose paths contain spaces/quotes.
python3 - "$(native "$WORK/probe.schema.json")" "$(native "$WORK")" <<'PY'
import json,pathlib,sys
work=pathlib.Path(sys.argv[2])
(work/'probe.lms').write_text('p = _lmcode_ schema='+json.dumps(sys.argv[1])+';\nlet n = str_len("implicit std");\nend _lmcode_\nr = run_lmcode(p, {command: ["lmphysics", "--lmcode", "$DSLFILE"]});\n')
PY
if [ -n "$candidate" ] &&
   "$candidate" --lmcode-signatures "$WORK/probe.schema.json" > /dev/null 2>&1 &&
   "$candidate" --check "$WORK/probe.lms" > /dev/null 2>&1
then
  printf '%s\n' "$candidate"
else
  if [ -n "${LMPHYSICS_DEBUG:-}" ]; then
    echo "--- compiler probe diagnostics (candidate=$candidate)" >&2
    cat "$WORK/probe.lms" >&2 || true
    [ -n "$candidate" ] && "$candidate" --lmcode-signatures "$WORK/probe.schema.json" 2>&1 | head -3 >&2
    [ -n "$candidate" ] && "$candidate" --check "$WORK/probe.lms" 2>&1 | head -10 >&2
    ls -la "$WORK" >&2
  fi
  echo "error: no implicit-std lmcode compiler with run_lmcode found; install @lmctl-ai/lmctl@staging so lmscript is on PATH, or set LMSCRIPT_BIN" >&2
  exit 2
fi
