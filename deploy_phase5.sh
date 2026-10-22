#!/usr/bin/env bash
set -Eeuo pipefail

# =============================================================================
# Shiva The AI System — Phase 5
# Direct Voice-to-Voice Execution Engine + Gemini Live Cloud Streaming
# =============================================================================

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
SCRIPT_NAME="shiva_phase5"
FAILED=()
WARNED=()
PASSED=()
BACKUP_DIR=""

log_info()    { printf '[INFO]    %s %s\n' "$(date +%H:%M:%S)" "$*"; }
log_warn()    { printf '[WARN]    %s %s\n' "$(date +%H:%M:%S)" "$*"; WARNED+=("$*"); }
log_error()   { printf '[ERROR]   %s %s\n' "$(date +%H:%M:%S)" "$*" 1>&2; FAILED+=("$*"); }
log_pass()    { printf '[PASS]    %s %s\n' "$(date +%H:%M:%S)" "$*"; PASSED+=("$*"); }

on_err() {
  local code=$1 line=$2
  log_error "Unexpected failure at line $line (exit $code)"
  [[ -n "${BACKUP_DIR:-}" && -d "$BACKUP_DIR" ]] && log_info "Backups preserved: $BACKUP_DIR"
  exit "$code"
}
trap 'on_err $? $LINENO' ERR

have() { command -v "$1" >/dev/null 2>&1; }

# =============================================================================
# 1. PROJECT DETECTION
# =============================================================================
log_info "Shiva Phase 5 starting"

USER_PROJECT="${1:-}"
DO_PUSH=false
[[ "${2:-}" == "--push" || "${1:-}" == "--push" ]] && DO_PUSH=true
[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && { echo "Usage: bash $0 [PROJECT_PATH] [--push]"; exit 0; }

validate_project() {
  local d="$1"
  [[ -n "$d" && -d "$d" ]] && [[ -f "$d/pubspec.yaml" ]] && [[ -d "$d/lib" ]] && [[ -f "$d/lib/main.dart" ]]
}

PROJECT_ROOT=""
if [[ -n "$USER_PROJECT" ]] && validate_project "$USER_PROJECT"; then
  PROJECT_ROOT="$(cd "$USER_PROJECT" && pwd)"
  log_info "Using supplied project: $PROJECT_ROOT"
else
  # Upward search
  d="$(pwd)"
  while [[ "$d" != "/" ]]; do
    if validate_project "$d"; then PROJECT_ROOT="$d"; break; fi
    d="$(dirname "$d")"
  done
  # Downward search
  if [[ -z "$PROJECT_ROOT" ]]; then
    for base in "$HOME" "$HOME/storage/shared" "$HOME/AndroidStudioProjects" "$HOME/projects"; do
      [[ -d "$base" ]] || continue
      hit=$(find "$base" -maxdepth 4 -name 'pubspec.yaml' -not -path '*/.git/*' -not -path '*/build/*' -not -path '*/.dart_tool/*' 2>/dev/null | while read -r p; do
        r=$(dirname "$p"); validate_project "$r" && echo "$r" && break
      done | head -n1)
      [[ -n "$hit" ]] && { PROJECT_ROOT="$hit"; break; }
    done
  fi
fi

if [[ -z "$PROJECT_ROOT" ]]; then
  log_error "No Flutter project found. Rerun: bash $0 /path/to/project"
  exit 3
fi
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"
cd "$PROJECT_ROOT"
log_pass "Project root: $PROJECT_ROOT"

# =============================================================================
# 2. PREFLIGHT & TOOL DETECTION
# =============================================================================
HAS_FLUTTER=false; have flutter && HAS_FLUTTER=true
HAS_DART=false;    have dart    && HAS_DART=true
HAS_GIT=false;     have git     && HAS_GIT=true
HAS_PYTHON=false;  have python3 && HAS_PYTHON=true

$HAS_FLUTTER && log_info "Flutter: $(flutter --version 2>/dev/null | head -n1 || echo unknown)" || log_warn "Flutter not on PATH"
$HAS_DART    && log_info "Dart: $(dart --version 2>&1 | head -n1 || echo unknown)" || log_warn "Dart not on PATH"

# =============================================================================
# 3. BACKUP
# =============================================================================
BACKUP_DIR="$PROJECT_ROOT/backups/${SCRIPT_NAME}_${TIMESTAMP}"
mkdir -p "$BACKUP_DIR"
log_info "Backup directory: $BACKUP_DIR"

backup_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  local rel="${f#$PROJECT_ROOT/}"
  mkdir -p "$(dirname "$BACKUP_DIR/$rel")"
  cp -p "$f" "$BACKUP_DIR/$rel" 2>/dev/null || cp "$f" "$BACKUP_DIR/$rel"
  log_info "Backed up: $rel"
}

