import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' show License;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(MyApp());
}

// Simple localization map
final Map<String, Map<String, String>> L = {
  'en': {
    'title': 'First Aid BLE Controller',
    'connect': 'Connect Bluetooth',
    'proceed': 'Proceed',
    'select_dialect': 'Select Dialect',
    'english': 'English',
    'tagalog': 'Tagalog',
    'select_mode': 'Select Mode',
    'checkup': 'Check Up Mode',
    'emergency': 'Emergency Mode',
    'cancel': 'Cancel',
    'done': 'Done',
    'go_back': 'Go Back',
    'confirmation': 'Are you done?',
    'done_yes': 'Done',
    'done_no': 'Not Done',
    'feedback': 'Feedback',
    'submit': 'Submit',
    'skip': 'Skip',
    'thank_you': 'Thank you!',
    'back_to_main': 'Back to Main',
    'saving': 'Saving...',
  },
  'tl': {
    'title': 'Unang Tulong BLE Controller',
    'connect': 'Ikabit ang Bluetooth',
    'proceed': 'Tuloy',
    'select_dialect': 'Pumili ng Diyalekto',
    'english': 'Ingles',
    'tagalog': 'Tagalog',
    'select_mode': 'Pumili ng Mode',
    'checkup': 'Check Up Mode',
    'emergency': 'Emergency Mode',
    'cancel': 'Kanselahin',
    'done': 'Tapos na',
    'go_back': 'Bumalik',
    'confirmation': 'Tapos ka na ba?',
    'done_yes': 'Tapos',
    'done_no': 'Hindi pa',
    'feedback': 'Puna',
    'submit': 'Isumite',
    'skip': 'Laktawan',
    'thank_you': 'Salamat!',
    'back_to_main': 'Bumalik sa Simula',
    'saving': 'Isinusulat...',
  },
};

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _lang = 'en';
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    final lang = _prefs?.getString('lang') ?? 'en';
    setState(() => _lang = lang);
  }

  void _setLang(String code) async {
    await _prefs?.setString('lang', code);
    setState(() => _lang = code);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'First Aid BLE App',
      theme: ThemeData(primarySwatch: Colors.teal),
      initialRoute: '/',
      routes: {
        '/': (ctx) =>
            MainScreen(onProceed: () => Navigator.pushNamed(ctx, '/dialect')),
        '/dialect': (ctx) => DialectScreen(
          lang: _lang,
          setLang: (code) {
            _setLang(code);
            Navigator.pushNamed(ctx, '/mode');
          },
        ),
        '/mode': (ctx) => ModeScreen(lang: _lang),
        '/checkup': (ctx) => CheckupScreen(lang: _lang),
        '/emergency': (ctx) => EmergencyScreen(lang: _lang),
        '/confirmation': (ctx) => ConfirmationScreen(lang: _lang),
        '/feedback': (ctx) => FeedbackScreen(lang: _lang),
        '/thankyou': (ctx) => ThankYouScreen(lang: _lang),
      },
    );
  }
}

// BLE Manager
class BLEManager {
  static final FlutterBluePlus _fb = FlutterBluePlus();
  StreamSubscription<List<ScanResult>>? scanSub;
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? writeCharacteristic;

  Future<void> requestPermissions() async {
    await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();
    await Permission.locationWhenInUse.request();
  }

