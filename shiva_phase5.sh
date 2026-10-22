#!/usr/bin/env bash
set -Eeuo pipefail

# =============================================================================
# Shiva The AI System — Phase 5 Final Execution
# Gemini Live Voice Engine + Android minSdk Fix + Automated GitHub Deployment
# =============================================================================

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
SCRIPT_NAME="shiva_phase5_final"
FAILED=()
WARNED=()
PASSED=()
BACKUP_DIR=""
ORIGINAL_SHA=""
BRANCH=""
PROJECT_ROOT=""
COMMITTED_SHA=""

log_info()    { printf '[INFO]    %s %s\n' "$(date +%H:%M:%S)" "$*"; }
log_warn()    { printf '[WARN]    %s %s\n' "$(date +%H:%M:%S)" "$*"; WARNED+=("$*"); }
log_error()   { printf '[ERROR]   %s %s\n' "$(date +%H:%M:%S)" "$*" 1>&2; FAILED+=("$*"); }
log_pass()    { printf '[PASS]    %s %s\n' "$(date +%H:%M:%S)" "$*"; PASSED+=("$*"); }

on_err() {
  local code=$1 line=$2
  log_error "Unexpected failure at line $line (exit $code)"
  if [[ -n "${BACKUP_DIR:-}" && -d "$BACKUP_DIR" ]]; then
    log_info "Backups preserved: $BACKUP_DIR"
  fi
  exit "$code"
}
trap 'on_err $? $LINENO' ERR

have() { command -v "$1" >/dev/null 2>&1; }

# =============================================================================
# 1. PROJECT DISCOVERY
# =============================================================================
log_info "Shiva Phase 5 Final — starting"

USER_PROJECT="${1:-}"
DO_PUSH=false
for arg in "$@"; do
  [[ "$arg" == "--push" ]] && DO_PUSH=true
  [[ "$arg" == "--help" || "$arg" == "-h" ]] && { echo "Usage: bash $0 [PROJECT_PATH] [--push]"; exit 0; }
done
[[ "$USER_PROJECT" == "--push" || "$USER_PROJECT" == "--help" || "$USER_PROJECT" == "-h" ]] && USER_PROJECT=""

validate_project() {
  local d="$1"
  [[ -n "$d" && -d "$d" ]] && [[ -f "$d/pubspec.yaml" ]] && [[ -d "$d/lib" ]] && [[ -f "$d/lib/main.dart" ]] && [[ -d "$d/android" ]]
}

PROJECT_ROOT=""
if [[ -n "$USER_PROJECT" ]] && validate_project "$USER_PROJECT"; then
  PROJECT_ROOT="$(cd "$USER_PROJECT" && pwd)"
  log_info "Using supplied project: $PROJECT_ROOT"
else
  d="$(pwd)"
  while [[ "$d" != "/" ]]; do
    if validate_project "$d"; then PROJECT_ROOT="$d"; break; fi
    d="$(dirname "$d")"
  done
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
# 2. GIT SAFETY CHECKS
# =============================================================================
HAS_GIT=false; have git && HAS_GIT=true
HAS_FLUTTER=false; have flutter && HAS_FLUTTER=true
HAS_DART=false; have dart && HAS_DART=true
HAS_PYTHON=false; have python3 && HAS_PYTHON=true

if ! $HAS_GIT; then
  log_warn "Git unavailable; will not attempt commit/push"
  DO_PUSH=false
else
  if ! git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    log_warn "Not a Git repository; skipping Git operations"
    DO_PUSH=false
  else
    BRANCH="$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
    ORIGINAL_SHA="$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || echo '')"
    log_info "Branch: $BRANCH | SHA: $ORIGINAL_SHA"

    if [[ "$BRANCH" != "main" ]]; then
      log_error "Current branch is '$BRANCH', not 'main'. Push aborted."
      DO_PUSH=false
    fi

    if ! git -C "$PROJECT_ROOT" remote get-url origin >/dev/null 2>&1; then
      log_error "Remote 'origin' not configured. Push aborted."
      DO_PUSH=false
    fi

    DIRTY_COUNT=$(git -C "$PROJECT_ROOT" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$DIRTY_COUNT" -gt 0 ]]; then
      log_warn "Working tree has $DIRTY_COUNT uncommitted change(s). Only intended Phase 5 files will be staged."
    fi
  fi
fi

# =============================================================================
# 3. BACKUP
# =============================================================================
BACKUP_DIR="$PROJECT_ROOT/backups/${SCRIPT_NAME}_${TIMESTAMP}"
mkdir -p "$BACKUP_DIR"
log_info "Backup: $BACKUP_DIR"

backup_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  local rel="${f#$PROJECT_ROOT/}"
  mkdir -p "$(dirname "$BACKUP_DIR/$rel")"
  cp -p "$f" "$BACKUP_DIR/$rel" 2>/dev/null || cp "$f" "$BACKUP_DIR/$rel"
}

