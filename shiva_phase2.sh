
#!/data/data/com.termux/files/usr/bin/bash
# ============================================================================
# SHIVA THE AI SYSTEM — PHASE 2 AUTOMATION SCRIPT
# Gemini API + Multilingual STT/TTS for Termux
#
# Run from your existing Flutter project root:
#   cd ~/shiva-the-ai-system
#   bash shiva_phase2.sh
#
# This script is safe to re-run. It backs up every file before changing it.
# ============================================================================

set -Eeuo pipefail

# ---------------------------------------------------------------------------
# COLORS
# ---------------------------------------------------------------------------
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

log()  { printf '%s[SHIVA]%s %s\n' "$BLUE"  "$NC" "$*"; }
ok()   { printf '%s[ OK ]%s %s\n'  "$GREEN" "$NC" "$*"; }
warn() { printf '%s[WARN]%s %s\n'  "$YELLOW" "$NC" "$*"; }
err()  { printf '%s[FAIL]%s %s\n'  "$RED"   "$NC" "$*" >&2; }

fail_exit() {
  local msg="${1:-unknown error}"
  err "$msg"
  if [[ -n "${BACKUP_DIR:-}" && -d "${BACKUP_DIR}" ]]; then
    err "Backups are in: $BACKUP_DIR"
  fi
  printf '%sSHIVA AI PHASE 2: INCOMPLETE — SEE ERRORS ABOVE%s\n' "$RED" "$NC"
  exit 1
}

trap 'fail_exit "Unhandled error at line $LINENO"' ERR

# ---------------------------------------------------------------------------
# 1. PRE-FLIGHT CHECKS
# ---------------------------------------------------------------------------
log "Running pre-flight checks..."

if [[ -z "${BASH_VERSION:-}" ]]; then
  fail_exit "This script must be run with bash, not sh."
fi

for cmd in flutter dart git; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    fail_exit "Required command not found: $cmd"
  fi
done
ok "Bash, flutter, dart, git are available."

if [[ ! -f "pubspec.yaml" ]]; then
  fail_exit "pubspec.yaml not found. Run this script from the Flutter project root."
fi

MANIFEST="android/app/src/main/AndroidManifest.xml"
if [[ ! -f "$MANIFEST" ]]; then
  fail_exit "AndroidManifest.xml not found at $MANIFEST"
fi

PROJECT_NAME=$(grep -E '^name:' pubspec.yaml | head -n1 | sed -E 's/^name:[[:space:]]*//' || true)
log "Detected Flutter project: ${PROJECT_NAME:-<unknown>}"

IN_GIT=0
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  IN_GIT=1
  ok "Git repository detected."
else
  warn "Not a Git repository. Continuing without git safety net."
fi

# ---------------------------------------------------------------------------
# 2. BACKUP DIRECTORY
# ---------------------------------------------------------------------------
STAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$(pwd)/.shiva_phase2_backups/$STAMP"
mkdir -p "$BACKUP_DIR"
ok "Backup directory: $BACKUP_DIR"

backup_file() {
  local f="$1"
  if [[ -f "$f" ]]; then
    local dest="$BACKUP_DIR/$(echo "$f" | tr '/' '_')"
    cp -p "$f" "$dest"
    ok "Backed up $f -> $dest"
  fi
}

restore_file() {
  local f="$1"
  local dest="$BACKUP_DIR/$(echo "$f" | tr '/' '_')"
  if [[ -f "$dest" ]]; then
    cp -p "$dest" "$f"
    warn "Restored $f from backup."
  fi
}

# ---------------------------------------------------------------------------
# 3. UPDATE pubspec.yaml
# ---------------------------------------------------------------------------
log "Updating pubspec.yaml dependencies..."

backup_file "pubspec.yaml"

python3 - <<'PYEOF'
import re, sys, pathlib

path = pathlib.Path("pubspec.yaml")
text = path.read_text()

required = {
    "http": "^1.2.0",
    "speech_to_text": "^7.0.0",
    "flutter_tts": "^4.2.0",
    "permission_handler": "^11.3.0",
}

lines = text.splitlines()
in_deps = False
deps_start = None
deps_end = None
existing = {}

