# Open items

- Mesh/convex-hull bodies and collision (needs file loading and the GIMPACT/HACD code paths; license
  note in `02-...` already covers them).
- Linear motors and actuated TSDAs; force/torque expressions applied to bodies.
- Chrono's `Joint` kinds not exposed: cylindrical, planar, point-line, universal, gears, belts.
- Body-local joint anchors for `spring` (now body centres only).
- NSC restitution accuracy (see `04-numerics.md`): could expose the envelope/margin or substep.
- Reproducibility across platforms is tolerance-based; no cross-platform byte-identical guarantee.
- `System.save_keyframes(path, body, every, r,g,b)` (t,x,y,z,r,g,b CSV) so lmcad can render and animate bodies; rotations would need a richer lmcad keyframe format.
- Newton non-convergence of hht/newmark/euler_implicit/trapezoidal steps is accepted silently (Chrono, step
  control off); see `04-numerics.md` for why a simple iteration-count check gives false alarms.
- A `spring` between bodies whose centres coincide has no direction; Chrono picks one silently.
