
#!/usr/bin/env bash
set -Eeuo pipefail

# =====================================================================
# Shiva The AI System - Phase 4
# HUD UI Mounting, Final Validation, and APK Build Preparation
# =====================================================================

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
SCRIPT_NAME="shiva_phase4"

# ---------- Logging ----------
log_info()    { printf '[INFO]    %s %s\n' "$(date +%H:%M:%S)" "$*"; }
log_warn()    { printf '[WARN]    %s %s\n' "$(date +%H:%M:%S)" "$*"; }
log_error()   { printf '[ERROR]   %s %s\n' "$(date +%H:%M:%S)" "$*" 1>&2; }
log_success() { printf '[SUCCESS] %s %s\n' "$(date +%H:%M:%S)" "$*"; }

FAILED_STEPS=()
SKIPPED_STEPS=()
PASSED_STEPS=()

record_pass()   { PASSED_STEPS+=("$1"); log_success "$1"; }
record_fail()   { FAILED_STEPS+=("$1"); log_error   "$1"; }
record_skip()   { SKIPPED_STEPS+=("$1"); log_warn   "$1"; }

on_err() {
  local code=$1 line=$2
  log_error "Unexpected failure at line $line (exit $code)"
  if [[ -n "${BACKUP_DIR:-}" && -d "$BACKUP_DIR" ]]; then
    log_info "Backup preserved at: $BACKUP_DIR"
  fi
  exit "$code"
}
trap 'on_err $? $LINENO' ERR

have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<USAGE_EOF
Usage: bash $0 [PROJECT_PATH] [--push] [--help]

  PROJECT_PATH   Optional. Path to the Shiva Flutter project root.
  --push         Opt-in: commit and push intended Phase 4 changes.
  --help         Show this message.
USAGE_EOF
}

# =====================================================================
# 1. ARGUMENT PARSING
# =====================================================================
USER_PROJECT=""
DO_PUSH=false

for arg in "$@"; do
  case "$arg" in
    --help|-h) usage; exit 0 ;;
    --push)    DO_PUSH=true ;;
    --*)       log_error "Unknown option: $arg"; usage; exit 2 ;;
    *)
      if [[ -z "$USER_PROJECT" ]]; then
        USER_PROJECT="$arg"
      else
        log_error "Multiple project paths supplied: '$USER_PROJECT' and '$arg'"
        exit 2
      fi
      ;;
  esac
done

# =====================================================================
# 2. PROJECT PATH DETECTION
# =====================================================================
log_info "Starting Shiva The AI System - Phase 4"

validate_project_root() {
  local d="$1"
  [[ -n "$d" && -d "$d" ]] || return 1
  [[ -f "$d/pubspec.yaml" ]] || return 1
  [[ -d "$d/lib" ]] || return 1
  return 0
}

# Upward search from current directory
find_upward() {
  local d
  d="$(pwd)"
  while [[ "$d" != "/" && -n "$d" ]]; do
    if [[ -f "$d/pubspec.yaml" && -d "$d/lib" ]]; then
      printf '%s\n' "$d"
      return 0
    fi
    d="$(dirname "$d")"
  done
  return 1
}

# Bounded downward search
find_under() {
  local base="$1"
  [[ -d "$base" ]] || return 0
  find "$base" -maxdepth 4 -type f -name 'pubspec.yaml' \
    -not -path '*/.git/*' \
    -not -path '*/build/*' \
    -not -path '*/.dart_tool/*' \
    -not -path '*/backups/*' \
    2>/dev/null | while IFS= read -r pf; do
      local r
      r="$(dirname "$pf")"
      if [[ -d "$r/lib" ]]; then
        printf '%s\n' "$r"
      fi
    done
}

PROJECT_ROOT=""
CANDIDATES=()

if [[ -n "$USER_PROJECT" ]]; then
  if validate_project_root "$USER_PROJECT"; then
    PROJECT_ROOT="$(cd "$USER_PROJECT" && pwd)"
    log_info "Using CLI-supplied project: $PROJECT_ROOT"
  else
    log_error "Supplied path is not a valid Flutter project: $USER_PROJECT"
    exit 3
  fi
