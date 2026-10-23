#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"
BUILD_DIR="${BUILD_DIR:-build}"
HOST="$BUILD_DIR/lmphysics"
UNAME_S="$(uname -s)"
case "$UNAME_S" in MINGW*|MSYS*|CYGWIN*) HOST="$HOST.exe";; esac
WORK="$(mktemp -d "${TMPDIR:-/tmp}/lmphysics-test-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
ROOT="$HERE"
# Native Windows tools (node, the host) cannot address git-bash /tmp or /d/a paths.
case "$UNAME_S" in MINGW*|MSYS*|CYGWIN*) WORK="$(cd "$WORK" && pwd -W | tr '\\' '/')"; ROOT="$(pwd -W | tr '\\' '/')";; esac
pass=0
ok(){ pass=$((pass+1)); echo "ok $pass - $1"; }
fail(){ echo "FAIL: $*" >&2; exit 1; }
sha(){ if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -c1-64; else shasum -a 256 "$1" | cut -c1-64; fi; }

# lmscript resolves cli="lmphysics" on PATH first, so programs bind to the binary under test.
export PATH="$(cd "$BUILD_DIR" 2>/dev/null && pwd || echo "$HERE/$BUILD_DIR"):$PATH"
LMSCRIPT="$(scripts/select-compiler.sh)"
scripts/sync-sdk.sh --verify >/dev/null || fail "SDK header pin mismatch"
ok "SDK header matches sdk.lock"
scripts/sync-deps.sh --verify >/dev/null || fail "third_party pin mismatch"
ok "third_party matches deps.lock"

GEN=""
command -v ninja >/dev/null 2>&1 && GEN="-G Ninja"
# shellcheck disable=SC2086
cmake -S . -B "$BUILD_DIR" $GEN -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build "$BUILD_DIR" >"$WORK/build.log" 2>&1 || { tail -40 "$WORK/build.log" >&2; fail "build"; }
ok "build"

want_version="lmphysics $(sed -n 's/^project(lmphysics VERSION \([0-9.]*\).*/\1/p' CMakeLists.txt)"
[ "$("$HOST" --version)" = "$want_version" ] || fail "--version is not exactly '$want_version'"
ok "--version prints exactly '$want_version'"
python3 scripts/gen-schema.py >/dev/null && git diff --quiet -- schema/lmphysics.dsl.json 2>/dev/null || [ ! -d .git ] || fail "schema/lmphysics.dsl.json is stale: run scripts/gen-schema.py"
ok "schema matches the registrations in cpp/main.cpp"
"$HOST" --dsl-schema --json >"$WORK/schema.json" || fail "embedded schema print"
cmp -s "$WORK/schema.json" schema/lmphysics.dsl.json || fail "embedded schema differs from schema/lmphysics.dsl.json"
ok "--dsl-schema --json prints byte-identical embedded schema bytes"
diff -u <("$LMSCRIPT" --dsl-signatures schema/lmphysics.dsl.json) <("$HOST" --dsl-signatures) || fail "host/compiler signatures differ"
ok "host registry matches compiler signatures"
"$HOST" --notices | grep -q "Project Chrono" || fail "--notices missing third-party text"
ok "--notices prints the third-party license texts"

case "$UNAME_S" in
  Linux) if ldd "$HOST" >/dev/null 2>&1; then fail "executable is dynamically linked"; fi; ok "executable is fully static (no dynamic loader)";;
  Darwin) bad="$(otool -L "$HOST" | tail -n +2 | grep -v -E '/usr/lib/(libSystem|libc\+\+|libresolv)' || true)"
          [ -z "$bad" ] || fail "non-system dylib dependencies: $bad"; ok "only system libraries linked";;
  MINGW*|MSYS*|CYGWIN*)
    if command -v objdump >/dev/null 2>&1; then
      bad="$(objdump -p "$HOST" | grep 'DLL Name' | grep -i -E 'libstdc|libgcc|winpthread|libgomp' || true)"
      [ -z "$bad" ] || fail "MinGW runtime DLLs are imported: $bad"
      ok "no MinGW runtime DLL imports"
    else ok "static-link check skipped (no objdump)"; fi;;
  *) ok "static-link check skipped on $UNAME_S";;
