#!/usr/bin/env bash
set -Eeuo pipefail

# =====================================================================
# Shiva The AI System - Phase 3 Automation
# Creates Phase 3 controller + widgets, safely mounts into HUD if possible.
# Termux-safe, idempotent, backup-first.
# =====================================================================

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
SCRIPT_NAME="shiva_phase3_setup"

log_info()    { printf '[INFO]    %s %s\n' "$(date +%H:%M:%S)" "$*"; }
log_warn()    { printf '[WARN]    %s %s\n' "$(date +%H:%M:%S)" "$*"; }
log_error()   { printf '[ERROR]   %s %s\n' "$(date +%H:%M:%S)" "$*" 1>&2; }
log_success() { printf '[SUCCESS] %s %s\n' "$(date +%H:%M:%S)" "$*"; }

on_err() {
  local code=$1 line=$2
  log_error "Unexpected failure at line $line (exit $code)"
  log_info  "Backups (if any) preserved under: ${BACKUP_DIR:-<none>}"
  exit "$code"
}
trap 'on_err $? $LINENO' ERR

have() { command -v "$1" >/dev/null 2>&1; }

# =====================================================================
# 1. PROJECT DETECTION
# =====================================================================
log_info "Starting Shiva The AI System - Phase 3 automation"

validate_project_root() {
  local dir="$1"
  [[ -n "$dir" && -d "$dir" ]] || return 1
  [[ -f "$dir/pubspec.yaml" ]] || return 1
  # Must look like a Flutter project
  grep -qE '^[[:space:]]*flutter:' "$dir/pubspec.yaml" 2>/dev/null || return 1
  return 0
}

find_flutter_roots_under() {
  local base="$1"
  [[ -d "$base" ]] || return 0
  find "$base" -maxdepth 4 -type f -name 'pubspec.yaml' \
    \( -name '.git' -prune -o -name 'build' -prune -o -name '.dart_tool' -prune \) \
    2>/dev/null | while IFS= read -r pf; do
      local r
      r="$(dirname "$pf")"
      if validate_project_root "$r"; then
        printf '%s\n' "$r"
      fi
    done
}

CANDIDATE_DIRS=()
if [[ -n "${1:-}" ]]; then
  CANDIDATE_DIRS+=("$1")
  log_info "Using CLI-supplied project path: $1"
fi
if [[ -n "${SHIVA_PROJECT_DIR:-}" ]]; then
  CANDIDATE_DIRS+=("$SHIVA_PROJECT_DIR")
  log_info "Using SHIVA_PROJECT_DIR env: $SHIVA_PROJECT_DIR"
fi
CANDIDATE_DIRS+=("$PWD")
CANDIDATE_DIRS+=("$HOME")
CANDIDATE_DIRS+=("$HOME/Shiva-AI-System")
CANDIDATE_DIRS+=("$HOME/shiva-ai-system")
CANDIDATE_DIRS+=("$HOME/AndroidStudioProjects")
CANDIDATE_DIRS+=("$HOME/storage/shared")
CANDIDATE_DIRS+=("$HOME/storage/shared/Download")
CANDIDATE_DIRS+=("$HOME/storage/shared/Documents")

PROJECT_ROOT=""
FOUND_LIST=""

for base in "${CANDIDATE_DIRS[@]}"; do
  [[ -d "$base" ]] || continue
  # Direct hit
  if validate_project_root "$base"; then
    PROJECT_ROOT="$base"
    log_info "Direct project root match: $PROJECT_ROOT"
    break
  fi
  # Bounded search
  hits="$(find_flutter_roots_under "$base" || true)"
  if [[ -n "$hits" ]]; then
    count="$(printf '%s\n' "$hits" | grep -c . || true)"
    if [[ "$count" -eq 1 ]]; then
      PROJECT_ROOT="$hits"
      log_info "Detected project root via search under $base: $PROJECT_ROOT"
      break
    else
      FOUND_LIST="$hits"
      log_warn "Multiple Flutter roots under $base:"
      printf '%s\n' "$hits" | while IFS= read -r r; do printf '        - %s\n' "$r"; done
      # Prefer one named like shiva if present
      preferred="$(printf '%s\n' "$hits" | grep -iE 'shiva' | head -n1 || true)"
      if [[ -n "$preferred" ]] && validate_project_root "$preferred"; then
        PROJECT_ROOT="$preferred"
        log_info "Preferred Shiva project root: $PROJECT_ROOT"
        break
      fi
    fi
  fi