else
  if UP="$(find_upward)"; then
    PROJECT_ROOT="$UP"
    log_info "Detected project via upward search: $PROJECT_ROOT"
  else
    for base in "$HOME" "$HOME/storage/shared" "$HOME/AndroidStudioProjects" "$HOME/projects"; do
      [[ -d "$base" ]] || continue
      while IFS= read -r r; do
        [[ -n "$r" ]] && CANDIDATES+=("$r")
      done < <(find_under "$base")
    done

    # Deduplicate
    if [[ ${#CANDIDATES[@]} -gt 0 ]]; then
      mapfile -t CANDIDATES < <(printf '%s\n' "${CANDIDATES[@]}" | sort -u)
    fi

    if [[ ${#CANDIDATES[@]} -eq 0 ]]; then
      log_error "No Flutter project found."
      log_error "Rerun: bash $0 /path/to/project"
      exit 3
    elif [[ ${#CANDIDATES[@]} -eq 1 ]]; then
      PROJECT_ROOT="${CANDIDATES[0]}"
      log_info "Detected single project: $PROJECT_ROOT"
    else
      # Prefer one that contains phase3 markers
      PREF=""
      for c in "${CANDIDATES[@]}"; do
        if [[ -f "$c/lib/integration/shiva_phase3_controller.dart" ]]; then
          PREF="$c"
          break
        fi
      done
      if [[ -n "$PREF" ]]; then
        PROJECT_ROOT="$PREF"
        log_info "Preferred project (contains Phase 3): $PROJECT_ROOT"
      else
        log_error "Multiple Flutter projects detected; please specify one:"
        for c in "${CANDIDATES[@]}"; do printf '        - %s\n' "$c"; done
        exit 3
      fi
    fi
  fi
fi

PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"
cd "$PROJECT_ROOT"
log_success "Project root: $PROJECT_ROOT"

# =====================================================================
# 3. PREFLIGHT & BACKUP
# =====================================================================
BACKUP_DIR="$PROJECT_ROOT/backups/${SCRIPT_NAME}_${TIMESTAMP}"
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

# Tool availability
HAS_FLUTTER=false; have flutter && HAS_FLUTTER=true
HAS_DART=false;    have dart    && HAS_DART=true
HAS_GIT=false;     have git     && HAS_GIT=true
HAS_GH=false;      have gh      && HAS_GH=true

$HAS_FLUTTER && log_info "Flutter: $(flutter --version 2>/dev/null | head -n1 || echo unknown)" \
             || log_warn "Flutter not on PATH"
$HAS_DART    && log_info "Dart: $(dart --version 2>&1 | head -n1 || echo unknown)" \
             || log_warn "Dart not on PATH"

# Verify required files
CONTROLLER_FILE="$PROJECT_ROOT/lib/integration/shiva_phase3_controller.dart"
WIDGETS_FILE="$PROJECT_ROOT/lib/integration/shiva_phase3_widgets.dart"
MAIN_FILE="$PROJECT_ROOT/lib/main.dart"

MISSING=()
[[ -f "$CONTROLLER_FILE" ]] || MISSING+=("lib/integration/shiva_phase3_controller.dart")
[[ -f "$WIDGETS_FILE"    ]] || MISSING+=("lib/integration/shiva_phase3_widgets.dart")
[[ -f "$MAIN_FILE"       ]] || MISSING+=("lib/main.dart")

if [[ ${#MISSING[@]} -gt 0 ]]; then
  log_error "Missing required Phase 3 / application files:"
  for f in "${MISSING[@]}"; do printf '        - %s\n' "$f"; done
  log_error "Phase 4 requires Phase 3 artifacts. Aborting."
  exit 4
fi

record_pass "Required Phase 3 files present"

# =====================================================================
# 4. PHASE 3 COMPONENT DISCOVERY
# =====================================================================
log_info "Inspecting Phase 3 components and services"

# Detect services
SPEECH_PATH=""; GEMINI_PATH=""; TTS_PATH=""
while IFS= read -r f; do
  if grep -qE 'class[[:space:]]+SpeechService' "$f" 2>/dev/null; then SPEECH_PATH="$f"; fi
  if grep -qE 'class[[:space:]]+GeminiService' "$f" 2>/dev/null; then GEMINI_PATH="$f"; fi
  if grep -qE 'class[[:space:]]+(TtsService|TTSService|TextToSpeechService)' "$f" 2>/dev/null; then TTS_PATH="$f"; fi
done < <(find "$PROJECT_ROOT/lib" -type f -name '*.dart' 2>/dev/null)

CONTROLLER_CLASS=""
if grep -qE 'class[[:space:]]+ShivaPhase3Controller' "$CONTROLLER_FILE" 2>/dev/null; then
  CONTROLLER_CLASS="ShivaPhase3Controller"
fi
PANEL_CLASS=""
if grep -qE 'class[[:space:]]+ShivaPhase3Panel' "$WIDGETS_FILE" 2>/dev/null; then
  PANEL_CLASS="ShivaPhase3Panel"
fi

[[ -n "$SPEECH_PATH"    ]] && log_info "SpeechService: ${SPEECH_PATH#$PROJECT_ROOT/}" || log_warn "SpeechService not found"
[[ -n "$GEMINI_PATH"    ]] && log_info "GeminiService: ${GEMINI_PATH#$PROJECT_ROOT/}" || log_warn "GeminiService not found"
[[ -n "$TTS_PATH"       ]] && log_info "TTS Service:   ${TTS_PATH#$PROJECT_ROOT/}"    || log_warn "TTS service not found"
[[ -n "$CONTROLLER_CLASS" ]] && log_info "Controller: $CONTROLLER_CLASS" || log_warn "Controller class not detected"
[[ -n "$PANEL_CLASS"    ]] && log_info "Panel:      $PANEL_CLASS"         || log_warn "Panel class not detected"

if [[ -z "$CONTROLLER_CLASS" || -z "$PANEL_CLASS" ]]; then
  log_error "Cannot establish Phase 3 API. Aborting HUD mount."
  exit 4
fi

# Detect controller constructor signature (services or Object?)
CTRL_REQUIRES_SERVICES=false
if grep -qE 'required[[:space:]]+this\.(speechService|geminiService|ttsService)' "$CONTROLLER_FILE" 2>/dev/null; then
  CTRL_REQUIRES_SERVICES=true
fi
log_info "Controller requires services: $CTRL_REQUIRES_SERVICES"

# =====================================================================
# 5. SAFE HUD MOUNT
# =====================================================================
log_info "Analyzing HUD file: lib/main.dart"

MAIN_TEXT="$(cat "$MAIN_FILE")"

PANEL_ALREADY="no"
if grep -qE "$PANEL_CLASS" "$MAIN_FILE" 2>/dev/null; then
  PANEL_ALREADY="yes"
fi

MOUNT_STATUS="skipped"
MUTATED_MAIN=false

if [[ "$PANEL_ALREADY" == "yes" ]]; then
  log_info "Panel already referenced in main.dart; verifying only"
  MOUNT_STATUS="already-present"
  record_pass "HUD mount already present"
else
  # Heuristic: does main.dart contain a StatefulWidget we can hook into?
  HAS_STATEFUL=$(grep -cE 'extends[[:space:]]+StatefulWidget' "$MAIN_FILE" || true)
  HAS_STATELESS=$(grep -cE 'extends[[:space:]]+StatelessWidget' "$MAIN_FILE" || true)
  HAS_MYAPP=$(grep -cE 'class[[:space:]]+[A-Za-z0-9_]+[[:space:]]+extends[[:space:]]+(StatelessWidget|StatefulWidget)' "$MAIN_FILE" || true)

  if [[ "$HAS_MYAPP" -eq 0 ]]; then
    log_warn "No widget class detected in main.dart; cannot mount automatically"
    MOUNT_STATUS="manual-required"
    record_skip "HUD mounting skipped (no widget anchor)"
  else
    # Generate a small, self-contained patch as a separate file the app can adopt.
    # We deliberately DO NOT overwrite main.dart blindly. We instead write a
    # helper file and report mounting as "prepared" so a developer can call it.
    MOUNT_HELPER="$PROJECT_ROOT/lib/integration/shiva_phase3_mount.dart"
    if [[ -f "$MOUNT_HELPER" ]] && grep -q '// SHIVA_PHASE3_MOUNT_V1' "$MOUNT_HELPER" 2>/dev/null; then
      log_info "Mount helper already present; skipping rewrite"
      MOUNT_STATUS="helper-prepared"
      record_skip "HUD mounting: helper file present"
    else
      [[ -f "$MOUNT_HELPER" ]] && backup_path "$MOUNT_HELPER"

      # Determine relative import paths for services
      rel_path() {
        local t="$1"
        if [[ -z "$t" ]]; then printf 'null'; return; fi
        printf "import '../%s';\n" "${t#$PROJECT_ROOT/lib/}"
      }

      SPEECH_IMPORT=""
      GEMINI_IMPORT=""
      TTS_IMPORT=""
      [[ -n "$SPEECH_PATH" ]] && SPEECH_IMPORT="$(rel_path "$SPEECH_PATH")"
      [[ -n "$GEMINI_PATH" ]] && GEMINI_IMPORT="$(rel_path "$GEMINI_PATH")"
      [[ -n "$TTS_PATH"    ]] && TTS_IMPORT="$(rel_path "$TTS_PATH")"

      CTRL_REL="import 'shiva_phase3_controller.dart';\n"
      WIDG_REL="import 'shiva_phase3_widgets.dart';\n"

      {
        printf '// SHIVA_PHASE3_MOUNT_V1\n'
        printf '// Provides a ready-to-use wrapper that mounts ShivaPhase3Panel with\n'
        printf '// the discovered services. Import and call ShivaPhase3Mount.build(...).\n\n'
        printf "import 'package:flutter/material.dart';\n"
        printf '%s' "$CTRL_REL"
        printf '%s' "$WIDG_REL"
        [[ -n "$SPEECH_IMPORT" ]] && printf '%b' "$SPEECH_IMPORT"
        [[ -n "$GEMINI_IMPORT" ]] && printf '%b' "$GEMINI_IMPORT"
        [[ -n "$TTS_IMPORT"    ]] && printf '%b' "$TTS_IMPORT"
        printf '\n'
        cat <<'SHIVA_MOUNT_EOF'
class ShivaPhase3Mount {
  ShivaPhase3Mount._();

  /// Builds a ShivaPhase3Panel wrapped in an owned StatefulWidget that
  /// initializes and disposes the controller.
  static Widget build({SpeechService? speechService, GeminiService? geminiService, TtsService? ttsService}) {
    return _ShivaPhase3MountHost(
      speechService: speechService,
      geminiService: geminiService,
      ttsService: ttsService,
    );
  }
}

class _ShivaPhase3MountHost extends StatefulWidget {
  const _ShivaPhase3MountHost({this.speechService, this.geminiService, this.ttsService});
  final SpeechService? speechService;
  final GeminiService? geminiService;
  final TtsService? ttsService;

  @override
  State<_ShivaPhase3MountHost> createState() => _ShivaPhase3MountHostState();
}

class _ShivaPhase3MountHostState extends State<_ShivaPhase3MountHost> {
  late final ShivaPhase3Controller _controller;

  @override
  void initState() {
    super.initState();
    _controller = ShivaPhase3Controller(
      speechService: widget.speechService,
      geminiService: widget.geminiService,
      ttsService: widget.ttsService,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShivaPhase3Panel(controller: _controller);
  }
}
SHIVA_MOUNT_EOF
      } > "$MOUNT_HELPER"
      MUTATED_MAIN=false
      MOUNT_STATUS="helper-prepared"
      log_info "Wrote mount helper: ${MOUNT_HELPER#$PROJECT_ROOT/}"
      record_skip "HUD mounting requires manual call to ShivaPhase3Mount.build(...)"
    fi
  fi
fi

# =====================================================================
# 6. FORMATTING & VALIDATION
# =====================================================================
FORMAT_STATUS="skipped"
PUBGET_STATUS="skipped"
ANALYZE_STATUS="skipped"

if $HAS_DART; then
  log_info "Running dart format on lib/"
  if ( cd "$PROJECT_ROOT" && dart format lib/ 2>&1 ); then
    FORMAT_STATUS="pass"
    record_pass "dart format lib/"
  else
    FORMAT_STATUS="fail"
    record_fail "dart format lib/ failed"
  fi
else
  record_skip "dart format skipped (Dart unavailable)"
fi

if $HAS_FLUTTER; then
  log_info "Running flutter pub get"
  if ( cd "$PROJECT_ROOT" && flutter pub get 2>&1 ); then
    PUBGET_STATUS="pass"
    record_pass "flutter pub get"
  else
    PUBGET_STATUS="fail"
    record_fail "flutter pub get failed"
  fi

  if [[ "$PUBGET_STATUS" == "pass" ]]; then
    log_info "Running flutter analyze"
    set +e
    ANALYZE_OUT="$( cd "$PROJECT_ROOT" && flutter analyze 2>&1 )"
    ANALYZE_CODE=$?
    set -e
    printf '%s\n' "$ANALYZE_OUT" | tail -n 40
    if [[ "$ANALYZE_CODE" -eq 0 ]]; then
      ANALYZE_STATUS="pass"
      record_pass "flutter analyze"
    else
      ANALYZE_STATUS="fail"
      record_fail "flutter analyze (exit $ANALYZE_CODE)"
    fi
  else
    record_skip "flutter analyze skipped (pub get failed)"
  fi
else
  record_skip "flutter pub get / analyze skipped (Flutter unavailable)"
fi

# Structural checks
log_info "Structural checks"
STRUCT_OK=true
DUPE_MAIN=$(grep -cE '^void[[:space:]]+main[[:space:]]*\(' "$PROJECT_ROOT/lib/main.dart" 2>/dev/null || true)
if [[ "$DUPE_MAIN" -gt 1 ]]; then
  log_warn "Multiple main() declarations detected in lib/main.dart"
  STRUCT_OK=false
fi
if ! grep -q 'android.permission.RECORD_AUDIO' "$PROJECT_ROOT/android/app/src/main/AndroidManifest.xml" 2>/dev/null; then
  log_warn "RECORD_AUDIO permission not present in AndroidManifest.xml"
fi
[[ "$STRUCT_OK" == "true" ]] && record_pass "Structural checks" || record_skip "Structural checks (see warnings)"

# =====================================================================
# 7. GITHUB ACTIONS WORKFLOW
# =====================================================================
log_info "Inspecting GitHub Actions workflows"
WF_DIR="$PROJECT_ROOT/.github/workflows"
WF_FILE=""
if [[ -d "$WF_DIR" ]]; then
  while IFS= read -r f; do
    if grep -qE 'flutter' "$f" 2>/dev/null; then WF_FILE="$f"; break; fi
  done < <(find "$WF_DIR" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null)
fi

WF_STATUS="skipped"
if [[ -n "$WF_FILE" ]]; then
  log_info "Found Flutter workflow: ${WF_FILE#$PROJECT_ROOT/}"
  if grep -qE 'flutter[[:space:]]+build[[:space:]]+apk' "$WF_FILE" 2>/dev/null; then
    log_info "Workflow already runs flutter build apk"
    WF_STATUS="present"
    record_pass "GitHub Actions APK workflow present"
  else
    log_warn "Workflow exists but no 'flutter build apk' step detected"
    WF_STATUS="present-no-apk"
    record_skip "Workflow present but no APK step"
  fi
else
  log_warn "No Flutter workflow found; creating minimal APK workflow"
  mkdir -p "$WF_DIR"
  WF_FILE="$WF_DIR/flutter_apk.yml"
  if [[ -f "$WF_FILE" ]]; then
    backup_path "$WF_FILE"
  fi
  cat > "$WF_FILE" <<'SHIVA_WF_EOF'
name: Flutter APK

on:
  push:
    branches: [ main, master ]
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: 'zulu'
          java-version: '17'
      - uses: subosito/flutter-action@v2
        with:
          channel: 'stable'
          cache: true
      - name: Flutter version
        run: flutter --version
      - name: Pub get
        run: flutter pub get
      - name: Analyze
        run: flutter analyze || true
      - name: Build APK (debug)
        run: flutter build apk --debug
      - name: Upload APK artifact
        uses: actions/upload-artifact@v4
        with:
          name: shiva-apk-debug
          path: build/app/outputs/flutter-apk/app-debug.apk
          if-no-files-found: error
SHIVA_WF_EOF
  WF_STATUS="created"
  record_pass "Created minimal APK workflow"
fi

# =====================================================================
# 8. GIT COMMIT & PUSH (opt-in)
# =====================================================================
GIT_STATUS="skipped"
GIT_COMMIT="no"
GIT_PUSH="no"

if ! $HAS_GIT; then
  record_skip "Git operations skipped (git unavailable)"
else
  if ! git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    record_skip "Git operations skipped (not a Git repo)"
    GIT_STATUS="not-a-repo"
  else
    GIT_STATUS="ready"
    BRANCH="$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
    log_info "Current branch: ${BRANCH:-<unknown>}"

    # Compute intended file list (only Phase 4 additions)
    INTENDED=()
    [[ -f "$PROJECT_ROOT/lib/integration/shiva_phase3_mount.dart" ]] && \
      INTENDED+=("lib/integration/shiva_phase3_mount.dart")
    if [[ -n "$WF_FILE" && -f "$WF_FILE" ]] && \
       [[ "$WF_FILE" == "$PROJECT_ROOT/.github/workflows/flutter_apk.yml" ]]; then
      INTENDED+=(".github/workflows/flutter_apk.yml")
    fi

    if [[ ${#INTENDED[@]} -eq 0 ]]; then
      log_info "No Phase 4 files detected for commit"
      GIT_STATUS="no-changes"
    else
      log_info "Intended Phase 4 files:"
      for f in "${INTENDED[@]}"; do printf '        - %s\n' "$f"; done

      if [[ "$DO_PUSH" != "true" ]]; then
        record_skip "Git commit/push skipped (use --push to enable)"
        GIT_STATUS="prepared"
      else
        # Require identity & remote
        if ! git -C "$PROJECT_ROOT" config user.email >/dev/null 2>&1; then
          record_fail "Git commit identity (user.email) not configured"
          GIT_STATUS="no-identity"
        elif ! git -C "$PROJECT_ROOT" remote get-url origin >/dev/null 2>&1; then
          record_fail "Git remote 'origin' not configured"
          GIT_STATUS="no-remote"
        else
          # Stage only intended files
          git -C "$PROJECT_ROOT" add -- "${INTENDED[@]}"
          if git -C "$PROJECT_ROOT" diff --cached --quiet; then
            log_info "No staged changes to commit"
            GIT_STATUS="no-changes-staged"
          else
            COMMIT_MSG="Phase 4: HUD mount helper and APK workflow"
            if git -C "$PROJECT_ROOT" commit -m "$COMMIT_MSG" >/dev/null 2>&1; then
              GIT_COMMIT="yes"
              record_pass "Git commit created"
              if git -C "$PROJECT_ROOT" push origin "$BRANCH" >/dev/null 2>&1; then
                GIT_PUSH="yes"
                record_pass "Git push to origin/$BRANCH"
                GIT_STATUS="pushed"
              else
                record_fail "Git push failed"
                GIT_STATUS="push-failed"
              fi
            else
              record_fail "Git commit failed"
              GIT_STATUS="commit-failed"
            fi
          fi
        fi
      fi
    fi
  fi
fi

# =====================================================================
# 9. OPTIONAL GITHUB RUN INSPECTION
# =====================================================================
GH_RUN_STATUS="skipped"
if [[ "$GIT_PUSH" == "yes" ]] && $HAS_GH; then
  if gh auth status >/dev/null 2>&1; then
    log_info "Inspecting latest workflow run"
    set +e
    GH_OUT="$( cd "$PROJECT_ROOT" && gh run list --limit 1 2>&1 )"
    set -e
    if [[ -n "$GH_OUT" ]]; then
      printf '%s\n' "$GH_OUT"
      GH_RUN_STATUS="queried"
    else
      GH_RUN_STATUS="query-empty"
    fi
  else
    GH_RUN_STATUS="gh-unauthenticated"
  fi
fi

# =====================================================================
# 10. FINAL REPORT
# =====================================================================
echo
echo "================ Shiva Phase 4 Report ================"
echo "Project root:        $PROJECT_ROOT"
echo "Backup directory:    $BACKUP_DIR"
echo
echo "Phase 3 discovery:"
echo "  Controller:        ${CONTROLLER_CLASS:-<none>}"
echo "  Panel:             ${PANEL_CLASS:-<none>}"
echo "  SpeechService:     ${SPEECH_PATH:-<missing>}"
echo "  GeminiService:     ${GEMINI_PATH:-<missing>}"
echo "  TtsService:        ${TTS_PATH:-<missing>}"
echo
echo "HUD mount:           $MOUNT_STATUS"
echo "Dart format:         $FORMAT_STATUS"
echo "Pub get:             $PUBGET_STATUS"
echo "Flutter analyze:     $ANALYZE_STATUS"
echo "Workflow status:     $WF_STATUS"
echo "Git status:          $GIT_STATUS (commit=$GIT_COMMIT push=$GIT_PUSH)"
echo "GH run query:        $GH_RUN_STATUS"
echo
echo "Passed steps:        ${#PASSED_STEPS[@]}"
for s in "${PASSED_STEPS[@]}"; do printf '  [PASS] %s\n' "$s"; done
echo "Skipped steps:       ${#SKIPPED_STEPS[@]}"
for s in "${SKIPPED_STEPS[@]}"; do printf '  [SKIP] %s\n' "$s"; done
echo "Failed steps:        ${#FAILED_STEPS[@]}"
for s in "${FAILED_STEPS[@]}"; do printf '  [FAIL] %s\n' "$s"; done
echo "======================================================"

if [[ ${#FAILED_STEPS[@]} -gt 0 ]]; then
  echo
  echo "Recovery: restore any modified files from:"
  echo "  $BACKUP_DIR"
  exit 1
fi

if [[ ${#SKIPPED_STEPS[@]} -gt 0 ]]; then
  log_warn "PARTIAL: some steps were skipped (see above)"
  exit 0
fi

log_success "SUCCESS: Phase 4 completed"
exit 0
+0
+
