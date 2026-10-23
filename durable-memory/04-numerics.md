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
| cylinder rolling down the same incline | NSC | a = 2/3 g sin within 2.2 % (Bullet cylinder-box contact; asserted to 4 %) |

## Integrator choices

- `hht` / `newmark` need a direct solver and a Newton budget; `Phys.integrator("hht")` presets
  `sparse_lu`, 30 iterations, rtol 1e-6, atol 1e-9 (Chrono's defaults of 6 iterations fail with
  "HHT: Reached minimum allowable step size"). Not compatible with NSC contact (use SMC) and fails
  ("zero diagonal" from the LU) on mechanisms with redundant constraints such as a planar linkage
  built from 3D revolute joints; use `trapezoidal` with PSOR there. HHT is slightly dissipative (alpha -0.2
  default, `hht_alpha`), so it is not exact for free fall.
- Everything else uses the NSC/PSOR default solver unless `solver()` says otherwise.

## Restitution (NSC) is not a precise oracle

Chrono applies the Newton rebound model only if the ball would still be penetrating after the
rebound within the step, otherwise the step ends exactly in touch, absorbing up to
`(1 - e)` of the approach speed, and the rebound at the next step starts from the reduced speed. The
effective coefficient lies in `[e^2, e]` depending on the impact phase, independent of dt, so apex
heights shrink by a factor in `[e^4, e^2]` per bounce. Tests assert that window, not 0.64. SMC
restitution (Hertz damping derived from `e`) gives ratio ~0.78 for e = 0.8 (apex ratio 0.61 for the second bounce); not asserted.

## Newton convergence is not reported

HHT with the host preset (30 iterations, rtol 1e-6, atol 1e-9, step control off) routinely ends a step
"unconverged": in the 115 degree pendulum |R| is 1e-20 but the constraint residual stalls at 1.8e-9 > atol and
the WRMS update oscillates around 1.6 (round-off). Chrono then accepts the step silently. Treating that as an
error would reject correct runs, so the host does not check Newton convergence (open item: a residual-based
check would need Chrono internals that are not exposed).

## Determinism

Single thread (`SetNumThreads(1)`, OpenMP off). Same program twice gives byte-identical CSV on
one machine. Across platforms (x86 FMA, arm64) expect last-digit differences; contact tests
assert tolerances, never exact numbers.
