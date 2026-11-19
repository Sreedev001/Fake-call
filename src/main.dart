import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:vibration/vibration.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FakeCallApp());
}

class FakeCallApp extends StatelessWidget {
  const FakeCallApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fake Call',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const HomePage(),
    );
  }
}

enum Stage { setup, waiting, ringing, inCall }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _nameCtrl = TextEditingController(text: 'Mom');
  final _numberCtrl = TextEditingController(text: '+1 555 010 1234');

  Stage _stage = Stage.setup;
  int _delay = 10;
  int _remaining = 0;
  int _callSeconds = 0;
  Timer? _timer;

  static const _delays = <int, String>{
    5: '5 sec',
    10: '10 sec',
    30: '30 sec',
    60: '1 min',
    300: '5 min',
  };

  String _fmt(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  void _startWaiting() {
    FocusScope.of(context).unfocus();
    WakelockPlus.enable();
    _remaining = _delay;
    setState(() => _stage = Stage.waiting);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_remaining <= 1) {
        t.cancel();
        _startRinging();
      } else {
        setState(() => _remaining--);
      }
    });
  }

  Future<void> _startRinging() async {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    setState(() => _stage = Stage.ringing);
    try {
      await FlutterRingtonePlayer().playRingtone(looping: true, volume: 1.0);
    } catch (_) {}
    try {
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(pattern: [0, 1000, 1000], repeat: 0);
      }
    } catch (_) {}
  }

  Future<void> _stopAlerts() async {
    try {
      await FlutterRingtonePlayer().stop();
    } catch (_) {}
    try {
      await Vibration.cancel();
    } catch (_) {}
  }

  Future<void> _accept() async {
    await _stopAlerts();
    _callSeconds = 0;
    setState(() => _stage = Stage.inCall);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _callSeconds++);
    });
  }

  Future<void> _reset() async {
    _timer?.cancel();
    await _stopAlerts();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (mounted) setState(() => _stage = Stage.setup);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stopAlerts();
    WakelockPlus.disable();
    _nameCtrl.dispose();
    _numberCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (_stage) {
      case Stage.setup:
        return _setup();
      case Stage.waiting:
        return _waiting();
      case Stage.ringing:
        return _ringing();
      case Stage.inCall:
        return _inCall();
    }
  }

  Widget _setup() {
    return Scaffold(
      appBar: AppBar(title: const Text('Fake Call')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Caller name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _numberCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Caller number',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          const Text('Call me in', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _delays.entries
                .map((e) => ChoiceChip(
                      label: Text(e.value),
                      selected: _delay == e.key,
                      onSelected: (_) => setState(() => _delay = e.key),
                    ))
                .toList(),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _startWaiting,
            icon: const Icon(Icons.phone_callback),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('Schedule fake call', style: TextStyle(fontSize: 18)),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Tip: after scheduling, leave the app open with the screen on. '
            'The call screen will appear when the timer ends.',
            style: TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _waiting() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onLongPress: _reset,
        child: SizedBox.expand(
          child: Center(
            child: Text(
              'Call in ${_fmt(_remaining)}\n\n(long-press to cancel)',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white24, fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }

  Widget _callerInfo(String status) {
    return Column(
      children: [
        Text(status, style: const TextStyle(color: Colors.white70, fontSize: 16)),
        const SizedBox(height: 16),
        const CircleAvatar(
          radius: 48,
          backgroundColor: Colors.white12,
          child: Icon(Icons.person, size: 56, color: Colors.white70),
        ),
        const SizedBox(height: 20),
        Text(
          _nameCtrl.text.isEmpty ? 'Unknown' : _nameCtrl.text,
          style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        Text(_numberCtrl.text,
            style: const TextStyle(color: Colors.white60, fontSize: 16)),
      ],
    );
  }

  Widget _roundButton(IconData icon, Color color, String label, VoidCallback onTap) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: CircleAvatar(
            radius: 36,
            backgroundColor: color,
            child: Icon(icon, size: 34, color: Colors.white),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }

  Widget _ringing() {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1B2735), Color(0xFF090A0F)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 60, 24, 60),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _callerInfo('Incoming call'),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _roundButton(Icons.call_end, Colors.red, 'Decline', _reset),
                    _roundButton(Icons.call, Colors.green, 'Accept', _accept),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _inCall() {
    Widget small(IconData i, String l) => Column(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: Colors.white12,
              child: Icon(i, color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(l, style: const TextStyle(color: Colors.white60, fontSize: 12)),
          ],
        );

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1B2735), Color(0xFF090A0F)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 60, 24, 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _callerInfo(_fmt(_callSeconds)),
                Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        small(Icons.mic_off, 'Mute'),
                        small(Icons.dialpad, 'Keypad'),
                        small(Icons.volume_up, 'Speaker'),
                      ],
                    ),
                    const SizedBox(height: 40),
                    _roundButton(Icons.call_end, Colors.red, 'End', _reset),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