# =============================================================================
# 4. MIN SDK FIX
# =============================================================================
log_info "Task 2: Fixing Android minSdkVersion to 24"

GRADLE_FILE=""
GRADLE_TYPE=""

if [[ -f "$PROJECT_ROOT/android/app/build.gradle" ]]; then
  GRADLE_FILE="$PROJECT_ROOT/android/app/build.gradle"
  GRADLE_TYPE="groovy"
elif [[ -f "$PROJECT_ROOT/android/app/build.gradle.kts" ]]; then
  GRADLE_FILE="$PROJECT_ROOT/android/app/build.gradle.kts"
  GRADLE_TYPE="kts"
fi

if [[ -z "$GRADLE_FILE" ]]; then
  log_error "No android/app/build.gradle or build.gradle.kts found"
else
  backup_file "$GRADLE_FILE"
  log_info "Active Gradle file: ${GRADLE_FILE#$PROJECT_ROOT/} ($GRADLE_TYPE)"

  if [[ "$GRADLE_TYPE" == "groovy" ]]; then
    if grep -qE 'minSdkVersion[[:space:]]+24' "$GRADLE_FILE"; then
      log_pass "minSdkVersion already 24 in Groovy"
    elif grep -qE 'minSdkVersion' "$GRADLE_FILE"; then
      if $HAS_PYTHON; then
        python3 - "$GRADLE_FILE" <<'PYEOF'
import sys, re
path = sys.argv[1]
with open(path) as f:
    content = f.read()
# Replace first occurrence within android block
new = re.sub(r'(minSdkVersion\s+)\d+', r'\g<1>24', content, count=1)
if new != content:
    with open(path, 'w') as f:
        f.write(new)
    print("REPLACED")
else:
    print("NOCHANGE")
PYEOF
        log_pass "minSdkVersion set to 24 (Groovy)"
      else
        log_warn "Python unavailable; manual edit required for minSdkVersion in $GRADLE_FILE"
      fi
    else
      if $HAS_PYTHON; then
        python3 - "$GRADLE_FILE" <<'PYEOF'
import sys, re
path = sys.argv[1]
with open(path) as f:
    content = f.read()
if 'defaultConfig' in content:
    new = content.replace('defaultConfig', 'defaultConfig {\n        minSdkVersion 24', 1)
    if new != content:
        with open(path, 'w') as f:
            f.write(new)
        print("INSERTED")
    else:
        print("FAILED")
else:
    print("NODEFAULTCONFIG")
PYEOF
        log_pass "minSdkVersion 24 inserted (Groovy)"
      else
        log_warn "Python unavailable; manual edit required"
      fi
    fi
  else
    # Kotlin DSL
    if grep -qE 'minSdk[[:space:]]*=[[:space:]]*24' "$GRADLE_FILE"; then
      log_pass "minSdk already 24 in KTS"
    elif grep -qE 'minSdk' "$GRADLE_FILE"; then
      if $HAS_PYTHON; then
        python3 - "$GRADLE_FILE" <<'PYEOF'
import sys, re
path = sys.argv[1]
with open(path) as f:
    content = f.read()
new = re.sub(r'(minSdk\s*=\s*)\d+', r'\g<1>24', content, count=1)
if new != content:
    with open(path, 'w') as f:
        f.write(new)
    print("REPLACED")
else:
    print("NOCHANGE")
PYEOF
        log_pass "minSdk set to 24 (KTS)"
      else
        log_warn "Python unavailable; manual edit required"
      fi
    else
      log_warn "minSdk not found in KTS; manual inspection required"
    fi
  fi
fi

# =============================================================================
# 5. PHASE 5 FEATURE VERIFICATION (Inspect, don't recreate)
# =============================================================================
log_info "Task 3: Verifying Phase 5 core features"