done

if [[ -z "$PROJECT_ROOT" ]]; then
  if [[ -n "$FOUND_LIST" ]]; then
    log_error "Ambiguous project detection. Re-run with explicit path:"
    printf '%s\n' "$FOUND_LIST" | while IFS= read -r r; do printf '        - %s\n' "$r"; done
    exit 3
  fi
  log_error "No valid Flutter project detected in candidate locations."
  log_error "Run again with: bash $0 /absolute/path/to/project"
  exit 3
fi

PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"
log_success "Selected project root: $PROJECT_ROOT"
cd "$PROJECT_ROOT"

# =====================================================================
# 2. BACKUP
# =====================================================================
BACKUP_ROOT="$PROJECT_ROOT/backups"
BACKUP_DIR="$BACKUP_ROOT/${SCRIPT_NAME}_${TIMESTAMP}"
mkdir -p "$BACKUP_DIR"
log_info "Backup directory: $BACKUP_DIR"

backup_path() {
  local p="$1"
  [[ -e "$p" ]] || return 0
  local rel="${p#$PROJECT_ROOT/}"
  local dest="$BACKUP_DIR/$rel"
  mkdir -p "$(dirname "$dest")"
  cp -pR "$p" "$dest" 2>/dev/null || cp -R "$p" "$dest"
  log_info "Backed up: $rel"
}

# =====================================================================
# 3. INSPECT EXISTING SERVICES / CONFIG
# =====================================================================
log_info "Inspecting existing Phase 1/2 services"

SPEECH_PATH=""
GEMINI_PATH=""
TTS_PATH=""

if [[ -d "$PROJECT_ROOT/lib" ]]; then
  while IFS= read -r f; do
    if grep -qE 'class[[:space:]]+SpeechService' "$f" 2>/dev/null; then SPEECH_PATH="$f"; fi
    if grep -qE 'class[[:space:]]+GeminiService' "$f" 2>/dev/null; then GEMINI_PATH="$f"; fi
    if grep -qE 'class[[:space:]]+(TtsService|TTSService|TextToSpeechService)' "$f" 2>/dev/null; then TTS_PATH="$f"; fi
  done < <(find "$PROJECT_ROOT/lib" -type f -name '*.dart' 2>/dev/null)
fi

[[ -n "$SPEECH_PATH" ]] && log_info "Found SpeechService: ${SPEECH_PATH#$PROJECT_ROOT/}" || log_warn "SpeechService not found"
[[ -n "$GEMINI_PATH" ]] && log_info "Found GeminiService: ${GEMINI_PATH#$PROJECT_ROOT/}" || log_warn "GeminiService not found"
[[ -n "$TTS_PATH"    ]] && log_info "Found TTS Service:   ${TTS_PATH#$PROJECT_ROOT/}"    || log_warn "TTS service not found"

# Derive relative import paths for controller
rel_import() {
  local target="$1"
  if [[ -z "$target" ]]; then printf '%s\n' ""; return; fi
  local rel="${target#$PROJECT_ROOT/lib/}"
  printf '../%s\n' "$rel"
}

SPEECH_REL="$(rel_import "$SPEECH_PATH")"
GEMINI_REL="$(rel_import "$GEMINI_PATH")"
TTS_REL="$(rel_import "$TTS_PATH")"

# If a service is missing, we fall back to a lazy-call pattern; controller
# will accept injected service instances via Object? and call by name.

