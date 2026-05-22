import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// የማሳወቂያ መቆጣጠሪያ ማዕከል
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// በጀርባ (Background) በየጊዜው የሚሠራው ዋናው ሥራ
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    await checkContactsAndNotify();
    return Future.value(true);
  });
}

// 1 ቀን ያለፋቸውን እውቂያዎች ፈልጎ ማሳወቂያ የሚልከው ተግባር
Future<void> checkContactsAndNotify() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  
  // የስልክ እውቂያዎችን ፈቃድ ካለን ማምጣት
  if (await FlutterContacts.requestPermission(readonly: true)) {
    List<Contact> contacts = await FlutterContacts.getContacts(withProperties: true);
    DateTime now = DateTime.now();

    for (var contact in contacts) {
      if (contact.phones.isNotEmpty) {
        String phone = contact.phones.first.number;
        
        String? lastCallStr = prefs.getString('last_call_$phone');
        DateTime lastCall = lastCallStr != null ? DateTime.parse(lastCallStr) : now;

        int differenceInDays = now.difference(lastCall).inDays;

        // 1 ቀንና ከዚያ በላይ ከሆናቸው ማሳወቂያ ይልካል
        if (differenceInDays >= 1) {
          await showNotification(
            contact.displayName,
            "ከ ${contact.displayName} ጋር ካወራህ 1 ቀን አልፏል። እባክህ ደውልለት/ላት!",
          );
        }
      }
    }
  }
}

// ማሳወቂያውን ለተጠቃሚው ስክሪን ላይ የሚያሳይ ተግባር
Future<void> showNotification(String title, String body) async {
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
    'call_channel_id',
    'Call Notifications',
    channelDescription: 'Notifications to remind you to call contacts',
    importance: Importance.max,
    priority: Priority.high,
  );
  
  const NotificationDetails platformChannelSpecifics =
      NotificationDetails(android: androidPlatformChannelSpecifics);
      
  await flutterLocalNotificationsPlugin.show(
    title.hashCode,
    title,
    body,
    platformChannelSpecifics,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // የማሳወቂያ ቅንብሮችን ማስጀመር
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // የጀርባ ሥራ መቆጣጠሪያውን (Workmanager) ማስጀመር
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: true);
  
  // በየ 15 ደቂቃው በጀርባ ሆኖ ስልኩን እንዲፈትሽ ማዘዝ
  await Workmanager().registerPeriodicTask(
    "1",
    "periodicCallCheckTask",
    frequency: const Duration(minutes: 15),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Call Reminder App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomeScreen(),
    );
  }
}

// የአፑ ዋናው ገጽ (UI)
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    checkContactsAndNotify();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('የጥሪ ማስታወሻ')),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.phone_in_talk, size: 80, color: Colors.blue),
            SizedBox(height: 20),
            Text(
              'አፑ በሰላም እየሠራ ነው!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              'በየ 1 ቀኑ ያልተደወለላቸውን ሰዎች እየፈለገ ማሳወቂያ ይልክልሃል።',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}