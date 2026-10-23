# lmphysics poses to lmblender

`pose_obj.lms` is a small portable lmscript module. Import it from a script, record `x,y,z,qw,qx,qy,qz` for each lmphysics body, parse the resulting CSV with `csv_parse(read_file(path))`, choose a row, then call:

```text
pose_box_obj(row, "body_name", size_x, size_y, size_z, "body.obj");
```

Import that file with lmblender `scene.import_obj("body.obj")` and assign a material. Dimensions are the full box lengths supplied to lmphysics. `pose_point(row,name,[x,y,z])` transforms any body-local point, for joints or other custom meshes. Coordinates stay in metres in the right-handed Z-up frame shared by Chrono and Cycles. Quaternions are Hamilton, scalar first, and map body-local to world coordinates. The helper normalizes them and refuses missing/nonfinite/oversized values and zero quaternions.

The OBJ contains eight world-space vertices and twelve outward-facing triangles, without external materials. It represents a single snapshot; it does not interpolate motion, infer shape sizes from CSV, or recreate constraints. Put dimensions and material choices in the rendering script. Repeating it for selected rows produces a sequence of snapshots. No shell tools, Python, native reader additions or new releases are needed.

`../blender_brick_stack.lms` shows three contact snapshots; `../blender_pendulum_chain.lms` checks that transformed link endpoints coincide. Both use published `@latest` hosts. Relative imports also resolve when running the raw example URL through lmctl autorun.