# =====================================================================
# 4. CREATE CONTROLLER
# =====================================================================
INTEG_DIR="$PROJECT_ROOT/lib/integration"
mkdir -p "$INTEG_DIR"
CONTROLLER_FILE="$INTEG_DIR/shiva_phase3_controller.dart"
WIDGETS_FILE="$INTEG_DIR/shiva_phase3_widgets.dart"

[[ -f "$CONTROLLER_FILE" ]] && backup_path "$CONTROLLER_FILE"
[[ -f "$WIDGETS_FILE"    ]] && backup_path "$WIDGETS_FILE"

# Build the controller with conditional imports
build_controller_imports() {
  if [[ -n "$SPEECH_REL" ]]; then
    printf "import '%s';\n" "$SPEECH_REL"
  else
    printf "// SpeechService import omitted (not detected at build time)\n"
  fi
  if [[ -n "$GEMINI_REL" ]]; then
    printf "import '%s';\n" "$GEMINI_REL"
  else
    printf "// GeminiService import omitted (not detected at build time)\n"
  fi
  if [[ -n "$TTS_REL" ]]; then
    printf "import '%s';\n" "$TTS_REL"
  else
    printf "// TtsService import omitted (not detected at build time)\n"
  fi
}

if [[ -f "$CONTROLLER_FILE" ]] && grep -q '// SHIVA_PHASE3_CONTROLLER_V1' "$CONTROLLER_FILE" 2>/dev/null; then
  log_info "Controller already present with Phase 3 marker; skipping rewrite"
