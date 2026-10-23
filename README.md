# lmphysics

**Rigid-body physics (Project Chrono) in one static executable, driven from lmscript.**

[![CI](https://github.com/lmctl-ai/lmphysics/actions/workflows/ci.yml/badge.svg)](https://github.com/lmctl-ai/lmphysics/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

| ![pendulum_phase](docs/images/pendulum_phase.png) | ![energy_drift](docs/images/energy_drift.png) |
| --- | --- |
| Phase portrait of a pendulum on a joint: ellipses for small swings, the separatrix for large ones.<br>`lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmphysics/main/examples/viz_pendulum_phase.lms` | Energy error of one pendulum under three Chrono integrators: HHT conserves it, trapezoidal bleeds it.<br>`lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmphysics/main/examples/viz_energy_drift.lms` |

| ![damping](docs/images/damping.png) | ![restitution](docs/images/restitution.png) |
| --- | --- |
| Mass-spring-damper, four damping ratios, simulation on top of the closed form.<br>`lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmphysics/main/examples/viz_damping.lms` | A ball dropped for four coefficients of restitution.<br>`lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmphysics/main/examples/viz_restitution.lms` |

| ![slider_crank](docs/images/slider_crank.png) | ![incline](docs/images/incline.png) |
| --- | --- |
| Slider-crank mechanism driven by a motor: slider position vs closed form.<br>`lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmphysics/main/examples/slider_crank.lms` | Friction on a 30 degree ramp: sliding at g(sin - mu cos), sticking when tan < mu.<br>`lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmphysics/main/examples/incline.lms` |

| ![pendulum](docs/images/pendulum.png) | ![bounce](docs/images/bounce.png) |
| --- | --- |
| Revolute pendulum: joint angle and the reaction force at the pin.<br>`lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmphysics/main/examples/pendulum.lms` | A bouncing ball, simulated by lmphysics and drawn by lmplot in one script.<br>`lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmphysics/main/examples/combo/bounce_plot.lms` |

Every picture is made by the script named under it: the script runs the simulation with lmphysics, draws with [lmplot](https://github.com/lmctl-ai/lmplot) and writes `images/` into the current directory. `examples/render-all.sh` regenerates `docs/images/`.

It is a scripting host, not a command-line tool: write an [lmscript](https://lmctl.com/tools/lmscript/skill.html) `_dsl_` block and run it. No Python, no data files, no shared libraries.

```
# pendulum.lms
p = _dsl_ cli="lmphysics" install="github:lmctl-ai/lmphysics@latest";
let s = phys.system("nsc");
s.integrator("hht").timestep(0.0005);
let pin = s.ground("pin");
let bob = s.sphere("bob", 0.05, 2000.0).pos(0.866, 0.0, -0.5);       # released at 60 degrees
let hinge = s.revolute("hinge", pin, bob, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0);
s.record("bob", "x,z,vx,vz").record("hinge", "angle,fx,fz");
let e0 = s.energy();
s.run(5.0);
phys.assert_close(s.energy() / e0, 1.0, 0.0001);                     # energy is conserved
s.save_csv("pendulum.csv");
end _dsl_
savedsl(p, "pendulum.dslb");
system ${dsl_cli(p)} --dsl pendulum.dslb;
```

`lmscript pendulum.lms` finds `lmphysics` on `PATH` or downloads the release binary for your
platform on first use, compiles against the schema built into it, and runs the program.

## What it does

The world is a `System` (`phys.system("nsc")` for non-smooth contact with complementarity, or
`"smc"` for penalty contact). It owns named `Body` and `Joint` objects created by chained
builder calls; the DSL has no lists or closures, so time functions are expression strings in `t`
(`"2.5"`, `"0.5*sin(3*t)"`) and results leave as a CSV. The world is right-handed with
gravity `(0, 0, -9.81)` by default; lengths in m, masses in kg, angles in rad.

| `phys.` | |
| --- | --- |
| `system("nsc"\|"smc")` | new world |
| `assert_close(a, b, tol)` `print(text)` `version()` | checks and output |

| `System.` | |
| --- | --- |
| `gravity(x,y,z)` `timestep(dt)` `integrator(name)` `solver(name, iters)` `newton(iters, rtol, atol)` `hht_alpha(a)` | numerics |
| `material(name, friction, restitution)` `stiffness(name, young, poisson)` | contact materials (`"default"` always exists) |
| `ground(name)` `box(name, sx,sy,sz, density)` `sphere(name, r, density)` `cylinder(name, r, h, density)` `floor(name, material)` | bodies (cylinder axis is local y; `floor` is a fixed collision slab with its top at z = 0) |
| `revolute` `prismatic` (`name, A, B, px,py,pz, ax,ay,az`) `lock` `spherical` (`name, A, B, px,py,pz`) `distance` (`name, A, B, ax,ay,az, bx,by,bz`) | joints between bodies A and B; points and axes in world coordinates at creation |
| `spring(name, A, B, k, c, rest)` | linear spring-damper between the body centres |
| `motor_speed(name, A, B, px,py,pz, ax,ay,az, "expr(t)")` `motor_angle(...)` | rotational motor, speed or angle given as an expression |
| `record(name, "col,col")` `step()` `run(t_end)` `save_csv(path)` | fixed-step integration and logging (one CSV row per step) |
| `time()` `energy()` `contacts()` | state queries |

`Body`: `pos(x,y,z)` `vel(x,y,z)` `rot_axis(ax,ay,az,angle)` `omega(x,y,z)` `fixed(bool)`
`mass_props(m, ixx,iyy,izz)` `collide(material)`, and readers `mass x y z vx vy vz wx wy wz lx ly lz speed ke`
(`l*` is angular momentum about the centre, world frame; `ke` kinetic energy).
`Joint`: `angle` (rotation of B about the joint axis since creation, unwrapped) `length` `force`
(spring force, otherwise reaction magnitude) `torque` and `reaction_x/y/z` (force on B, world frame).
Record columns are the same names, joints also `fx fy fz tx ty tz`. Schema and rules:
[durable-memory/03-schema-v0.md](durable-memory/03-schema-v0.md).

### Choosing numerics

| need | use |
| --- | --- |
| contact (NSC) | default `integrator("euler")` and PSOR; `solver("apgd", 200)` for stacks |
| smooth mechanisms, energy conservation | `integrator("hht")` (direct solver, Newton budget preset) |
| constant accelerations, springs without joints | `integrator("trapezoidal")` (exact for constant forces) |
| mechanisms with redundant constraints (planar linkage built from 3D joints) | `integrator("trapezoidal")` with PSOR |

Measured accuracies are listed in [durable-memory/05-build-run-test.md](durable-memory/05-build-run-test.md).

Combine it with other hosts in one script: [examples/combo/bounce_plot.lms](examples/combo/bounce_plot.lms)
simulates a bouncing ball with lmphysics and draws the trajectory with
[lmplot](https://github.com/lmctl-ai/lmplot) (two `_dsl_` blocks, two hosts).

## Build

C++17 compiler, CMake 3.24, git; nothing else.

```sh
scripts/sync-deps.sh            # Eigen and Chrono at the commits in deps.lock (Chrono: sparse partial clone of src/, ~50 MB)
cmake -S . -B build && cmake --build build
./test.sh                       # needs lmscript on PATH
```

Linux builds are fully static; macOS links only system libraries; Windows links the MinGW runtime
statically. `lmphysics --notices` prints the license texts of everything inside.

## Resource limits

A program may use at most 4096 MiB in total (bodies, joints, recorded steps, Chrono and Bullet state,
everything the host keeps); beyond that it stops with a run error (exit 3) naming the limit, instead
of exhausting the machine. Set `LMPHYSICS_MAX_MEMORY_MB` to change it, e.g.
`LMPHYSICS_MAX_MEMORY_MB=16384 lmscript long_run.lms`. Every recorded step costs 8 bytes per column.

## License

MIT ([LICENSE](LICENSE)). Project Chrono is BSD-3-Clause, its bundled Bullet collision code is zlib,
Eigen is MPL-2.0 (used with `EIGEN_MPL2_ONLY`, unmodified); see [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES).