  Future<List<ScanResult>> startScan({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    await requestPermissions();
    final results = <ScanResult>[];
    final completer = Completer<List<ScanResult>>();

    // ✅ Use static startScan
    await FlutterBluePlus.startScan(timeout: timeout);

    // ✅ Listen to List<ScanResult>
    scanSub = FlutterBluePlus.scanResults.listen(
      (List<ScanResult> devices) {
        for (var r in devices) {
          if (!results.any((d) => d.device.remoteId == r.device.remoteId)) {
            results.add(r);
          }
        }
      },
      onDone: () => completer.complete(results),
      onError: (e) => completer.completeError(e),
    );

    return completer.future;
  }

 Future<void> connectToDevice(BluetoothDevice device) async {
  await device.connect(
  license: License.free,
  timeout: const Duration(seconds: 15),
);


  connectedDevice = device;

  final services = await device.discoverServices();
  for (var s in services) {
    for (var c in s.characteristics) {
      if (c.properties.write || c.properties.writeWithoutResponse) {
        writeCharacteristic = c;
        return;
      }
    }
  }
}


  Future<void> disconnect() async {
    await connectedDevice?.disconnect();
    connectedDevice = null;
    writeCharacteristic = null;
  }

  Future<void> sendString(String data) async {
    if (writeCharacteristic == null) throw 'No write characteristic set';
    final bytes = utf8.encode(data);
    await writeCharacteristic!.write(bytes, withoutResponse: true);
  }
}

// ============= UI SCREENS =============

// Screen 1
class MainScreen extends StatefulWidget {
  final VoidCallback onProceed;
  const MainScreen({super.key, required this.onProceed});
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final BLEManager ble = BLEManager();
  List<ScanResult> devices = [];
  BluetoothDevice? selected;
  bool scanning = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('First Aid BLE')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton.icon(
              icon: Icon(Icons.bluetooth_searching),
              label: Text('Scan for HM-10'),
              onPressed: scanning ? null : _scan,
            ),
            if (scanning) LinearProgressIndicator(),
            Expanded(
              child: ListView.builder(
                itemCount: devices.length,
                itemBuilder: (ctx, i) {
                  final r = devices[i];
                  return ListTile(
                    title: Text(
                      r.device.name.isEmpty
                          ? r.device.id.toString()
                          : r.device.name,
                    ),
                    trailing: ElevatedButton(
                      onPressed: selected == r.device
                          ? null
                          : () => _connect(r.device),
                      child: Text(
                        selected == r.device ? 'Connected' : 'Connect',
                      ),
                    ),
                  );
                },
              ),
            ),
            ElevatedButton(onPressed: widget.onProceed, child: Text('Proceed')),
          ],
        ),
      ),
    );
  }

  Future<void> _scan() async {
    setState(() {
      scanning = true;
      devices = [];
    });
    try {
      final results = await ble.startScan();
      setState(() => devices = results);
    } catch (e) {
      print('scan error: $e');
    } finally {
      setState(() => scanning = false);
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    try {
      await ble.connectToDevice(device);
      setState(() => selected = device);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Connected to ${device.name.isEmpty ? device.id : device.name}',
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Connection failed: $e')));
    }
  }
}

// Screen 2 - Dialect selection
class DialectScreen extends StatelessWidget {
  final String lang;
  final Function(String) setLang;
  const DialectScreen({super.key, required this.lang, required this.setLang});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L[lang]!['select_dialect']!)),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            ListTile(
              title: Text(L[lang]!['english']!),
              onTap: () => setLang('en'),
            ),
            ListTile(
              title: Text(L[lang]!['tagalog']!),
              onTap: () => setLang('tl'),
            ),
          ],
        ),
      ),
    );
  }
}

// Screen 3 - Mode selection
class ModeScreen extends StatelessWidget {
  final String lang;
  const ModeScreen({super.key, required this.lang});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L[lang]!['select_mode']!)),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton(
              child: Text(L[lang]!['checkup']!),
              onPressed: () => Navigator.pushNamed(context, '/checkup'),
            ),
            ElevatedButton(
              child: Text(L[lang]!['emergency']!),
              onPressed: () => Navigator.pushNamed(context, '/emergency'),
            ),
          ],
        ),
      ),
    );
  }
}

