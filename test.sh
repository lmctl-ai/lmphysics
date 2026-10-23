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
python3 scripts/gen-schema.py >/dev/null && git diff --quiet -- schema/lmphysics.dsl.json 2>/dev/null || [ ! -e .git ] || fail "schema/lmphysics.dsl.json is stale: run scripts/gen-schema.py"
ok "schema matches the registrations in cpp/main.cpp"
"$HOST" --dsl-schema --json >"$WORK/schema.json" || fail "embedded schema print"
cmp -s "$WORK/schema.json" schema/lmphysics.dsl.json || fail "embedded schema differs from schema/lmphysics.dsl.json"
ok "--dsl-schema --json prints byte-identical embedded schema bytes"
diff -u <("$LMSCRIPT" --dsl-signatures schema/lmphysics.dsl.json) <("$HOST" --dsl-signatures) || fail "host/compiler signatures differ"
ok "host registry matches compiler signatures"
"$HOST" --notices | grep -q "Project Chrono" || fail "--notices missing third-party text"
cmp -s <("$HOST" --notices) THIRD_PARTY_NOTICES || fail "--notices differs from THIRD_PARTY_NOTICES"
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

[ "$(wc -l <build/loads_thinned.csv | tr -d ' ')" = 102 ] || fail "record_every(10) over 1000 steps should give header + 101 rows"
ok "record_every thins the CSV (101 rows) and keeps the final state"

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
expect_error margins_smc 'let s = phys.system("smc"); s.collision_margins(0.0, 0.0);' "only nsc"
expect_error margins_late 'let s = phys.system("nsc"); s.material("m", 0.5, 0.0); s.floor("f", "m"); s.collision_margins(0.0, 0.0);' "before any body collides"
expect_error margins_range 'let s = phys.system("nsc"); s.collision_margins(0.5, 0.0);' "must be in"
expect_error force_fixed 'let s = phys.system("nsc"); let g = s.ground("g"); g.force("1.0", "0.0", "0.0");' "is fixed"
expect_error force_expr 'let s = phys.system("nsc"); let a = s.sphere("a", 0.1, 1.0); a.force("1 +* t", "0.0", "0.0");' "expression"
expect_error force_late 'let s = phys.system("nsc"); let a = s.sphere("a", 0.1, 1.0); s.step(); a.force("1.0", "0.0", "0.0");' "after the simulation has started"
expect_error every_bad 'let s = phys.system("nsc"); s.record_every(0);' "must be in"
expect_error every_late 'let s = phys.system("nsc"); s.step(); s.record_every(5);' "after the simulation has started"
expect_error assertfail 'phys.assert_close(1.0, 2.0, 0.1);' "assert_close failed"
expect_error nanfriction 'let s = phys.system("nsc"); s.material("m", sqrt(-1.0), 0.5);' "friction >= 0"
expect_error matredefine 'let s = phys.system("nsc"); s.material("m", 0.5, 0.0); s.floor("f", "m"); s.material("m", 0.9, 0.0);' "already attached"
expect_error diverged 'let s = phys.system("nsc"); s.gravity(0.0, 0.0, 0.0); let g = s.ground("g"); let a = s.sphere("a", 0.1, 1.0).pos(1.0, 0.0, 0.0); let m = s.motor_speed("m", g, a, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, "sqrt(-1)"); s.run(0.1);' "diverged: body 'a'"
expect_error singular 'let s = phys.system("nsc"); s.integrator("hht"); let g = s.ground("g"); let a = s.box("a", 1.0, 0.1, 0.1, 100.0).pos(0.5, 0.0, 0.0); let r1 = s.revolute("r1", g, a, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0); let r2 = s.revolute("r2", g, a, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0); s.step();' "factorization failed"
expect_error nsc_direct 'let s = phys.system("nsc"); s.integrator("hht"); s.floor("f", "default"); let b = s.sphere("b", 0.1, 500.0).pos(0.0, 0.0, 0.3).collide("default"); s.run(1.0);' "nsc contact needs a complementarity solver"
ok "errors stop the program with exit 3 and a clear message (32 cases)"

# Determinism without lmplot: a contact run that records every step gives byte-identical CSV twice.
cat >"$WORK/det.lms" <<LMS
p = _dsl_ cli="lmphysics";
let s = phys.system("nsc");
s.material("r", 0.3, 0.8).timestep(0.001);
s.floor("floor", "r");
let b = s.sphere("b", 0.1, 500.0).pos(0.0, 0.0, 1.0).vel(0.5, 0.2, 0.0).omega(1.0, 0.0, 3.0).collide("r");
let c = s.box("c", 0.2, 0.3, 0.1, 300.0).pos(0.3, 0.0, 0.5).rot_axis(1.0, 1.0, 0.0, 0.4).collide("r");
s.record("b", "x,y,z,vx,vy,vz,wx,wy,wz").record("c", "x,y,z,qw,qx,qy,qz");
s.run(2.0);
s.save_csv("$WORK/det.csv");
end _dsl_
savedsl(p, "$WORK/det.dslb");
LMS
"$LMSCRIPT" "$WORK/det.lms" >/dev/null || fail "determinism program compile"
"$HOST" --dsl "$WORK/det.dslb" >/dev/null 2>&1 || fail "determinism run 1"
mv "$WORK/det.csv" "$WORK/det1.csv"
"$HOST" --dsl "$WORK/det.dslb" >/dev/null 2>&1 || fail "determinism run 2"
mv "$WORK/det.csv" "$WORK/det2.csv"
[ "$(wc -l <"$WORK/det1.csv" | tr -d ' ')" = 2002 ] || fail "determinism CSV has $(wc -l <"$WORK/det1.csv") lines, expected 2002"
cmp -s "$WORK/det1.csv" "$WORK/det2.csv" || fail "contact CSV differs between two identical runs"
ok "a recorded contact run is byte-identical on rerun"

