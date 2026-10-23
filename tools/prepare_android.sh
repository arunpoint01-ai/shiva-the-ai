#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

rm -rf android
flutter create --platforms=android --org com.shiva --project-name shiva_ai --no-pub .
rm -f test/widget_test.dart

GR=android/app/build.gradle.kts; [ -f "$GR" ] || GR=android/app/build.gradle
sed -i 's/com\.shiva\.shiva_ai/com.shiva.ai/g' "$GR"
sed -i -E 's/minSdk(Version)? *= *flutter\.minSdkVersion/minSdk = 24/; s/minSdkVersion +flutter\.minSdkVersion/minSdkVersion 24/' "$GR"
grep -n "minSdk\|applicationId\|namespace" "$GR"

rm -rf android/app/src/main/kotlin
mkdir -p android/app/src/main/kotlin/com/shiva/ai
cat > android/app/src/main/kotlin/com/shiva/ai/MainActivity.kt <<'KT'
package com.shiva.ai

import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
KT

M=android/app/src/main/AndroidManifest.xml
sed -i 's/android:label="[^"]*"/android:label="Shiva AI"/' "$M"
sed -i '0,/<manifest[^>]*>/s//&\n    <uses-permission android:name="android.permission.RECORD_AUDIO"\/>\n    <uses-permission android:name="android.permission.INTERNET"\/>\n    <uses-permission android:name="android.permission.USE_BIOMETRIC"\/>\n    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"\/>/' "$M"
sed -i 's#<queries>#<queries>\n        <intent><action android:name="android.speech.RecognitionService"/></intent>\n        <intent><action android:name="android.intent.action.TTS_SERVICE"/></intent>#' "$M"

for S in android/app/src/main/res/values/styles.xml android/app/src/main/res/values-night/styles.xml; do
  [ -f "$S" ] && sed -i 's#parent="@android:style/Theme.Light.NoTitleBar"#parent="Theme.AppCompat.Light.NoActionBar"#; s#parent="@android:style/Theme.Black.NoTitleBar"#parent="Theme.AppCompat.NoActionBar"#' "$S"
done
echo "--- manifest ---"
cat "$M"
