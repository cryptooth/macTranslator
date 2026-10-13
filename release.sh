#!/bin/bash
# Başkalarına dağıtmak için: Developer ID ile imzala + Apple'a notarize ettir + zip'le
#   ./release.sh   →  dist/Translator.zip  (arkadaşına bunu gönder)
#
# Tek seferlik hazırlık:
#  1) developer.apple.com → Certificates → "Developer ID Application" sertifikası oluştur, Keychain'e kur
#     (Xcode › Settings › Accounts › Manage Certificates › + › Developer ID Application da olur)
#  2) appleid.apple.com → Uygulamaya özel parola oluştur
#  3) xcrun notarytool store-credentials "translator-notary" \
#        --apple-id "APPLE_ID_EPOSTAN" --team-id "TEAM_ID" --password "uygulamaya-ozel-parola"
set -euo pipefail
cd "$(dirname "$0")"

PROFILE="${NOTARY_PROFILE:-translator-notary}"
DEPLOY="${DEPLOY_TARGET:-15.0}"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
DIST="dist"
APP="$DIST/Translator.app"

IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 'Developer ID Application' | sed -E 's/.*"(.*)"/\1/' || true)"
fi
if [ -z "$IDENTITY" ]; then
  echo "✗ Keychain'de 'Developer ID Application' sertifikası bulunamadı (betiğin başındaki adım 1'e bak)."
  exit 1
fi
echo "▸ İmza: $IDENTITY"

EXTRA=()
if [ -d "$SDK_PATH/System/Library/Frameworks/FoundationModels.framework" ]; then
  EXTRA+=(-Xfrontend -disable-autolink-framework -Xfrontend FoundationModels
          -Xlinker -weak_framework -Xlinker FoundationModels)
fi

rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Apple Silicon + (mümkünse) Intel → universal binary
SLICES=()
for arch in arm64 x86_64; do
  echo "▸ Derleniyor: $arch"
  if xcrun swiftc -O -parse-as-library -target "${arch}-apple-macos${DEPLOY}" -sdk "$SDK_PATH" \
       ${EXTRA[@]+"${EXTRA[@]}"} Sources/*.swift -o "$DIST/Translator-$arch"; then
    SLICES+=("$DIST/Translator-$arch")
  else
    [ "$arch" = "arm64" ] && exit 1
    echo "  ⚠︎ $arch derlenemedi — yalnızca Apple Silicon sürümü dağıtılacak"
  fi
done
lipo -create -output "$APP/Contents/MacOS/Translator" "${SLICES[@]}"
rm -f "$DIST"/Translator-*
cp Info.plist "$APP/Contents/Info.plist"

echo "▸ İmzalanıyor (hardened runtime + timestamp)"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "▸ Apple'a notarize için gönderiliyor (birkaç dakika sürebilir)…"
ditto -c -k --keepParent "$APP" "$DIST/upload.zip"
xcrun notarytool submit "$DIST/upload.zip" --keychain-profile "$PROFILE" --wait
rm -f "$DIST/upload.zip"

echo "▸ Bilet uygulamaya iliştiriliyor (staple)"
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose=2 "$APP"

ditto -c -k --keepParent "$APP" "$DIST/Translator.zip"
echo "✓ Dağıtıma hazır: $DIST/Translator.zip  ($(lipo -archs "$APP/Contents/MacOS/Translator"))"
