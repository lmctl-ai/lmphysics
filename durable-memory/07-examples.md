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
