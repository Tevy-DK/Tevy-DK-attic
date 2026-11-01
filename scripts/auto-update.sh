#!/usr/bin/env bash
# Fetch the latest upstream releases, rewrite version/hashes in the package
# expressions, and build the results.  Run it inside the repository dev shell:
#
#   nix develop --command bash scripts/auto-update.sh
#   nix develop --command bash scripts/auto-update.sh --commit
#
# --commit commits the validated changes and pushes them to main.  Without it
# the working tree is left dirty for inspection.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

commit=false
for arg in "$@"; do
  case "$arg" in
    --commit) commit=true ;;
    -h | --help)
      echo "usage: $0 [--commit]"
      exit 0
      ;;
    *)
      echo "unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

changed_packages=()
changed_files=()

github_api() {
  local repo=$1
  if [[ -n "${GH_TOKEN:-}" ]]; then
    GH_TOKEN="$GH_TOKEN" gh api "repos/$repo/releases/latest"
  else
    # Local runs without a token fall back to the unauthenticated API.
    curl --fail --silent --show-error \
      -H 'Accept: application/vnd.github+json' \
      "https://api.github.com/repos/$repo/releases/latest"
  fi
}

asset_url() {
  local json=$1 name=$2 url
  url=$(jq -er --arg name "$name" \
    'first(.assets[] | select(.name == $name) | .browser_download_url)' "$json") || {
    echo "asset '$name' is missing from the latest release" >&2
    return 1
  }
  printf '%s\n' "$url"
}

sri_hash() {
  local url=$1 hash
  echo "  prefetching $url" >&2
  hash=$(nix store prefetch-file --json "$url" | jq -er '.hash') || {
    echo "failed to prefetch $url" >&2
    return 1
  }
  [[ $hash == sha256-* ]] || {
    echo "unexpected hash for $url: $hash" >&2
    return 1
  }
  printf '%s\n' "$hash"
}

current_version() {
  local version
  version=$(sed -n 's/^  version = "\([^"]*\)";$/\1/p' "$1")
  [[ -n $version ]] || {
    echo "could not find the version line in $1" >&2
    return 1
  }
  printf '%s\n' "$version"
}

update_nix_file() {
  local file=$1 version=$2 arm_hash=$3 x86_hash=$4
  python3 - "$file" "$version" "$arm_hash" "$x86_hash" <<'PY'
import re
import sys

path, version, arm_hash, x86_hash = sys.argv[1:]

with open(path, encoding="utf-8") as handle:
    text = handle.read()

text, count = re.subn(
    r'^  version = "[^"]*";$',
    f'  version = "{version}";',
    text,
    count=1,
    flags=re.MULTILINE,
)
assert count == 1, f"expected one version line in {path}, found {count}"

hash_pattern = re.compile(
    r'(if [^\n]*isAarch64 then\s*\n\s*")(sha256-[A-Za-z0-9+/=]+)'
    r'("\s*\n\s*else\s*\n\s*")(sha256-[A-Za-z0-9+/=]+)(")'
)
text, count = hash_pattern.subn(
    lambda match: (
        match.group(1) + arm_hash + match.group(3) + x86_hash + match.group(5)
    ),
    text,
)
assert count == 1, f"expected one if-isAarch64 hash pair in {path}, found {count}"

with open(path, "w", encoding="utf-8") as handle:
    handle.write(text)
PY
}

update_package() {
  local pkg=$1 repo=$2 file=$3 tag_prefix=$4 arm_asset=$5 x86_asset=$6
  local json="$work/$pkg.json"
  local tag latest current arm_asset_name x86_asset_name arm_hash x86_hash

  echo "==> $pkg ($repo)"
  github_api "$repo" >"$json"
  tag=$(jq -er '.tag_name' "$json")

  [[ $tag == "$tag_prefix"* ]] || {
    echo "$pkg: tag '$tag' does not start with '$tag_prefix'" >&2
    return 1
  }
  latest=${tag#"$tag_prefix"}
  [[ -n $latest && $latest != */* ]] || {
    echo "$pkg: invalid version parsed from tag '$tag'" >&2
    return 1
  }

  current=$(current_version "$file")
  if [[ $current == "$latest" ]]; then
    echo "    already at $latest"
    return 0
  fi

  # Do not silently downgrade a manually pinned newer version.
  if [[ $(printf '%s\n%s\n' "$current" "$latest" | sort -V | tail -n1) == "$current" ]]; then
    echo "    local version $current is newer than upstream $latest; keeping it"
    return 0
  fi

  echo "    $current -> $latest"
  arm_asset_name=${arm_asset//%VERSION%/$latest}
  x86_asset_name=${x86_asset//%VERSION%/$latest}

  arm_hash=$(sri_hash "$(asset_url "$json" "$arm_asset_name")") || return 1
  x86_hash=$(sri_hash "$(asset_url "$json" "$x86_asset_name")") || return 1

  update_nix_file "$file" "$latest" "$arm_hash" "$x86_hash"
  changed_packages+=("$pkg")
  changed_files+=("$file")
}

build_package() {
  local pkg=$1
  echo "==> nix build .#$pkg"
  nix build ".#$pkg" --out-link "result-$pkg" --print-build-logs
  # The aarch64 branch is not buildable on an x86_64 runner, but it must at
  # least evaluate after the hash rewrite.
  nix eval --raw ".#packages.aarch64-linux.$pkg.drvPath" >/dev/null

  case "$pkg" in
    omp) "./result-$pkg/bin/omp" --version ;;
    codex) "./result-$pkg/bin/codex" --version ;;
    sjmcl)
      # Tauri ignores --version as a dry-run and starts the GUI, so a timeout
      # after a successful launch is expected.  Any other non-zero status is a
      # startup failure.
      local status=0
      xvfb-run -a timeout 15 "./result-$pkg/bin/SJMCL" --version || status=$?
      if ((status != 0 && status != 124)); then
        echo "SJMCL failed to start (status $status)" >&2
        return "$status"
      fi
      ;;
  esac
}

update_package \
  omp can1357/oh-my-pi pkgs/binaries/omp/default.nix v \
  omp-linux-arm64 omp-linux-x64
update_package \
  codex openai/codex pkgs/binaries/codex/default.nix rust-v \
  codex-aarch64-unknown-linux-musl.tar.gz codex-x86_64-unknown-linux-musl.tar.gz
update_package \
  sjmcl UNIkeEN/SJMCL pkgs/binaries/sjmcl/default.nix v \
  'SJMCL_%VERSION%_linux_aarch64_portable' 'SJMCL_%VERSION%_linux_x86_64_portable'

if ((${#changed_packages[@]} == 0)); then
  echo "All packages are up to date."
  exit 0
fi

# Validate both mandatory packages after any update, plus every other package
# whose expression changed.
declare -A to_build=([omp]=1 [codex]=1)
for pkg in "${changed_packages[@]}"; do
  to_build[$pkg]=1
done

for pkg in "${!to_build[@]}"; do
  build_package "$pkg"
done

if $commit; then
  git config user.name "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  git add -- "${changed_files[@]}"
  if git diff --cached --quiet; then
    echo "No staged changes; nothing to commit."
  else
    git commit -m "chore: auto update binaries [skip ci]"
    git push origin HEAD:main
  fi
else
  echo "Updated: ${changed_packages[*]} (not committed)"
fi
