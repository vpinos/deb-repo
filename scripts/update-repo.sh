#!/usr/bin/env bash
# Usage: update-repo.sh [source-release-tag]
#
# Pulls the .deb files from a release of the build repo (default: latest),
# verifies their checksums, merges them into the current apt repo, and
# publishes the signed metadata to the fixed "apt" release.
#
# Env: VPINOS_GPG_KEY (required), SOURCE_REPO, REPO, REPO_TAG,
#      DRY_RUN=1 (build locally in .work/, upload nothing)
set -euo pipefail

source_repo="${SOURCE_REPO:-vpinos/deb-package-builder}"
repo="${REPO:-vpinos/deb-repo}"
repo_tag="${REPO_TAG:-apt}"
source_tag="${1:-}"
dry_run="${DRY_RUN:-0}"
: "${VPINOS_GPG_KEY:?Set VPINOS_GPG_KEY (run scripts/generate-key.sh first)}"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="${WORKDIR:-$root/.work}"
stage="$work/stage"
incoming="$work/incoming"
out="$work/out"

command -v gh >/dev/null || { echo "gh is required." >&2; exit 1; }

rm -rf "$work"
mkdir -p "$stage" "$incoming"

# 1. Current repo contents, so packages from earlier runs are kept.
release_exists=0
if gh release view "$repo_tag" -R "$repo" >/dev/null 2>&1; then
  release_exists=1
  gh release download "$repo_tag" -R "$repo" --pattern '*.deb' -D "$stage" 2>/dev/null || true
fi

# 2. New packages from the build repo, checksum-verified.
echo "Downloading ${source_tag:-latest} release from $source_repo..."
gh release download ${source_tag:+"$source_tag"} -R "$source_repo" \
  --pattern '*.deb' --pattern '*.deb.sha256' -D "$incoming"

shopt -s nullglob
new_debs=("$incoming"/*.deb)
(( ${#new_debs[@]} )) || { echo "That release has no .deb files." >&2; exit 1; }
for deb in "${new_debs[@]}"; do
  [[ -f "$deb.sha256" ]] || { echo "Missing checksum for $(basename "$deb")." >&2; exit 1; }
done
(cd "$incoming" && sha256sum --check ./*.sha256)

new_names=()
for deb in "${new_debs[@]}"; do
  cp "$deb" "$stage/"
  new_names+=("$(basename "$deb")")
done

# 3. Prune, generate, sign.
"$root/scripts/build-repo.sh" "$stage" "$out"
cp "$root/keys/vpinos.asc" "$out/vpinos.asc"

if [[ "$dry_run" == 1 ]]; then
  echo "DRY_RUN=1: nothing uploaded. Inspect $work."
  exit 0
fi

# 4. Publish: debs first, metadata last, then remove superseded debs.
if (( ! release_exists )); then
  gh release create "$repo_tag" -R "$repo" --title "VPINOS apt repository" \
    --notes "Signed flat apt repository. See the README for setup; do not download assets by hand."
fi

upload=()
for name in "${new_names[@]}"; do
  [[ -f "$stage/$name" ]] && upload+=("$stage/$name")
done
(( ${#upload[@]} )) && gh release upload "$repo_tag" -R "$repo" --clobber "${upload[@]}"

gh release upload "$repo_tag" -R "$repo" --clobber \
  "$out/Packages" "$out/Packages.gz" "$out/vpinos.asc" \
  "$out/Release" "$out/InRelease" "$out/Release.gpg"

while IFS= read -r asset; do
  [[ "$asset" == *.deb && ! -f "$stage/$asset" ]] || continue
  echo "Deleting superseded asset $asset"
  gh release delete-asset "$repo_tag" "$asset" -R "$repo" --yes
done < <(gh release view "$repo_tag" -R "$repo" --json assets --jq '.assets[].name')

echo "Published. Base URL: https://github.com/$repo/releases/download/$repo_tag"
