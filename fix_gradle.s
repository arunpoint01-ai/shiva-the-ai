#!/usr/bin/env bash
set -Eeuo pipefail

# 1. प्रोजेक्टचे रूट शोधा
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
    echo "[ERROR] Flutter प्रोजेक्ट सापडला नाही. कृपया प्रोजेक्टच्या रूट फोल्डरमधून स्क्रिप्ट चालवा."
    exit 1
}
cd "$PROJECT_ROOT"
echo "[INFO] प्रोजेक्ट रूट: $PROJECT_ROOT"

# 2. Gradle फाईलचा मार्ग निश्चित करा
GRADLE_FILE="$PROJECT_ROOT/android/app/build.gradle.kts"
if [[ ! -f "$GRADLE_FILE" ]]; then
    echo "[ERROR] $GRADLE_FILE सापडली नाही. ही स्क्रिप्ट फक्त Kotlin DSL (.kts) साठी आहे."
    exit 1
fi

# 3. बॅकअप तयार करा
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$PROJECT_ROOT/backups/gradle_fix_$TIMESTAMP"
mkdir -p "$BACKUP_DIR"
cp "$GRADLE_FILE" "$BACKUP_DIR/"
echo "[INFO] बॅकअप तयार: $BACKUP_DIR"

# 4. Python द्वारे फाईलमधील बदल करा
python3 - "$GRADLE_FILE" <<'PYEOF'
import sys, re

file_path = sys.argv[1]
with open(file_path, 'r') as f:
    content = f.read()

# targetSdk -> targetSdkVersion
content = re.sub(
    r'(?m)^(\s*)targetSdk(\s*=\s*)',
    r'\1targetSdkVersion\2',
    content
)

# minSdkVersion = 24
if re.search(r'(?m)^\s*minSdkVersion\s*=\s*24\s*$', content):
    print("[INFO] minSdkVersion आधीच 24 आहे.")
else:
    content = re.sub(
        r'(?m)^(\s*)minSdkVersion\s*=\s*\d+',
        r'\1minSdkVersion = 24',
        content
    )
    if not re.search(r'(?m)^\s*minSdkVersion\s*=', content):
        content = content.replace(
            'defaultConfig {',
            'defaultConfig {\n        minSdkVersion = 24'
        )
        print("[INFO] minSdkVersion = 24 जोडले.")

with open(file_path, 'w') as f:
    f.write(content)
print("[SUCCESS] Gradle फाईल यशस्वीरित्या अद्ययावत केली.")
PYEOF

# 5. बदल तपासा
echo "[INFO] अद्ययावत केलेल्या ओळी:"
grep -nE 'minSdkVersion|targetSdkVersion' "$GRADLE_FILE" || true

echo "[SUCCESS] दुरुस्ती पूर्ण. कृपया बदल GitHub वर पुश करा."