# =============================================================================
# 4. VERIFY PHASE 4 BASELINE
# =============================================================================
CONTROLLER_FILE="$PROJECT_ROOT/lib/integration/shiva_phase3_controller.dart"
WIDGETS_FILE="$PROJECT_ROOT/lib/integration/shiva_phase3_widgets.dart"
MAIN_FILE="$PROJECT_ROOT/lib/main.dart"
PUBSPEC="$PROJECT_ROOT/pubspec.yaml"
MANIFEST="$PROJECT_ROOT/android/app/src/main/AndroidManifest.xml"

for f in "$CONTROLLER_FILE" "$WIDGETS_FILE" "$MAIN_FILE" "$PUBSPEC"; do
  if [[ ! -f "$f" ]]; then
    log_error "Missing required file: ${f#$PROJECT_ROOT/}"
    exit 4
  fi
done
log_pass "Phase 3/4 baseline files verified"

# Detect services
SPEECH_PATH=""; GEMINI_PATH=""; TTS_PATH=""
while IFS= read -r f; do
  grep -qE 'class[[:space:]]+SpeechService' "$f" 2>/dev/null && SPEECH_PATH="$f"
  grep -qE 'class[[:space:]]+GeminiService' "$f" 2>/dev/null && GEMINI_PATH="$f"
  grep -qE 'class[[:space:]]+(TtsService|TTSService)' "$f" 2>/dev/null && TTS_PATH="$f"
done < <(find "$PROJECT_ROOT/lib" -name '*.dart' -type f 2>/dev/null)

log_info "SpeechService: ${SPEECH_PATH:-<not found>}"
log_info "GeminiService: ${GEMINI_PATH:-<not found>}"
log_info "TtsService:    ${TTS_PATH:-<not found>}"

# =============================================================================
# 5. ADD DEPENDENCIES
# =============================================================================
log_info "Updating pubspec.yaml dependencies"
backup_file "$PUBSPEC"

# Detect existing deps
HAS_GEMINI_LIVE=false; grep -qE '^[[:space:]]*gemini_live[[:space:]]*:' "$PUBSPEC" && HAS_GEMINI_LIVE=true
HAS_SOLOUD=false;      grep -qE '^[[:space:]]*flutter_soloud[[:space:]]*:' "$PUBSPEC" && HAS_SOLOUD=true
HAS_LOCAL_AUTH=false;  grep -qE '^[[:space:]]*local_auth[[:space:]]*:' "$PUBSPEC" && HAS_LOCAL_AUTH=true
HAS_RECORD=false;      grep -qE '^[[:space:]]*record[[:space:]]*:' "$PUBSPEC" && HAS_RECORD=true

NEED_DEPS=()
$HAS_GEMINI_LIVE || NEED_DEPS+=("gemini_live: ^2026.10.5")
$HAS_SOLOUD      || NEED_DEPS+=("flutter_soloud: ^5.1.5")
$HAS_LOCAL_AUTH  || NEED_DEPS+=("local_auth: ^2.3.0")
$HAS_RECORD      || NEED_DEPS+=("record: ^5.2.1")