else
  CTRL_IMPORTS="$(build_controller_imports)"
  {
    printf '// SHIVA_PHASE3_CONTROLLER_V1\n'
    printf '// Phase 3 controller - manages UI state for Shiva AI assistant.\n'
    printf '// Additive: does NOT replace any existing services.\n\n'
    printf "import 'package:flutter/foundation.dart';\n"
    printf '%s\n' "$CTRL_IMPORTS"
    printf '\n'
    cat <<'SHIVA_CONTROLLER_EOF'
enum ShivaAssistantState { idle, listening, processing, speaking, error }

class ShivaPhase3Controller extends ChangeNotifier {
  ShivaPhase3Controller({
    this.speechService,
    this.geminiService,
    this.ttsService,
  });

  // Injected services (typed as Object? to avoid hard dependency on class names,
  // but concrete services in lib/services/ are used by name at call time).
  final Object? speechService;
  final Object? geminiService;
  final Object? ttsService;

  static const supportedLocales = <String, String>{
    'mr-IN': 'Marathi',
    'hi-IN': 'Hindi',
    'en-IN': 'English (India)',
  };

  ShivaAssistantState _state = ShivaAssistantState.idle;
  ShivaAssistantState get state => _state;

  String _locale = 'en-IN';
  String get locale => _locale;
  String get localeLabel => supportedLocales[_locale] ?? _locale;

  String _partialTranscript = '';
  String get partialTranscript => _partialTranscript;

  String _finalTranscript = '';
  String get finalTranscript => _finalTranscript;

  String _response = '';
  String get response => _response;

  String _errorMessage = '';
  String get errorMessage => _errorMessage;

  // Session token to invalidate stale async results.
  int _sessionId = 0;
  bool _speakingForSession = false;
  bool _geminiInFlight = false;
  bool _disposed = false;

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  bool setLocale(String newLocale) {
    if (!supportedLocales.containsKey(newLocale)) {
      _errorMessage = 'Unsupported locale: $newLocale';
      _state = ShivaAssistantState.error;
      _safeNotify();
      return false;
    }
    if (_locale == newLocale) return true;
    _locale = newLocale;
    _safeNotify();
    return true;
  }

  void updatePartialTranscript(String text) {
    if (_state != ShivaAssistantState.listening) return;
    if (text == _partialTranscript) return;
    _partialTranscript = text;
    _safeNotify();
  }

  Future<void> beginListening() async {
    if (_state == ShivaAssistantState.listening) return;
    if (_geminiInFlight) return;
    _sessionId++;
    _partialTranscript = '';
    _finalTranscript = '';
    _response = '';
    _errorMessage = '';
    _speakingForSession = false;
    _state = ShivaAssistantState.listening;
    _safeNotify();
  }

  Future<void> submitFinalTranscript(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      _state = ShivaAssistantState.idle;
      _safeNotify();
      return;
    }
    _finalTranscript = trimmed;
    final sid = _sessionId;
    _state = ShivaAssistantState.processing;
    _safeNotify();
    await _runGemini(sid, trimmed);
  }

  Future<void> _runGemini(int sid, String prompt) async {
    if (_geminiInFlight) return;
    _geminiInFlight = true;
    try {
      if (geminiService == null) {
        _setError('GeminiService not wired; please provide an instance.');
        return;
      }
      dynamic result;
      try {
        result = await (geminiService as dynamic).generateResponse(prompt);
      } catch (_) {
        try {
          result = await (geminiService as dynamic).generateResponse(prompt: prompt);
        } catch (e) {
          _setError('Gemini request failed.');
          return;
        }
      }
      if (sid != _sessionId) return;
      final text = (result?.toString() ?? '').trim();
      if (text.isEmpty) {
        _setError('Empty response from Gemini.');
        return;
      }
      _response = text;
      _state = ShivaAssistantState.speaking;
      _safeNotify();
      await _speak(sid, text);
    } finally {
      _geminiInFlight = false;
    }
  }

  Future<void> _speak(int sid, String text) async {
    if (_speakingForSession) return;
    _speakingForSession = true;
    try {
      if (ttsService == null) {
        _state = ShivaAssistantState.idle;
        _safeNotify();
        return;
      }
      try {
        await (ttsService as dynamic).speak(text);
      } catch (_) {
        try {
          await (ttsService as dynamic).speak(text, locale: _locale);
        } catch (e) {
          _setError('TTS failed.');
          return;
        }
      }
    } finally {
      if (sid == _sessionId && _state == ShivaAssistantState.speaking) {
        _state = ShivaAssistantState.idle;
        _safeNotify();
      }
    }
  }

  Future<void> stopListening() async {
    if (_state != ShivaAssistantState.listening) return;
    try {
      await (speechService as dynamic)?.stop?.call();
    } catch (_) {/* ignore */}
    _state = ShivaAssistantState.idle;
    _safeNotify();
  }

  Future<void> stopSpeaking() async {
    try {
      await (ttsService as dynamic)?.stop?.call();
    } catch (_) {/* ignore */}
    if (_state == ShivaAssistantState.speaking) {
      _state = ShivaAssistantState.idle;
      _safeNotify();
    }
  }

  Future<void> cancelAll() async {
    _sessionId++;
    try { await (speechService as dynamic)?.stop?.call(); } catch (_) {/* ignore */}
    try { await (ttsService as dynamic)?.stop?.call(); } catch (_) {/* ignore */}
    _state = ShivaAssistantState.idle;
    _safeNotify();
  }

  void reset() {
    _sessionId++;
    _partialTranscript = '';
    _finalTranscript = '';
    _response = '';
    _errorMessage = '';
    _speakingForSession = false;
    _state = ShivaAssistantState.idle;
    _safeNotify();
  }

  void _setError(String msg) {
    _errorMessage = msg;
    _state = ShivaAssistantState.error;
    _safeNotify();
  }
}
SHIVA_CONTROLLER_EOF
  } > "$CONTROLLER_FILE"
  log_success "Created controller: ${CONTROLLER_FILE#$PROJECT_ROOT/}"
fi

# =====================================================================
# 5. CREATE WIDGETS
# =====================================================================
if [[ -f "$WIDGETS_FILE" ]] && grep -q '// SHIVA_PHASE3_WIDGETS_V1' "$WIDGETS_FILE" 2>/dev/null; then
  log_info "Widgets already present with Phase 3 marker; skipping rewrite"
