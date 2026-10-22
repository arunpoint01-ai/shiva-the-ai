#!/usr/bin/env bash

echo "=========================================="
echo "🔍 SHIVA AI - HEALTH CHECK (Phase 1 to 5)"
echo "=========================================="

# 1. Check Flutter & Android Folder Structure
echo -n "1. Android Folder Exists? : "
if [ -d "android" ]; then echo "✅ YES"; else echo "❌ NO"; fi

echo -n "2. MainActivity.kt Exists?: "
if [ -f "android/app/src/main/kotlin/com/shiva/ai/MainActivity.kt" ]; then echo "✅ YES"; else echo "❌ NO (Missing)"; fi

echo -n "3. Build.gradle Exists?   : "
if [ -f "android/app/build.gradle" ]; then echo "✅ YES"; else echo "❌ NO"; fi

echo "------------------------------------------"
# 2. Check Build.gradle contents
echo "📄 BUILD.GRADLE CONTENTS:"
if [ -f "android/app/build.gradle" ]; then
    grep -E "applicationId|minSdk|targetSdk" android/app/build.gradle | sed 's/^/   /'
fi

echo "------------------------------------------"
# 3. Check AndroidManifest.xml for V1 embedding traces
echo "📄 ANDROID MANIFEST CHECK:"
if [ -f "android/app/src/main/AndroidManifest.xml" ]; then
    if grep -q "io.flutter.app" android/app/src/main/AndroidManifest.xml; then
        echo "   ❌ FOUND V1 EMBEDDING (io.flutter.app)"
    else
        echo "   ✅ No V1 embedding found."
    fi
    
    if grep -q "applicationName" android/app/src/main/AndroidManifest.xml; then
        echo "   ❌ FOUND applicationName tag"
    else
        echo "   ✅ No applicationName tag found."
    fi
    echo "   <application> tag status:"
    grep -A 2 "<application" android/app/src/main/AndroidManifest.xml | sed 's/^/     /'
fi

echo "------------------------------------------"
# 4. Check Workflow
echo "📄 WORKFLOW CHECK (.github/workflows/build.yml):"
if [ -f ".github/workflows/build.yml" ]; then
    if grep -q "flutter create" .github/workflows/build.yml; then
        echo "   ❌ Found 'flutter create' (This overwrites your files!)"
    else
        echo "   ✅ No 'flutter create' found."
    fi
else
    echo "   ❌ Workflow file missing!"
fi

echo "------------------------------------------"
# 5. Check Files not committed
echo "📄 GIT STATUS (Uncommitted changes):"
git status --short | head -n 10

echo "=========================================="
+0
+
