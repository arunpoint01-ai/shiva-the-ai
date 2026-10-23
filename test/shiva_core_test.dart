import 'package:flutter_test/flutter_test.dart';
import 'package:shiva_ai/core/shiva_core.dart';
import 'package:shiva_ai/integration/shiva_intent_router.dart';
import 'package:shiva_ai/voice_engine.dart';

void main() {
  late ShivaCore core;
  setUp(() => core = ShivaCore());
  tearDown(() => core.dispose());

  test('stop asks the UI to stop audio', () async {
    final reply = await core.handle('थांब', VoiceLanguage.marathi);
    expect(reply, isNotNull);
    expect(reply!.intent, ShivaIntent.stop);
    expect(reply.stopAudio, isTrue);
  });

  test('language switch carries the target language', () async {
    final reply = await core.handle('मराठीत बोल', VoiceLanguage.english);
    expect(reply!.switchTo, VoiceLanguage.marathi);
  });

  test('media request is answered honestly (player not built yet)', () async {
    final reply = await core.handle('आरती लाव', VoiceLanguage.marathi);
    expect(reply!.intent, ShivaIntent.playMedia);
    expect(reply.text.contains('अजून तयार नाही'), isTrue);
  });

  test('quickReply is used for unknown commands', () async {
    final reply = await core.handle('hello', VoiceLanguage.english, quickReply: (_) => 'Hi there');
    expect(reply!.text, 'Hi there');
  });

  test('a newer command makes the older one stale', () async {
    final first = core.handle('hello', VoiceLanguage.english, quickReply: (_) => null);
    final second = await core.handle('stop', VoiceLanguage.english);
    expect(second, isNotNull);
    await first; // must complete without throwing
  });
}
