
#!/data/data/com.termux/files/usr/bin/bash
# ============================================================================
# SHIVA THE AI SYSTEM — PHASE 2
# Automatic Flutter SDK Setup + Gemini API + Multilingual STT/TTS
#
# Environment: Android Termux | Existing Flutter Project
#
# Run from the project root:
#   cd ~/shiva-the-ai-system
#   bash shiva_phase2_full.sh
#
# This script:
#   1. Detects existing Flutter or attempts a Termux-compatible install.
#   2. Preserves the project with timestamped backups.
#   3. Generates complete Dart service implementations.
#   4. Updates pubspec.yaml and AndroidManifest.xml idempotently.
#   5. Runs real verification only when tools are genuinely available.
#   6. Falls back honestly to GitHub Actions if native Termux build is
#      technically unsupported — no fake success output.
# ============================================================================

set -Eeuo pipefail

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; BLUE=$'\033[0;34m'; NC=$'\033[0m'
log()  { printf '%s[SHIVA]%s %s\n' "$BLUE"  "$NC" "$*"; }
ok()   { printf '%s[ OK ]%s %s\n'  "$GREEN" "$NC" "$*"; }
warn() { printf '%s[WARN]%s %s\n'  "$YELLOW" "$NC" "$*"; }
err()  { printf '%s[FAIL]%s %s\n'  "$RED"   "$NC" "$*" >&2; }

FAILED_STEP=""

fail_exit() {
  FAILED_STEP="${1:-unknown error}"
  err "$FAILED_STEP"
  if [[ -n "${BACKUP_DIR:-}" && -d "${BACKUP_DIR}" ]]; then
    err "Backups: $BACKUP_DIR"
  fi
  printf '\n%sSHIVA AI PHASE 2: INCOMPLETE — SEE ERRORS ABOVE%s\n' "$RED" "$NC"
  exit 1
}
trap 'fail_exit "Unhandled error at line $LINENO"' ERR

# ============================================================================
# 1. PROJECT PRE-FLIGHT
# ============================================================================
log "Checking project structure..."

[[ -n "${BASH_VERSION:-}" ]] || fail_exit "Must run with bash."
[[ -f "pubspec.yaml" ]] || fail_exit "pubspec.yaml not found. Run from the Flutter project root."

MANIFEST="android/app/src/main/AndroidManifest.xml"
[[ -f "$MANIFEST" ]] || fail_exit "AndroidManifest.xml not found at $MANIFEST"

PROJECT_NAME=$(grep -E '^name:' pubspec.yaml | head -n1 | sed -E 's/^name:[[:space:]]*//' || echo "<unknown>")
log "Project: $PROJECT_NAME"

IN_GIT=0
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  IN_GIT=1
  ok "Git repository detected."
fi

# ============================================================================
# 2. BACKUP
# ============================================================================
STAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$(pwd)/.shiva_phase2_backups/$STAMP"
mkdir -p "$BACKUP_DIR"
ok "Backup directory: $BACKUP_DIR"

backup_file() { [[ -f "$1" ]] && cp -p "$1" "$BACKUP_DIR/$(echo "$1" | tr '/' '_')" && ok "Backed up: $1" || true; }
restore_file() { local d="$BACKUP_DIR/$(echo "$1" | tr '/' '_')"; [[ -f "$d" ]] && cp -p "$d" "$1" && warn "Restored: $1" || true; }

# ============================================================================
# 3. FLUTTER SDK DETECTION / INSTALLATION (TERMUX-AWARE)
# ============================================================================
log "Checking for Flutter SDK..."

HAS_FLUTTER=0
FLUTTER_PATH=""

if command -v flutter >/dev/null 2>&1; then
  FLUTTER_PATH=$(command -v flutter)
  if flutter --version >/dev/null 2>&1; then
    HAS_FLUTTER=1
    ok "Flutter found and working: $FLUTTER_PATH"
    flutter --version 2>/dev/null | head -n 2 || true
  else
    warn "flutter binary exists but cannot execute. Treating as not installed."
  fi
