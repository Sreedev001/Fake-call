import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:vibration/vibration.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Bridge to MainActivity.kt (contacts + proximity screen-off).
const MethodChannel _native = MethodChannel('contact_book/native');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ContactBookApp());
}

class ContactBookApp extends StatelessWidget {
  const ContactBookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Contact Book',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E88E5),
          brightness: Brightness.dark,
        ),
      ),
      home: const HomePage(),
    );
  }
}

class Contact {
  final String name;
  final String number;
  const Contact(this.name, this.number);

  String get initial {
    final t = name.trim();
    if (t.isEmpty) return '#';
    return String.fromCharCode(t.runes.first).toUpperCase();
  }

  String get letter {
    final c = initial;
    return c.toLowerCase() != c.toUpperCase() ? c : '#';
  }

  Color get color =>
      Colors.primaries[name.hashCode.abs() % Colors.primaries.length].shade700;
}

enum Stage { list, detail, outgoing, ringing, inCall }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Stage _stage = Stage.list;

  // Contacts
  List<Contact> _contacts = [];
  bool? _permissionGranted; // null = still loading
  String _query = '';
  Contact? _selected;

  // Call-back scheduling
  int _delaySeconds = 60;
  DateTime? _callbackAt;

  // Call state
  String _outStatus = 'Calling…';
  int _callSeconds = 0;
  bool _muted = false;
  bool _speaker = false;

  Timer? _ticker;
  Timer? _outgoingTimer;
  Timer? _ringTimeout;
  Timer? _callTimer;

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _outgoingTimer?.cancel();
    _ringTimeout?.cancel();
    _callTimer?.cancel();
    _stopAlerts();
    _setProximity(false);
    WakelockPlus.disable();
    super.dispose();
  }

  // ---------------------------------------------------------------- helpers

  String _fmt(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  String _delayLabel(int s) => s < 60 ? '$s sec' : '${s ~/ 60} min';

  void _syncWakelock() {
    final keep = _callbackAt != null ||
        _stage == Stage.outgoing ||
        _stage == Stage.ringing ||
        _stage == Stage.inCall;
    if (keep) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  Future<bool> _setProximity(bool on) async {
    try {
      return (await _native.invokeMethod<bool>('setProximityScreenOff', {'on': on})) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _stopAlerts() async {
    try {
      await FlutterRingtonePlayer().stop();
    } catch (_) {}
    try {
      await Vibration.cancel();
    } catch (_) {}
  }

  void _sortContacts() {
    _contacts.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  // --------------------------------------------------------------- contacts

  Future<void> _loadContacts() async {
    try {
      var granted =
          (await _native.invokeMethod<bool>('hasContactsPermission')) ?? false;
      if (!granted) {
        granted =
            (await _native.invokeMethod<bool>('requestContactsPermission')) ?? false;
      }
      if (!granted) {
        if (mounted) setState(() => _permissionGranted = false);
        return;
      }
      final raw = await _native.invokeMethod<List<dynamic>>('getContacts');
      final list = <Contact>[];
      for (final item in raw ?? const <dynamic>[]) {
        final m = Map<dynamic, dynamic>.from(item as Map);
        list.add(Contact('${m['name']}', '${m['number']}'));
      }
      if (!mounted) return;
      setState(() {
        _contacts = list;
        _sortContacts();
        _permissionGranted = true;
      });
    } catch (_) {
      if (mounted) setState(() => _permissionGranted = false);
    }
  }

  Future<void> _addContact() async {
    final n = TextEditingController();
    final p = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: n,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: p,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok == true && n.text.trim().isNotEmpty) {
      setState(() {
        _contacts = [..._contacts, Contact(n.text.trim(), p.text.trim())];
        _sortContacts();
        _permissionGranted = true;
      });
    }
  }

  Future<void> _pickDelay() async {
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Call-back delay'),
        children: [
          for (final s in const [15, 30, 60, 120, 300])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, s),
              child: Text(_delayLabel(s) + (s == _delaySeconds ? '   ✓' : '')),
            ),
        ],
      ),
    );
    if (v != null) setState(() => _delaySeconds = v);
  }

  void _cancelCallback() {
    setState(() => _callbackAt = null);
    _syncWakelock();
  }

  // ------------------------------------------------------------ call logic

  /// User taps "Call" on a contact: show an outgoing call, then schedule the
  /// same contact to call back after the chosen delay.
  void _startCall(Contact c) {
    _selected = c;
    _callbackAt = DateTime.now().add(Duration(seconds: _delaySeconds));
    _outStatus = 'Calling…';
    setState(() => _stage = Stage.outgoing);
    _syncWakelock();
    _outgoingTimer?.cancel();
    _outgoingTimer = Timer(const Duration(seconds: 7), _hangUpOutgoing);
  }

  void _hangUpOutgoing() {
    if (_stage != Stage.outgoing) return;
    _outgoingTimer?.cancel();
    setState(() => _outStatus = 'Call ended');
    Timer(const Duration(milliseconds: 1200), () {
      if (mounted && _stage == Stage.outgoing) {
        setState(() => _stage = Stage.list);
        _syncWakelock();
      }
    });
  }

  void _tick() {
    final at = _callbackAt;
    if (at == null) return;
    if (DateTime.now().isBefore(at)) return;
    if (_stage == Stage.list || _stage == Stage.detail) {
      _callbackAt = null;
      _startRinging();
    }
  }

  Future<void> _startRinging() async {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    setState(() => _stage = Stage.ringing);
    _syncWakelock();
    _ringTimeout?.cancel();
    _ringTimeout = Timer(const Duration(seconds: 30), _decline); // missed call
    try {
      await FlutterRingtonePlayer().playRingtone(looping: true, volume: 1.0);
    } catch (_) {}
    try {
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(pattern: [0, 1000, 1000], repeat: 0);
      }
    } catch (_) {}
    if (_stage != Stage.ringing) _stopAlerts();
  }

  Future<void> _decline() async {
    _ringTimeout?.cancel();
    await _stopAlerts();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (!mounted) return;
    setState(() => _stage = Stage.list);
    _syncWakelock();
  }

  Future<void> _answer() async {
    _ringTimeout?.cancel();
    await _stopAlerts();
    _callSeconds = 0;
    _muted = false;
    _speaker = false;
    if (!mounted) return;
    setState(() => _stage = Stage.inCall);
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _callSeconds++);
    });
    // Screen turns off when the phone is held to the ear.
    _setProximity(true);
  }

  Future<void> _endCall() async {
    _callTimer?.cancel();
    await _setProximity(false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (!mounted) return;
    setState(() => _stage = Stage.list);
    _syncWakelock();
  }

  void _onBack() {
    if (_stage == Stage.detail) {
      setState(() => _stage = Stage.list);
    } else if (_stage == Stage.outgoing) {
      _hangUpOutgoing();
    }
  }

  // -------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    Widget body;
    switch (_stage) {
      case Stage.list:
        body = _listScreen();
        break;
      case Stage.detail:
        body = _detailScreen();
        break;
      case Stage.outgoing:
        body = _outgoingScreen();
        break;
      case Stage.ringing:
        body = _ringingScreen();
        break;
      case Stage.inCall:
        body = _inCallScreen();
        break;
    }
    return PopScope(
      canPop: _stage == Stage.list,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _onBack();
      },
      child: body,
    );
  }

  Widget _listScreen() {
    final q = _query.trim().toLowerCase();
    final filtered = _contacts
        .where((c) =>
            q.isEmpty || c.name.toLowerCase().contains(q) || c.number.contains(q))
        .toList();

    final entries = <Object>[];
    String? last;
    for (final c in filtered) {
      if (c.letter != last) {
        last = c.letter;
        entries.add(c.letter);
      }
      entries.add(c);
    }

    Widget content;
    if (_permissionGranted == null) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_permissionGranted == false && _contacts.isEmpty) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Allow access to contacts to see them here.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadContacts,
                child: const Text('Allow access'),
              ),
            ],
          ),
        ),
      );
    } else if (entries.isEmpty) {
      content = const Center(child: Text('No contacts'));
    } else {
      content = ListView.builder(
        itemCount: entries.length,
        itemBuilder: (context, i) {
          final e = entries[i];
          if (e is String) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Text(
                e,
                style: const TextStyle(
                  color: Color(0xFF64B5F6),
                  fontWeight: FontWeight.bold,
                ),
              ),
            );
          }
          final c = e as Contact;
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: c.color,
              child: Text(c.initial, style: const TextStyle(color: Colors.white)),
            ),
            title: Text(c.name),
            onTap: () => setState(() {
              _selected = c;
              _stage = Stage.detail;
            }),
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'settings') _pickDelay();
              if (v == 'cancel') _cancelCallback();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'settings',
                child: Text('Settings (${_delayLabel(_delaySeconds)})'),
              ),
              if (_callbackAt != null)
                const PopupMenuItem(
                  value: 'cancel',
                  child: Text('Clear scheduled call'),
                ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addContact,
        child: const Icon(Icons.person_add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search contacts',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(child: content),
        ],
      ),
    );
  }

  Widget _detailScreen() {
    final c = _selected!;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => _stage = Stage.list),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 56,
              backgroundColor: c.color,
              child: Text(
                c.initial,
                style: const TextStyle(fontSize: 44, color: Colors.white),
              ),
            ),
            const SizedBox(height: 20),
            Text(c.name, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 6),
            Text(c.number, style: const TextStyle(color: Colors.white60, fontSize: 16)),
            const SizedBox(height: 36),
            _roundButton(Icons.call, Colors.green, 'Call', () => _startCall(c)),
          ],
        ),
      ),
    );
  }

  Widget _callBackground(Widget child) {
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
            padding: const EdgeInsets.fromLTRB(24, 60, 24, 50),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _callerInfo(String status) {
    final c = _selected!;
    return Column(
      children: [
        Text(status, style: const TextStyle(color: Colors.white70, fontSize: 16)),
        const SizedBox(height: 16),
        CircleAvatar(
          radius: 48,
          backgroundColor: c.color,
          child: Text(
            c.initial,
            style: const TextStyle(fontSize: 40, color: Colors.white),
          ),
        ),
        const SizedBox(height: 20),
        Text(c.name, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        Text(c.number, style: const TextStyle(color: Colors.white60, fontSize: 16)),
      ],
    );
  }

  Widget _roundButton(IconData icon, Color color, String label, VoidCallback onTap) {
    return Column(
      mainAxisSize: MainAxisSize.min,
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

  Widget _toggleButton(IconData icon, String label, bool on, VoidCallback onTap) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: CircleAvatar(
            radius: 30,
            backgroundColor: on ? Colors.white : Colors.white12,
            child: Icon(icon, color: on ? Colors.black : Colors.white),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
      ],
    );
  }

  Widget _outgoingScreen() {
    return _callBackground(
      Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _callerInfo(_outStatus),
          _roundButton(Icons.call_end, Colors.red, 'End', _hangUpOutgoing),
        ],
      ),
    );
  }

  Widget _ringingScreen() {
    return _callBackground(
      Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _callerInfo('Incoming call'),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _roundButton(Icons.call_end, Colors.red, 'Decline', _decline),
              _roundButton(Icons.call, Colors.green, 'Answer', _answer),
            ],
          ),
        ],
      ),
    );
  }

  Widget _inCallScreen() {
    return _callBackground(
      Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _callerInfo(_fmt(_callSeconds)),
          Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _toggleButton(Icons.mic_off, 'Mute', _muted,
                      () => setState(() => _muted = !_muted)),
                  _toggleButton(Icons.dialpad, 'Keypad', false, () {}),
                  _toggleButton(Icons.volume_up, 'Speaker', _speaker,
                      () => setState(() => _speaker = !_speaker)),
                ],
              ),
              const SizedBox(height: 40),
              _roundButton(Icons.call_end, Colors.red, 'End', _endCall),
            ],
          ),
        ],
      ),
    );
  }
}
