import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'voice_engine.dart';

void main() => runApp(const ShivaApp());

const Color _bgTop = Color(0xFF02040A);
const Color _bgBottom = Color(0xFF0A1428);
const Color _cyan = Color(0xFF00E5FF);
const Color _teal = Color(0xFF1DE9B6);
const Color _blue = Color(0xFF448AFF);
const Color _sky = Color(0xFF00B0FF);
const Color _red = Color(0xFFFF5252);

Color _a(Color c, double opacity) => c.withAlpha((opacity * 255).round());

Color _stateColor(VoiceState s) {
  switch (s) {
    case VoiceState.idle:
      return _cyan;
    case VoiceState.listening:
      return _teal;
    case VoiceState.processing:
      return _blue;
    case VoiceState.speaking:
      return _sky;
    case VoiceState.error:
      return _red;
  }
}

const Map<VoiceLanguage, Map<String, String>> _tr = {
  VoiceLanguage.marathi: {
    'title': 'शिवा AI',
    'listening': 'ऐकतोय...',
    'speak': 'बोला',
    'ask': 'बोला शिवा',
    'greetCard': 'अभिवादन करा',
    'langCard': 'भाषा बदला',
    'stopSpeaking': 'बोलणे थांबवा',
    'cancel': 'रद्द करा',
    'retry': 'पुन्हा प्रयत्न करा',
    'ready': 'कोर तयार',
    'processing': 'प्रक्रिया सुरू आहे...',
    'speaking': 'बोलतोय...',
    'error': 'त्रुटी',
    'you': 'तुम्ही',
    'shiva': 'शिवा',
    'empty': 'सुरू करण्यासाठी रिंगला स्पर्श करा.',
    'greeting': 'नमस्कार! मी शिवा AI आहे. मी तुमची कशी मदत करू?',
    'name': 'माझे नाव शिवा AI आहे.',
    'confirm': 'शिवा AI तयार आहे. व्हॉइस इंजिन सुरू आहे.',
    'unknown':
        'हा आदेश मला अजून समजत नाही. संवादात्मक AI पुढील टप्प्यात जोडला जाईल.',
    'e_permission':
        'मायक्रोफोन परवानगी नाकारली आहे. Android सेटिंग्जमध्ये ती सुरू करा.',
    'e_unavailable': 'या डिव्हाइसवर स्पीच रेकग्निशन उपलब्ध नाही.',
    'e_locale': 'ही भाषा या डिव्हाइसवर उपलब्ध नाही. दुसरी भाषा निवडा.',
    'e_nospeech': 'काही ऐकू आले नाही. पुन्हा प्रयत्न करा.',
    'e_tts':
        'या भाषेचा आवाज डिव्हाइसवर उपलब्ध नाही. Android च्या Text-to-speech सेटिंग्जमध्ये भाषा डेटा इन्स्टॉल करा.',
    'e_platform': 'व्हॉइस इंजिनमध्ये त्रुटी आली.',
  },
  VoiceLanguage.hindi: {
    'title': 'शिवा AI',
    'listening': 'सुन रहा हूँ...',
    'speak': 'बोलिए',
    'ask': 'बोलिए शिवा',
    'greetCard': 'अभिवादन करें',
    'langCard': 'भाषा बदलें',
    'stopSpeaking': 'बोलना बंद करें',
    'cancel': 'रद्द करें',
    'retry': 'फिर से कोशिश करें',
    'ready': 'कोर तैयार',
    'processing': 'प्रोसेस हो रहा है...',
    'speaking': 'बोल रहा हूँ...',
    'error': 'त्रुटि',
    'you': 'आप',
    'shiva': 'शिवा',
    'empty': 'शुरू करने के लिए रिंग को छुएँ।',
    'greeting': 'नमस्ते! मैं शिवा AI हूँ। मैं आपकी कैसे मदद करूँ?',
    'name': 'मेरा नाम शिवा AI है।',
    'confirm': 'शिवा AI तैयार है। वॉइस इंजन चालू है।',
    'unknown':
        'यह आदेश मुझे अभी समझ नहीं आता। बातचीत वाला AI अगले चरण में जोड़ा जाएगा।',
    'e_permission':
        'माइक्रोफ़ोन की अनुमति नहीं मिली। Android सेटिंग्स में इसे चालू करें।',
    'e_unavailable': 'इस डिवाइस पर स्पीच रिकग्निशन उपलब्ध नहीं है।',
    'e_locale': 'यह भाषा इस डिवाइस पर उपलब्ध नहीं है। कोई दूसरी भाषा चुनें।',
    'e_nospeech': 'कुछ सुनाई नहीं दिया। फिर से कोशिश करें।',
    'e_tts':
        'इस भाषा की आवाज़ डिवाइस पर उपलब्ध नहीं है। Android की Text-to-speech सेटिंग्स में भाषा डेटा इंस्टॉल करें।',
    'e_platform': 'वॉइस इंजन में त्रुटि हुई।',
  },
  VoiceLanguage.english: {
    'title': 'Shiva AI',
    'listening': 'Listening...',
    'speak': 'Speak',
    'ask': 'Talk to Shiva',
    'greetCard': 'Speak a Greeting',
    'langCard': 'Change Language',
    'stopSpeaking': 'Stop Speaking',
    'cancel': 'Cancel',
    'retry': 'Retry',
    'ready': 'CORE READY',
    'processing': 'Processing...',
    'speaking': 'Speaking...',
    'error': 'Error',
    'you': 'YOU',
    'shiva': 'SHIVA',
    'empty': 'Tap the ring to begin.',
    'greeting': 'Hello! I am Shiva AI. How can I help you?',
    'name': 'My name is Shiva AI.',
    'confirm': 'Shiva AI is ready. The voice engine is running.',
    'unknown':
        'I do not understand that command yet. Conversational AI will be added in a later phase.',
    'e_permission':
        'Microphone permission was denied. Enable it in Android Settings.',
    'e_unavailable': 'Speech recognition is not available on this device.',
    'e_locale':
        'This language is not available for recognition on this device. Choose another language.',
    'e_nospeech': 'I did not hear anything. Please try again.',
    'e_tts':
        'No voice for this language is installed. Install the language data in Android Text-to-speech settings.',
    'e_platform': 'The voice engine reported an error.',
  },
};

