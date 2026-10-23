import 'package:flutter_test/flutter_test.dart';
import 'package:shiva_ai/integration/shiva_intent_router.dart';

ShivaIntent r(String s) => ShivaIntentRouter.route(s).intent;

void main() {
  test('stop words in Marathi, Hindi and English', () {
    expect(r('थांब'), ShivaIntent.stop);
    expect(r('आरती बंद कर'), ShivaIntent.stop);
    expect(r('stop'), ShivaIntent.stop);
    expect(r('रुको'), ShivaIntent.stop);
  });

  test('play media', () {
    expect(r('गणपती आरती लाव'), ShivaIntent.playMedia);
    expect(r('भजन वाजव'), ShivaIntent.playMedia);
    expect(r('play bhajan'), ShivaIntent.playMedia);
    expect(r('भक्ती गीत लावा'), ShivaIntent.playMedia);
    expect(r('मराठी गाणी लाव'), ShivaIntent.playMedia);
  });

  test('scripture question', () {
    expect(r('गीतेतील कर्मयोगाबद्दल सांगा'), ShivaIntent.spiritualQuestion);
    expect(r('tell me the meaning of this verse'), ShivaIntent.spiritualQuestion);
  });

  test('language switch', () {
    final m = ShivaIntentRouter.route('मराठीत बोल');
    expect(m.intent, ShivaIntent.changeLanguage);
    expect(m.targetLanguage, 'mr-IN');
    expect(ShivaIntentRouter.route('hindi please').targetLanguage, 'hi-IN');
  });

  test('download', () {
    expect(r('हे गाणं डाऊनलोड कर'), ShivaIntent.downloadMedia);
    expect(r('download this song'), ShivaIntent.downloadMedia);
  });

  test('unrelated commands are not treated as media', () {
    expect(r('वायफाय चालू करा'), ShivaIntent.unknown);
    expect(r('hey shiva'), ShivaIntent.unknown);
  });

  test('wake word', () {
    expect(ShivaIntentRouter.containsWakeWord('Hey Shiva play aarti'), isTrue);
    expect(ShivaIntentRouter.containsWakeWord('हे शिवा आरती लाव'), isTrue);
    expect(ShivaIntentRouter.stripWakeWord('hey shiva stop'), 'stop');
  });
}