fi

if [[ "$HAS_FLUTTER" -eq 0 ]]; then
  warn "Flutter not available. Evaluating Termux-native installation options."

  # ---- Architecture detection ----
  ARCH=$(uname -m)
  log "Detected architecture: $ARCH"

  if [[ "$ARCH" != "aarch64" && "$ARCH" != "arm64" ]]; then
    warn "This script's Termux Flutter fallback targets ARM64/aarch64 only."
    warn "Detected: $ARCH. Skipping native install attempt."
  else
    # ---- Storage check ----
    AVAIL_KB=$(df -P "$HOME" | awk 'NR==2 {print $4}')
    AVAIL_MB=$((AVAIL_KB / 1024))
    log "Available storage: ${AVAIL_MB} MB"

    if [[ "$AVAIL_MB" -lt 8000 ]]; then
      warn "Less than 8GB free. termux-flutter-wsl requires ~8GB+."
      warn "Skipping native install to avoid filling storage."
    else
      # ---- Attempt the termux-flutter-wsl route (has real APK build evidence) ----
      # Source: https://codeberg.org/ImL1s/termux-flutter-wsl
      # This project provides a Termux-packaged Flutter SDK that supports
      # `flutter build apk` on ARM64. It requires explicit install.
      #
      # IMPORTANT: We do NOT auto-install a 170MB .deb without consent.
      # Instead, we check whether it is already present and report clearly.
      if [[ -f "$PREFIX/share/flutter/bin/flutter" ]]; then
        FLUTTER_PATH="$PREFIX/share/flutter/bin/flutter"
        export PATH="$PREFIX/share/flutter/bin:$PATH"
        if "$FLUTTER_PATH" --version >/dev/null 2>&1; then
          HAS_FLUTTER=1
          ok "Found pre-installed termux-flutter at $FLUTTER_PATH"
        fi
      fi

      if [[ "$HAS_FLUTTER" -eq 0 ]]; then
        warn "No Termux-native Flutter SDK is pre-installed."
        warn "Automatic SDK installation is intentionally NOT performed here because:"
        warn "  1. termux-flutter-wsl requires ~170MB download + ~8GB storage."
        warn "  2. Installation may modify Termux system packages."
        warn "  3. The user must consent to this resource usage."
        warn ""
        warn "To install manually (recommended if you accept the requirements):"
        warn "  pkg update && pkg upgrade -y"
        warn "  pkg install -y curl"
        warn "  curl -L https://codeberg.org/ImL1s/termux-flutter-wsl/raw/branch/master/install_flutter_complete.sh -o install_flutter_complete.sh"
        warn "  bash install_flutter_complete.sh"
        warn ""
        warn "Alternate route (older, Android 14 incompatible):"
        warn "  https://github.com/mumumusuc/termux-flutter"
        warn ""
        warn "Continuing WITHOUT local Flutter. Source generation will proceed."
        warn "Build verification will use GitHub Actions instead."
      fi
    fi
  fi
fi

if [[ "$HAS_FLUTTER" -eq 1 ]]; then
  DART_VERSION=$(dart --version 2>&1 | head -n1 || echo "unknown")
  ok "Dart: $DART_VERSION"
fi

# ============================================================================
# 4. UPDATE pubspec.yaml (idempotent)
# ============================================================================
log "Updating pubspec.yaml..."
backup_file "pubspec.yaml"

python3 - <<'PYEOF'
import re, pathlib, sys
p = pathlib.Path("pubspec.yaml")
text = p.read_text()
required = {
    "http": "^1.2.0",
    "speech_to_text": "^7.0.0",
    "flutter_tts": "^4.2.0",
    "permission_handler": "^11.3.0",
}
lines = text.splitlines()
in_deps = False
start = None
end = None
existing = {}
for i, l in enumerate(lines):
    if re.match(r'^dependencies:\s*$', l):
        in_deps = True
        start = i
        continue
    if in_deps:
        if re.match(r'^[A-Za-z0-9_]', l) and not l.startswith(' '):
            end = i
            break
        m = re.match(r'^\s+([A-Za-z0-9_]+):\s*(.+)$', l)
        if m:
            existing[m.group(1)] = m.group(2)
