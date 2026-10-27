#!/usr/bin/env bash
# Export all platforms, tag HEAD with the next version, push the tag,
# publish a GitHub release and push to itch.io.
#USAGE arg "[version]" default="patch" help="patch (default), minor, major, or an explicit tag like v1.2.3"
set -euo pipefail
version="${usage_version}"
case "$version" in
  patch|minor|major) ;;
  *) [[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must be patch, minor, major or look like v1.2.3, got '$version'" >&2; exit 1; } ;;
esac
git diff --quiet HEAD || { echo "uncommitted changes to tracked files; commit or stash first" >&2; exit 1; }
branch="$(git branch --show-current)"
[[ "$branch" == main ]] || { echo "on branch '${branch:-detached HEAD}'; releases must be cut from main" >&2; exit 1; }
git fetch --tags --quiet origin main
read -r behind ahead < <(git rev-list --left-right --count origin/main...HEAD)
if (( ahead || behind )); then
  echo "main is out of sync with origin/main ($ahead ahead, $behind behind); push/pull first" >&2
  exit 1
fi
latest="$(git tag -l 'v*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n1 || true)"
IFS=. read -r major minor patch <<< "${latest#v}"
major=${major:-0} minor=${minor:-0} patch=${patch:-0}
case "$version" in
  patch) tag="v$major.$minor.$((patch + 1))" ;;
  minor) tag="v$major.$((minor + 1)).0" ;;
  major) tag="v$((major + 1)).0.0" ;;
  *) tag="$version" ;;
esac
git rev-parse -q --verify "refs/tags/$tag" >/dev/null && { echo "tag $tag already exists" >&2; exit 1; }
# Fails before anything is tagged if butler isn't logged in or the itch.io project is wrong.
# Without credentials butler would start an interactive login, hidden by the redirect below.
[[ -n "${BUTLER_API_KEY:-}" || -f "$HOME/Library/Application Support/itch/butler_creds" ]] || { echo "butler isn't logged in; run 'butler login' or 'mise run setup' first" >&2; exit 1; }
butler status "$ITCH_TARGET" >/dev/null || { echo "butler can't reach itch.io project $ITCH_TARGET" >&2; exit 1; }
echo "Releasing $tag (previous: ${latest:-none})"
mise run export
git tag -a "$tag" -m "$tag"
git push origin "$tag"
gh release create "$tag" build/release/*.zip --title "$tag" --notes-file - --generate-notes <<'EOF'
**Easiest install:** get the game with the [itch app](https://itch.io/app) from https://dustinmichels.itch.io/street-faighter. It installs and updates in one click.

**macOS:** the app isn't notarized by Apple, so the first launch says Apple could not verify it. Move **street-faighter.app** to Applications, double-click it, click **Done**, then open **System Settings → Privacy & Security** and click **Open Anyway**. Or run `xattr -dr com.apple.quarantine /Applications/street-faighter.app`.

**Windows:** unzip to a folder first. The game isn't signed, so Windows may say "Windows protected your PC": click **More info**, then **Run anyway**.

Full steps: https://github.com/dustinmichels/street-faighter/blob/main/docs/guide/download.md
EOF
mise run itch "$tag"
