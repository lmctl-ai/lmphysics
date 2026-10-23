# Libraries and licenses

| component | version | license | role |
| --- | --- | --- | --- |
| Project Chrono core | 9.0.1 (commit 2617649b, pinned in `deps.lock`) | BSD-3-Clause | dynamics, joints, contact |
| Bullet collision (Chrono's renamed `cbt*` copy) | bundled | zlib | broad/narrow phase |
| GIMPACT | bundled | LGPL-2.1+ **or** BSD **or** zlib (triple): we take zlib | triangle-mesh collision, unreachable from the schema |
| HACD, HACDv2 (+ Newton Game Dynamics code) | bundled | BSD-3, MIT, zlib | convex decomposition, unreachable |
| tinyobjloader, libstl | bundled | MIT | mesh loading, unreachable |
| Eigen | pinned like lmnum (3147391d) | MPL-2.0, `EIGEN_MPL2_ONLY` | linear algebra |
| cpp-dsl-sdk `dslvm.hpp` | pinned in `sdk.lock` | MIT | DSL VM |

No GPL/AGPL code. The only copyleft-offered component (GIMPACT) is used under its zlib option; the
notice file says so. All texts are in `THIRD_PARTY_NOTICES`, embedded in the binary (`--notices`).

## How Chrono is built (cmake/Chrono.cmake)

Chrono's own top-level CMake copies its ~1 GB `data/` tree and probes OpenMP, CUDA, MPI, Thrust, ...
So `cmake/Chrono.cmake` does not use it: it generates `ChConfig.h` / `ChVersion.h` (every optional
feature `#undef`ed), sets the few variables `src/chrono/CMakeLists.txt` expects and `add_subdirectory`s
that file (target `ChronoEngine`, static, `CH_STATIC`). OpenMP off, SIMD probing off, no optional
modules. Chrono is therefore compiled unmodified; nothing of it is committed.

`scripts/sync-deps.sh` fetches Chrono as a partial, sparse clone (only `/src/` and `/LICENSE`,
~50 MB instead of 1.6 GB; extra words after the commit in `deps.lock` are the sparse paths).
Gotcha: `git ls-remote` lists the *tag object* for annotated tags; pin the peeled commit.

## Upstream bug we work around

`ChContactContainerNSC::min_bounce_speed` is not initialized in Chrono 9.0.1 (documented default:
0.15). Restitution then depends on heap garbage, so the same program gave different bounces when only a
file-path string in the bytecode changed length. `Phys.system("nsc")` always calls
`SetMinBounceSpeed(0.15)`; `System.bounce_speed(v)` changes it. Found with a path-length experiment,
MemorySanitizer was unusable (libstdc++ noise, and WSL2's ASLR needs `setarch -R`).
