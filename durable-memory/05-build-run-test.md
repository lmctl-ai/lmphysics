# Build, run, test

```sh
scripts/sync-deps.sh && cmake -S . -B build -G Ninja && cmake --build build && ./test.sh
```

Measured (WSL2, 4 cores, g++ 11.4): clean build of Chrono core + host ~4 min (479 translation
units); binary 9.8 MB static, stripped, no dynamic loader.

`test.sh` checks (18 numbered checks; 7 programs: 3 tests + 4 examples, + the combo example when
lmplot or the network is available):
1. SDK header and `third_party/` match their pins;
2. build; `--version` is exactly `lmphysics 0.1.0`;
3. schema file is what `gen-schema.py` regenerates; embedded schema bytes equal the file; the host
   registry equals `lmscript --dsl-signatures`;
4. `--notices` contains the Chrono text; no dynamic linking (Linux), only system libs (macOS),
   no MinGW runtime DLLs (Windows);
5. every program under `tests/` and `examples/` compiles to bytecode v5 and runs with `"ok": true`;
   they assert their own physics (closed forms, textbook values; see `04-numerics.md`);
6. CSV outputs are byte-identical when the examples are re-run, and a recorded two-body contact run
   written twice by test.sh itself is byte-identical (also without lmplot); `--notices` equals the file;
7. 24 error cases exit 3 with a message naming the problem (bad kind, duplicate name, non-positive
   size, unknown material/body/column, late `record`, bad/unknown expression, same body twice, zero
   axis, mixed systems, `stiffness` on NSC, unknown solver/integrator, `newton` on a stepper without
   Newton, bad timestep, unwritable CSV, failed `assert_close`, NaN friction, redefining an attached
   material, a diverging (NaN) motor, a singular LU factorization, NSC contact under a linear solver);
8. memory budget (`09-resource-limits.md`): a runaway recording loop exits 3 at
   `LMPHYSICS_MAX_MEMORY_MB=64` and, on Linux, at the default 4096 MiB under `ulimit -v 6291456`
   (~30 s); 20000 contacting spheres at 50 MiB fail inside the first step with
   `step failed at t = 0: memory budget exceeded`; a bad variable value exits 2;
9. usage (exit 2) and missing bytecode (exit 3).
