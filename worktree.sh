#!/usr/bin/env bash
# worktree.sh — per-feature git worktrees so a build never occupies the main checkout.
#
# The iron rule it enforces: every feature build runs in its OWN worktree, cut off the
# freshest main; the repo's main checkout stays parked on `main` for the designer. Any
# number of builds (and design work) coexist with zero branch collisions.
#
# Usage:
#   worktree.sh new  <repo-path> <branch>   # create (or continue) a worktree for <branch>; prints its path on stdout
#   worktree.sh done <repo-path> <branch>   # after the PR merges: remove the worktree and delete the branch
#   worktree.sh list <repo-path>            # list this repo's worktrees
#
# Worktrees live at ~/.worktrees/<repo-name>/<branch> — grouped, out of the way, never nested in a repo.
# `new` prints ONLY the worktree path to stdout (status goes to stderr) so callers can do:
#   wt=$(worktree.sh new "$repo" "$branch") && git -C "$wt" add -A

set -euo pipefail

cmd="${1:-}"; repo="${2:-}"; branch="${3:-}"

die(){ echo "worktree.sh: $*" >&2; exit 1; }
[ -n "$cmd" ]  || die "usage: worktree.sh new|done|list <repo-path> [branch]"
[ -n "$repo" ] || die "missing <repo-path>"
git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || die "$repo is not a git repo"

repo_name="$(basename "$repo")"
wt_root="$HOME/.worktrees/$repo_name"
san(){ printf '%s' "$1" | tr '/' '-'; }     # branch -> dir-safe name (feature/14-x -> feature-14-x)

# Copy the gitignored local config a build needs but git won't carry.
seed(){
  local src="$1" dst="$2"; local seeded=() skipped=()
  for f in "$src"/.env "$src"/.env.*; do
    [ -e "$f" ] || continue
    cp "$f" "$dst"/ && seeded+=("$(basename "$f")")
  done
  if [ -d "$src/node_modules" ] && [ ! -e "$dst/node_modules" ]; then
    # junction on Windows (instant, no copy); symlink elsewhere
    if command -v cygpath >/dev/null 2>&1; then
      cmd.exe //c mklink //J "$(cygpath -w "$dst/node_modules")" "$(cygpath -w "$src/node_modules")" >/dev/null 2>&1 \
        && seeded+=("node_modules(junction)") || skipped+=("node_modules")
    else
      ln -s "$src/node_modules" "$dst/node_modules" && seeded+=("node_modules(symlink)") || skipped+=("node_modules")
    fi
  fi
  echo "  seeded:  ${seeded[*]:-(nothing — no .env/node_modules in main checkout)}" >&2
  [ ${#skipped[@]} -eq 0 ] || echo "  SKIPPED: ${skipped[*]} — seed manually if the build needs it" >&2
}

case "$cmd" in
  new)
    [ -n "$branch" ] || die "usage: worktree.sh new <repo-path> <branch>"
    wt="$wt_root/$(san "$branch")"
    if [ -d "$wt" ]; then echo "$wt"; exit 0; fi          # already exists — continue on it
    git -C "$repo" fetch --quiet origin 2>/dev/null || true
    mkdir -p "$wt_root"
    if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
      git -C "$repo" worktree add "$wt" "$branch" >&2      # continue an existing branch
    else
      # fork off the freshest main: origin/main if we have it, else local main
      base=main
      git -C "$repo" show-ref --verify --quiet refs/remotes/origin/main && base=origin/main
      git -C "$repo" worktree add "$wt" -b "$branch" "$base" >&2
      echo "  forked $branch off $base" >&2
    fi
    seed "$repo" "$wt"
    echo "$wt"                                              # stdout: the path, for the caller to cd/-C into
    ;;
  done)
    [ -n "$branch" ] || die "usage: worktree.sh done <repo-path> <branch>"
    wt="$wt_root/$(san "$branch")"
    git -C "$repo" worktree remove "$wt" --force 2>/dev/null || true
    git -C "$repo" branch -D "$branch" 2>/dev/null || true
    git -C "$repo" worktree prune
    rmdir "$wt_root" 2>/dev/null || true     # drop the repo's worktree dir if it's now empty
    echo "removed worktree + branch: $branch" >&2
    ;;
  list)
    git -C "$repo" worktree list
    ;;
  *) die "unknown command: $cmd (use new|done|list)";;
esac
