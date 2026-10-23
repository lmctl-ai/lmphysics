# Numerics: what is accurate

Measured on Linux x86-64 (errors are what the test programs assert, with margin).

| scenario | integrator | result |
| --- | --- | --- |
| free fall z(t) | `trapezoidal` | exact to 1e-12 (constant acceleration) |
| free fall z(t) | `euler` (default) | error g dt t / 2 = 4.9e-3 at dt = 1 ms, t = 1 s (first order) |
| spring-mass, 2 s, dt 1 ms | `trapezoidal` | x error 1.5e-4, energy drift 2.6e-8 |
| damped oscillator | `trapezoidal` | error 8e-6 (euler: 1e-3) |
| revolute pendulum, quarter period | `hht` | within 5e-4 relative of the elliptic-integral value (115 degrees) |
| pendulum energy over 5 s | `trapezoidal` | **loses 2 %** (Chrono's constraint treatment); `hht`: 3e-7 |
| torque-free asymmetric box, 10 s | `trapezoidal` | |L| and KE conserved to 1e-9; `euler` gains 2e-3 |
| motor_speed 2.5 rad/s, 2 s | any | angle exact to ~1e-6 |
| slider-crank (3 revolute-like joints + guide) | `trapezoidal` | slider x within 2e-5 of closed form, motor angle lags 3.5e-4 (redundant constraints) |
| block on 30 degree incline | NSC and SMC | a = g (sin - mu cos) to 1e-4 relative; sticks when tan > mu |
| sphere rolling down 0.3 rad incline, psor 300 | NSC | a = 5/7 g sin to 1e-5 relative, v = w r |
| cylinder rolling down the same incline | NSC | a = 2/3 g sin within -2.2 % (x86-64) / +6.5 % (macOS arm64): Bullet cylinder-box contact; asserted to 10 % |

## Integrator choices

- `hht` / `newmark` need a direct solver and a Newton budget; `Phys.integrator("hht")` presets
  `sparse_lu`, 30 iterations, rtol 1e-6, atol 1e-9 (Chrono's defaults of 6 iterations fail with
  "HHT: Reached minimum allowable step size"). Not compatible with NSC contact (use SMC) and fails
  ("zero diagonal" from the LU) on mechanisms with redundant constraints such as a planar linkage
  built from 3D revolute joints; use `trapezoidal` with PSOR there. HHT is slightly dissipative (alpha -0.2
  default, `hht_alpha`), so it is not exact for free fall.
- Everything else uses the NSC/PSOR default solver unless `solver()` says otherwise.

## Restitution (NSC) and the collision margins

Chrono applies the Newton rebound model only if the ball would still be penetrating after the rebound within the
step. With the default 3 cm collision envelope and 1 cm margin a contact exists before the shapes touch, so the
step ends exactly in touch (absorbing up to `(1 - e)` of the approach speed) and the rebound happens a step later from
the reduced speed: the effective coefficient lies in `[e^2, e]` depending on the impact phase, independent of dt (a
ball with e = 0.5 reached 0.07 m instead of 0.25 m). `System.collision_margins(0, 0)` removes the early contact:
apex = e^2 h to 1 % (0.248 and 0.0613 m for e = 0.5 from 1 m, tested). The price: boxes stacked three high with a
sphere on top collapse with envelope 0 (they are stable with the defaults and with envelope >= 5 mm and margin 0 the
restitution gain is lost), so the margins are opt-in. Only envelope AND margin at 0 fixes restitution; Chrono keeps both
as process-wide statics read when a body's collision model is created and when the step binds it, so the host sets
them around every body creation and step of an NSC system (`MarginGuard`). SMC restitution (Hertz damping derived from
`e`) gives an apex ratio of about 0.78 for e = 0.8; not asserted.

## Friction hop

Chrono's cone-complementarity friction keeps a sliding body `mu |v| dt` above the floor (the Anitescu relaxation). A
block that starts exactly in contact therefore gets an upward speed `mu |v|` on the first step and hops (0.14 m for
mu = 0.3, 5.5 m/s, 2 ms steps). Start it a few millimetres above the floor, or start it at rest, or use a smaller dt; once
the contact has been established the block slides at a constant gap of `mu |v| dt` (2.9 mm in that example) and the
friction oracles (stopping distance v^2 / (2 mu g), a = g (sin - mu cos)) hold to 1e-4.

## Determinism

Single thread (`SetNumThreads(1)`, OpenMP off). Same program twice gives byte-identical CSV on
one machine. Across platforms (x86 FMA, arm64) expect last-digit differences; contact tests
assert tolerances, never exact numbers.

## Applied loads, recording

`Body.force/torque` take three expressions in t (world frame, force at the centre of mass) and use Chrono's `ChForce`
with `WORLD_DIR`. Tested: F = 3 N on 2 kg gives x = F t^2 / 2m to 1e-4; torque about z gives w = tau t / I; a driven damped
oscillator reaches the analytic steady-state amplitude F0 / sqrt((k - m w^2)^2 + (c w)^2) within 2 % at 49 frequencies
(`viz_resonance.lms`). `record_every(n)` keeps every n-th step and `save_csv` always appends the final state.

## HHT details

The double pendulum (two revolute joints) is chaotic: with `hht_alpha(0)` (no numerical damping) HHT diverged at 6.9 s;
the default alpha keeps the energy to 2e-5 over 12 s. Two runs a micro-radian apart separate by one e-fold per ~0.8 s.

## Contact geometry accuracy (measured 2026-10-23)

- Tipping over an edge: with the default NSC envelope/margin (3 cm / 1 cm) a 40 cm block with its centre of mass
  1 or 2 cm past a table edge rests indefinitely; with collision_margins(0.002, 0.001) it tips at 1 cm and rests at 0.
- Rolling cylinder (r 10 cm, 15 deg ramp, mu 0.6) after 4 s: 1.02 (margins 0), 1.03 (dt 1e-4), 0.73 (APGD 150),
  0.95 (PSOR 1000) of the closed-form distance; a sphere is exact to 1e-3.
- Body.drag: explicit per step through the force accumulator; terminal speed exact, exponential approach to 0.1% at dt 5e-4.