esac

# Programs under tests/: compile to bytecode and run (they assert their own numbers).
mkdir -p build
n=0
for src in tests/*.lms; do
  name="$(basename "$src" .lms)"
  "$LMSCRIPT" "$src" "build/$name.dslb" >"$WORK/$name.log" 2>&1 || { cat "$WORK/$name.log" >&2; fail "$name compile"; }
  "$HOST" --dsl "build/$name.dslb" >"$WORK/$name.out" 2>"$WORK/$name.err" || { cat "$WORK/$name.out" "$WORK/$name.err" >&2; fail "$name run"; }
  grep -q '"ok": true' "$WORK/$name.out" || { cat "$WORK/$name.out" >&2; fail "$name did not report ok"; }
  n=$((n+1))
done
ok "$n test programs compile as bytecode v5, run and pass their own assertions"

# Gallery: every image the README references exists and is a valid PNG/GIF; every linked example exists.
img_ok() { # file
  head -c 8 "$1" | od -An -tx1 | tr -d ' \n' | grep -q '^89504e470d0a1a0a' && return 0
  head -c 6 "$1" | grep -q '^GIF8' && return 0
  return 1
}
gal=0
for img in $(grep -oE 'docs/images/[A-Za-z0-9_.-]+\.(png|gif)' README.md | sort -u); do
  [ -s "$img" ] || fail "README references missing image $img"
  img_ok "$img" || fail "$img is not a valid PNG/GIF"
  [ "$(wc -c <"$img")" -le 3145728 ] || fail "$img is larger than 3 MB"
  gal=$((gal+1))
done
for ex in $(grep -o 'examples/[A-Za-z0-9_/.-]*\.lms' README.md | sort -u); do
  [ -f "$ex" ] || fail "README links missing example $ex"
done
ok "README gallery: $gal images exist and are valid, linked examples exist"

# Examples are self-contained: each runs its own simulation, draws with lmplot and writes images/ and
# build/ under the current directory. They need lmplot (on PATH or installable), so skip loudly without it.
if command -v lmplot >/dev/null 2>&1 || [ "${LMPHYSICS_TEST_NETWORK:-}" = 1 ]; then
  EXDIR="$WORK/exrun"; mkdir -p "$EXDIR"
  n=0
  for src in examples/*.lms examples/combo/*.lms; do
    name="$(basename "$src" .lms)"
    (cd "$EXDIR" && "$LMSCRIPT" "$ROOT/$src") >"$WORK/$name.log" 2>&1 || { cat "$WORK/$name.log" >&2; fail "$name example"; }
    n=$((n+1))
  done
  imgs=0
  for f in "$EXDIR"/images/*.png; do [ -s "$f" ] && img_ok "$f" || fail "example image $f missing or not a PNG"; imgs=$((imgs+1)); done
  ok "$n examples ran by themselves (simulate, draw) and wrote $imgs valid PNGs"
  for f in "$EXDIR"/build/examples/*.csv; do echo "$(sha "$f") $(basename "$f")"; done >"$WORK/before.txt"
  for src in examples/*.lms examples/combo/*.lms; do
    (cd "$EXDIR" && "$LMSCRIPT" "$ROOT/$src") >/dev/null 2>&1 || fail "$src rerun"
  done
  for f in "$EXDIR"/build/examples/*.csv; do echo "$(sha "$f") $(basename "$f")"; done >"$WORK/after.txt"
  cmp -s "$WORK/before.txt" "$WORK/after.txt" || fail "result files differ on rerun"
  ok "all $(wc -l <"$WORK/after.txt" | tr -d ' ') result files are byte-identical on rerun"
else
  echo "SKIPPED: examples (no lmplot on PATH and LMPHYSICS_TEST_NETWORK unset): images were not regenerated"
  ok "examples skipped loudly (no lmplot, LMPHYSICS_TEST_NETWORK unset)"
fi

# Error paths: each snippet must fail the run with exit 3 and a message naming the problem.
expect_error() { # name, snippet, expected message fragment
  cat >"$WORK/$1.lms" <<LMS
p = _dsl_ cli="lmphysics";
$2
end _dsl_
savedsl(p, "$WORK/$1.dslb");
LMS
  "$LMSCRIPT" "$WORK/$1.lms" >/dev/null 2>"$WORK/$1.cerr" || { cat "$WORK/$1.cerr" >&2; fail "$1 compile"; }
  set +e; out="$("$HOST" --dsl "$WORK/$1.dslb" 2>/dev/null)"; code=$?; set -e
  [ "$code" = 3 ] || fail "$1: exit code $code, expected 3 ($out)"
  echo "$out" | grep -q "$3" || fail "$1: message lacks '$3': $out"
}
expect_error badkind 'let s = phys.system("rigid");' "must be"
expect_error dupname 'let s = phys.system("nsc"); let a = s.sphere("a", 0.1, 1.0); let b = s.box("a", 1.0, 1.0, 1.0, 1.0);' "already used"
expect_error badsize 'let s = phys.system("nsc"); let a = s.sphere("a", -0.1, 1.0);' "must be positive"
expect_error nomaterial 'let s = phys.system("nsc"); let a = s.sphere("a", 0.1, 1.0).collide("steel");' "unknown material"
expect_error ghostrecord 'let s = phys.system("nsc"); s.record("nobody", "x");' "no body or joint named"
expect_error badcolumn 'let s = phys.system("nsc"); let a = s.sphere("a", 0.1, 1.0); s.record("a", "banana");' "unknown body column"
expect_error lateRecord 'let s = phys.system("nsc"); let a = s.sphere("a", 0.1, 1.0); s.step(); s.record("a", "x");' "after the simulation has started"
expect_error badexpr 'let s = phys.system("nsc"); let g = s.ground("g"); let a = s.sphere("a", 0.1, 1.0); let m = s.motor_speed("m", g, a, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, "2 +* t");' "expression"
expect_error unknownvar 'let s = phys.system("nsc"); let g = s.ground("g"); let a = s.sphere("a", 0.1, 1.0); let m = s.motor_speed("m", g, a, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, "omega*t");' "unknown name"
expect_error samebody 'let s = phys.system("nsc"); let a = s.sphere("a", 0.1, 1.0); let j = s.revolute("j", a, a, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0);' "two different bodies"
expect_error zeroaxis 'let s = phys.system("nsc"); let g = s.ground("g"); let a = s.sphere("a", 0.1, 1.0); let j = s.revolute("j", g, a, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);' "axis must not be zero"
expect_error othersystem 'let s = phys.system("nsc"); let t = phys.system("nsc"); let g = s.ground("g"); let a = t.sphere("a", 0.1, 1.0); let j = s.lock("j", g, a, 0.0, 0.0, 0.0);' "different system"
expect_error nsc_young 'let s = phys.system("nsc"); s.material("m", 0.5, 0.0); s.stiffness("m", 1000000.0, 0.3);' "only smc"
expect_error badsolver 'let s = phys.system("nsc"); s.solver("magic", 10);' "unknown solver"
expect_error badintegrator 'let s = phys.system("nsc"); s.integrator("rk4");' "unknown integrator"
expect_error newton_na 'let s = phys.system("nsc"); s.integrator("euler_projected").newton(5, 0.001, 0.001); s.hht_alpha(-0.1);' "integrator"
expect_error badtimestep 'let s = phys.system("nsc"); s.timestep(0.0);' "must be positive"
expect_error badcsv 'let s = phys.system("nsc"); s.save_csv("/nonexistent-dir/x.csv");' "cannot write"
expect_error assertfail 'phys.assert_close(1.0, 2.0, 0.1);' "assert_close failed"
ok "errors stop the program with exit 3 and a clear message (19 cases)"

set +e; "$HOST" --dsl "$WORK/does-not-exist.dslb" >/dev/null 2>&1; code=$?; set -e
[ "$code" = 3 ] || fail "missing bytecode exit code $code, expected 3"
set +e; "$HOST" >/dev/null 2>&1; code=$?; set -e
[ "$code" = 2 ] || fail "usage exit code $code, expected 2"
ok "usage and load errors use exit codes 2 and 3"

echo "all $pass checks passed"