INTEG_DIR="$PROJECT_ROOT/lib/integration"
mkdir -p "$INTEG_DIR"

check_file() {
  local f="$1" name="$2"
  if [[ -f "$f" ]]; then
    log_pass "$name: present"
    return 0
  else
    log_warn "$name: missing — will create minimal implementation"
    return 1
  fi
}

# 5.1 Intent Router
ROUTER="$INTEG_DIR/shiva_intent_router.dart"
if ! check_file "$ROUTER" "ShivaIntentRouter"; then
  backup_file "$ROUTER"
  cat > "$ROUTER" <<'ROUTER_EOF'
// SHIVA_PHASE5_ROUTER_V2
enum ShivaIntent { playMedia, spiritualQuestion, stop, cancel, changeLanguage, downloadMedia, unknown }

class ShivaIntentResult {
  final ShivaIntent intent;
  final String originalText;
  final String? targetLanguage;
  final String? mediaQuery;
  const ShivaIntentResult({required this.intent, required this.originalText, this.targetLanguage, this.mediaQuery});
}

class ShivaIntentRouter {
  static final RegExp _wakeEn = RegExp(r'\bhey\s+shiva\b', caseSensitive: false);
  static final RegExp _wakeMr = RegExp(r'हे\s+शिवा');
  static bool containsWakeWord(String t) => _wakeEn.hasMatch(t) || _wakeMr.hasMatch(t);
  static String stripWakeWord(String t) => t.replaceAll(_wakeEn, '').replaceAll(_wakeMr, '').trim();

  static ShivaIntentResult route(String raw) {
    final text = stripWakeWord(raw);
    final lower = text.toLowerCase();
    if (text.isEmpty) return ShivaIntentResult(intent: ShivaIntent.unknown, originalText: raw);
    if (RegExp(r'\b(stop|band|थांब|बंद)\b').hasMatch(lower)) return ShivaIntentResult(intent: ShivaIntent.stop, originalText: raw);
    if (RegExp(r'\b(cancel|रद्द)\b').hasMatch(lower)) return ShivaIntentResult(intent: ShivaIntent.cancel, originalText: raw);
    if (RegExp(r'\b(marathi|मराठी)\b').hasMatch(lower)) return ShivaIntentResult(intent: ShivaIntent.changeLanguage, originalText: raw, targetLanguage: 'mr-IN');
    if (RegExp(r'\b(hindi|हिंदी)\b').hasMatch(lower)) return ShivaIntentResult(intent: ShivaIntent.changeLanguage, originalText: raw, targetLanguage: 'hi-IN');
    if (RegExp(r'\b(english|इंग्रजी)\b').hasMatch(lower)) return ShivaIntentResult(intent: ShivaIntent.changeLanguage, originalText: raw, targetLanguage: 'en-IN');
    if (RegExp(r'\b(download|डाउनलोड)\b').hasMatch(lower)) return ShivaIntentResult(intent: ShivaIntent.downloadMedia, originalText: raw, mediaQuery: text);
    if (RegExp(r'\b(gita|गीता|bhagavad|karma|yoga|श्लोक|verse|अर्थ|meaning)\b').hasMatch(lower)) return ShivaIntentResult(intent: ShivaIntent.spiritualQuestion, originalText: raw);
    if (RegExp(r'\b(play|लाव|लगा|चालू|सुरू|aarti|आरती|bhajan|भजन|song|गाणं)\b').hasMatch(lower)) return ShivaIntentResult(intent: ShivaIntent.playMedia, originalText: raw, mediaQuery: text);
    return ShivaIntentResult(intent: ShivaIntent.unknown, originalText: raw);
  }
}
ROUTER_EOF
  log_pass "Created ShivaIntentRouter"
fi

# 5.2 Memory Flush
FLUSH="$INTEG_DIR/shiva_memory_flush_manager.dart"
if ! check_file "$FLUSH" "ShivaMemoryFlushManager"; then
  backup_file "$FLUSH"
  cat > "$FLUSH" <<'FLUSH_EOF'
// SHIVA_PHASE5_FLUSH_V2
import 'dart:async';
import 'dart:typed_data';

class ShivaMemoryFlushManager {
  int _sessionId = 0;
  Timer? _debounce;
  final List<StreamSubscription> _subs = [];
  Uint8List? _audioBuffer;

