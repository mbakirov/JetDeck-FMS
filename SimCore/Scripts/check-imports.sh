#!/bin/bash
# Checks the layer rule: a target imports only the targets that the rule permits.
# SwiftPM does not always reject an import of a target that is not in the dependencies.
# Thus this script is the check. Keep it the same as the dependency graph in Package.swift.
set -euo pipefail
cd "$(dirname "$0")/../Sources"

SYSTEM="Foundation Synchronization"

allowed() {
    case "$1" in
        SimCoreContract) echo "" ;;
        Kernel) echo "SimCoreContract" ;;
        World|Sensors|FMS|AutoFlight|FBW|Aircraft|Warnings|Displays) echo "Kernel SimCoreContract" ;;
        SnapshotDiff) echo "SimCoreContract" ;;
        SimCore) echo "SimCoreContract Kernel World Sensors FMS AutoFlight FBW Aircraft Warnings Displays" ;;
        simcore-cli) echo "SimCore SnapshotDiff SimCoreContract" ;;
        *) echo "__unknown__" ;;
    esac
}

failed=0
for dir in */; do
    target="${dir%/}"
    permitted="$(allowed "$target")"
    if [ "$permitted" = "__unknown__" ]; then
        echo "Sources/$target: the target is not in Scripts/check-imports.sh. Add its permitted imports."
        failed=1
        continue
    fi
    while IFS= read -r match; do
        [ -z "$match" ] && continue
        file="${match%%:*}"
        rest="${match#*:}"
        line="${rest%%:*}"
        # The module name is the first word after `import` (and after `struct`, `class`, ... if present).
        module="$(echo "${rest#*:}" | sed -E 's/^.*import[[:space:]]+((typealias|struct|class|enum|protocol|let|var|func)[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*).*$/\3/')"
        ok=0
        for name in $SYSTEM $permitted; do
            [ "$name" = "$module" ] && ok=1
        done
        if [ "$ok" = 0 ]; then
            echo "Sources/$file:$line: forbidden import '$module' in target '$target'"
            failed=1
        fi
    done < <(grep -rnE '^[[:space:]]*(@[A-Za-z_]+(\([^)]*\))?[[:space:]]+)*import[[:space:]]+' "$target" --include='*.swift' || true)
done

if [ "$failed" = 0 ]; then
    echo "Imports are correct."
fi
exit "$failed"