// Screen 4 - Checkup selection
class CheckupScreen extends StatelessWidget {
  final String lang;
  const CheckupScreen({super.key, required this.lang});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L[lang]!['checkup']!)),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton(
              child: Text('Thermometer'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ToolDetailScreen(
                    lang: lang,
                    title: 'Thermometer',
                    toolKey: 'therm',
                  ),
                ),
              ),
            ),
            ElevatedButton(
              child: Text('Oximeter'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ToolDetailScreen(
                    lang: lang,
                    title: 'Oximeter',
                    toolKey: 'ox',
                  ),
                ),
              ),
            ),
            ElevatedButton(
              child: Text('Blood Pressure'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ToolDetailScreen(
                    lang: lang,
                    title: 'Blood Pressure',
                    toolKey: 'bp',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Screen 5 - Emergency selection
class EmergencyScreen extends StatelessWidget {
  final String lang;
  const EmergencyScreen({super.key, required this.lang});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L[lang]!['emergency']!)),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton(
              child: Text('Burn'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ToolDetailScreen(
                    lang: lang,
                    title: 'Burn',
                    toolKey: 'burn',
                  ),
                ),
              ),
            ),
            ElevatedButton(
              child: Text('Cut'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ToolDetailScreen(
                    lang: lang,
                    title: 'Cut',
                    toolKey: 'cut',
                  ),
                ),
              ),
            ),
            ElevatedButton(
              child: Text('Splinter'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ToolDetailScreen(
                    lang: lang,
                    title: 'Splinter',
                    toolKey: 'splinter',
                  ),
                ),
              ),
            ),
            ElevatedButton(
              child: Text('Strain'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ToolDetailScreen(
                    lang: lang,
                    title: 'Strain',
                    toolKey: 'strain',
                  ),
                ),
              ),
            ),
            ElevatedButton(
              child: Text('Nosebleed'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ToolDetailScreen(
                    lang: lang,
                    title: 'Nosebleed',
                    toolKey: 'nose',
                  ),
                ),
              ),
            ),
            SizedBox(height: 12),
            ElevatedButton(
              child: Text(L[lang]!['cancel']!),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

// Screens 6-13 - ToolDetailScreen (reused for all tools)
class ToolDetailScreen extends StatelessWidget {
  final String lang;
  final String title;
  final String toolKey;
  ToolDetailScreen({super.key, 
    required this.lang,
    required this.title,
    required this.toolKey,
  });

  // Example content for each tool
  Map<String, Map<String, dynamic>> content = {
    'therm': {
      'tools': ['Thermometer device', 'Alcohol swab'],
      'steps': [
        'Turn on thermometer',
        'Place under tongue or forehead',
        'Wait for beep',
        'Read value',
      ],
      'notes': ['Use clean probe', 'Do not share without cleaning'],
    },
    'ox': {
      'tools': ['Pulse oximeter'],
      'steps': ['Turn on', 'Place on finger', 'Wait for reading'],
      'notes': ['Keep still', 'Trim nails for accurate reading'],
    },
    'bp': {
      'tools': ['BP cuff', 'Stethoscope (if manual)'],
      'steps': ['Wrap cuff', 'Inflate', 'Observe values'],
      'notes': ['Sit relaxed', 'Use correct cuff size'],
    },
    'burn': {
      'tools': ['Cool water', 'Sterile dressing'],
      'steps': ['Cool burn with water', 'Cover with sterile dressing'],
      'notes': ['Do not apply ice directly', 'Seek medical help if severe'],
    },
    'cut': {
      'tools': ['Clean water', 'Sterile gauze', 'Bandage'],
      'steps': ['Wash wound', 'Apply pressure to stop bleeding', 'Bandage'],
      'notes': ['Seek stitches for deep cuts'],
    },
    'splinter': {
      'tools': ['Tweezers', 'Alcohol swab'],
      'steps': ['Clean area', 'Remove splinter with tweezers', 'Disinfect'],
      'notes': ['If deep or infected, see doctor'],
    },
    'strain': {
      'tools': ['ICE pack', 'Compression bandage'],
      'steps': ['Rest', 'Ice', 'Compress', 'Elevate'],
      'notes': ['If severe pain, seek help'],
    },
    'nose': {
      'tools': ['Tissue', 'Pinch technique'],
      'steps': [
        'Sit forward',
        'Pinch nose for 10 minutes',
        'Apply cold compress',
      ],
      'notes': ['Do not tilt head back'],
    },
  };

  @override
  Widget build(BuildContext context) {
    final data = content[toolKey]!;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tools needed',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            ...List.generate(
              data['tools'].length,
              (i) => Text('- ' + data['tools'][i]),
            ),
            SizedBox(height: 12),
            Text(
              'Steps',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            ...List.generate(
              data['steps'].length,
              (i) => Text('${i + 1}. ' + data['steps'][i]),
            ),
            SizedBox(height: 12),
            Text(
              'Important notes',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            ...List.generate(
              data['notes'].length,
              (i) => Text('- ' + data['notes'][i]),
            ),
            Spacer(),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    child: Text(L[lang]!['go_back']!),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    child: Text(L[lang]!['done']!),
                    onPressed: () =>
                        Navigator.pushNamed(context, '/confirmation'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Screen 14 - Confirmation
class ConfirmationScreen extends StatelessWidget {
  final String lang;
  const ConfirmationScreen({super.key, required this.lang});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L[lang]!['confirmation']!)),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Text(L[lang]!['confirmation']!, style: TextStyle(fontSize: 20)),
            SizedBox(height: 20),
            ElevatedButton(
              child: Text(L[lang]!['done_yes']!),
              onPressed: () => Navigator.pushNamed(context, '/feedback'),
            ),
            ElevatedButton(
              child: Text(L[lang]!['done_no']!),
              onPressed: () => Navigator.pushNamedAndRemoveUntil(
                context,
                '/dialect',
                (r) => false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Screen 15 - Feedback (save to CSV)
class FeedbackScreen extends StatefulWidget {
  final String lang;
  const FeedbackScreen({super.key, required this.lang});

  @override
  _FeedbackScreenState createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _answers = <int>[]; // store 3 ratings 1..5
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _answers.addAll([0, 0, 0]);
  }

  Future<void> _saveCsv() async {
    setState(() => saving = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/feedback.csv');
      final exists = await file.exists();
      final sink = file.openWrite(mode: FileMode.append);
      if (!exists) {
        // write header
        sink.writeln('timestamp,q1,q2,q3');
      }
      final ts = DateTime.now().toIso8601String();
      sink.writeln('$ts,${_answers[0]},${_answers[1]},${_answers[2]}');
      await sink.flush();
      await sink.close();
    } catch (e) {
      print('save error: $e');
    } finally {
      setState(() => saving = false);
    }
  }

  void _submit() async {
    // validate
    if (_answers.any((a) => a == 0)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Please answer all questions')));
      return;
    }
    await _saveCsv();
    Navigator.pushReplacementNamed(context, '/thankyou');
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.lang;
    return Scaffold(
      appBar: AppBar(title: Text(L[lang]!['feedback']!)),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('1) How easy was it to follow the steps? (1-5)'),
            _ratingRow(0),
            SizedBox(height: 12),
            Text('2) Was the information useful? (1-5)'),
            _ratingRow(1),
            SizedBox(height: 12),
            Text('3) Would you recommend this app? (1-5)'),
            _ratingRow(2),
            Spacer(),
            if (saving) Center(child: Text(L[lang]!['saving']!)),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    child: Text(L[lang]!['go_back']!),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    child: Text(L[lang]!['skip']!),
                    onPressed: () =>
                        Navigator.pushReplacementNamed(context, '/thankyou'),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _submit,
                    child: Text(L[lang]!['submit']!),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _ratingRow(int index) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(5, (i) {
        final val = i + 1;
        return IconButton(
          icon: Icon(_answers[index] >= val ? Icons.star : Icons.star_border),
          onPressed: () => setState(() => _answers[index] = val),
        );
      }),
    );
  }
}

// Screen 16 - Thank you page
class ThankYouScreen extends StatelessWidget {
  final String lang;
  const ThankYouScreen({super.key, required this.lang});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L[lang]!['thank_you']!)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              L[lang]!['thank_you']!,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              child: Text(L[lang]!['back_to_main']!),
              onPressed: () =>
                  Navigator.pushNamedAndRemoveUntil(context, '/', (r) => false),
            ),
          ],
        ),
      ),
    );
  }
}

// End of file