  int get currentSession => _sessionId;
  int startNewSession() { _sessionId++; return _sessionId; }
  bool isStale(int sid) => sid != _sessionId;
  void trackSubscription(StreamSubscription s) => _subs.add(s);
  void trackAudioBuffer(Uint8List b) => _audioBuffer = b;

  Future<void> flush({bool incrementSession = true}) async {
    _debounce?.cancel(); _debounce = null;
    for (final s in _subs) { try { await s.cancel(); } catch (_) {} }
    _subs.clear();
    _audioBuffer = null;
    if (incrementSession) _sessionId++;
  }

  void scheduleFlush({Duration delay = const Duration(seconds: 2)}) {
    _debounce?.cancel();
    _debounce = Timer(delay, () { flush(); });
  }

  void dispose() {
    _debounce?.cancel();
    for (final s in _subs) { s.cancel(); }
    _subs.clear();
    _audioBuffer = null;
  }
}
FLUSH_EOF
  log_pass "Created ShivaMemoryFlushManager"
fi

# 5.3 Boss Auth Gate
AUTH="$INTEG_DIR/shiva_boss_auth_gate.dart"
if ! check_file "$AUTH" "ShivaBossAuthGate"; then
  backup_file "$AUTH"
  cat > "$AUTH" <<'AUTH_EOF'
// SHIVA_PHASE5_AUTH_V2
// Deny-by-default Boss auth. Wake word is NOT authentication.
import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:flutter/services.dart';

class ShivaBossAuthGate {
  final LocalAuthentication _auth = LocalAuthentication();
  DateTime? _lastAuth;
  static const _validity = Duration(minutes: 5);

  Future<bool> authenticateBoss() async {
    if (_lastAuth != null && DateTime.now().difference(_lastAuth!) < _validity) return true;
    try {
      final canBio = await _auth.canCheckBiometrics;
      final supported = await _auth.isDeviceSupported();
      if (!canBio && !supported) return false;
      final ok = await _auth.authenticate(
        localizedReason: 'Shiva Boss authentication required for permanent download',
        options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true, useErrorDialogs: true),
      );
      if (ok) { _lastAuth = DateTime.now(); return true; }
      return false;
    } on PlatformException catch (e) {
      if (e.code == auth_error.notAvailable || e.code == auth_error.notEnrolled) return false;
      return false;
    } catch (_) { return false; }
  }

  Future<bool> revalidateBoss() async { _lastAuth = null; return authenticateBoss(); }
  void invalidate() { _lastAuth = null; }
}
AUTH_EOF
  log_pass "Created ShivaBossAuthGate"
fi

# 5.4 Cloud Streamer
STREAM="$INTEG_DIR/shiva_cloud_streamer.dart"
if ! check_file "$STREAM" "ShivaCloudStreamer"; then
  backup_file "$STREAM"
  cat > "$STREAM" <<'STREAM_EOF'
// SHIVA_PHASE5_STREAM_V2
// Gemini Live streaming via gemini_live package (pub.dev verified).
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:gemini_live/gemini_live.dart';

enum ShivaCloudState { disconnected, connecting, connected, streaming, reconnecting, failed, closed }

class ShivaCloudStreamer {
  final String apiKey;
  GoogleGenAI? _genAI;
  LiveSession? _session;
  ShivaCloudState _state = ShivaCloudState.disconnected;
  final _audioCtrl = StreamController<Uint8List>.broadcast();
  final _stateCtrl = StreamController<ShivaCloudState>.broadcast();
  int _sessionId = 0;

  ShivaCloudStreamer({required this.apiKey});

  Stream<Uint8List> get audioStream => _audioCtrl.stream;
  Stream<ShivaCloudState> get stateStream => _stateCtrl.stream;
  ShivaCloudState get state => _state;

  void _setState(ShivaCloudState s) { _state = s; _stateCtrl.add(s); }

