import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:call_log/call_log.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // 🎯 የራስህን እውነተኛ የFirebase ቁልፎች እዚህ ያስገቡ
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyYourOwnApiKeyHere", 
        appId: "1:YourOwnAppIdHere:web:abcd", 
        messagingSenderId: "YourSenderId", 
        projectId: "callreminder", 
      ),
    );
    debugPrint("🚀 Firebase በተሳካ ሁኔታ ተገናኝቷል!");
  } catch (e) {
    debugPrint("❌ Firebase Error: $e");
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Call Reminder',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _autoReminders = [];
  bool _isLoading = true;
  String _statusMessage = "የጥሪ መረጃዎችን በመፈተሽ ላይ...";

  // 🎯 የTwilio ኤስኤምኤስ መላኪያ ቁልፎች (ከTwilio Dashboard የሚገኙ)
  final String twilioAccountSid = 'YOUR_TWILIO_ACCOUNT_SID';
  final String twilioAuthToken = 'YOUR_TWILIO_AUTH_TOKEN';
  final String twilioNumber = 'YOUR_TWILIO_PHONE_NUMBER'; // ለምሳሌ: +1234567890

  @override
  void initState() {
    super.initState();
    _fetchCallLogsAndAnalyze();
  }

  // የጥሪ ታሪክን መርምሮ የ7 ቀን ልዩነት ያላቸውን የመለየት ተግባር
  Future<void> _fetchCallLogsAndAnalyze() async {
    List<Map<String, dynamic>> tempReminders = [];
    DateTime now = DateTime.now();

    // 💡 ማሳሰቢያ፡ አፑ በChrome ላይ ሲከፈት የጥሪ ታሪክ ማንበብ ስማይችል የሙከራ ዳታ (Mock Data) ይጠቀማል
    try {
      Iterable<CallLogEntry> entries = await CallLog.get();
      Set<String> processedNumbers = {};

      for (CallLogEntry entry in entries) {
        String? number = entry.number;
        if (number == null || number.isEmpty || processedNumbers.contains(number)) continue;

        DateTime callDate = DateTime.fromMillisecondsSinceEpoch(entry.timestamp ?? 0);
        int differenceInDays = now.difference(callDate).inDays;

        if (differenceInDays >= 7) {
          processedNumbers.add(number);
          String personName = (entry.name != null && entry.name!.isNotEmpty) ? entry.name! : "ያልተቀመጠ ቁጥር";

          tempReminders.add({
            "name": personName,
            "phone": number,
            "daysPassed": differenceInDays,
          });
          await _syncWithFirebase(personName, number, callDate);
        }
      }
    } catch (e) {
      // በኮምፒውተር Chrome ላይ ስንሞክረው የሚመጣ የሙከራ ዳታ (ትናንት የሠራነው)
      tempReminders = [
        {"name": "ዮናስ", "phone": "+251911223344", "daysPassed": 9},
        {"name": "ሄለን", "phone": "+251922334455", "daysPassed": 14},
        {"name": "ኪያ", "phone": "+251933445566", "daysPassed": 7},
      ];
    }

    setState(() {
      _autoReminders = tempReminders;
      _isLoading = false;
    });
  }

  // ወደ Firebase Firestore ዳታ የመላኪያ ክፍል
  Future<void> _syncWithFirebase(String name, String phone, DateTime lastCall) async {
    try {
      await FirebaseFirestore.instance.collection('auto_reminders').doc(phone).set({
        'name': name,
        'phone': phone,
        'lastCall': lastCall.toIso8601String(),
        'updatedAt': Timestamp.now(),
      });
    } catch (e) {
      debugPrint("Firebase Sync Error: $e");
    }
  }

  // 🚀 አንድ ጊዜ ክሊክ ሲደረግ በዝርዝሩ ላሉት ሰዎች በሙሉ ኤስኤምኤስ የሚልከው ቁልፍ ተግባር
  Future<void> _sendSmsToAll() async {
    if (_autoReminders.isEmpty) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('⏳ ማስታወሻዎች ለሁሉም ሰው በመላክ ላይ ናቸው...')),
    );

    for (var person in _autoReminders) {
      String message = "ሰላም ${person['name']}፣ ከተደዋወልን ${person['daysPassed']} ቀን አልፎናል። እባክህ በትርፍ ጊዜህ ደውልልኝ! 📞";
      await _executeTwilioSms(person['phone'], message);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ ሁሉም ማስታወሻዎች በተሳካ ሁኔታ ተልከዋል!'), backgroundColor: Colors.green),
    );
  }

  // የTwilio API በመጠቀም እውነተኛ ኤስኤምኤስ የሚልከው የጀርባ ኮድ
  Future<void> _executeTwilioSms(String toPhoneNumber, String messageBody) async {
    final String url = 'https://api.twilio.com/2010-04-01/Accounts/$twilioAccountSid/Messages.json';

    // የTwilio Auth ስሪት ማዘጋጃ
    String creds = "$twilioAccountSid:$twilioAuthToken";
    String bytes = base64Encode(utf8.encode(creds));

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Basic $bytes',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'From': twilioNumber,
          'To': toPhoneNumber,
          'Body': messageBody,
        },
      );

      if (response.statusCode == 201) {
        debugPrint("✅ ኤስኤምኤስ በተሳካ ሁኔታ ተልኳል ወደ፦ $toPhoneNumber");
      } else {
        debugPrint("❌ Twilio Error: ${response.body}");
      }
    } catch (e) {
      debugPrint("❌ የኔትወርክ ስህተት፦ $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Call Reminder 📞', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blue,
        centerTitle: true,
        actions: [
          if (!_isLoading && _autoReminders.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                onPressed: _sendSmsToAll, // 👈 አንዴ ሲነካ ለሁሉም በአንድ ላይ ይልካል
                icon: const Icon(Icons.send, color: Colors.white),
                label: const Text('ለሁሉም ላክ', style: TextStyle(color: Colors.white)),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 15),
                  Text(_statusMessage, style: const TextStyle(fontSize: 16)),
                ],
              ),
            )
          : _autoReminders.isEmpty
              ? const Center(child: Text('ከተደዋወልህ 1 ሳምንት የሆነው ምንም ሰው የለም።'))
              : ListView.builder(
                  itemCount: _autoReminders.length,
                  itemBuilder: (context, index) {
                    final person = _autoReminders[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                      elevation: 4,
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.blue,
                          child: Icon(Icons.person, color: Colors.white),
                        ),
                        title: Text(person['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("${person['phone']}\n(${person['daysPassed']} ቀን አልፎታል)"),
                        trailing: const Icon(Icons.schedule, color: Colors.orange),
                      ),
                    );
                  },
                ),
    );
  }
}