for i, line in enumerate(lines):
    if re.match(r'^dependencies:\s*$', line):
        in_deps = True
        deps_start = i
        continue
    if in_deps:
        # End of dependencies block = a top-level key (no leading whitespace, ends with :).
        if re.match(r'^[A-Za-z0-9_]', line) and not line.startswith(' '):
            deps_end = i
            break
        m = re.match(r'^\s+([A-Za-z0-9_]+):\s*(.+)$', line)
        if m:
            existing[m.group(1)] = m.group(2).strip()

if deps_end is None:
    deps_end = len(lines)

if deps_start is None:
    print("ERROR: no 'dependencies:' section found in pubspec.yaml", file=sys.stderr)
    sys.exit(1)

# Only add missing entries; do not overwrite user's existing versions.
additions = [f"  {k}: {v}" for k, v in required.items() if k not in existing]

if not additions:
    print("All required dependencies already present. No changes.")
    sys.exit(0)

new_lines = lines[:deps_end] + additions + lines[deps_end:]
path.write_text("\n".join(new_lines) + "\n")
print("Added dependencies:", ", ".join(k for k in required if k not in existing))
PYEOF

ok "pubspec.yaml updated."

log "Running flutter pub get (this may take a while)..."
if ! flutter pub get; then
  restore_file "pubspec.yaml"
  fail_exit "flutter pub get failed. Restored pubspec.yaml."
fi
ok "flutter pub get succeeded."

# ---------------------------------------------------------------------------
# 4. UPDATE ANDROID MANIFEST
# ---------------------------------------------------------------------------
log "Updating AndroidManifest.xml..."

backup_file "$MANIFEST"

python3 - "$MANIFEST" <<'PYEOF'
import sys, pathlib
import xml.etree.ElementTree as ET

path = pathlib.Path(sys.argv[1])
text = path.read_text()

# --- Permissions ---
required_perms = [
    "android.permission.INTERNET",
    "android.permission.RECORD_AUDIO",
]

for perm in required_perms:
    needle = f'android:name="{perm}"'
    if needle in text:
        print(f"Permission already present: {perm}")
        continue
    # Insert just before </manifest>
    insert = f'    <uses-permission {needle} />\n'
    text = text.replace("</manifest>", insert + "</manifest>", 1)
    print(f"Inserted permission: {perm}")

# --- Queries block ---
queries_needed = [
    ("android.speech.RecognitionService", "intent"),
    ("android.intent.action.TTS_SERVICE", "intent"),
]

# Only add queries that are missing.
to_add = []
for action, kind in queries_needed:
    if action not in text:
        to_add.append(action)

if to_add:
    q_inner = ""
    for action in to_add:
        q_inner += (
            f'        <intent>\n'
            f'            <action android:name="{action}" />\n'
            f'        </intent>\n'
        )
    queries_block = (
        '    <queries>\n'
        + q_inner +
        '    </queries>\n'
    )
    text = text.replace("</manifest>", queries_block + "</manifest>", 1)
    print("Inserted <queries> block for:", ", ".join(to_add))
else:
    print("All required <queries> actions already present.")

path.write_text(text)

# --- Validate XML ---
try:
    ET.parse(str(path))
    print("XML validation: OK")
except ET.ParseError as e:
    print("XML validation FAILED:", e, file=sys.stderr)
    sys.exit(1)
PYEOF

if [[ $? -ne 0 ]]; then
  restore_file "$MANIFEST"
  fail_exit "AndroidManifest.xml update failed. Restored from backup."
fi
ok "AndroidManifest.xml updated and validated."

# ---------------------------------------------------------------------------
# 5. CREATE DIRECTORIES
# ---------------------------------------------------------------------------
mkdir -p lib/config lib/services
ok "Ensured lib/config and lib/services exist."

# ---------------------------------------------------------------------------
# 6. GENERATE lib/config/ai_config.dart
# ---------------------------------------------------------------------------
AI_CONFIG="lib/config/ai_config.dart"
backup_file "$AI_CONFIG"

