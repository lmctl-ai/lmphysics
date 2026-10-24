# Build, run, test

```sh
scripts/sync-deps.sh && cmake -S . -B build -G Ninja && cmake --build build && ./test.sh
```

Measured (WSL2, 4 cores, g++ 11.4): clean build of Chrono core + host ~4 min (479 translation
units); Linux links system glibc dynamically (>= 2.35), keeping Chrono, Bullet, Eigen and GCC C++ runtimes static.

`test.sh` checks (19 numbered checks; 5 DSL test programs and 35 self-contained examples when
lmplot or the network is available):
1. SDK header and `third_party/` match their pins;
2. build; `--version` is exactly `lmphysics 0.1.3`;
3. schema file is what `gen-schema.py` regenerates; embedded schema bytes equal the file; the host
   registry equals `lmscript --dsl-signatures`;
4. `--notices` contains the Chrono text; glibc dependency/ABI allowlist (Linux), only system libs (macOS),
   no MinGW runtime DLLs (Windows);
5. every program under `tests/` and `examples/` compiles to bytecode v5 and runs with `"ok": true`;
   they assert their own physics (closed forms, textbook values; see `04-numerics.md`);
6. CSV outputs are byte-identical when the examples are re-run, and a recorded two-body contact run
   written twice by test.sh itself is byte-identical (also without lmplot); `--notices` equals the file;
7. 40 error cases exit 3 with a message naming the problem (including bad kind, duplicate name, non-positive
   size, unknown material/body/column, late `record`, bad/unknown expression, same body twice, zero
   axis, mixed systems, `stiffness` on NSC, unknown solver/integrator, `newton` on a stepper without
   Newton, bad timestep, unwritable CSV, failed `assert_close`, NaN friction, redefining an attached
   material, a diverging (NaN) motor, a singular LU factorization, NSC contact under a linear solver);
8. memory budget (`09-resource-limits.md`): a runaway recording loop exits 3 at
   `LMPHYSICS_MAX_MEMORY_MB=64` and, on Linux, at the default 4096 MiB under `ulimit -v 6291456`
   (~30 s); 20000 contacting spheres at 50 MiB fail inside the first step with
   `step failed at t = 0: memory budget exceeded`; a bad variable value exits 2;
9. usage (exit 2) and missing bytecode (exit 3).

Current v0.1.3 Linux verification: all 19 checks pass, with 40 gallery images validated, 35 example runs, 106 deterministic result files and 40 error cases. The Linux x64 executable is 9,408,352 bytes stripped, needs only libm.so.6, libc.so.6 and ld-linux-x86-64.so.2, and has maximum GLIBC_2.34 (supported baseline glibc >= 2.35). Separate fresh-directory pendulum, bounce and gear-train README runs passed using the built binary and published lmplot v0.2.1.
