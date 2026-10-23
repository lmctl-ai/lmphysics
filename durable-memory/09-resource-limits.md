# Resource limits

Why: host objects (systems, bodies, joints, recorded steps) live until exit, and `System.run`
records every step (up to 5e7 steps per call), so a DSL loop could grow without bound. On
2026-10-23 a runaway lmnum process reached 16 GB RSS and filled the 24 GB WSL machine; every lm*
host now has a total budget.

- **Total memory budget**, default 4096 MiB, set with `LMPHYSICS_MAX_MEMORY_MB` (positive whole
  MiB; anything else exits 2 with the usage text). Shown in the usage message.
- `cpp/memory_budget.{hpp,cpp}` (identical copy in every lm* host) replaces the global
  `operator new`/`delete` and counts block sizes from the C allocator. Exceeding the budget throws
  `membudget::Exceeded` (a `std::bad_alloc`); the first failure prints
  `lmphysics: memory budget exceeded: ... (set LMPHYSICS_MAX_MEMORY_MB ...)` on stderr and the run
  ends with the usual JSON error, exit 3 (64 MiB of headroom is granted once for the error path).

How it is counted here:
- Chrono objects (ChSystem, ChBody, links, materials, collision shapes, contacts) and all
  std containers come from `operator new`: counted. Chrono's `EIGEN_MAKE_ALIGNED_OPERATOR_NEW`
  expands to nothing under C++17 (verified: `chrono_types::class_has_custom_new_operator` is false
  for ChBody, ChSystemNSC, the links and shapes), so no Chrono object bypasses the count.
- Bullet takes memory from `malloc` by default; `main` installs `cbtAlignedAllocSetCustom` with
  `::operator new`/`delete` before any Bullet object exists (Bullet's aligned allocator uses the
  same hook on all our platforms: `BT_HAS_ALIGNED_ALLOCATOR` is MSVC-only).
- Recorded steps are one flat `std::deque<double>` (8 bytes per value, grown in 512-byte blocks,
  no 3x peak of a doubling vector); before this, one `std::vector` per row cost ~56 bytes per step
  for a single column.
- Exceptions inside `DoStepDynamics` (Chrono and Bullet are C++, no C frames or `noexcept` on the
  path) reach `do_step`'s handler: `std::bad_alloc` becomes `step failed at t = ...: memory budget
  exceeded ...` (without the hht/newmark solver hint).
- Body/joint name lookup is a `std::set` now (was a linear scan, quadratic in a body loop).

Not covered: Eigen dynamic matrices inside Chrono use `malloc` (state vectors, the system
descriptor, the sparse LU's dense supernode blocks). They are O(degrees of freedom) per system and
mostly per-step temporaries; measured ~10-20% on top of the tracked bytes for body-heavy
programs (below). A pathological dense coupling could make the LU fill larger; not seen.
No `setrlimit` (not portable to macOS static builds).

Measured (x86_64 WSL2, Release):
- runaway recording (one sphere, 2048 recorded columns = 16 KiB/step, `run` in a `while`):
  64 MiB budget in 0.5 s (72 MB peak RSS); 1024 MiB in 8.8 s (1.05 GB RSS); default 4096 MiB in
  27 s with 4.16 GB peak RSS. `test.sh` runs 64 MiB everywhere and the default on Linux only,
  under `ulimit -v 6291456`.
- runaway body creation (colliding spheres): 1024 MiB budget reached in 13 s, 1.18 GB peak RSS.
- 200000 colliding spheres on a floor, one step: ~650 MiB tracked, 747 MB peak RSS; 20000 spheres
  need 30-40 MiB to create and ~70 MiB for the first step, so test.sh's 50 MiB fails inside the
  step.
