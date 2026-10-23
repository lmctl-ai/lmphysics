#!/usr/bin/env bash
# Fetch every dependency in deps.lock into git-ignored third_party/NAME at the pinned commit.
# --verify only checks that each checkout is at its pin. Extra words after the commit are sparse-checkout paths
# (a partial clone then downloads only those blobs: Chrono ships ~1 GB of sample data we never read).
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
while read -r name repo commit paths; do
  case "$name" in ''|\#*) continue;; esac
  dir="$HERE/third_party/$name"
  if [ "${1:-}" = "--verify" ]; then
    [ -d "$dir/.git" ] || { echo "third_party/$name missing: run scripts/sync-deps.sh" >&2; exit 1; }
    have="$(git -C "$dir" rev-parse HEAD)"
    [ "$have" = "$commit" ] || { echo "third_party/$name at $have, deps.lock pins $commit" >&2; exit 1; }
    continue
  fi
  if [ ! -d "$dir/.git" ]; then mkdir -p "$dir"; git -C "$dir" init -q; git -C "$dir" remote add origin "$repo"; fi
  if [ -n "$paths" ]; then
    # git-bash on Windows would rewrite the leading "/" of the patterns into a Windows path: no conversion
    # for this one command, which therefore runs inside $dir instead of using git -C.
    # shellcheck disable=SC2086
    ( cd "$dir" && git sparse-checkout init --no-cone && MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*" git sparse-checkout set $paths )
    git -C "$dir" fetch -q --depth 1 --filter=blob:none origin "$commit"
  else
    git -C "$dir" fetch -q --depth 1 origin "$commit"
  fi
  git -C "$dir" checkout -q -f FETCH_HEAD
  echo "synced third_party/$name at $commit"
done < "$HERE/deps.lock"
[ "${1:-}" = "--verify" ] && echo "third_party matches deps.lock"
exit 0
