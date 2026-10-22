// SHIVA_PHASE5_AUTH
import 'package:local_auth/local_auth.dart';

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
        localizedReason: 'बॉस, डाऊनलोडसाठी ओळख पटवा',
        options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true, useErrorDialogs: true),
      );
      if (ok) { _lastAuth = DateTime.now(); return true; }
      return false;
    } catch (_) { return false; }
  }

  Future<bool> revalidateBoss() async { _lastAuth = null; return authenticateBoss(); }
  void invalidate() { _lastAuth = null; }
}
