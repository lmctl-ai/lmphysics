# Examples

| program | what it taught |
| --- | --- |
| `pendulum.lms` | Chrono's `trapezoidal` loses 2 % of the energy in 5 s on a joint (constraint handling); `hht` with a direct solver conserves it to 3e-7. Hence the `hht` preset. |
| `bouncing_ball.lms` | restitution is applied one step late (see `04-numerics.md`); also uncovered Chrono's uninitialized `min_bounce_speed`. |
| `incline.lms` | friction oracle works for NSC (PSOR) and SMC to 1e-4. |
| `slider_crank.lms` | a planar linkage of 3D joints is over-constrained: LU fails, PSOR works; closed-form slider position is a strong check of motor + joints. |
| `combo/bounce_plot.lms` | CSV hand-off to lmplot (needs lmplot on PATH or `LMPHYSICS_TEST_NETWORK=1`). |

The `tests/` programs (dynamics, joints, contact) hold the oracle checks: free fall, projectile,
spring and damped spring, energy, motors, torque-free rotation, pendulum periods against the AGM
elliptic integral, hanging reaction = m g, prismatic slide, rigid rod, bounce windows, incline,
resting contact.

## Pictures (VISUALS.md)

README starts with a gallery of 8 PNGs in `docs/images/` (<= 300 KB, ~900 px). Every image is produced by an
example script that is self-contained: `lmctl autorun <raw url>` in an empty directory runs the simulation
(`system ${dsl_cli(sim)} --dsl ...`), draws with lmplot and writes `images/<name>.png` plus scratch
`build/` under the current directory. `examples/render-all.sh` runs them all with `docs/` as the cwd to
refresh `docs/images/`. `test.sh` checks the gallery (files exist, PNG/GIF magic bytes, <= 3 MB), runs every
example in a scratch directory (needs lmplot: on PATH or `LMPHYSICS_TEST_NETWORK=1`, otherwise it prints
`SKIPPED` loudly) and compares the CSVs of a second run byte for byte.

New viz examples: `viz_pendulum_phase`, `viz_energy_drift`, `viz_damping`, `viz_restitution`. The old
examples (`pendulum`, `bouncing_ball`, `incline`, `slider_crank`, `combo/bounce_plot`) now also draw.
Not done: 3D renders/animation with lmcad (its keyframe CSV needs `t,x,y,z,r,g,b`, which would need a
`save_keyframes` helper in lmphysics; see 08-open-items.md). Newton's cradle was tried: the rigid NSC solver
sends part of the momentum back, so it is not a clean demo.
