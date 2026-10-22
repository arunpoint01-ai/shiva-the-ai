#!/usr/bin/env bash
set -Eeuo pipefail

# प्रोजेक्ट रूट शोधा
find_project_root() {
    local dir="$(pwd)"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/pubspec.yaml" ]] && [[ -d "$dir/lib" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

PROJECT_ROOT=$(find_project_root) || {
    echo "[ERROR] Flutter प्रोजेक्ट सापडला नाही."
    exit 1
}
cd "$PROJECT_ROOT"
echo "[INFO] प्रोजेक्ट रूट: $PROJECT_ROOT"

# कोणती फाईल उपलब्ध आहे ते तपासा
GRADLE_FILE=""
FILE_TYPE=""

if [[ -f "$PROJECT_ROOT/android/app/build.gradle.kts" ]]; then
    GRADLE_FILE="$PROJECT_ROOT/android/app/build.gradle.kts"
    FILE_TYPE="kts"
elif [[ -f "$PROJECT_ROOT/android/app/build.gradle" ]]; then
    GRADLE_FILE="$PROJECT_ROOT/android/app/build.gradle"
    FILE_TYPE="groovy"
else
    echo "[ERROR] android/app/ फोल्डरमध्ये build.gradle किंवा build.gradle.kts सापडली नाही."
    exit 1
fi

echo "[INFO] सापडलेली फाईल: $GRADLE_FILE ($FILE_TYPE)"

# बॅकअप तयार करा
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$PROJECT_ROOT/backups/gradle_fix_$TIMESTAMP"
mkdir -p "$BACKUP_DIR"
cp "$GRADLE_FILE" "$BACKUP_DIR/"
echo "[INFO] बॅकअप तयार: $BACKUP_DIR"

# Python द्वारे बदल करा
python3 - "$GRADLE_FILE" "$FILE_TYPE" <<'PYEOF'
import sys, re

file_path = sys.argv[1]
file_type = sys.argv[2]

with open(file_path, 'r') as f:
    content = f.read()

if file_type == "kts":
    # Kotlin DSL (.kts)
    content = re.sub(r'(?m)^(\s*)targetSdk(\s*=\s*)', r'\1targetSdkVersion\2', content)
    if re.search(r'(?m)^\s*minSdkVersion\s*=\s*24\s*$', content):
        print("[INFO] minSdkVersion आधीच 24 आहे.")
    else:
        content = re.sub(r'(?m)^(\s*)minSdkVersion\s*=\s*\d+', r'\1minSdkVersion = 24', content)
        if not re.search(r'(?m)^\s*minSdkVersion\s*=', content):
            content = content.replace('defaultConfig {', 'defaultConfig {\n        minSdkVersion = 24')
            print("[INFO] minSdkVersion = 24 जोडले.")
else:
    # Groovy (.gradle)
    content = re.sub(r'(?m)^(\s*)targetSdkVersion\s+\d+', r'\1targetSdkVersion 33', content)
    if re.search(r'(?m)^\s*minSdkVersion\s+24\s*$', content):
        print("[INFO] minSdkVersion आधीच 24 आहे.")
    else:
        content = re.sub(r'(?m)^(\s*)minSdkVersion\s+\d+', r'\1minSdkVersion 24', content)
        if not re.search(r'(?m)^\s*minSdkVersion\s+', content):
            content = content.replace('defaultConfig {', 'defaultConfig {\n        minSdkVersion 24')
            print("[INFO] minSdkVersion 24 जोडले.")

with open(file_path, 'w') as f:
    f.write(content)
print("[SUCCESS] Gradle फाईल यशस्वीरित्या अद्ययावत केली.")
PYEOF

echo "[INFO] अद्ययावत केलेल्या ओळी:"
grep -nE 'minSdkVersion|targetSdk' "$GRADLE_FILE" || true

echo "[SUCCESS] दुरुस्ती पूर्ण."
++0
+