cat > "$AI_CONFIG" <<'DARTEOF'
// ============================================================================
// Shiva AI — Centralized AI configuration
//
// Compile-time overrides (pass via --dart-define):
//   GEMINI_API_KEY   your Google Gemini API key
//   GEMINI_MODEL     Gemini model identifier (default: gemini-3.8-flash)
//
// SECURITY NOTE:
//   Values provided via --dart-define are compiled into the APK and can be
//   extracted by a determined user. For production-grade protection, route
//   requests through an authenticated backend proxy that holds the key
//   server-side. Do NOT expose an unauthenticated public proxy.
//
// MODEL NOTE:
//   "gemini-3.8-flash" is the assumed current Flash-tier model. If the API
//   returns 404 for this model, check the provider's current documentation
//   and update AiConfig.geminiModel accordingly.
// ============================================================================

class AiConfig {
  AiConfig._();

  /// Compile-time configured API key. Empty string if not supplied.
  static const String geminiApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );

  /// Compile-time configured Gemini model identifier.
  static const String geminiModel = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-3.8-flash',
  );

  /// Max conversation turns retained in context (user+assistant combined).
  static const int maxHistoryEntries = 20;

  /// Network timeout for a single Gemini request.
  static const Duration requestTimeout = Duration(seconds: 30);

  /// Base Gemini REST endpoint.
  static const String geminiBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta';

  /// True when the API key has been provided at build time.
  static bool get hasApiKey => geminiApiKey.isNotEmpty;
}
DARTEOF
ok "Generated $AI_CONFIG"

# ---------------------------------------------------------------------------
# 7. GENERATE lib/services/gemini_service.dart
# ---------------------------------------------------------------------------
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

/// A typed error raised by [GeminiService].
class GeminiException implements Exception {
  final String userMessage;
  final String? technicalDetail;
  final int? statusCode;

  const GeminiException(
    this.userMessage, {
    this.technicalDetail,
    this.statusCode,
  });

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

  /// Sends a single text prompt to Gemini and returns the assistant's reply.
  Future<String> generateResponse(String prompt) async {
    if (prompt.trim().isEmpty) {
      throw const GeminiException('Prompt is empty.');
    }
    if (_apiKey.isEmpty) {
      throw const GeminiException(
        'Gemini API key is not configured. '
        'Rebuild the app with --dart-define=GEMINI_API_KEY=your_key.',
      );
    }

    final uri = Uri.parse(
      '${AiConfig.geminiBaseUrl}/models/$_model:generateContent'
      '?key=$_apiKey',
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
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(AiConfig.requestTimeout);
    } on TimeoutException {
      throw const GeminiException(
        'The request timed out. Check your connection and retry.',
      );
    } on http.ClientException catch (e) {
      throw GeminiException(
        'Network error. Please check your connection.',
        technicalDetail: e.message,
      );
    } catch (e) {
      throw GeminiException(
        'Unexpected network failure.',
        technicalDetail: e.toString(),
      );
    }

    if (response.statusCode != 200) {
      throw _mapHttpError(response.statusCode, response.body);
    }

    return _parseResponseBody(response.body);
  }

  String _parseResponseBody(String rawBody) {
    dynamic decoded;
    try {
      decoded = jsonDecode(rawBody);
    } catch (e) {
      throw GeminiException(
        'Received an invalid response from the AI service.',
        technicalDetail: 'JSON parse failed: $e',
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw const GeminiException('Unexpected response shape from Gemini.');
    }

    // Safety / prompt feedback block
    final feedback = decoded['promptFeedback'];
    if (feedback is Map && feedback['blockReason'] != null) {
      throw GeminiException(
        'The request was blocked by safety filters. Please rephrase.',
        technicalDetail: 'blockReason=${feedback['blockReason']}',
      );
    }

    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw const GeminiException('The AI returned an empty response.');
    }

    final first = candidates.first;
    if (first is! Map) {
      throw const GeminiException('Malformed candidate in response.');
    }

    final finishReason = first['finishReason'];
    if (finishReason is String &&
        finishReason.isNotEmpty &&
        finishReason != 'STOP') {
      if (finishReason == 'SAFETY' ||
          finishReason == 'RECITATION' ||
          finishReason == 'BLOCKLIST') {
        throw GeminiException(
          'The response was blocked ($finishReason). Please try a different prompt.',
        );
      }
    }

    final content = first['content'];
    if (content is! Map) {
      throw const GeminiException('AI response was incomplete.');
    }

    final parts = content['parts'];
    if (parts is! List || parts.isEmpty) {
      throw const GeminiException('AI response contained no text parts.');
    }

    final buffer = StringBuffer();
    for (final part in parts) {
      if (part is Map && part['text'] is String) {
        buffer.write(part['text']);
      }
    }

    final text = buffer.toString().trim();
    if (text.isEmpty) {
      throw const GeminiException('AI response was empty.');
    }
    return text;
  }