else
  {
    printf '// SHIVA_PHASE3_WIDGETS_V1\n'
    printf '// Phase 3 UI widgets for Shiva AI assistant (JARVIS-inspired).\n'
    printf '// Additive: does NOT create a second main() and does NOT alter global theme.\n\n'
    cat <<'SHIVA_WIDGETS_EOF'
import 'package:flutter/material.dart';
import 'shiva_phase3_controller.dart';

class ShivaPhase3Palette {
  static const Color bg      = Color(0xFF060A18);
  static const Color panel   = Color(0xFF0E1530);
  static const Color accent  = Color(0xFF00E5FF);
  static const Color accent2 = Color(0xFF3D7BFF);
  static const Color text    = Color(0xFFE6F1FF);
  static const Color muted   = Color(0xFF8FA3C7);
  static const Color error   = Color(0xFFFF4D6D);
}

class ShivaStatusIndicator extends StatelessWidget {
  const ShivaStatusIndicator({super.key, required this.controller});
  final ShivaPhase3Controller controller;

  String _label() {
    switch (controller.state) {
      case ShivaAssistantState.idle:       return 'IDLE';
      case ShivaAssistantState.listening:  return 'LISTENING';
      case ShivaAssistantState.processing: return 'PROCESSING';
      case ShivaAssistantState.speaking:   return 'SPEAKING';
      case ShivaAssistantState.error:      return 'ERROR';
    }
  }

  Color _color() {
    switch (controller.state) {
      case ShivaAssistantState.error:      return ShivaPhase3Palette.error;
      case ShivaAssistantState.idle:       return ShivaPhase3Palette.muted;
      default:                             return ShivaPhase3Palette.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 10, height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _color(),
                boxShadow: [
                  BoxShadow(color: _color().withOpacity(0.7), blurRadius: 12, spreadRadius: 2),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _label(),
              style: TextStyle(
                color: _color(),
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
                fontSize: 12,
              ),
            ),
          ],
        );
      },
    );
  }
}

class ShivaLanguageSelector extends StatelessWidget {
  const ShivaLanguageSelector({super.key, required this.controller});
  final ShivaPhase3Controller controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: ShivaPhase3Palette.panel,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: ShivaPhase3Palette.accent2.withOpacity(0.4)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: controller.locale,
              isDense: true,
              dropdownColor: ShivaPhase3Palette.panel,
              iconEnabledColor: ShivaPhase3Palette.accent,
              style: const TextStyle(color: ShivaPhase3Palette.text, fontSize: 13),
              items: ShivaPhase3Controller.supportedLocales.entries
                  .map((e) => DropdownMenuItem<String>(
                        value: e.key,
                        child: Text('${e.value} (${e.key})'),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) controller.setLocale(v);
              },
            ),
          ),
        );
      },
    );
  }
}

class ShivaVoiceOrb extends StatelessWidget {
  const ShivaVoiceOrb({super.key, required this.controller, this.size = 96});
  final ShivaPhase3Controller controller;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final s = controller.state;
        final active = s == ShivaAssistantState.listening || s == ShivaAssistantState.speaking;
        final isError = s == ShivaAssistantState.error;
        final color = isError
            ? ShivaPhase3Palette.error
            : (active ? ShivaPhase3Palette.accent : ShivaPhase3Palette.accent2);
        final icon = (s == ShivaAssistantState.listening)
            ? Icons.mic
            : (s == ShivaAssistantState.speaking
                ? Icons.volume_up
                : (s == ShivaAssistantState.processing
                    ? Icons.autorenew
                    : Icons.graphic_eq));
        return SizedBox(
          width: size, height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    color.withOpacity(0.28),
                    color.withOpacity(0.05),
                  ]),
                  boxShadow: [
                    BoxShadow(color: color.withOpacity(0.5), blurRadius: active ? 26 : 12, spreadRadius: active ? 4 : 1),
                  ],
                ),
              ),
              Container(
                width: size * 0.72, height: size * 0.72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ShivaPhase3Palette.panel,
                  border: Border.all(color: color, width: 1.6),
                ),
                child: Icon(icon, color: color, size: size * 0.36),
              ),
            ],
          ),
        );
      },
    );
  }
}