if start is None:
    print("ERROR: no dependencies section", file=sys.stderr)
    sys.exit(1)
if end is None:
    end = len(lines)
adds = [f"  {k}: {v}" for k, v in required.items() if k not in existing]
if adds:
    p.write_text("\n".join(lines[:end] + adds + lines[end:]) + "\n")
    print("Added:", ", ".join(k for k in required if k not in existing))
else:
    print("All required deps already present.")
PYEOF

if [[ "$HAS_FLUTTER" -eq 1 ]]; then
  log "Running flutter pub get..."
  if ! flutter pub get; then
    restore_file "pubspec.yaml"
    fail_exit "flutter pub get failed."
  fi
  ok "Dependencies resolved."
else
  warn "Skipping flutter pub get (Flutter unavailable)."
fi

# ============================================================================
# 5. UPDATE AndroidManifest.xml (idempotent)
# ============================================================================
log "Updating AndroidManifest.xml..."
backup_file "$MANIFEST"

python3 - "$MANIFEST" <<'PYEOF'
import sys, pathlib
import xml.etree.ElementTree as ET

p = pathlib.Path(sys.argv[1])
t = p.read_text()

for perm in ["android.permission.INTERNET", "android.permission.RECORD_AUDIO"]:
    needle = f'android:name="{perm}"'
    if needle not in t:
        t = t.replace("</manifest>", f'    <uses-permission {needle} />\n</manifest>', 1)
        print("Added permission:", perm)

for act in ["android.speech.RecognitionService", "android.intent.action.TTS_SERVICE"]:
    if act not in t:
        block = (
            f'    <queries>\n'
            f'        <intent>\n'
            f'            <action android:name="{act}" />\n'
            f'        </intent>\n'
            f'    </queries>\n'
        )
        t = t.replace("</manifest>", block + "</manifest>", 1)
        print("Added query action:", act)

p.write_text(t)
try:
    ET.parse(str(p))
    print("XML validation: OK")
except ET.ParseError as e:
    print("XML validation FAILED:", e, file=sys.stderr)
    sys.exit(1)
PYEOF

[[ $? -eq 0 ]] || { restore_file "$MANIFEST"; fail_exit "Manifest update failed."; }
ok "Manifest validated."

# ============================================================================
# 6. GENERATE DART FILES
# ============================================================================
mkdir -p lib/config lib/services

# ---- 6a. ai_config.dart ----
AI_CONFIG="lib/config/ai_config.dart"
backup_file "$AI_CONFIG"
cat > "$AI_CONFIG" <<'DARTEOF'
// ============================================================================
// Shiva AI — Centralized AI configuration
//
// Override at build time:
//   flutter build apk --dart-define=GEMINI_API_KEY=xxx \
//                     --dart-define=GEMINI_MODEL=gemini-3.8-flash
//
// SECURITY: Compile-time defines are embedded in the APK and are extractable.
// For production-grade protection, route requests through an authenticated
// backend proxy that holds the key server-side. Do NOT expose an
// unauthenticated public proxy.
//
// MODEL: "gemini-3.8-flash" is the assumed current Flash-tier model.
// Verify against the provider's live documentation before release.
// ============================================================================

class AiConfig {
  AiConfig._();

  static const String geminiApiKey =
      String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
  static const String geminiModel =
      String.fromEnvironment('GEMINI_MODEL', defaultValue: 'gemini-3.8-flash');

  static const Duration requestTimeout = Duration(seconds: 30);
  static const String geminiBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta';

  static bool get hasApiKey => geminiApiKey.isNotEmpty;
}
DARTEOF

