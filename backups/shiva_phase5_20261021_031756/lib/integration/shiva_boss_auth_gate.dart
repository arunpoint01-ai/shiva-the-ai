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