class ShivaTranscriptCard extends StatelessWidget {
  const ShivaTranscriptCard({super.key, required this.controller});
  final ShivaPhase3Controller controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final partial = controller.partialTranscript;
        final finalText = controller.finalTranscript;
        final response = controller.response;
        final err = controller.errorMessage;
        if (partial.isEmpty && finalText.isEmpty && response.isEmpty && err.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: _panelDecoration(),
            child: const Text(
              'Say "Shiva" or tap the microphone to begin.',
              style: TextStyle(color: ShivaPhase3Palette.muted),
            ),
          );
        }
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: _panelDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (partial.isNotEmpty && finalText.isEmpty)
                _line('YOU (partial)', partial, ShivaPhase3Palette.accent),
              if (finalText.isNotEmpty)
                _line('YOU', finalText, ShivaPhase3Palette.accent),
              if (response.isNotEmpty) ...[
                const SizedBox(height: 8),
                _line('SHIVA', response, ShivaPhase3Palette.text),
              ],
              if (err.isNotEmpty) ...[
                const SizedBox(height: 8),
                _line('ERROR', err, ShivaPhase3Palette.error),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _line(String label, String text, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: color.withOpacity(0.8),
            fontSize: 11,
            letterSpacing: 2,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(text, style: const TextStyle(color: ShivaPhase3Palette.text, height: 1.35)),
      ],
    );
  }

  BoxDecoration _panelDecoration() => BoxDecoration(
        color: ShivaPhase3Palette.panel.withOpacity(0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ShivaPhase3Palette.accent2.withOpacity(0.35)),
      );
}

class ShivaQuickActionsRow extends StatelessWidget {
  const ShivaQuickActionsRow({super.key, required this.controller});
  final ShivaPhase3Controller controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final listening = controller.state == ShivaAssistantState.listening;
        final speaking = controller.state == ShivaAssistantState.speaking;
        final processing = controller.state == ShivaAssistantState.processing;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _action(
              icon: listening ? Icons.stop : Icons.mic,
              label: listening ? 'STOP' : 'LISTEN',
              onTap: processing ? null : () async {
                if (listening) {
                  await controller.stopListening();
                } else {
                  await controller.beginListening();
                }
              },
            ),
            _action(
              icon: Icons.volume_off,
              label: 'MUTE',
              onTap: speaking ? () async => controller.stopSpeaking() : null,
            ),
            _action(
              icon: Icons.cancel,
              label: 'CANCEL',
              onTap: () async => controller.cancelAll(),
            ),
          ],
        );
      },
    );
  }

  Widget _action({
    required IconData icon,
    required String label,
    required Future<void> Function()? onTap,
  }) {
    final enabled = onTap != null;
    final color = enabled ? ShivaPhase3Palette.accent : ShivaPhase3Palette.muted;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: ShivaPhase3Palette.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ShivaPhase3Panel extends StatelessWidget {
  const ShivaPhase3Panel({super.key, required this.controller});
  final ShivaPhase3Controller controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ShivaPhase3Palette.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ShivaStatusIndicator(controller: controller),
              ShivaLanguageSelector(controller: controller),
            ],
          ),
          const SizedBox(height: 24),
          Center(child: ShivaVoiceOrb(controller: controller)),
          const SizedBox(height: 24),
          ShivaTranscriptCard(controller: controller),
          const SizedBox(height: 20),
          ShivaQuickActionsRow(controller: controller),
        ],
      ),
    );
  }
}
SHIVA_WIDGETS_EOF
  } > "$WIDGETS_FILE"
  log_success "Created widgets: ${WIDGETS_FILE#$PROJECT_ROOT/}"
fi

# =====================================================================
# 6. OPTIONAL HUD MOUNT (best effort, non-destructive)
# =====================================================================
MOUNT_STATUS="not-attempted"
HUD_PATH="$PROJECT_ROOT/lib/main.dart"