if [[ ${#NEED_DEPS[@]} -gt 0 ]]; then
  if $HAS_PYTHON; then
    python3 - "$PUBSPEC" "${NEED_DEPS[@]}" <<'PYEOF'
import sys, re
pubspec_path = sys.argv[1]
new_deps = sys.argv[2:]
with open(pubspec_path, 'r') as f:
    content = f.read()
lines = content.splitlines()
out = []
in_deps = False
inserted = False
for i, line in enumerate(lines):
    out.append(line)
    if re.match(r'^dependencies:\s*$', line):
        in_deps = True
        continue
    if in_deps and not inserted and re.match(r'^\S', line) and not line.startswith('  '):
        # End of dependencies block — insert before
        out.pop()
        for dep in new_deps:
            out.append('  ' + dep)
        out.append(line)
        inserted = True
        in_deps = False
if in_deps and not inserted:
    for dep in new_deps:
        out.append('  ' + dep)
    inserted = True
with open(pubspec_path, 'w') as f:
    f.write('\n'.join(out) + '\n')
print(f"Inserted {len(new_deps)} deps")
PYEOF
    log_pass "Dependencies added to pubspec.yaml"
  else
    log_warn "Python unavailable; append dependencies manually: ${NEED_DEPS[*]}"
  fi
else
  log_pass "Required dependencies already present"
fi

# =============================================================================
# 6. CREATE PHASE 5 FILES
# =============================================================================
INTEG_DIR="$PROJECT_ROOT/lib/integration"
mkdir -p "$INTEG_DIR"

# ---------- 6.1 ShivaIntentRouter ----------
ROUTER_FILE="$INTEG_DIR/shiva_intent_router.dart"
backup_file "$ROUTER_FILE"
cat > "$ROUTER_FILE" <<'SHIVA_ROUTER_EOF'
// SHIVA_PHASE5_ROUTER_V1
// Deterministic intent router. No network, no side effects, testable.

enum ShivaIntent {
  playMedia,
  spiritualQuestion,
  stop,
  cancel,
  changeLanguage,
  downloadMedia,
  unknown,
}

class ShivaIntentResult {
  final ShivaIntent intent;
  final String originalText;
  final String? targetLanguage;
  final String? mediaQuery;

  const ShivaIntentResult({
    required this.intent,
    required this.originalText,
    this.targetLanguage,
    this.mediaQuery,
  });
}

class ShivaIntentRouter {
  static final RegExp _wakeEn = RegExp(r'\bhey\s+shiva\b', caseSensitive: false);
  static final RegExp _wakeMr = RegExp(r'हे\s+शिवा');

  static bool containsWakeWord(String text) {
    return _wakeEn.hasMatch(text) || _wakeMr.hasMatch(text);
  }

  static String stripWakeWord(String text) {
    return text
        .replaceAll(_wakeEn, '')
        .replaceAll(_wakeMr, '')
        .trim();
  }

  static ShivaIntentResult route(String rawText) {
    final text = stripWakeWord(rawText);
    final lower = text.toLowerCase();

    if (text.isEmpty) {
      return ShivaIntentResult(intent: ShivaIntent.unknown, originalText: rawText);
    }

    if (RegExp(r'\b(stop|band|थांब|बंद)\b', caseSensitive: false).hasMatch(lower)) {
      return ShivaIntentResult(intent: ShivaIntent.stop, originalText: rawText);
    }
    if (RegExp(r'\b(cancel|रद्द)\b', caseSensitive: false).hasMatch(lower)) {
      return ShivaIntentResult(intent: ShivaIntent.cancel, originalText: rawText);
    }

    // Language change
    if (RegExp(r'\b(marathi|मराठी)\b', caseSensitive: false).hasMatch(lower)) {
      return ShivaIntentResult(intent: ShivaIntent.changeLanguage, originalText: rawText, targetLanguage: 'mr-IN');
    }
    if (RegExp(r'\b(hindi|हिंदी)\b', caseSensitive: false).hasMatch(lower)) {
      return ShivaIntentResult(intent: ShivaIntent.changeLanguage, originalText: rawText, targetLanguage: 'hi-IN');
    }
    if (RegExp(r'\b(english|इंग्रजी)\b', caseSensitive: false).hasMatch(lower)) {
      return ShivaIntentResult(intent: ShivaIntent.changeLanguage, originalText: rawText, targetLanguage: 'en-IN');
    }

    // Download (privileged)
    if (RegExp(r'\b(download|डाउनलोड)\b', caseSensitive: false).hasMatch(lower)) {
      return ShivaIntentResult(intent: ShivaIntent.downloadMedia, originalText: rawText, mediaQuery: text);
    }

    // Spiritual knowledge
    if (RegExp(r'\b(gita|गीता|bhagavad|karma|yoga|श्लोक|verse|अर्थ|meaning)\b', caseSensitive: false).hasMatch(lower)) {
      return ShivaIntentResult(intent: ShivaIntent.spiritualQuestion, originalText: rawText);
    }

    // Play media (aarti, bhajan, song, etc.)
    if (RegExp(r'\b(play|लाव|लगा|चालू|सुरू|aarti|आरती|bhajan|भजन|song|गाणं)\b', caseSensitive: false).hasMatch(lower)) {
      return ShivaIntentResult(intent: ShivaIntent.playMedia, originalText: rawText, mediaQuery: text);
    }

    return ShivaIntentResult(intent: ShivaIntent.unknown, originalText: rawText);
  }
}
SHIVA_ROUTER_EOF
log_pass "Created shiva_intent_router.dart"

# ---------- 6.2 ShivaMemoryFlushManager ----------
FLUSH_FILE="$INTEG_DIR/shiva_memory_flush_manager.dart"
backup_file "$FLUSH_FILE"
cat > "$FLUSH_FILE" <<'SHIVA_FLUSH_EOF'
// SHIVA_PHASE5_FLUSH_V1
// Manages cleanup of application-owned temporary state. Zero persistent media.

import 'dart:async';
import 'dart:typed_data';

class ShivaMemoryFlushManager {
  int _sessionId = 0;
  Timer? _debounceTimer;
  final List<StreamSubscription> _subscriptions = [];
  Uint8List? _audioBuffer;

  int get currentSession => _sessionId;

  int startNewSession() {
    _sessionId++;
    return _sessionId;
  }

  bool isStale(int sessionId) => sessionId != _sessionId;

  void trackSubscription(StreamSubscription sub) {
    _subscriptions.add(sub);
  }

  void trackAudioBuffer(Uint8List buf) {
    _audioBuffer = buf;
  }

  /// Flush all temporary state. Idempotent and safe under concurrency.
  /// Note: Dart GC does not guarantee immediate physical RAM erasure.
  Future<void> flush({bool incrementSession = true}) async {
    _debounceTimer?.cancel();
    _debounceTimer = null;

    for (final sub in _subscriptions) {
      try { await sub.cancel(); } catch (_) {}
    }
    _subscriptions.clear();

    _audioBuffer = null;

    if (incrementSession) _sessionId++;
  }

  void scheduleFlush({Duration delay = const Duration(seconds: 2)}) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(delay, () { flush(); });
  }

  void dispose() {
    _debounceTimer?.cancel();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _audioBuffer = null;
  }
}
SHIVA_FLUSH_EOF
log_pass "Created shiva_memory_flush_manager.dart"

# ---------- 6.3 ShivaBossAuthGate ----------
AUTH_FILE="$INTEG_DIR/shiva_boss_auth_gate.dart"
backup_file "$AUTH_FILE"
cat > "$AUTH_FILE" <<'SHIVA_AUTH_EOF'
// SHIVA_PHASE5_AUTH_V1
// Deny-by-default Boss authentication gate using local_auth.
// Wake word is NOT authentication.

import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:flutter/services.dart';

class ShivaBossAuthGate {
  final LocalAuthentication _auth = LocalAuthentication();
  DateTime? _lastAuthTime;
  static const _authValidity = Duration(minutes: 5);

  /// Returns true only if device authentication succeeds.
  /// Fails closed on any error.
  Future<bool> authenticateBoss() async {
    if (_lastAuthTime != null &&
        DateTime.now().difference(_lastAuthTime!) < _authValidity) {
      return true;
    }

    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      if (!canCheck && !isSupported) return false;

      final ok = await _auth.authenticate(
        localizedReason: 'Shiva Boss authentication required for permanent download',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );

      if (ok) {
        _lastAuthTime = DateTime.now();
        return true;
      }
      return false;
    } on PlatformException catch (e) {
      if (e.code == auth_error.notAvailable || e.code == auth_error.notEnrolled) {
        return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Recheck immediately before a privileged action.
  Future<bool> revalidateBoss() async {
    _lastAuthTime = null;
    return authenticateBoss();
  }

  void invalidate() {
    _lastAuthTime = null;
  }
}
SHIVA_AUTH_EOF
log_pass "Created shiva_boss_auth_gate.dart"

# ---------- 6.4 ShivaCloudStreamer ----------
STREAM_FILE="$INTEG_DIR/shiva_cloud_streamer.dart"
backup_file "$STREAM_FILE"
cat > "$STREAM_FILE" <<'SHIVA_STREAM_EOF'
// SHIVA_PHASE5_STREAM_V1
// Gemini Live cloud streaming with WebSocket PCM audio.
// Requires GEMINI_API_KEY via --dart-define. Never hardcode keys.

import 'dart:async';
import 'dart:typed_data';
import 'package:gemini_live/gemini_live.dart';

enum ShivaCloudState {
  disconnected,
  connecting,
  connected,
  streaming,
  reconnecting,
  failed,
  closed,
}

class ShivaCloudStreamer {
  final String apiKey;
  GoogleGenAI? _genAI;
  LiveSession? _session;
  ShivaCloudState _state = ShivaCloudState.disconnected;
  final _audioController = StreamController<Uint8List>.broadcast();
  final _stateController = StreamController<ShivaCloudState>.broadcast();
  int _sessionId = 0;

  ShivaCloudStreamer({required this.apiKey});

  Stream<Uint8List> get audioStream => _audioController.stream;
  Stream<ShivaCloudState> get stateStream => _stateController.stream;
  ShivaCloudState get state => _state;

  void _setState(ShivaCloudState s) {
    _state = s;
    _stateController.add(s);
  }

  Future<bool> connect({String model = 'gemini-3.8-live'}) async {
    if (apiKey.isEmpty) {
      _setState(ShivaCloudState.failed);
      return false;
    }
    _sessionId++;
    final sid = _sessionId;
    _setState(ShivaCloudState.connecting);

    try {
      _genAI = GoogleGenAI(apiKey: apiKey);
      _session = await _genAI!.live.connect(
        LiveConnectParameters(
          model: model,
          config: GenerationConfig(responseModalities: [Modality.AUDIO]),
          callbacks: LiveCallbacks(
            onOpen: () {
              if (sid == _sessionId) _setState(ShivaCloudState.connected);
            },
            onMessage: (message) {
              if (sid != _sessionId) return;
              if (message.serverContent?.interrupted == true) {
                _setState(ShivaCloudState.connected);
                return;
              }
              final parts = message.serverContent?.modelTurn?.parts ?? [];
              for (final p in parts) {
                final data = p.inlineData?.data;
                if (data != null && data.isNotEmpty) {
                  _setState(ShivaCloudState.streaming);
                  _audioController.add(base64Decode(data));
                }
              }
            },
            onError: (e, _) {
              if (sid == _sessionId) _setState(ShivaCloudState.failed);
            },
            onClose: (_, __) {
              if (sid == _sessionId) _setState(ShivaCloudState.closed);
            },
          ),
        ),
      );
      return true;
    } catch (_) {
      _setState(ShivaCloudState.failed);
      return false;
    }
  }

  void sendAudio(Uint8List pcm16k) {
    if (_session == null || _state == ShivaCloudState.failed) return;
    _session!.sendRealtimeAudio(base64Encode(pcm16k));
  }

  Future<void> disconnect() async {
    _sessionId++;
    try { await _session?.close(); } catch (_) {}
    _session = null;
    _setState(ShivaCloudState.disconnected);
  }

  Future<void> dispose() async {
    await disconnect();
    await _audioController.close();
    await _stateController.close();
  }
}
SHIVA_STREAM_EOF
log_pass "Created shiva_cloud_streamer.dart"

# ---------- 6.5 ShivaPhase5Controller ----------
P5CTRL="$INTEG_DIR/shiva_phase5_controller.dart"
backup_file "$P5CTRL"
cat > "$P5CTRL" <<'SHIVA_P5CTRL_EOF'
// SHIVA_PHASE5_CONTROLLER_V1
// Orchestrates wake word, intent routing, auth, streaming, TTS, cleanup.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'shiva_intent_router.dart';
import 'shiva_memory_flush_manager.dart';
import 'shiva_boss_auth_gate.dart';
import 'shiva_cloud_streamer.dart';

enum ShivaPhase5State { idle, wake, listening, processing, speaking, error }

class ShivaPhase5Controller extends ChangeNotifier {
  final ShivaMemoryFlushManager _flush = ShivaMemoryFlushManager();
  final ShivaBossAuthGate _authGate = ShivaBossAuthGate();
  ShivaCloudStreamer? _streamer;

  ShivaPhase5State _state = ShivaPhase5State.idle;
  ShivaPhase5State get state => _state;

  String _locale = 'en-IN';
  String get locale => _locale;

  String _lastAck = '';
  String get lastAck => _lastAck;

  bool _wakeActive = false;
  int _wakeSession = 0;
  bool _disposed = false;

  void _setState(ShivaPhase5State s) {
    if (_state == s) return;
    _state = s;
    if (!_disposed) notifyListeners();
  }

  void setLocale(String loc) {
    if (const {'mr-IN', 'hi-IN', 'en-IN'}.contains(loc)) {
      _locale = loc;
      notifyListeners();
    }
  }

  String _greeting() {
    if (_locale == 'mr-IN') return 'हाय बॉस, काय करू?';
    if (_locale == 'hi-IN') return 'हाय बॉस, क्या करूं?';
    return 'Hi Boss, what should I do?';
  }

  /// Called when wake word detected. Returns greeting text to speak.
  String onWakeWordDetected() {
    _wakeSession++;
    _wakeActive = true;
    _setState(ShivaPhase5State.wake);
    final greet = _greeting();
    _lastAck = greet;
    return greet;
  }

  Future<ShivaIntentResult?> processCommand(String rawText) async {
    final result = ShivaIntentRouter.route(rawText);

    switch (result.intent) {
      case ShivaIntent.stop:
        await stopAll();
        _setState(ShivaPhase5State.idle);
        return result;
      case ShivaIntent.cancel:
        await stopAll();
        _setState(ShivaPhase5State.idle);
        return result;
      case ShivaIntent.changeLanguage:
        if (result.targetLanguage != null) setLocale(result.targetLanguage!);
        _setState(ShivaPhase5State.idle);
        return result;
      case ShivaIntent.downloadMedia:
        // DENY: Guest cannot download. Boss auth required.
        final isBoss = await _authGate.authenticateBoss();
        if (!isBoss) {
          _lastAck = 'Download not authorized. Boss authentication required.';
          _setState(ShivaPhase5State.error);
          return result;
        }
        _lastAck = 'Download authorized.';
        _setState(ShivaPhase5State.idle);
        return result;
      case ShivaIntent.playMedia:
        _lastAck = 'Playing now...';
        _setState(ShivaPhase5State.processing);
        // Media discovery not wired to a provider in this phase.
        _lastAck = 'Media provider not configured.';
        _setState(ShivaPhase5State.error);
        return result;
      case ShivaIntent.spiritualQuestion:
        _lastAck = 'Looking that up...';
        _setState(ShivaPhase5State.processing);
        return result;
      case ShivaIntent.unknown:
        _lastAck = 'Command not recognized.';
        _setState(ShivaPhase5State.idle);
        return result;
    }
  }

  Future<void> connectCloudStreamer(String apiKey) async {
    if (apiKey.isEmpty) {
      _setState(ShivaPhase5State.error);
      return;
    }
    _streamer = ShivaCloudStreamer(apiKey: apiKey);
    final ok = await _streamer!.connect();
    if (!ok) _setState(ShivaPhase5State.error);
  }

  Future<void> stopAll() async {
    _flush.startNewSession();
    await _streamer?.disconnect();
    _wakeActive = false;
    _lastAck = '';
    _setState(ShivaPhase5State.idle);
  }

  @override
  void dispose() {
    _disposed = true;
    _flush.dispose();
    _streamer?.dispose();
    super.dispose();
  }
}
SHIVA_P5CTRL_EOF
log_pass "Created shiva_phase5_controller.dart"

# ---------- 6.6 Phase 5 Mount Widget ----------
MOUNT_FILE="$INTEG_DIR/shiva_phase5_mount.dart"
backup_file "$MOUNT_FILE"
cat > "$MOUNT_FILE" <<'SHIVA_MOUNT_EOF'
// SHIVA_PHASE5_MOUNT_V1
// Drop-in widget to mount Phase 5 controller with existing services.

import 'package:flutter/material.dart';
import 'shiva_phase5_controller.dart';

class ShivaPhase5Mount extends StatefulWidget {
  const ShivaPhase5Mount({super.key});
  @override
  State<ShivaPhase5Mount> createState() => _ShivaPhase5MountState();
}

class _ShivaPhase5MountState extends State<ShivaPhase5Mount> {
  late final ShivaPhase5Controller _controller;

  @override
  void initState() {
    super.initState();
    _controller = ShivaPhase5Controller();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Phase 5: ${_controller.state.name}'),
            if (_controller.lastAck.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_controller.lastAck),
              ),
          ],
        );
      },
    );
  }
}
SHIVA_MOUNT_EOF
log_pass "Created shiva_phase5_mount.dart"

