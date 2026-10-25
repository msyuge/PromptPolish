#!/bin/bash
# Сборка PromptPolish для распространения: Developer ID, нотаризация Apple, DMG.
#
#   scripts/release.sh                  полный релиз с нотаризацией
#   SKIP_NOTARIZE=1 scripts/release.sh  подписанный DMG без нотаризации (для проверки)
#
# Нотаризация берёт учётные данные из профиля связки ключей (по умолчанию PromptPolish),
# который создаётся один раз командой из README.
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${NOTARY_PROFILE:-PromptPolish}"
IDENTITY="Developer ID Application: Aleksei Maksimov (6ALXRXJXN6)"
OUT="build/release"

step() { printf '\n==> %s\n' "$1"; }

notarize() {
    xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait --timeout 30m
}

if [[ "${SKIP_NOTARIZE:-0}" != 1 ]] && ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    echo "Нет профиля нотаризации «$PROFILE» в связке ключей. Создайте его (см. README, раздел «Распространение»)" >&2
    echo "или соберите без нотаризации: SKIP_NOTARIZE=1 scripts/release.sh" >&2
    exit 1
fi

step "Генерация проекта"
xcodegen generate --quiet
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" PromptPolish/Resources/Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" PromptPolish/Resources/Info.plist)
DMG="$OUT/PromptPolish-$VERSION.dmg"
rm -rf "$OUT"
mkdir -p "$OUT"

step "Лицензии сторонних компонентов"
xcodebuild -project PromptPolish.xcodeproj -scheme PromptPolish -derivedDataPath build/DerivedData \
    -resolvePackageDependencies -quiet
scripts/make-acknowledgements.sh

step "Архив Release $VERSION ($BUILD)"
xcodebuild -project PromptPolish.xcodeproj -scheme PromptPolish -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$OUT/PromptPolish.xcarchive" \
    -derivedDataPath build/DerivedData archive -quiet

step "Экспорт с подписью Developer ID"
xcodebuild -exportArchive -archivePath "$OUT/PromptPolish.xcarchive" \
    -exportOptionsPlist scripts/ExportOptions.plist -exportPath "$OUT/export" -quiet
APP="$OUT/export/PromptPolish.app"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -d --verbose=2 "$APP" 2>&1 | grep -E "Authority=Developer ID Application|flags=.*runtime" >/dev/null \
    || { echo "Приложение подписано не Developer ID или без Hardened Runtime" >&2; exit 1; }

if [[ "${SKIP_NOTARIZE:-0}" != 1 ]]; then
    step "Нотаризация приложения"
    ditto -c -k --keepParent "$APP" "$OUT/PromptPolish.zip"
    notarize "$OUT/PromptPolish.zip"
    xcrun stapler staple "$APP"
fi

step "DMG"
STAGING="$OUT/dmg"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "PromptPolish $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" -quiet
codesign --sign "$IDENTITY" --timestamp "$DMG"

if [[ "${SKIP_NOTARIZE:-0}" != 1 ]]; then
    step "Нотаризация DMG"
    notarize "$DMG"
    xcrun stapler staple "$DMG"
    step "Проверка Gatekeeper"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
    spctl --assess --type execute --verbose=2 "$APP"
fi

shasum -a 256 "$DMG" | tee "$DMG.sha256"
step "Готово: $DMG"
