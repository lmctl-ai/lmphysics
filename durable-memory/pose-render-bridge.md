# Portable pose rendering bridge

The gallery's blender_brick_stack and blender_pendulum_chain scripts record x,y,z,qw,qx,qy,qz and use examples/bridge/pose_obj.lms to bake full box poses into world-space OBJ files for existing lmblender Scene.import_obj. Units are metres; both hosts use right-handed Z-up coordinates and Hamilton scalar-first quaternions. No native API addition or new release is needed. Shared module imports are pinned by immutable raw URL because autorun resolves relative imports against its working directory.

Verified on 2026-10-23 against published lmphysics 0.1.1 and lmblender 0.3.6: both scripts run through lmctl autorun from empty directories using raw commit ebb079513e97a9243b36610923881d843da64e8c and produce byte-identical copies of the gallery PNGs (211170 and 140170 bytes). Each render is bounded to 300 seconds. The contact script checks the resting bottom brick height; the chain checks energy and transformed joint endpoints. Visual reviews scored 94 and 93.

The always-on test.sh bridge regression checks translation, quaternion order/handedness and normalization, OBJ topology, and rejection of missing, zero and oversized poses. The network-enabled gallery loop runs both complete examples on every platform and repeats the simulations to check CSV determinism. Regenerate images with examples/render-all.sh.

The bridge covers box geometry; shape dimensions and materials remain explicit in each script. It exports selected snapshots, not motion interpolation or constraints. pose_point can transform body-local vertices for additional shapes.