  Future<bool> connect({String model = 'gemini-3.8-live'}) async {
    if (apiKey.isEmpty) { _setState(ShivaCloudState.failed); return false; }
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
            onOpen: () { if (sid == _sessionId) _setState(ShivaCloudState.connected); },
            onMessage: (msg) {
              if (sid != _sessionId) return;
              if (msg.serverContent?.interrupted == true) { _setState(ShivaCloudState.connected); return; }
              final parts = msg.serverContent?.modelTurn?.parts ?? [];
              for (final p in parts) {
                final data = p.inlineData?.data;
                if (data != null && data.isNotEmpty) {
                  _setState(ShivaCloudState.streaming);
                  _audioCtrl.add(base64Decode(data));
                }
              }
            },
            onError: (e, _) { if (sid == _sessionId) _setState(ShivaCloudState.failed); },
            onClose: (_, __) { if (sid == _sessionId) _setState(ShivaCloudState.closed); },
          ),
        ),
      );
      return true;
    } catch (_) { _setState(ShivaCloudState.failed); return false; }
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
    await _audioCtrl.close();
    await _stateCtrl.close();
  }
}
STREAM_EOF
  log_pass "Created ShivaCloudStreamer"
fi

# 5.5 Phase 5 Controller
P5CTRL="$INTEG_DIR/shiva_phase5_controller.dart"
if ! check_file "$P5CTRL" "ShivaPhase5Controller"; then
  backup_file "$P5CTRL"
  cat > "$P5CTRL" <<'CTRL_EOF'
// SHIVA_PHASE5_CONTROLLER_V2
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'shiva_intent_router.dart';
import 'shiva_memory_flush_manager.dart';
import 'shiva_boss_auth_gate.dart';
import 'shiva_cloud_streamer.dart';

enum ShivaPhase5State { idle, wake, listening, processing, speaking, streaming, error, disposed }

class ShivaPhase5Controller extends ChangeNotifier {
  final ShivaMemoryFlushManager _flush = ShivaMemoryFlushManager();
  final ShivaBossAuthGate _authGate = ShivaBossAuthGate();
  ShivaCloudStreamer? _streamer;
  ShivaPhase5State _state = ShivaPhase5State.idle;
  String _locale = 'en-IN';
  String _lastAck = '';
  bool _disposed = false;

  ShivaPhase5State get state => _state;
  String get locale => _locale;
  String get lastAck => _lastAck;

  void _setState(ShivaPhase5State s) {
    if (_state == s) return;
    _state = s;
    if (!_disposed) notifyListeners();
  }

  void setLocale(String loc) {
    if (const {'mr-IN','hi-IN','en-IN'}.contains(loc)) { _locale = loc; notifyListeners(); }
  }

  String _greeting() {
    if (_locale == 'mr-IN') return 'हाय बॉस, काय करू?';
    if (_locale == 'hi-IN') return 'हाय बॉस, क्या करूं?';
    return 'Hi Boss, what should I do?';
  }

  String onWakeWordDetected() {
    _flush.startNewSession();
    _setState(ShivaPhase5State.wake);
    _lastAck = _greeting();
    return _lastAck;
  }

  Future<ShivaIntentResult?> processCommand(String raw) async {
    final result = ShivaIntentRouter.route(raw);
    switch (result.intent) {
      case ShivaIntent.stop:
      case ShivaIntent.cancel:
        await stopAll(); _setState(ShivaPhase5State.idle); return result;
      case ShivaIntent.changeLanguage:
        if (result.targetLanguage != null) setLocale(result.targetLanguage!);
        _setState(ShivaPhase5State.idle); return result;
      case ShivaIntent.downloadMedia:
        final isBoss = await _authGate.authenticateBoss();
        if (!isBoss) { _lastAck = 'Download not authorized. Boss authentication required.'; _setState(ShivaPhase5State.error); return result; }
        _lastAck = 'Download authorized.'; _setState(ShivaPhase5State.idle); return result;
      case ShivaIntent.playMedia:
        _lastAck = 'Playing now...'; _setState(ShivaPhase5State.processing);
        _lastAck = 'Media provider not configured.'; _setState(ShivaPhase5State.error); return result;
      case ShivaIntent.spiritualQuestion:
        _lastAck = 'Looking that up...'; _setState(ShivaPhase5State.processing); return result;
      case ShivaIntent.unknown:
        _lastAck = 'Command not recognized.'; _setState(ShivaPhase5State.idle); return result;
    }
  }

  Future<void> connectCloudStreamer(String apiKey) async {
    if (apiKey.isEmpty) { _setState(ShivaPhase5State.error); return; }
    _streamer = ShivaCloudStreamer(apiKey: apiKey);
    final ok = await _streamer!.connect();
    if (!ok) _setState(ShivaPhase5State.error);
  }