if [[ -f "$HUD_PATH" ]]; then
  if grep -q 'ShivaPhase3Panel' "$HUD_PATH" 2>/dev/null; then
    log_info "HUD already references ShivaPhase3Panel; skipping mount"
    MOUNT_STATUS="already-mounted"
  else
    log_warn "Automatic HUD mounting skipped: existing main.dart not modified (safe default)."
    log_warn "Widgets available at: ${WIDGETS_FILE#$PROJECT_ROOT/}"
    log_warn "Mount manually via: ShivaPhase3Panel(controller: <your controller>)"
    MOUNT_STATUS="manual-required"
  fi
fi

# =====================================================================
# 7. VALIDATION
# =====================================================================
log_info "Validating created files"

VALIDATION_PASS=0
VALIDATION_FAIL=0

check_file() {
  local f="$1"
  if [[ -s "$f" ]]; then
    log_success "OK: ${f#$PROJECT_ROOT/} ($(wc -l < "$f") lines)"
    VALIDATION_PASS=$((VALIDATION_PASS+1))
  else
    log_error "Missing or empty: $f"
    VALIDATION_FAIL=$((VALIDATION_FAIL+1))
  fi
}

check_file "$CONTROLLER_FILE"
check_file "$WIDGETS_FILE"

# Balanced braces sanity (best effort, non-fatal)
check_braces() {
  local f="$1"
  local opens closes
  opens=$(grep -o '{' "$f" 2>/dev/null | wc -l | tr -d ' ')
  closes=$(grep -o '}' "$f" 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$opens" -eq "$closes" ]]; then
    log_info "Brace balance OK: ${f#$PROJECT_ROOT/} ($opens vs $closes)"
  else
    log_warn "Brace balance mismatch in ${f#$PROJECT_ROOT/}: {=$opens }=$closes (inspect manually)"
  fi
}
check_braces "$CONTROLLER_FILE"
check_braces "$WIDGETS_FILE"

# Flutter / Dart tooling
HAS_FLUTTER=false
HAS_DART=false
have flutter && HAS_FLUTTER=true
have dart    && HAS_DART=true

DART_ANALYZE_STATUS="skipped"
if $HAS_FLUTTER; then
  log_info "Flutter detected; running analyze on integration files"
  if ( cd "$PROJECT_ROOT" && flutter analyze lib/integration 2>&1 | tee /tmp/shiva_phase3_analyze.log >/dev/null ); then
    DART_ANALYZE_STATUS="passed"
    log_success "flutter analyze: passed"
  else
    DART_ANALYZE_STATUS="warnings-or-errors"
    log_warn "flutter analyze reported issues (see /tmp/shiva_phase3_analyze.log)"
  fi
elif $HAS_DART; then
  log_info "Dart detected; analyze skipped (requires Flutter for Flutter imports)"
  DART_ANALYZE_STATUS="dart-only-skipped"
else
  log_warn "Flutter/Dart not on PATH; source-level validation only"
fi

# =====================================================================
# 8. FINAL REPORT
# =====================================================================
echo
echo "================ Shiva Phase 3 Report ================"
echo "Project root:      $PROJECT_ROOT"
echo "Backup directory:  $BACKUP_DIR"
echo "Controller file:   ${CONTROLLER_FILE#$PROJECT_ROOT/}"
echo "Widgets file:      ${WIDGETS_FILE#$PROJECT_ROOT/}"
echo "HUD mount status:  $MOUNT_STATUS"
echo "Analyzer status:   $DART_ANALYZE_STATUS"
echo "Validation pass:   $VALIDATION_PASS"
echo "Validation fail:   $VALIDATION_FAIL"
echo "======================================================"

if [[ "$VALIDATION_FAIL" -gt 0 ]]; then
  log_error "FAILED: One or more required files could not be created"
  exit 1
fi

if [[ "$MOUNT_STATUS" == "manual-required" ]]; then
  log_warn "PARTIAL: Files created and validated; HUD mount requires manual wiring"
  exit 0
fi

log_success "SUCCESS: Phase 3 files created and validated"
exit 0
+0
+