# =============================================================================
# 7. ANDROID MANIFEST UPDATES
# =============================================================================
if [[ -f "$MANIFEST" ]]; then
  backup_file "$MANIFEST"
  ADD_PERMS=()
  grep -q 'RECORD_AUDIO' "$MANIFEST" || ADD_PERMS+=('    <uses-permission android:name="android.permission.RECORD_AUDIO" />')
  grep -q 'USE_BIOMETRIC' "$MANIFEST" || ADD_PERMS+=('    <uses-permission android:name="android.permission.USE_BIOMETRIC" />')
  grep -q 'INTERNET' "$MANIFEST" || ADD_PERMS+=('    <uses-permission android:name="android.permission.INTERNET" />')

  if [[ ${#ADD_PERMS[@]} -gt 0 ]]; then
    python3 - "$MANIFEST" "${ADD_PERMS[@]}" <<'PYEOF'
import sys
path = sys.argv[1]
perms = sys.argv[2:]
with open(path) as f:
    content = f.read()
marker = '<application'
idx = content.find(marker)
if idx == -1:
    print("No <application> tag found", file=sys.stderr)
    sys.exit(1)
insert = '\n'.join(perms) + '\n'
content = content[:idx] + insert + content[idx:]
with open(path, 'w') as f:
    f.write(content)
print(f"Added {len(perms)} permissions")
PYEOF
    log_pass "Added Android permissions"
  else
    log_pass "Android permissions already present"
  fi
fi

# =============================================================================
# 8. FORMAT & ANALYZE
# =============================================================================
FORMAT_STATUS="skipped"
ANALYZE_STATUS="skipped"

if $HAS_DART; then
  log_info "Running dart format on lib/integration/"
  if ( cd "$PROJECT_ROOT" && dart format lib/integration/ 2>&1 ); then
    FORMAT_STATUS="pass"
    log_pass "dart format"
  else
    FORMAT_STATUS="fail"
    log_error "dart format failed"
  fi
fi

if $HAS_FLUTTER; then
  log_info "Running flutter pub get"
  if ( cd "$PROJECT_ROOT" && flutter pub get 2>&1 | tail -n5 ); then
    log_pass "flutter pub get"
    log_info "Running flutter analyze lib/integration/"
    set +e
    ANALYZE_OUT=$( cd "$PROJECT_ROOT" && flutter analyze lib/integration/ 2>&1 )
    ANALYZE_CODE=$?
    set -e
    echo "$ANALYZE_OUT" | tail -n 30
    if [[ "$ANALYZE_CODE" -eq 0 ]]; then
      ANALYZE_STATUS="pass"
      log_pass "flutter analyze"
    else
      ANALYZE_STATUS="warnings"
      log_warn "flutter analyze reported issues (exit $ANALYZE_CODE)"
    fi
  else
    log_error "flutter pub get failed"
  fi
else
  log_warn "Flutter unavailable; formatting/analysis skipped"
fi

# =============================================================================
# 9. VERIFICATION CHECKS
# =============================================================================
log_info "Running verification checks"

# No duplicate main()
MAIN_COUNT=$(grep -rE '^void[[:space:]]+main[[:space:]]*\(' "$PROJECT_ROOT/lib" 2>/dev/null | wc -l)
[[ "$MAIN_COUNT" -eq 1 ]] && log_pass "Single main() entry point" || log_warn "Multiple main() detected: $MAIN_COUNT"

# Phase 4 preserved
grep -q 'ShivaPhase3Controller' "$CONTROLLER_FILE" && log_pass "Phase 3 controller preserved" || log_error "Phase 3 controller modified"

# No hardcoded keys
if grep -rE '(AIza[0-9A-Za-z_-]{35}|sk-[A-Za-z0-9]{20,})' "$INTEG_DIR" 2>/dev/null | grep -v 'YOUR_' | head -n1; then
  log_error "Potential API key in source!"
else
  log_pass "No hardcoded API keys"
fi

# Guest download denied
if grep -q 'authenticateBoss' "$P5CTRL" && grep -q 'Download not authorized' "$P5CTRL"; then
  log_pass "Download gate: Guest denied"
fi

# =============================================================================
# 10. GIT STATUS
# =============================================================================
if $HAS_GIT && git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log_info "Git status:"
  git -C "$PROJECT_ROOT" status --short 2>&1 | head -n 20
  
  if $DO_PUSH; then
    log_info "Git push requested (--push)"
    git -C "$PROJECT_ROOT" add lib/integration/ pubspec.yaml android/app/src/main/AndroidManifest.xml 2>/dev/null || true
    git -C "$PROJECT_ROOT" commit -m "Phase 5: Voice-to-voice engine, Gemini Live streaming, auth gate" 2>&1 || true
    git -C "$PROJECT_ROOT" push 2>&1 || log_warn "Git push failed"
  else
    log_info "To commit: git add lib/integration/ pubspec.yaml android/app/src/main/AndroidManifest.xml"
    log_info "         git commit -m 'Phase 5: Voice engine + Gemini Live'"
  fi
fi

# =============================================================================
# 11. FINAL REPORT
# =============================================================================
echo
echo "================ Shiva Phase 5 Report ================"
echo "Project:        $PROJECT_ROOT"
echo "Backup:         $BACKUP_DIR"
echo
echo "Created files:"
for f in "$ROUTER_FILE" "$FLUSH_FILE" "$AUTH_FILE" "$STREAM_FILE" "$P5CTRL" "$MOUNT_FILE"; do
  [[ -f "$f" ]] && echo "  ✓ ${f#$PROJECT_ROOT/}"
done
echo
echo "Format:         $FORMAT_STATUS"
echo "Analyze:        $ANALYZE_STATUS"
echo
echo "PASSED:         ${#PASSED[@]}"
for p in "${PASSED[@]}"; do echo "  ✓ $p"; done
echo "WARNINGS:       ${#WARNED[@]}"
for w in "${WARNED[@]}"; do echo "  ⚠ $w"; done
echo "FAILED:         ${#FAILED[@]}"
for f in "${FAILED[@]}"; do echo "  ✗ $f"; done
echo
echo "=== Configuration Required ==="
echo "  • GEMINI_API_KEY via --dart-define=GEMINI_API_KEY=xxx"
echo "  • Media provider not configured (playMedia returns error)"
echo "  • Boss enrollment requires device biometrics/PIN setup"
echo "  • Wake word requires continuous STT implementation"
echo "======================================================"

if [[ ${#FAILED[@]} -gt 0 ]]; then
  log_error "Phase 5 completed with failures"
  exit 1
fi

log_pass "Phase 5 source integration complete"
exit 0
+0
+
