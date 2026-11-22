#!/usr/bin/env bash
# Ajusta el proyecto Android generado por `flutter create`:
# nombre visible, permisos de cámara e internet.
set -euo pipefail

MANIFEST="android/app/src/main/AndroidManifest.xml"

sed -i 's/android:label="[^"]*"/android:label="CompraClara"/' "$MANIFEST"

if ! grep -q 'android.permission.CAMERA' "$MANIFEST"; then
  sed -i 's#<application#<uses-permission android:name="android.permission.CAMERA"/>\n    <uses-permission android:name="android.permission.INTERNET"/>\n    <uses-feature android:name="android.hardware.camera" android:required="false"/>\n    <application#' "$MANIFEST"
fi

echo "Manifest parcheado:"
grep -n 'uses-permission\|uses-feature\|android:label' "$MANIFEST"