  GeminiException _mapHttpError(int status, String body) {
    String? detail;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map) {
          detail = error['message']?.toString();
        }
      }
    } catch (_) {
      // Ignore — detail is optional.
    }

    switch (status) {
      case 400:
        return GeminiException(
          'Invalid request to Gemini.',
          technicalDetail: detail,
          statusCode: status,
        );
      case 401:
      case 403:
        return GeminiException(
          'Gemini API key is invalid or lacks permission.',
          technicalDetail: detail,
          statusCode: status,
        );
      case 404:
        return GeminiException(
          'The configured Gemini model is unavailable.',
          technicalDetail: detail,
          statusCode: status,
        );
      case 429:
        return GeminiException(
          'Rate limit reached. Please wait and retry.',
          technicalDetail: detail,
          statusCode: status,
        );
      default:
        if (status >= 500) {
          return GeminiException(
            'Gemini server error ($status). Please retry later.',
            technicalDetail: detail,
            statusCode: status,
          );
        }
        return GeminiException(
          'Unexpected Gemini error (HTTP $status).',
          technicalDetail: detail,
          statusCode: status,
        );
    }
  }

  void dispose() => _client.close();
}
DARTEOF
ok "Generated $GEMINI_SVC"

# ---------------------------------------------------------------------------
# 8. GENERATE lib/services/speech_service.dart
# ---------------------------------------------------------------------------
SPEECH_SVC="lib/services/speech_service.dart"
backup_file "$SPEECH_SVC"

cat > "$SPEECH_SVC" <<'DARTEOF'
// ============================================================================
// Shiva AI — Speech-to-Text service (speech_to_text wrapper)
// ============================================================================

import 'dart:async';

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

class SpeechServiceException implements Exception {
  final String message;
  const SpeechServiceException(this.message);
  @override
  String toString() => message;
}

class SpeechService {
  final SpeechToText _speech = SpeechToText();

  bool _initialized = false;
  bool _listening = false;

  bool get isListening => _listening && _speech.isListening;
  bool get isInitialized => _initialized;

  /// Initializes the underlying recognizer. Safe to call multiple times.
  Future<bool> initialize({
    void Function(String error)? onError,
  }) async {
    if (_initialized) return true;
    try {
      _initialized = await _speech.initialize(
        onError: (SpeechRecognitionError e) {
          _listening = false;
          onError?.call(_describeError(e));
        },
        onStatus: (String status) {
          if (status == 'done' || status == 'notListening') {
            _listening = false;
          }
        },
      );
      return _initialized;
    } catch (e) {
      _initialized = false;
      onError?.call('Speech initialization failed: $e');
      return false;
    }
  }

  /// Returns the list of locale IDs the device supports.
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

  /// True if [localeId] is supported by this device.
  Future<bool> isLocaleAvailable(String localeId) async {
    final ids = await availableLocaleIds();
    return ids.contains(localeId);
  }

  /// Returns the first of [preferred] that the device supports,
  /// or null if none are supported.
  Future<String?> pickSupportedLocale(List<String> preferred) async {
    final ids = await availableLocaleIds();
    for (final p in preferred) {
      if (ids.contains(p)) return p;
    }
    // Try prefix match (e.g. "mr" for "mr-IN").
    for (final p in preferred) {
      final lang = p.split('-').first;
      for (final id in ids) {
        if (id.startsWith(lang)) return id;
      }
    }
    return null;
  }

  /// Starts listening.
  ///
  /// [onPartial] is called for interim transcripts.
  /// [onFinal]   is called once, with the finalized transcript.
  /// [onError]   is called for any recognition error.
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

    final ok = await initialize(onError: onError);
    if (!ok) {
      onError('Speech recognition is unavailable on this device.');
      return;
    }

    final supported = await isLocaleAvailable(localeId);
    if (!supported) {
      onError('Language $localeId is not available for speech input.');
      return;
    }