const Set<String> _greetWords = {
  'hello', 'hi', 'hey', 'namaste', 'namaskar', 'नमस्कार', 'नमस्ते', //
  'हॅलो', 'हेलो', 'हैलो', 'हाय', 'प्रणाम',
};

const List<String> _namePhrases = [
  'your name', 'who are you', 'तुझे नाव', 'तुमचे नाव', 'तेरा नाम', //
  'आपका नाम', 'तुम कौन', 'तू कोण', 'तुम्ही कोण', 'नाव काय', 'नाम क्या',
];

const List<String> _confirmPhrases = [
  'confirm', 'are you ready', 'ready', 'पुष्टी', 'कन्फर्म', 'तयार', 'तैयार',
];

class ShivaApp extends StatelessWidget {
  const ShivaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shiva AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _cyan,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: _bgTop,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 24))
        ..repeat();
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))
        ..repeat();
  final ValueNotifier<double> _level = ValueNotifier<double>(0);

  late final VoiceEngine _engine;
  VoiceLanguage _lang = VoiceLanguage.english;
  VoiceState _vs = VoiceState.idle;
  VoiceError? _error;
  String _heard = '';
  bool _heardFinal = false;
  String _reply = '';

  String _t(String key) => _tr[_lang]![key]!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _engine = VoiceEngine(
      onStateChanged: (s) {
        if (s != VoiceState.listening) _level.value = 0;
        _update(() => _vs = s);
      },
      onTranscript: _onTranscript,
      onError: (e) => _update(() => _error = e),
      onSoundLevel: (l) => _level.value = ((l + 2) / 12).clamp(0.0, 1.0),
    )..language = _lang;
    _engine.initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _engine.cancelListening();
      _engine.stopSpeaking();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _spin.dispose();
    _pulse.dispose();
    _level.dispose();
    _engine.dispose();
    super.dispose();
  }

  void _update(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  Future<void> _startListening() async {
    _update(() {
      _error = null;
      _heard = '';
      _heardFinal = false;
    });
    await _engine.startListening();
  }

  Future<void> _onRingTap() async {
    switch (_vs) {
      case VoiceState.idle:
      case VoiceState.error:
        await _startListening();
      case VoiceState.listening:
        await _engine.stopListening();
      case VoiceState.speaking:
        await _engine.stopSpeaking();
      case VoiceState.processing:
        break;
    }
  }

  void _onTranscript(String text, bool isFinal) {
    _update(() {
      _heard = text;
      _heardFinal = isFinal;
    });
    if (isFinal && text.trim().isNotEmpty) _say(_respond(text));
  }

  void _say(String text) {
    _update(() => _reply = text);
    _engine.speak(text, languageCode: _lang.ttsLocale);
  }

  Future<void> _setLanguage(VoiceLanguage lang) async {
    if (lang == _lang) return;
    await _engine.cancelListening();
    await _engine.stopSpeaking();
    _engine.language = lang;
    _engine.clearError();
    _update(() {
      _lang = lang;
      _error = null;
    });
  }

  Future<void> _cycleLanguage() {
    final all = VoiceLanguage.values;
    return _setLanguage(all[(_lang.index + 1) % all.length]);
  }

  String _respond(String raw) {
    final text = raw.toLowerCase();
    final tokens = text.split(RegExp(r'[\s,.!?।]+')).toSet();
    bool has(List<String> phrases) => phrases.any((p) => text.contains(p));
    if (has(_namePhrases)) return _t('name');
    if (has(_confirmPhrases)) return _t('confirm');
    if (tokens.any(_greetWords.contains)) return _t('greeting');
    return _t('unknown');
  }

  String get _statusLabel {
    switch (_vs) {
      case VoiceState.idle:
        return _t('ready');
      case VoiceState.listening:
        return _t('listening');
      case VoiceState.processing:
        return _t('processing');
      case VoiceState.speaking:
        return _t('speaking');
      case VoiceState.error:
        return _t('error');
    }
  }

  String _errorText(VoiceError e) {
    switch (e.type) {
      case VoiceErrorType.permissionDenied:
        return _t('e_permission');
      case VoiceErrorType.recognitionUnavailable:
        return _t('e_unavailable');
      case VoiceErrorType.localeUnavailable:
        return _t('e_locale');
      case VoiceErrorType.noSpeech:
        return _t('e_nospeech');
      case VoiceErrorType.ttsLanguageMissing:
        return _t('e_tts');
      case VoiceErrorType.platform:
        return _t('e_platform');
    }
  }

  bool get _canRetry {
    final e = _error;
    return e != null &&
        e.type != VoiceErrorType.localeUnavailable &&
        e.type != VoiceErrorType.ttsLanguageMissing;
  }

  IconData get _micIcon {
    switch (_vs) {
      case VoiceState.idle:
        return Icons.mic_none;
      case VoiceState.listening:
        return Icons.mic;
      case VoiceState.processing:
        return Icons.more_horiz;
      case VoiceState.speaking:
        return Icons.graphic_eq;
      case VoiceState.error:
        return Icons.mic_off;
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final ring = math.max(
      200.0,
      math.min(size.width * 0.78, math.min(size.height * 0.42, 320.0)),
    );
    final color = _stateColor(_vs);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bgTop, _bgBottom],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  children: [
                    _header(color),
                    const SizedBox(height: 20),
                    _ring(ring, color),
                    const SizedBox(height: 12),
                    Text(
                      _vs == VoiceState.idle ? _t('speak') : _statusLabel,
                      style: TextStyle(
                        color: color,
                        fontSize: 20,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _controls(),
                    if (_error != null) _errorBanner(_error!),
                    const SizedBox(height: 16),
                    _cards(),
                    const SizedBox(height: 16),
                    _conversation(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(Color color) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _t('title'),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: Colors.white,
                ),
              ),
            ),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [BoxShadow(color: _a(color, .8), blurRadius: 8)],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _statusLabel,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, letterSpacing: 1.2),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            children: [
              for (final l in VoiceLanguage.values)
                ChoiceChip(
                  label: Text(l.nativeName),
                  selected: l == _lang,
                  selectedColor: _a(_cyan, .25),
                  onSelected: (_) => _setLanguage(l),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _ring(double size, Color color) {
    return Semantics(
      button: true,
      label: _t('ask'),
      child: GestureDetector(
        onTap: _onRingTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              RepaintBoundary(
                child: CustomPaint(
                  size: Size.square(size),
                  painter: _RingPainter(
                    spin: _spin,
                    pulse: _pulse,
                    level: _level,
                    vs: _vs,
                  ),
                ),
              ),
              Icon(_micIcon, size: size * 0.17, color: color),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controls() {
    final busy = _vs == VoiceState.listening || _vs == VoiceState.processing;
    if (busy) {
      return OutlinedButton.icon(
        onPressed: _engine.cancelListening,
        icon: const Icon(Icons.close),
        label: Text(_t('cancel')),
      );
    }
    if (_vs == VoiceState.error && _canRetry) {
      return FilledButton.icon(
        onPressed: _startListening,
        icon: const Icon(Icons.refresh),
        label: Text(_t('retry')),
      );
    }
    return const SizedBox(height: 40);
  }

  Widget _errorBanner(VoiceError e) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _a(_red, .1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _a(_red, .5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: _red),
          const SizedBox(width: 10),
          Expanded(child: Text(_errorText(e))),
        ],
      ),
    );
  }

  Widget _cards() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _CommandCard(
                icon: Icons.mic,
                label: _t('ask'),
                onTap: _startListening,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _CommandCard(
                icon: Icons.waving_hand,
                label: _t('greetCard'),
                onTap: () => _say(_t('greeting')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _CommandCard(
                icon: Icons.translate,
                label: _t('langCard'),
                onTap: _cycleLanguage,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _CommandCard(
                icon: Icons.volume_off,
                label: _t('stopSpeaking'),
                onTap: _vs == VoiceState.speaking ? _engine.stopSpeaking : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _conversation() {
    if (_heard.isEmpty && _reply.isEmpty) {
      return Text(
        _t('empty'),
        textAlign: TextAlign.center,
        style: TextStyle(color: _a(Colors.white, .6)),
      );
    }
    return Column(
      children: [
        if (_heard.isNotEmpty)
          _panel(_t('you'), _heard, dim: !_heardFinal),
        if (_reply.isNotEmpty) ...[
          const SizedBox(height: 10),
          _panel(_t('shiva'), _reply),
        ],
      ],
    );
  }

  Widget _panel(String label, String text, {bool dim = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _a(_cyan, .06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _a(_cyan, .3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: _cyan, fontSize: 12, letterSpacing: 2),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 16,
              height: 1.4,
              fontStyle: dim ? FontStyle.italic : FontStyle.normal,
              color: dim ? _a(Colors.white, .6) : Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _CommandCard extends StatelessWidget {
  const _CommandCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: _a(_cyan, .06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: _a(_cyan, .3)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: Column(
              children: [
                Icon(icon, color: _cyan),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.spin,
    required this.pulse,
    required this.level,
    required this.vs,
  }) : super(repaint: Listenable.merge([spin, pulse, level]));

  final Animation<double> spin;
  final Animation<double> pulse;
  final ValueNotifier<double> level;
  final VoiceState vs;

  Paint _stroke(Color c, double w) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..color = c;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final color = _stateColor(vs);
    final active = vs == VoiceState.listening || vs == VoiceState.speaking;
    final lvl = vs == VoiceState.listening ? level.value : 0.0;
    final t = pulse.value;
    final base = spin.value * 2 * math.pi * (vs == VoiceState.processing ? 2 : 1);

    final glowRect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r * (0.8 + 0.12 * lvl),
      Paint()
        ..shader = RadialGradient(
          colors: [_a(color, .35 + .4 * lvl), _a(color, 0)],
        ).createShader(glowRect),
    );

    canvas.drawCircle(
      c,
      r * (0.55 + 0.45 * t),
      _stroke(_a(color, (1 - t) * (active ? .5 : .12)), 2),
    );

    canvas.drawCircle(c, r * .94, _stroke(_a(color, .35), 2));

    final arcRect = Rect.fromCircle(center: c, radius: r * .82);
    for (var i = 0; i < 3; i++) {
      canvas.drawArc(
        arcRect,
        base * 2 + i * 2 * math.pi / 3,
        1.1,
        false,
        _stroke(_a(color, .9), 6),
      );
    }

    final tick = _stroke(_a(color, .6), 1.5);
    for (var i = 0; i < 72; i++) {
      final angle = -base + i * 2 * math.pi / 72;
      final long = i % 6 == 0;
      canvas.drawLine(
        c + Offset.fromDirection(angle, r * (long ? .64 : .67)),
        c + Offset.fromDirection(angle, r * .72),
        tick,
      );
    }

    final innerRect = Rect.fromCircle(center: c, radius: r * .56);
    for (var i = 0; i < 2; i++) {
      canvas.drawArc(
        innerRect,
        base * 3 + i * math.pi,
        1.6,
        false,
        _stroke(_a(color, .8), 3),
      );
    }

    final coreR = r * (0.42 + 0.04 * lvl);
    canvas.drawCircle(
      c,
      coreR,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF0B2A4A), Color(0xFF020611)],
        ).createShader(Rect.fromCircle(center: c, radius: coreR)),
    );
    canvas.drawCircle(c, coreR, _stroke(_a(color, .9), 2));
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.vs != vs;
}
