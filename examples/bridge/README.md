# lmphysics poses to lmblender

`pose_obj.lms` is a small portable lmscript module. Import it from a script, record `x,y,z,qw,qx,qy,qz` for each lmphysics body, parse the resulting CSV with `csv_parse(read_file(path))`, choose a row, then call:

```text
pose_box_obj(row, "body_name", size_x, size_y, size_z, "body.obj");
```

Spheres and cylinders have their own writers:

```text
pose_sphere_obj(row, "ball", radius, segments, half, "ball.obj");      # half: 0 whole, 1 or -1 one hemisphere
pose_cylinder_obj(row, "link", radius, length, segments, "link.obj");  # axis = body-local y, like lmphysics
```

Writing the two hemispheres of a ball to two files with two materials makes its spin visible in a still.

Import that file with lmblender `scene.import_obj("body.obj")` and assign a material. Dimensions are the full box lengths supplied to lmphysics. `pose_point(row,name,[x,y,z])` transforms any body-local point, for joints or other custom meshes. Coordinates stay in metres in the right-handed Z-up frame shared by Chrono and Cycles. Quaternions are Hamilton, scalar first, and map body-local to world coordinates. The helper normalizes them and refuses missing/nonfinite/oversized values and zero quaternions.

The OBJ contains eight world-space vertices and twelve outward-facing triangles, without external materials. It represents a single snapshot; it does not interpolate motion, infer shape sizes from CSV, or recreate constraints. Put dimensions and material choices in the rendering script. Repeating it for selected rows produces a sequence of snapshots. No shell tools, Python, native reader additions or new releases are needed.

`../blender_brick_stack.lms` shows three contact snapshots; `../blender_pendulum_chain.lms` checks that transformed link endpoints coincide. Both use published `@latest` hosts. The examples pin an absolute raw URL for this module so lmctl autorun works from an empty directory. Relative imports are suitable for local scripts, but autorun resolves them against the working directory. When changing the helper, update the pinned import URLs after publishing and rerun the numeric tests.
