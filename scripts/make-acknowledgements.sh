#!/bin/bash
# Собирает тексты лицензий всех Swift-пакетов сборки в PromptPolish/Resources/Acknowledgements.txt.
# Пакеты берутся из Package.resolved, тексты — из их исходников в build/DerivedData.
set -euo pipefail
cd "$(dirname "$0")/.."

RESOLVED="PromptPolish.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
CHECKOUTS="build/DerivedData/SourcePackages/checkouts"
OUT="PromptPolish/Resources/Acknowledgements.txt"

[[ -f "$RESOLVED" && -d "$CHECKOUTS" ]] || { echo "Сначала соберите проект: make build" >&2; exit 1; }

{
    echo "PromptPolish использует следующие компоненты с открытым исходным кодом."
    echo "PromptPolish uses the following open source components."
    python3 - "$RESOLVED" <<'PY' | while IFS=$'\t' read -r name url version; do
import json, sys
for pin in sorted(json.load(open(sys.argv[1]))["pins"], key=lambda p: p["identity"]):
    print(pin["identity"], pin["location"], pin["state"].get("version") or pin["state"].get("revision", "")[:12], sep="\t")
PY
        directory=$(find "$CHECKOUTS" -maxdepth 1 -iname "$name" | head -1)
        license=$(find -E "$directory" -maxdepth 1 -iregex '.*/(license|licence|copying)(\.md|\.txt)?' | head -1)
        printf '\n\n%s\n%s %s\n%s\n\n' "================================================================" "$name" "$version" "$url"
        if [[ -n "$license" ]]; then cat "$license"; else echo "(файл лицензии не найден)"; fi
    done
} > "$OUT"

echo "Записано: $OUT ($(grep -c '^================' "$OUT") компонентов)"
