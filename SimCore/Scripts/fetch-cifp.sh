#!/bin/bash
# Downloads the FAA CIFP archive of an AIRAC cycle and unpacks FAACIFP18.
#   fetch-cifp.sh <output directory> [current|next]
# The archive is at https://aeronav.faa.gov/Upload_313-d/cifp/CIFP_YYMMDD.zip, where YYMMDD is the effective date.
# The FAA publishes the archive of the next cycle before its effective date.
set -euo pipefail

out="${1:?usage: fetch-cifp.sh <output directory> [current|next]}"
which="${2:-current}"
here="$(cd "$(dirname "$0")" && pwd)"
cycle="$("$here/airac.sh" "$which" ident)"
date="$("$here/airac.sh" "$which" cifp-date)"
url="https://aeronav.faa.gov/Upload_313-d/cifp/CIFP_${date}.zip"

mkdir -p "$out"
archive="$out/CIFP_${date}.zip"
echo "AIRAC $cycle: $url"
curl --fail --silent --show-error --location --retry 3 --output "$archive" "$url"
unzip -o -q "$archive" FAACIFP18 -d "$out"
test -s "$out/FAACIFP18"
head -c 40 "$out/FAACIFP18" | grep -q "^HDR01" || { echo "FAACIFP18 does not start with HDR01" >&2; exit 1; }
echo "$out/FAACIFP18"
