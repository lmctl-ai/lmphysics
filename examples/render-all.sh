#!/usr/bin/env bash
# Regenerate every picture in docs/images by running the examples with docs/ as the working directory
# (each example writes images/<name>.png and its scratch files under build/). Needs lmscript, lmphysics
# (on PATH or auto-installed), lmplot, lmdraw and lmcad (auto-installed) and ffmpeg (for the GIF).
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HERE/build:$PATH"
cd "$HERE/docs"
for ex in pendulum incline slider_crank viz_energy_drift viz_pendulum_phase viz_restitution viz_damping viz_double_pendulum anim_double_pendulum viz_projectile viz_friction_stop viz_resonance viz_incline_forces viz_crank_snapshots viz_pour combo/bounce_plot; do
  timeout 600 lmscript "../examples/$ex.lms"
done
ls -l images