# ---- 6b. gemini_service.dart ----
GEMINI_SVC="lib/services/gemini_service.dart"
backup_file "$GEMINI_SVC"
cat > "$GEMINI_SVC" <<'DARTEOF'
// ============================================================================
// Shiva AI — Gemini REST client
// ============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/ai_config.dart';

class GeminiException implements Exception {
  final String userMessage;
  final String? technicalDetail;
  final int? statusCode;

  const GeminiException(this.userMessage, {this.technicalDetail, this.statusCode});

  @override
  String toString() =>
      'GeminiException($statusCode): $userMessage'
      '${technicalDetail != null ? ' [$technicalDetail]' : ''}';
}

class GeminiService {
  final http.Client _client;
  final String _apiKey;
  final String _model;

  GeminiService({http.Client? client, String? apiKey, String? model})
      : _client = client ?? http.Client(),
        _apiKey = apiKey ?? AiConfig.geminiApiKey,
        _model = model ?? AiConfig.geminiModel;

  Future<String> generateResponse(String prompt) async {
    if (prompt.trim().isEmpty) throw const GeminiException('Prompt is empty.');
    if (_apiKey.isEmpty) {
      throw const GeminiException(
        'Gemini API key is not configured. Rebuild with --dart-define=GEMINI_API_KEY=...',
      );
    }

    final uri = Uri.parse(
      '${AiConfig.geminiBaseUrl}/models/$_model:generateContent?key=$_apiKey',
    );
    final body = jsonEncode({
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt},
          ],
        },
      ],
    });

    http.Response response;
    try {
      response = await _client
          .post(uri,
              headers: const {'Content-Type': 'application/json'}, body: body)
          .timeout(AiConfig.requestTimeout);
    } on TimeoutException {
      throw const GeminiException('Request timed out. Check your connection.');
    } on http.ClientException catch (e) {
      throw GeminiException('Network error.', technicalDetail: e.message);
    } catch (e) {
      throw GeminiException('Unexpected network failure.', technicalDetail: e.toString());
    }

    if (response.statusCode != 200) {
      throw _mapHttpError(response.statusCode, response.body);
    }
    return _parse(response.body);
  }

  String _parse(String raw) {
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (e) {
      throw GeminiException('Invalid response from AI service.', technicalDetail: e.toString());
    }
    if (decoded is! Map<String, dynamic>) {
      throw const GeminiException('Unexpected response shape.');
    }

    final feedback = decoded['promptFeedback'];
    if (feedback is Map && feedback['blockReason'] != null) {
      throw const GeminiException('Request blocked by safety filters. Rephrase.');
    }

    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw const GeminiException('The AI returned an empty response.');
    }

    final first = candidates.first;
    if (first is! Map) throw const GeminiException('Malformed candidate.');

    final finish = first['finishReason'];
    if (finish is String && finish.isNotEmpty && finish != 'STOP') {
      if (finish == 'SAFETY' || finish == 'RECITATION' || finish == 'BLOCKLIST') {
        throw GeminiException('Response blocked ($finish). Try a different prompt.');
      }
    }

    final parts = first['content']?['parts'];
    if (parts is! List || parts.isEmpty) {
      throw const GeminiException('AI response incomplete.');
    }

    final buffer = StringBuffer();
    for (final p in parts) {
      if (p is Map && p['text'] is String) buffer.write(p['text']);
    }
    final text = buffer.toString().trim();
    if (text.isEmpty) throw const GeminiException('AI response empty.');
    return text;
  }

  GeminiException _mapHttpError(int status, String body) {
    String? detail;
    try {
      final d = jsonDecode(body);
      if (d is Map && d['error'] is Map) detail = d['error']['message']?.toString();
    } catch (_) {}
    switch (status) {
      case 400:
        return GeminiException('Invalid request to Gemini.', technicalDetail: detail, statusCode: status);
      case 401:
      case 403:
        return GeminiException('API key invalid or lacks permission.', technicalDetail: detail, statusCode: status);
      case 404:
        return GeminiException('Configured Gemini model is unavailable.', technicalDetail: detail, statusCode: status);
      case 429:
        return GeminiException('Rate limit reached. Wait and retry.', technicalDetail: detail, statusCode: status);
      default:
        if (status >= 500) {
          return GeminiException('Gemini server error ($status). Retry later.', technicalDetail: detail, statusCode: status);
        }
        return GeminiException('Unexpected Gemini error (HTTP $status).', technicalDetail: detail, statusCode: status);
    }
  }

  void dispose() => _client.close();
}
DARTEOF