    _listening = true;
    try {
      await _speech.listen(
        localeId: localeId,
        onResult: (SpeechRecognitionResult result) {
          if (result.finalResult) {
            _listening = false;
            final text = result.recognizedWords.trim();
            if (text.isEmpty) {
              onError('No speech detected.');
            } else {
              onFinal(text);
            }
          } else {
            onPartial(result.recognizedWords);
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
      try {
        await _speech.stop();
      } catch (_) {}
    }
    _listening = false;
  }

  Future<void> cancel() async {
    if (_speech.isListening) {
      try {
        await _speech.cancel();
      } catch (_) {}
    }
    _listening = false;
  }

  String _describeError(SpeechRecognitionError e) {
    switch (e.errorMsg) {
      case 'error_no_match':
        return 'No speech detected.';
      case 'error_network':
        return 'Network error during speech recognition.';
      case 'error_busy':
        return 'Speech recognition is busy. Try again.';
      case 'error_permission':
        return 'Microphone permission denied.';
      default:
        return 'Speech recognition error: ${e.errorMsg}';
    }
  }
}
DARTEOF
ok "Generated $SPEECH_SVC"

# ---------------------------------------------------------------------------
# 9. GENERATE lib/services/tts_service.dart
# ---------------------------------------------------------------------------
TTS_SVC="lib/services/tts_service.dart"
backup_file "$TTS_SVC"

cat > "$TTS_SVC" <<'DARTEOF'
// ============================================================================
// Shiva AI — Text-to-Speech service (flutter_tts wrapper)
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

  /// True if the device TTS engine supports [localeId] (e.g. "mr-IN").
  Future<bool> isLocaleAvailable(String localeId) async {
    await initialize();
    try {
      final result = await _tts.isLanguageAvailable(localeId);
      // flutter_tts returns true (or 1) when available, false/null otherwise.
      return result == true || result == 1;
    } catch (_) {
      return false;
    }
  }

  /// Returns the first of [preferred] the device supports, or null.
  Future<String?> pickSupportedLocale(List<String> preferred) async {
    for (final p in preferred) {
      if (await isLocaleAvailable(p)) return p;
    }
    return null;
  }

  /// Speaks [text] using [localeId].
  ///
  /// Returns true when speech started successfully. Errors are reported
  /// via [onError] and by returning false; text remains visible in the UI.
  Future<bool> speak({
    required String text,
    required String localeId,
    void Function()? onStart,
    void Function()? onComplete,
    void Function(String error)? onError,
  }) async {
    if (text.trim().isEmpty) return false;
    await initialize();

    final available = await isLocaleAvailable(localeId);
    if (!available) {
      onError?.call('TTS language $localeId is not available.');
      return false;
    }

    try {
      await _tts.stop();
    } catch (_) {}

    try {
      await _tts.setLanguage(localeId);

      _tts.setStartHandler(() {
        _speaking = true;
        onStart?.call();
      });
      _tts.setCompletionHandler(() {
        _speaking = false;
        onComplete?.call();
      });
      _tts.setCancelHandler(() {
        _speaking = false;
      });
      _tts.setErrorHandler((msg) {
        _speaking = false;
        onError?.call(msg?.toString() ?? 'TTS playback error.');
      });

      final result = await _tts.speak(text);
      if (result != 1) {
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
    try {
      await _tts.stop();
    } catch (_) {}
    _speaking = false;
  }

  void dispose() {
    _speaking = false;
    try {
      _tts.stop();
    } catch (_) {}
  }
}
DARTEOF
ok "Generated $TTS_SVC"

# ---------------------------------------------------------------------------
# 10. VERIFY GENERATED FILES
# ---------------------------------------------------------------------------
log "Verifying generated Dart files..."
for f in "$AI_CONFIG" "$GEMINI_SVC" "$SPEECH_SVC" "$TTS_SVC"; do
  if [[ ! -s "$f" ]]; then
    fail_exit "Expected file is missing or empty: $f"
  fi
done
ok "All four Dart files exist and are non-empty."

# ---------------------------------------------------------------------------
# 11. FORMAT & ANALYZE
# ---------------------------------------------------------------------------
log "Formatting generated Dart files..."
if ! dart format "$AI_CONFIG" "$GEMINI_SVC" "$SPEECH_SVC" "$TTS_SVC"; then
  warn "dart format reported issues (continuing)."
fi

log "Running flutter analyze (this may take a while)..."
ANALYZE_OUT=$(flutter analyze 2>&1) || {
  printf '%s\n' "$ANALYZE_OUT" >&2
  fail_exit "flutter analyze failed."
}
ok "flutter analyze passed."

# ---------------------------------------------------------------------------
# 12. TESTS (optional)
# ---------------------------------------------------------------------------
if [[ -d "test" ]] && compgen -G "test/**/*_test.dart" >/dev/null 2>&1; then
  log "Running flutter test..."
  if ! flutter test; then
    fail_exit "flutter test failed."
  fi
  ok "flutter test passed."
else
  warn "No tests found in test/ — skipping flutter test."
fi

# ---------------------------------------------------------------------------
# 13. DEBUG BUILD
# ---------------------------------------------------------------------------
log "Building debug APK (this may take several minutes)..."
if ! flutter build apk --debug; then
  fail_exit "flutter build apk --debug failed."
fi
ok "Debug APK built."

APK_PATH="build/app/outputs/flutter-apk/app-debug.apk"
if [[ -f "$APK_PATH" ]]; then
  ok "APK output: $APK_PATH"
else
  warn "Expected APK not found at $APK_PATH (build may use a different output path)."
fi

# ---------------------------------------------------------------------------
# 14. GIT STATUS
# ---------------------------------------------------------------------------
GIT_STATUS=""
if [[ "$IN_GIT" -eq 1 ]]; then
  log "Git status (modified files):"
  GIT_STATUS=$(git status --short || true)
  printf '%s\n' "$GIT_STATUS"
fi

# ---------------------------------------------------------------------------
# 15. SUCCESS REPORT
# ---------------------------------------------------------------------------
echo
printf '%s========================================================%s\n' "$GREEN" "$NC"
printf '%sSHIVA AI PHASE 2: SETUP AND BUILD VERIFICATION SUCCESSFUL%s\n' "$GREEN" "$NC"
printf '%s========================================================%s\n' "$GREEN" "$NC"
echo
echo "Files created or updated:"
echo "  - pubspec.yaml"
echo "  - $MANIFEST"
echo "  - $AI_CONFIG"
echo "  - $GEMINI_SVC"
echo "  - $SPEECH_SVC"
echo "  - $TTS_SVC"
echo
echo "Dependency resolution : OK (flutter pub get)"
echo "Manifest XML validation: OK"
echo "Static analysis        : OK (flutter analyze)"
if [[ -d "test" ]] && compgen -G "test/**/*_test.dart" >/dev/null 2>&1; then
  echo "Unit tests             : OK"
else
  echo "Unit tests             : skipped (no test/ directory)"
fi
echo "Debug APK build        : OK"
[[ -f "$APK_PATH" ]] && echo "APK path               : $APK_PATH"
echo "Backup directory       : $BACKUP_DIR"
echo
echo "IMPORTANT — Manual integration still required:"
echo "  The following Dart services have been created but are NOT yet"
echo "  wired into your existing UI/HUD:"
echo "    - GeminiService    (lib/services/gemini_service.dart)"
echo "    - SpeechService    (lib/services/speech_service.dart)"
echo "    - TtsService       (lib/services/tts_service.dart)"
echo "  You must connect the microphone button and response display in your"
echo "  existing screens/controllers to use these services."
echo
echo "API key is NOT baked in. To include it for a local debug build:"
echo "  flutter build apk --debug \\"
echo "    --dart-define=GEMINI_API_KEY=YOUR_KEY \\"
echo "    --dart-define=GEMINI_MODEL=gemini-3.8-flash"
echo
echo "Suggested Git commands (NOT executed):"
echo "  git add pubspec.yaml pubspec.lock \\"
echo "          $MANIFEST \\"
echo "          $AI_CONFIG $GEMINI_SVC $SPEECH_SVC $TTS_SVC"
echo "  git commit -m \"Implement Shiva AI Phase 2 Gemini and Voice Engine\""
echo "  git push"
echo

exit 0
+0
+