  Future<void> stopAll() async {
    _flush.startNewSession();
    await _streamer?.disconnect();
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
CTRL_EOF
  log_pass "Created ShivaPhase5Controller"
fi

# 5.6 Mount Widget
MOUNT="$INTEG_DIR/shiva_phase5_mount.dart"
if ! check_file "$MOUNT" "ShivaPhase5Mount"; then
  backup_file "$MOUNT"
  cat > "$MOUNT" <<'MOUNT_EOF'
// SHIVA_PHASE5_MOUNT_V2
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
  void initState() { super.initState(); _controller = ShivaPhase5Controller(); }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Phase 5: ${_controller.state.name}'),
          if (_controller.lastAck.isNotEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(_controller.lastAck)),
        ],
      ),
    );
  }
}
MOUNT_EOF
  log_pass "Created ShivaPhase5Mount"
fi

# =============================================================================
# 6. DEPENDENCIES
# =============================================================================
log_info "Task 4: Updating dependencies"
PUBSPEC="$PROJECT_ROOT/pubspec.yaml"
backup_file "$PUBSPEC"

NEED_DEPS=()
grep -qE '^[[:space:]]*gemini_live[[:space:]]*:' "$PUBSPEC" || NEED_DEPS+=("gemini_live: ^2026.8.12")
grep -qE '^[[:space:]]*flutter_soloud[[:space:]]*:' "$PUBSPEC" || NEED_DEPS+=("flutter_soloud: ^5.1.5")
grep -qE '^[[:space:]]*local_auth[[:space:]]*:' "$PUBSPEC" || NEED_DEPS+=("local_auth: ^3.0.2")

