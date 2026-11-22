#!/bin/bash
# Prints the identifier of an AIRAC cycle, for example 2611.
#   airac.sh [current|next] [ident|date|cifp-date]
#     ident      2611 (default)
#     date       2026-10-29, the effective date
#     cifp-date  261029, the date in the name of the FAA archive CIFP_261029.zip
# The rule is the same as AIRACCycle in SimCoreContract: cycles are 28 days long, cycle 2001 started on 2020-01-02.
set -euo pipefail

which="${1:-current}"
format="${2:-ident}"

reference=18263                 # days from 1970-01-01 to 2020-01-02
today=$(( $(date -u +%s) / 86400 ))
index=$(( (today - reference) / 28 ))
[ "$which" = "next" ] && index=$(( index + 1 ))
effective=$(( reference + index * 28 ))

# BSD date (macOS) uses -r, GNU date uses -d.
day() {
    date -u -r $(( effective * 86400 )) "+$1" 2>/dev/null || date -u -d "@$(( effective * 86400 ))" "+$1"
}

case "$format" in
    ident)
        day_of_year=$((10#$(day %j)))
        printf "%s%02d\n" "$(day %y)" $(( (day_of_year - 1) / 28 + 1 ))
        ;;
    date) day %Y-%m-%d ;;
    cifp-date) day %y%m%d ;;
    *) echo "unknown format: $format" >&2; exit 2 ;;
esac