# Memory budget: a runaway loop stops with a run error (exit 3, message on stderr and in the JSON line)
# instead of exhausting the machine. The fastest runaway here is the step recording (2048 columns, so
# 16 KiB per step): a small budget everywhere; on Linux also the default 4096 MiB under a 6 GiB
# address-space limit (ulimit only here, never in the host; ~30 s). Then a budget that the bodies fit
# in but the first contact step does not: the failure inside Chrono/Bullet reaches the step's error.
cat >"$WORK/runaway.lms" <<LMS
p = _dsl_ cli="lmphysics";
let s = phys.system("nsc");
s.gravity(0.0, 0.0, 0.0);
let a = s.sphere("a", 0.1, 1.0);
let cols = "x";
for (i in range(0, 11)) { cols = cols + "," + cols; }
s.record("a", cols);
while (true) { s.run(s.time() + 1.0); }
end _dsl_
savedsl(p, "$WORK/runaway.dslb");
LMS
"$LMSCRIPT" "$WORK/runaway.lms" >/dev/null || fail "runaway.lms compile"
set +e; out="$(LMPHYSICS_MAX_MEMORY_MB=64 "$HOST" --dsl "$WORK/runaway.dslb" 2>"$WORK/runaway.err")"; code=$?; set -e
[ "$code" = 3 ] || fail "runaway loop under LMPHYSICS_MAX_MEMORY_MB=64: exit $code, expected 3 ($out)"
echo "$out" | grep -q "memory budget exceeded" || fail "runaway loop: JSON lacks the budget message: $out"
grep -q "LMPHYSICS_MAX_MEMORY_MB" "$WORK/runaway.err" || fail "runaway loop: no budget message on stderr"
set +e; LMPHYSICS_MAX_MEMORY_MB=-5 "$HOST" --dsl "$WORK/runaway.dslb" >/dev/null 2>"$WORK/badenv.err"; code=$?; set -e
[ "$code" = 2 ] && grep -q "positive whole number" "$WORK/badenv.err" || fail "bad LMPHYSICS_MAX_MEMORY_MB: exit $code"
cat >"$WORK/stepmem.lms" <<LMS
p = _dsl_ cli="lmphysics";
let s = phys.system("nsc");
s.floor("f", "default");
for (i in range(0, 20000)) { let b = s.sphere("b" + str(i), 0.1, 1.0).pos(float(i % 1000) * 0.3, float(i / 1000) * 0.3, 0.09).collide("default"); }
s.step();
end _dsl_
savedsl(p, "$WORK/stepmem.dslb");
LMS
"$LMSCRIPT" "$WORK/stepmem.lms" >/dev/null || fail "stepmem.lms compile"
set +e; out="$(LMPHYSICS_MAX_MEMORY_MB=50 "$HOST" --dsl "$WORK/stepmem.dslb" 2>/dev/null)"; code=$?; set -e
[ "$code" = 3 ] && echo "$out" | grep -q "step failed at t = 0: memory budget exceeded" || fail "budget exceeded inside a contact step: exit $code ($out)"
if [ "$UNAME_S" = Linux ]; then
  set +e; out="$(ulimit -v 6291456; "$HOST" --dsl "$WORK/runaway.dslb" 2>/dev/null)"; code=$?; set -e
  [ "$code" = 3 ] && echo "$out" | grep -q "limit 4096 MiB" || fail "runaway loop with the default budget under ulimit -v 6 GiB: exit $code ($out)"
  ok "memory budget: runaway recording stops at 64 MiB and at the default 4096 MiB (under ulimit -v 6 GiB); a step past it is a step error"
else
  ok "memory budget: runaway recording stops at LMPHYSICS_MAX_MEMORY_MB=64, a step past it is a step error (default-budget run is Linux-only)"
fi

set +e; "$HOST" --dsl "$WORK/does-not-exist.dslb" >/dev/null 2>&1; code=$?; set -e
[ "$code" = 3 ] || fail "missing bytecode exit code $code, expected 3"
set +e; "$HOST" >/dev/null 2>&1; code=$?; set -e
[ "$code" = 2 ] || fail "usage exit code $code, expected 2"
ok "usage and load errors use exit codes 2 and 3"

echo "all $pass checks passed"