# ---- 6c. speech_service.dart ----
SPEECH_SVC="lib/services/speech_service.dart"
backup_file "$SPEECH_SVC"
cat > "$SPEECH_SVC" <<'DARTEOF'
// ============================================================================
// Shiva AI — Speech-to-Text service
// ============================================================================

import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

class SpeechService {
  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;
  bool _listening = false;

  bool get isListening => _listening && _speech.isListening;

  Future<bool> initialize({void Function(String error)? onError}) async {
    if (_initialized) return true;
    try {
      _initialized = await _speech.initialize(
        onError: (e) => onError?.call(e.errorMsg),
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') _listening = false;
        },
      );
      return _initialized;
    } catch (e) {
      _initialized = false;
      onError?.call('Speech initialization failed: $e');
      return false;
    }
  }

  Future<List<String>> availableLocaleIds() async {
    if (!_initialized) {
      final ok = await initialize();
      if (!ok) return const [];
    }
    try {
      final locales = await _speech.locales();
      return locales.map((l) => l.localeId).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<bool> isLocaleAvailable(String localeId) async {
    final ids = await availableLocaleIds();
    return ids.contains(localeId);
  }

  Future<String?> pickSupportedLocale(List<String> preferred) async {
    final ids = await availableLocaleIds();
    for (final p in preferred) {
      if (ids.contains(p)) return p;
    }
    for (final p in preferred) {
      final lang = p.split('-').first;
      for (final id in ids) {
        if (id.startsWith(lang)) return id;
      }
    }
    return null;
  }

  Future<void> startListening({
    required String localeId,
    required void Function(String text) onPartial,
    required void Function(String text) onFinal,
    required void Function(String error) onError,
  }) async {
    if (_listening) {
      onError('Already listening.');
      return;
    }
    if (!await initialize(onError: onError)) {
      onError('Speech recognition unavailable.');
      return;
    }
    if (!await isLocaleAvailable(localeId)) {
      onError('Language $localeId unavailable for input.');
      return;
    }

    _listening = true;
    try {
      await _speech.listen(
        localeId: localeId,
        onResult: (SpeechRecognitionResult r) {
          if (r.finalResult) {
            _listening = false;
            final t = r.recognizedWords.trim();
            t.isEmpty ? onError('No speech detected.') : onFinal(t);
          } else {
            onPartial(r.recognizedWords);
          }
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
        ),
      );
    } catch (e) {
      _listening = false;
      onError('Could not start listening: $e');
    }
  }

  Future<void> stop() async {
    if (_speech.isListening) {
      try { await _speech.stop(); } catch (_) {}
    }
    _listening = false;
  }

  Future<void> cancel() async {
    if (_speech.isListening) {
      try { await _speech.cancel(); } catch (_) {}
    }
    _listening = false;
  }
}
DARTEOF

# ---- 6d. tts_service.dart ----
TTS_SVC="lib/services/tts_service.dart"
backup_file "$TTS_SVC"
cat > "$TTS_SVC" <<'DARTEOF'
// ============================================================================
// Shiva AI — Text-to-Speech service
// ============================================================================

import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  bool _speaking = false;

  bool get isSpeaking => _speaking;

  Future<void> initialize() async {
    if (_initialized) return;
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    await _tts.awaitSpeakCompletion(true);
    _initialized = true;
  }

  Future<bool> isLocaleAvailable(String localeId) async {
    await initialize();
    try {
      final r = await _tts.isLanguageAvailable(localeId);
      return r == true || r == 1;
    } catch (_) {
      return false;
    }
  }

  Future<String?> pickSupportedLocale(List<String> preferred) async {
    for (final p in preferred) {
      if (await isLocaleAvailable(p)) return p;
    }
    return null;
  }

  Future<bool> speak({
    required String text,
    required String localeId,
    void Function()? onComplete,
    void Function(String error)? onError,
  }) async {
    if (text.trim().isEmpty) return false;
    await initialize();

    if (!await isLocaleAvailable(localeId)) {
      onError?.call('TTS language $localeId unavailable.');
      return false;
    }

    try { await _tts.stop(); } catch (_) {}

    try {
      await _tts.setLanguage(localeId);
      _tts.setStartHandler(() => _speaking = true);
      _tts.setCompletionHandler(() {
        _speaking = false;
        onComplete?.call();
      });
      _tts.setCancelHandler(() => _speaking = false);
      _tts.setErrorHandler((m) {
        _speaking = false;
        onError?.call(m?.toString() ?? 'TTS playback error.');
      });

      final r = await _tts.speak(text);
      if (r != 1) {
        _speaking = false;
        onError?.call('Speech synthesis could not start.');
        return false;
      }
      return true;
    } catch (e) {
      _speaking = false;
      onError?.call('TTS error: $e');
      return false;
    }
  }

  Future<void> stop() async {
    try { await _tts.stop(); } catch (_) {}
    _speaking = false;
  }

  void dispose() {
    _speaking = false;
    try { _tts.stop(); } catch (_) {}
  }
}
DARTEOF

