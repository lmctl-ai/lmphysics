# lmphysics durable memory

- `01-purpose-and-place.md` — what lmphysics is, scope, relation to the family.
- `02-libraries-and-licenses.md` — Chrono core, bundled third-party code, Eigen, how it is built and pinned, the upstream bug we work around.
- `03-schema-v0.md` — the `phys` API and its conventions.
- `04-numerics.md` — integrators, solvers, restitution, what is accurate and what is not.
- `05-build-run-test.md` — measurements and the checks in `test.sh`.
- `06-ci.md` — GitHub Actions and releases.
- `07-examples.md` — the example programs and what they taught.
- `08-open-items.md` — what is not done.
- `09-resource-limits.md` — the total memory budget (`LMPHYSICS_MAX_MEMORY_MB`) and how it is counted.
- `10-linux-glibc.md` — dynamic system-glibc baseline, static dependency policy and release verification.
- `pose-render-bridge.md` — integration between physical simulation bodies and visual renderers (lmcad, lmdraw).

## Adding an example or function
- **New example**: Add `examples/<name>.lms` using `_dsl_ cli="lmphysics" install="github:lmctl-ai/lmphysics@latest"`. Output plots or CSVs to `images/` or stdout. Add golden checks in `test.sh` and update `README.md` gallery with `<img src="...">` and `lmctl autorun <raw .lms URL>` caption.
- **New host function**: Declare in `schema/lmphysics.dsl.json`, register in `src/registry.cpp` via `dslvm::Registry`, and verify `test.sh` passes (`--dsl-schema` and `--dsl-signatures` match compiler output).

## Releases
Releases are cut automatically on push to `main` when CI workflows pass all platforms.

