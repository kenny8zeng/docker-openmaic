#!/usr/bin/env bash
#
# Resolve the upstream OpenMAIC source tree that the container image is built
# from, apply this repository's overlay, and report the build inputs.
#
#   ./scripts/prepare-context.sh [REF]
#
# REF may be a tag, a branch or a commit sha. When it is omitted, the pinned
# ref in OPENMAIC_REF is used. The checkout lands in $SRC_DIR (default ./src)
# and is what `docker build` uses as its context.
#
# Environment:
#   UPSTREAM_REPO  upstream clone URL (default: THU-MAIC/OpenMAIC)
#   SRC_DIR        destination directory (default: <repo>/src)
#   GH_TOKEN       optional token used to authenticate the fetch, which avoids
#                  the anonymous GitHub clone rate limit in CI
#
# Outputs (also appended to $GITHUB_OUTPUT when it is set):
#   ref, tag, sha, short_sha, version
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
upstream_repo="${UPSTREAM_REPO:-https://github.com/THU-MAIC/OpenMAIC.git}"
src_dir="${SRC_DIR:-"$repo_root/src"}"

ref="${1:-}"
if [ -z "$ref" ]; then
  ref="$(tr -d '[:space:]' <"$repo_root/OPENMAIC_REF")"
fi
if [ -z "$ref" ]; then
  echo "error: no upstream ref given and $repo_root/OPENMAIC_REF is empty" >&2
  exit 1
fi

# A token turns the anonymous clone in CI into an authenticated one. It is
# passed per-command via http.extraheader so it never lands in .git/config or
# in the build context.
git_auth=()
if [ -n "${GH_TOKEN:-}" ]; then
  basic="$(printf 'x-access-token:%s' "$GH_TOKEN" | base64 | tr -d '\n')"
  git_auth=(-c "http.extraheader=AUTHORIZATION: basic $basic")
fi

# A tag or a branch resolves with a shallow fetch of that single ref: the image
# build needs the tree, not the history.
fetch_shallow() {
  rm -rf "$src_dir"
  mkdir -p "$src_dir"
  git -c init.defaultBranch=main -C "$src_dir" init -q
  git -C "$src_dir" remote add origin "$upstream_repo"
  git "${git_auth[@]}" -C "$src_dir" -c advice.detachedHead=false \
    fetch --depth 1 --no-tags origin "$ref"
  git -C "$src_dir" -c advice.detachedHead=false checkout -q FETCH_HEAD
}

# A commit sha is not a ref, so the shallow fetch above fails for it. Retrying
# with a filtered full clone keeps that case working: --filter=blob:none skips
# file contents during the clone and downloads only what the checkout touches.
fetch_sha() {
  rm -rf "$src_dir"
  git "${git_auth[@]}" -C "$repo_root" clone --quiet --no-checkout \
    --filter=blob:none "$upstream_repo" "$src_dir"
  git -C "$src_dir" -c advice.detachedHead=false checkout -q "$ref"
}

fetch_log="$(mktemp)"
trap 'rm -f "$fetch_log"' EXIT

if ! fetch_shallow 2>"$fetch_log"; then
  if printf '%s' "$ref" | grep -Eq '^[0-9a-fA-F]{7,40}$'; then
    echo "'$ref' is not a ref; retrying as a commit sha" >&2
    fetch_sha
  else
    cat "$fetch_log" >&2
    echo "error: could not fetch ref '$ref' from $upstream_repo" >&2
    exit 1
  fi
fi

# The whole point of this repository is to reuse the upstream Dockerfile; fail
# loudly here rather than deep inside a build when a ref does not carry one.
for required in Dockerfile package.json pnpm-lock.yaml; do
  if [ ! -f "$src_dir/$required" ]; then
    echo "error: ref '$ref' of $upstream_repo has no $required" >&2
    exit 1
  fi
done

# Overlay: entries in ./overlay are copied over the checkout, so a needed fix
# can be layered onto upstream without vendoring the whole Dockerfile. README.md
# only documents the mechanism and is never copied.
overlay_dir="$repo_root/overlay"
overlay_files=0
if [ -d "$overlay_dir" ]; then
  shopt -s dotglob nullglob
  for path in "$overlay_dir"/*; do
    [ "$(basename "$path")" = "README.md" ] && continue
    cp -a "$path" "$src_dir/"
    overlay_files=$((overlay_files + 1))
  done
  shopt -u dotglob nullglob
fi

sha="$(git -C "$src_dir" rev-parse HEAD)"
short_sha="${sha:0:7}"
version="$(sed -n 's/^[[:space:]]*"version":[[:space:]]*"\([^"]*\)".*/\1/p' \
  "$src_dir/package.json" | head -n1)"

# A Docker tag allows only [A-Za-z0-9_.-]; a branch override such as
# `fix/lesson-crash` has to be flattened before it can name a tag. A commit ref
# is shortened to the same `sha-<short>` form the workflow already publishes.
if printf '%s' "$ref" | grep -Eq '^[0-9a-fA-F]{7,40}$'; then
  tag="sha-$short_sha"
else
  tag="$(printf '%s' "$ref" | tr -c 'A-Za-z0-9_.-' '-' | sed -e 's/^[._-]*//' -e 's/[._-]*$//')"
  if [ -z "$tag" ]; then
    tag="sha-$short_sha"
  fi
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "ref=$ref"
    echo "tag=$tag"
    echo "sha=$sha"
    echo "short_sha=$short_sha"
    echo "version=$version"
  } >>"$GITHUB_OUTPUT"
fi

cat <<EOF
upstream repo : $upstream_repo
requested ref : $ref
resolved sha  : $sha
app version   : $version
source tree   : $src_dir
overlay files : $overlay_files
image tag     : $tag
EOF