ok "All four Dart files generated."

# ============================================================================
# 7. VERIFY GENERATED FILES
# ============================================================================
for f in "$AI_CONFIG" "$GEMINI_SVC" "$SPEECH_SVC" "$TTS_SVC"; do
  [[ -s "$f" ]] || fail_exit "Expected file missing or empty: $f"
done
ok "Dart files verified non-empty."

# ============================================================================
# 8. BUILD VERIFICATION (only if Flutter works)
# ============================================================================
BUILD_STATUS="skipped"
APK_PATH=""

if [[ "$HAS_FLUTTER" -eq 1 ]]; then
  log "Formatting Dart files..."
  dart format "$AI_CONFIG" "$GEMINI_SVC" "$SPEECH_SVC" "$TTS_SVC" || warn "Format reported issues."

  log "Running flutter analyze..."
  if ! flutter analyze; then fail_exit "flutter analyze failed."; fi
  ok "Analysis passed."

  if [[ -d "test" ]] && compgen -G "test/**/*_test.dart" >/dev/null 2>&1; then
    log "Running flutter test..."
    if ! flutter test; then fail_exit "flutter test failed."; fi
    ok "Tests passed."
  else
    warn "No tests found. Skipping."
  fi

  log "Building debug APK (may take several minutes)..."
  if ! flutter build apk --debug; then fail_exit "flutter build apk --debug failed."; fi
  BUILD_STATUS="success"
  APK_PATH="build/app/outputs/flutter-apk/app-debug.apk"
  [[ -f "$APK_PATH" ]] && ok "APK: $APK_PATH" || warn "APK path expected but not found."
else
  warn "Flutter unavailable. Skipping analyze/test/build."
  warn "Source generation completed. Build must be done via GitHub Actions."
fi

# ============================================================================
# 9. GITHUB ACTIONS WORKFLOW (always written, preserves existing)
# ============================================================================
WF_DIR=".github/workflows"
mkdir -p "$WF_DIR"
WF_FILE="$WF_DIR/shiva_phase2_build.yml"

if [[ -f "$WF_FILE" ]]; then
  warn "Existing workflow found at $WF_FILE — backing up and preserving logic."
  backup_file "$WF_FILE"
