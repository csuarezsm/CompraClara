#!/usr/bin/env bash
# Ajusta el proyecto Android generado por `flutter create`:
# nombre visible, permisos de cámara e internet.
set -euo pipefail

MANIFEST="android/app/src/main/AndroidManifest.xml"

sed -i 's/android:label="[^"]*"/android:label="CompraClara"/' "$MANIFEST"

if ! grep -q 'android.permission.CAMERA' "$MANIFEST"; then
  sed -i 's#<application#<uses-permission android:name="android.permission.CAMERA"/>\n    <uses-permission android:name="android.permission.INTERNET"/>\n    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>\n    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>\n    <uses-permission android:name="android.permission.RECORD_AUDIO"/>\n    <uses-feature android:name="android.hardware.camera" android:required="false"/>\n    <application#' "$MANIFEST"
fi

echo "Manifest parcheado:"
grep -n 'uses-permission\|uses-feature\|android:label' "$MANIFEST"

# Reconocimiento de voz (Android 11+ necesita declararlo)
if ! grep -q 'android.speech.RecognitionService' "$MANIFEST"; then
  sed -i 's#</manifest>#    <queries>\n        <intent>\n            <action android:name="android.speech.RecognitionService"/>\n        </intent>\n    </queries>\n</manifest>#' "$MANIFEST"
fi

# minSdk 23 (requerido por algunos complementos: OCR, voz)
GRADLE=""
for f in android/app/build.gradle.kts android/app/build.gradle; do
  if [ -f "$f" ]; then GRADLE="$f"; break; fi
done
sed -i 's/minSdk = flutter.minSdkVersion/minSdk = 23/; s/minSdkVersion flutter.minSdkVersion/minSdkVersion 23/' "$GRADLE"
grep -n "minSdk" "$GRADLE" || true

# ML Kit: el plugin referencia alfabetos (chino, japonés…) que no incluimos.
cat > android/app/proguard-rules.pro <<'RULES'
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
RULES
echo "proguard-rules.pro creado"
