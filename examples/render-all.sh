#!/usr/bin/env bash
# Regenerate every picture in docs/images by running the examples with docs/ as the working directory
# (each example writes images/<name>.png and its scratch files under build/). Needs lmscript, lmphysics
# (on PATH or auto-installed; projectile_drag, quarter_car, gear_train and cardan_joint need v0.1.2, i.e. this
# checkout's build/), lmplot, lmdraw, lmcad and lmblender (auto-installed) and ffmpeg (for the GIFs).
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HERE/build:$PATH"
cd "$HERE/docs"
for ex in pendulum incline slider_crank viz_energy_drift viz_pendulum_phase viz_restitution viz_damping viz_double_pendulum anim_double_pendulum viz_projectile viz_friction_stop viz_resonance viz_incline_forces viz_crank_snapshots viz_pour combo/bounce_plot blender_brick_stack blender_pendulum_chain \
    rolling_race bowling_skid newtons_cradle harmonic_overhang domino_cascade chain_whip anim_chain_whip gyroscope tennis_racket coupled_pendulums four_bar_linkage billiards_90 wrecking_ball \
    projectile_drag quarter_car gear_train cardan_joint; do
  timeout 600 lmscript "../examples/$ex.lms"
done
ls -l images