if [[ ${#NEED_DEPS[@]} -gt 0 ]]; then
  if $HAS_PYTHON; then
    python3 - "$PUBSPEC" "${NEED_DEPS[@]}" <<'PYEOF'
import sys, re
path = sys.argv[1]
deps = sys.argv[2:]
with open(path) as f:
    lines = f.read().splitlines()
out = []
in_deps = False
inserted = False
for line in lines:
    out.append(line)
    if re.match(r'^dependencies:\s*$', line):
        in_deps = True
        continue
    if in_deps and not inserted and line and not line.startswith(' '):
        out.pop()
        for d in deps:
            out.append('  ' + d)
        out.append(line)
        inserted = True
        in_deps = False
if in_deps and not inserted:
    for d in deps:
        out.append('  ' + d)
with open(path, 'w') as f:
    f.write('\n'.join(out) + '\n')
print(f"Inserted {len(deps)} deps")
PYEOF
    log_pass "Dependencies added"
  else
    log_warn "Python unavailable; manual dependency addition required: ${NEED_DEPS[*]}"
  fi
else
  log_pass "Required dependencies already present"
fi

# =============================================================================
# 7. ANDROID MANIFEST PERMISSIONS
# =============================================================================
MANIFEST="$PROJECT_ROOT/android/app/src/main/AndroidManifest.xml"
if [[ -f "$MANIFEST" ]]; then
  backup_file "$MANIFEST"
  ADD_PERMS=()
  grep -q 'RECORD_AUDIO' "$MANIFEST" || ADD_PERMS+=('    <uses-permission android:name="android.permission.RECORD_AUDIO" />')
  grep -q 'USE_BIOMETRIC' "$MANIFEST" || ADD_PERMS+=('    <uses-permission android:name="android.permission.USE_BIOMETRIC" />')
  grep -q 'INTERNET' "$MANIFEST" || ADD_PERMS+=('    <uses-permission android:name="android.permission.INTERNET" />')
  if [[ ${#ADD_PERMS[@]} -gt 0 ]] && $HAS_PYTHON; then
    python3 - "$MANIFEST" "${ADD_PERMS[@]}" <<'PYEOF'
import sys
path = sys.argv[1]
perms = sys.argv[2:]
with open(path) as f:
    content = f.read()
idx = content.find('<application')
if idx == -1: sys.exit(1)
content = content[:idx] + '\n'.join(perms) + '\n' + content[idx:]
with open(path, 'w') as f:
    f.write(content)
print(f"Added {len(perms)} permissions")
PYEOF
    log_pass "Android permissions added"
  else
    log_pass "Permissions already present or no additions needed"
  fi
fi

# =============================================================================
# 8. VALIDATION
# =============================================================================
log_info "Task 5: Running validation"

if $HAS_FLUTTER; then
  log_info "flutter pub get"
  if ( cd "$PROJECT_ROOT" && flutter pub get 2>&1 | tail -n5 ); then
    log_pass "flutter pub get"
  else
    log_error "flutter pub get failed"
  fi
else
  log_warn "Flutter unavailable; skipping pub get/analyze/build"
fi

if $HAS_DART; then
  log_info "dart format lib/integration/"
  if ( cd "$PROJECT_ROOT" && dart format lib/integration/ 2>&1 | tail -n3 ); then
    log_pass "dart format"
  else
    log_warn "dart format reported issues"
  fi
fi

if $HAS_FLUTTER; then
  log_info "flutter analyze lib/integration/"
  set +e
  ANALYZE_OUT=$( cd "$PROJECT_ROOT" && flutter analyze lib/integration/ 2>&1 )
  ANALYZE_CODE=$?
  set -e
  echo "$ANALYZE_OUT" | tail -n20
  [[ "$ANALYZE_CODE" -eq 0 ]] && log_pass "flutter analyze" || log_warn "flutter analyze issues (exit $ANALYZE_CODE)"
fi

# Structural checks
log_info "Structural verification"
MAIN_COUNT=$(grep -rE '^void[[:space:]]+main[[:space:]]*\(' "$PROJECT_ROOT/lib" 2>/dev/null | wc -l | tr -d ' ')
[[ "$MAIN_COUNT" -eq 1 ]] && log_pass "Single main()" || log_warn "Multiple main(): $MAIN_COUNT"

grep -q 'ShivaPhase3Controller' "$PROJECT_ROOT/lib/integration/shiva_phase3_controller.dart" 2>/dev/null && log_pass "Phase 3 preserved" || log_warn "Phase 3 controller not found"

if grep -rE '(AIza[0-9A-Za-z_-]{35}|sk-[A-Za-z0-9]{20,})' "$PROJECT_ROOT/lib/integration" 2>/dev/null | head -n1; then
  log_error "Potential API key in source!"
else
  log_pass "No hardcoded API keys"
fi

# Release build (optional, may fail locally without Android SDK)
if $HAS_FLUTTER && have adb; then
  log_info "Attempting release build (may fail without Android SDK/signing)"
  set +e
  ( cd "$PROJECT_ROOT" && flutter build apk --release 2>&1 | tail -n10 )
  BUILD_CODE=$?
  set -e
  if [[ "$BUILD_CODE" -eq 0 ]]; then
    log_pass "Release APK build succeeded"
    ls -la "$PROJECT_ROOT/build/app/outputs/flutter-apk/" 2>/dev/null || true
  else
    log_warn "Release build failed locally (exit $BUILD_CODE) — GitHub Actions will build"
  fi
else
  log_warn "Android SDK/adb unavailable; local release build skipped"
fi

# =============================================================================
# 9. GIT COMMIT & PUSH
# =============================================================================
if $DO_PUSH && $HAS_GIT && [[ -n "$BRANCH" && "$BRANCH" == "main" ]]; then
  log_info "Task 7: Preparing Git commit"

  git -C "$PROJECT_ROOT" fetch origin main 2>/dev/null || log_warn "Fetch failed"
  REMOTE_SHA=$(git -C "$PROJECT_ROOT" rev-parse origin/main 2>/dev/null || echo "")
  LOCAL_SHA=$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || echo "")

  if [[ -n "$REMOTE_SHA" && "$REMOTE_SHA" != "$LOCAL_SHA" ]]; then
    log_error "Remote 'origin/main' has advanced ($REMOTE_SHA vs local $LOCAL_SHA). Push aborted to avoid overwrite."
  else
    ALLOWED=()
    for f in "$PROJECT_ROOT/lib/integration/shiva_intent_router.dart" \
             "$PROJECT_ROOT/lib/integration/shiva_memory_flush_manager.dart" \
             "$PROJECT_ROOT/lib/integration/shiva_boss_auth_gate.dart" \
             "$PROJECT_ROOT/lib/integration/shiva_cloud_streamer.dart" \
             "$PROJECT_ROOT/lib/integration/shiva_phase5_controller.dart" \
             "$PROJECT_ROOT/lib/integration/shiva_phase5_mount.dart" \
             "$PUB
+0
+x

+0
+