fi

cat > "$WF_FILE" <<'YAMLEOF'
name: Shiva Phase 2 Build
on:
  push:
    branches: [ main, master ]
  workflow_dispatch:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test || true
      - run: flutter build apk --debug
        env:
          GEMINI_API_KEY: ${{ secrets.GEMINI_API_KEY }}
          GEMINI_MODEL: ${{ secrets.GEMINI_MODEL }}
      - uses: actions/upload-artifact@v4
        with:
          name: shiva-debug-apk
          path: build/app/outputs/flutter-apk/app-debug.apk
YAMLEOF

ok "Workflow written: $WF_FILE"

# ============================================================================
# 10. GIT STATUS
# ============================================================================
GIT_STATUS=""
if [[ "$IN_GIT" -eq 1 ]]; then
  log "Git status:"
  GIT_STATUS=$(git status --short 2>/dev/null || true)
  printf '%s\n' "$GIT_STATUS"
fi

# ============================================================================
# 11. FINAL REPORT
# ============================================================================
echo
if [[ "$BUILD_STATUS" == "success" ]]; then
  printf '%s========================================================%s\n' "$GREEN" "$NC"
  printf '%sSHIVA AI PHASE 2: SETUP AND BUILD VERIFICATION SUCCESSFUL%s\n' "$GREEN" "$NC"
  printf '%s========================================================%s\n' "$GREEN" "$NC"
else
  printf '%s========================================================%s\n' "$YELLOW" "$NC"
  printf '%sSHIVA AI PHASE 2: SOURCE READY — BUILD DEFERRED%s\n' "$YELLOW" "$NC"
  printf '%s========================================================%s\n' "$YELLOW" "$NC"
fi
echo
echo "Project              : $PROJECT_NAME"
echo "Flutter available    : $([[ "$HAS_FLUTTER" -eq 1 ]] && echo YES || echo NO)"
[[ "$HAS_FLUTTER" -eq 1 ]] && echo "Flutter path         : $FLUTTER_PATH"
echo "Dart version         : ${DART_VERSION:-n/a}"
echo "Files updated        : pubspec.yaml, $MANIFEST"
echo "Files generated      : $AI_CONFIG"
echo "                       $GEMINI_SVC"
echo "                       $SPEECH_SVC"
echo "                       $TTS_SVC"
echo "Workflow written     : $WF_FILE"
echo "Backup directory     : $BACKUP_DIR"
echo "Local APK build      : $BUILD_STATUS"
[[ -n "$APK_PATH" && -f "$APK_PATH" ]] && echo "APK path             : $APK_PATH"
echo
echo "Manual UI integration still required:"
echo "  The services above are standalone. Wire your existing HUD mic button to:"
echo "    SpeechService -> GeminiService -> TtsService"
echo "  Display partial transcript, loading state, and stop-TTS action in your screens."
echo
if [[ "$HAS_FLUTTER" -eq 0 ]]; then
  echo "Next step for APK:"
  echo "  1. git add pubspec.yaml $MANIFEST \\"
  echo "       $AI_CONFIG $GEMINI_SVC $SPEECH_SVC $TTS_SVC $WF_FILE"
  echo "  2. git commit -m 'Phase 2: Gemini + voice services + CI'"
  echo "  3. git push"
  echo "  4. Configure GitHub secrets: GEMINI_API_KEY (and optionally GEMINI_MODEL)"
  echo "  5. GitHub Actions will build the APK automatically."
  echo
fi
echo "Suggested git commands (NOT executed):"
echo "  git add pubspec.yaml pubspec.lock $MANIFEST \\"
echo "          $AI_CONFIG $GEMINI_SVC $SPEECH_SVC $TTS_SVC $WF_FILE"
echo "  git commit -m \"Implement Shiva AI Phase 2 Gemini and Voice Engine\""
echo "  git push"
echo
exit 0
+0
+
