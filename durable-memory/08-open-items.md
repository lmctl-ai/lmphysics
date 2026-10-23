# Open items

- Mesh/convex-hull bodies and collision (needs file loading and the GIMPACT/HACD code paths; license
  note in `02-...` already covers them).
- Linear motors and actuated TSDAs; force/torque expressions applied to bodies.
- Chrono's `Joint` kinds not exposed: cylindrical, planar, point-line, universal, gears, belts.
- Body-local joint anchors for `spring` (now body centres only).
- Per-step recording is every step; a `record_every(n)` would shrink long runs.
- NSC restitution accuracy (see `04-numerics.md`): could expose the envelope/margin or substep.
- Reproducibility across platforms is tolerance-based; no cross-platform byte-identical guarantee.
