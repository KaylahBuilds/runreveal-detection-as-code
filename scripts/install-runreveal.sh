#!/usr/bin/env bash
# Verified release metadata: https://github.com/runreveal/homebrew-runreveal/releases/tag/v2026.9.1
set -euo pipefail

if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
  printf '%s\n' 'This installer supports Linux x86_64 only; see the official release for other platforms.' >&2
  exit 2
fi
destination="${1:-.tools}"
version='v2026.9.1'
digest='b0c11b221043ecd3af628461bd97280109c52dbc6770e8810285fdde21720a31'
work_dir="$(mktemp -d)"
trap 'rm -f -- "$work_dir/runreveal-linux-amd64.tar.gz" "$work_dir/runreveal"; rmdir -- "$work_dir"' EXIT
archive="$work_dir/runreveal-linux-amd64.tar.gz"
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
  --retry 2 --max-time 120 \
  "https://github.com/runreveal/homebrew-runreveal/releases/download/$version/runreveal-linux-amd64.tar.gz" \
  --output "$archive"
printf '%s  %s\n' "$digest" "$archive" | sha256sum --check --strict -
tar -xzf "$archive" --directory "$work_dir" runreveal
mkdir -p -- "$destination"
install -m 0755 "$work_dir/runreveal" "$destination/runreveal"
printf '%s\n' "Installed checksum-pinned RunReveal $version to $destination/runreveal"
