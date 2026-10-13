#!/bin/bash
# Translator.app derleme betiği
#   ./build.sh            → build/Translator.app
#   ./build.sh install    → derle + /Applications'a kopyala + başlat
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Translator.app"
ARCH="$(uname -m)"
DEPLOY="${DEPLOY_TARGET:-15.0}"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SDK_VER="$(xcrun --sdk macosx --show-sdk-version)"
echo "▸ SDK $SDK_VER  •  hedef macOS $DEPLOY  •  $ARCH"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

EXTRA=()
# FoundationModels (Apple Intelligence) macOS 26+ — eski sistemlerde açılabilsin diye zayıf bağla
if [ -d "$SDK_PATH/System/Library/Frameworks/FoundationModels.framework" ]; then
  EXTRA+=(-Xfrontend -disable-autolink-framework -Xfrontend FoundationModels
          -Xlinker -weak_framework -Xlinker FoundationModels)
fi

echo "▸ Derleniyor…"
xcrun swiftc -O -parse-as-library \
  -target "${ARCH}-apple-macos${DEPLOY}" \
  -sdk "$SDK_PATH" \
  ${EXTRA[@]+"${EXTRA[@]}"} \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/Translator"

cp Info.plist "$APP/Contents/Info.plist"

# İmzalama: Apple Development sertifikası varsa onu kullan (Erişilebilirlik izni yeniden derlemede korunur),
# yoksa ad-hoc imza (her derlemeden sonra izni yeniden vermek gerekir).
IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 'Apple Development' | sed -E 's/.*"(.*)"/\1/' || true)"
fi
if [ -n "$IDENTITY" ]; then
  echo "▸ İmzalanıyor: $IDENTITY"
  codesign --force --sign "$IDENTITY" "$APP"
else
  echo "▸ Ad-hoc imza (sertifika bulunamadı)"
  codesign --force --sign - "$APP"
fi

echo "✓ $APP hazır"

if [ "${1:-}" = "install" ]; then
  pkill -x Translator 2>/dev/null || true
  sleep 0.5
  rm -rf /Applications/Translator.app
  ditto "$APP" /Applications/Translator.app
  open /Applications/Translator.app
  echo "✓ /Applications/Translator.app kuruldu ve başlatıldı"
fi
