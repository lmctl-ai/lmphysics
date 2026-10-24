# Purpose and place

lmphysics is the `lmphysics` entry of the *scripted scientific libraries* family
(`../../simulation/ROADMAP.md`, `../../simulation/FEASIBILITY.md` section "Recommendation 2"):
Project Chrono's core module, statically linked into one executable and driven from lmscript `_dsl_`
bytecode through an embedded schema. Script = policy and control flow, host = heavy code.

- **Scripting only.** No user CLI beyond `--dsl`, `--dry-run`, `--version`, `--notices`,
  `--dsl-schema [--json]`, `--dsl-signatures` (exit codes 2 usage, 3 load/run error).
- **Chrono, not Bullet.** The feasibility note allowed a fallback to Bullet if Chrono could not be
  built statically on all platforms. It can: the core module needs only Eigen, builds in ~4 min on
  4 cores, and yields one Linux executable (dynamic glibc >= 2.35, static scientific/C++ code). Chrono already provides joints, motors, TSDAs
  and NSC/SMC contact; an own solver on top of Bullet would have been the bigger project.
- **Scope (v0.1)**: NSC and SMC systems; box, sphere, cylinder bodies with computed inertia; fixed
  bodies; revolute, prismatic, spherical, lock, distance joints; TSDA spring-damper; rotational motors
  with speed or angle given as an expression in `t`; contact materials; fixed-step integration with
  several Chrono integrators; per-step CSV recording of body and joint quantities.
- **Not in scope**: meshes and mesh collision, FEA, vehicles, granular/multicore, visualization,
  other Chrono modules, OpenMP (single thread keeps runs deterministic).
- Programs bind with `_dsl_ cli="lmphysics" install="github:lmctl-ai/lmphysics@latest";`.

## Scope boundary (DSL has no lists, maps or closures)

- bodies and joints are host objects with chained builder methods; they are referenced by object,
  and by name for `record`;
- functions are expression strings in `t` (`cpp/expr.hpp`, copied from lmnum);
- results leave as CSV (`System.save_csv`); lmplot draws it (see `examples/combo/bounce_plot.lms`).
