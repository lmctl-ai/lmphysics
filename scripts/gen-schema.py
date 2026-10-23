#!/usr/bin/env python3
"""Regenerate schema/lmphysics.dsl.json from the method(...) and getter(...) registrations in
cpp/main.cpp so the schema and the host cannot drift. test.sh still diffs the registry against the compiler."""
import json, pathlib, re
root = pathlib.Path(__file__).resolve().parent.parent
src = (root / "cpp/main.cpp").read_text()
types = {}
for m in re.finditer(r'method\(r, "(\w+)", "(\w+)", \{([^}]*)\}, "(\w+)"', src):
    t, n, ps, rt = m.groups()
    params = [p.strip().strip('"') for p in ps.split(",") if p.strip()]
    types.setdefault(t, {"methods": {}})["methods"].setdefault(n, []).append({"params": params, "returns": rt})
for m in re.finditer(r'\bgetter\(r, "(\w+)", "(\w+)"\)', src):
    t, n = m.groups()
    types.setdefault(t, {"methods": {}})["methods"].setdefault(n, []).append({"params": [], "returns": "float"})
schema = {"dsl.schema": 2, "name": "lmphysics", "types": types, "functions": {}, "context": {"phys": "Phys"}}
with open(root / "schema/lmphysics.dsl.json", "w", newline="\n") as f:
    f.write(json.dumps(schema, indent=2) + "\n")
print({t: len(v["methods"]) for t, v in types.items()})
