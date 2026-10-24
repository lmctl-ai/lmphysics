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

## Pictures

The README opens with 16 images in `docs/images/`, grouped by theme. Every image is made by a self-contained example:
`lmctl autorun <raw url>` in an empty directory runs the simulation (`system ${dsl_cli(sim)} --dsl ...`), draws, and
writes `images/<name>.png` plus scratch files under `build/`. `examples/render-all.sh` runs all of them with `docs/` as the
working directory to refresh `docs/images/`.

| example | picture | story and check |
| --- | --- | --- |
| `viz_double_pendulum` | double_pendulum.png | chaos: two runs 1e-6 rad apart separate exponentially; energy conserved to 1e-3 (HHT) |
| `anim_double_pendulum` | double_pendulum.gif | the same system animated: lmdraw frame per 50 ms from the CSV, ffmpeg palette GIF |
| `viz_pendulum_phase` | pendulum_phase.png | phase portraits up to a release angle of 3.0 rad |
| `viz_energy_drift` | energy_drift.png | integrator comparison on one joint pendulum |
| `pendulum`, `slider_crank` | pendulum.png, slider_crank.png | joint reaction force; closed-form slider position |
| `viz_crank_snapshots` | crank_snapshots.png | lmdraw drawing of the linkage at 4 crank angles from the simulated numbers |
| `viz_restitution`, `combo/bounce_plot` | restitution.png, bounce.png | exact e^2 apexes with `collision_margins(0, 0)` |
| `incline`, `viz_incline_forces` | incline.png, incline_forces.png | a = g (sin - mu cos), sticking when tan < mu; free-body diagram (lmdraw) |
| `viz_friction_stop` | friction_stop.png | 40 sliding distances against v0^2 / (2 mu g) |
| `viz_pour` | pour.png | 40 balls settled in a box; lmscript turns the final CSV row into an lmcad keyframe file |
| `viz_damping`, `viz_resonance`, `viz_projectile` | damping.png, resonance.png, projectile.png | closed-form checks for oscillators and ballistics |

How the hosts talk: sweeps print one line per case with `phys.print`; lmscript saves `r.stdout` and lmplot reads the file
(`every ::0::N` skips the final JSON status line). lmscript has `csv_parse(read_file(..))`, `write_file`, `copy_file`,
`sprintf` (no `%e`), `sqrt`/`abs`, no trig, no `split`. `${x}` substitutes an integral number as an int literal, so wrap
with `+ 0.0001` or `float()` where the DSL wants a float. `plot.data` silently truncates large strings (about 8-11 KB seen):
write a file and read it from gnuplot instead. lmdraw may only write under `build/rendered/` (copy_file to `images/`),
and its `end _dsl_` line must start at column 1 even inside a loop. lmcad's `read_keyframes_csv` (header
`t,x,y,z,r,g,b`) doubles as a point-list reader. Chrono's y/z differ from lmcad's (y up): map (x, y, z) to (x, z, y).

`test.sh` checks the gallery (PNG/GIF magic, <= 3 MB, linked examples exist), runs the examples in a scratch directory
when lmplot is available (`LMPHYSICS_TEST_NETWORK=1`; the anim example is skipped loudly without ffmpeg) and compares the
CSVs of a second run byte for byte.

## Worked-problem examples (2026-10-23 verification pass)

Seventeen scripts, each a story with a known answer checked inside the script:
rolling_race (a = g sin / (1 + I/m r^2), spheres carry cylinder/hoop inertia because Bullet's cylinder contact
rolls 2-5% off), bowling_skid (skid 2 v0 / 7 mu g, then 5/7 v0; lmdraw FBD + chart), newtons_cradle (lmplot +
Cycles; 0.5 mm gaps, margins 0), harmonic_overhang (needs collision_margins(0.002, 0.001): with defaults a box 2 cm
past an edge does not tip), domino_cascade (wave ~ sqrt(g h); tilt-onset criterion 10 deg because close dominoes
lean and never reach 45), chain_whip + anim_chain_whip (tip 8.5 m/s vs 4.75 free fall), gyroscope (precession
m g d / I w, nutation 1/w^2), tennis_racket (intermediate-axis flips, filmstrip), coupled_pendulums (beats
pi/(w2 - w1)), four_bar_linkage (rocker limits by the law of cosines, trapezoidal + PSOR), billiards_90,
wrecking_ball (pyramid with APGD and default margins), and four that need v0.1.2: projectile_drag (Body.drag),
quarter_car (motor_position + spring_at), gear_train (gear + effort), cardan_joint (universal).

lmscript pitfalls met while writing them:
- no sin/cos/atan outside `_dsl_` blocks: the pose bridge carries `pose_sincos`; four_bar_linkage has `atan2s`;
- `${x}` writes an integral float (0.0) as an int literal, so a float parameter fails to compile; round to whole
  pixels and use `float(${xi})`, or nudge by 1e-6 (1e-7 has no literal form);
- CSV values from csv_parse may be strings (exponent form): wrap with `num()`;
- a variable named `cmd` inside a fn was parsed as a shell command; use another name.
