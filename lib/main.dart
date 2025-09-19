import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(
    MaterialApp(
      title: 'Hotel Bell App',
      home: TcpClientPage(),
      debugShowCheckedModeBanner: false,
    ),
  );
}

class Message {
  final String macAddress;
  final String? battery;
  final DateTime receivedAt;
  Message({required this.macAddress, this.battery, required this.receivedAt});
}

int _findMessageIndex(List<Message> messages, String macAddress) {
  return messages.indexWhere((msg) => msg.macAddress == macAddress);
}

class TcpClientPage extends StatefulWidget {
  const TcpClientPage({super.key});

  @override
  _TcpClientPageState createState() => _TcpClientPageState();
}

class _TcpClientPageState extends State<TcpClientPage> {
  final ipController = TextEditingController();
  final portController = TextEditingController();

  Socket? socket;
  bool isConnected = false;
  String _incomplete = '';

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  final List<Message> messages = [];

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _requestNotificationPermission();
    _loadLastUsedConfig();
  }

  Future<void> _loadLastUsedConfig() async {
    final prefs = await SharedPreferences.getInstance();
    ipController.text = prefs.getString('last_ip') ?? '';
    portController.text = prefs.getString('last_port') ?? '';
  }

  Future<void> _saveLastUsedConfig(String ip, String port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_ip', ip);
    await prefs.setString('last_port', port);
  }

  Future<void> _requestNotificationPermission() async {
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
    final status = await Permission.notification.status;
    print('🔔 Notification permission status: $status');
  }

  Future<void> _initNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  Future<void> _showNotification(String title, String body) async {
    try {
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
            'server_channel',
            'Server Messages',
            channelDescription: 'Channel for server messages',
            importance: Importance.max,
            priority: Priority.high,
            ticker: 'ticker',
          );
      const NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
      );
      await flutterLocalNotificationsPlugin.show(
        0,
        title,
        body,
        platformChannelSpecifics,
        payload: 'server_payload',
      );
      print('🔔 Notification shown: $title - $body');
    } catch (e) {
      print('❌ Notification error: $e');
    }
  }

  void connectToServer() async {
    final ip = ipController.text.trim();
    final port = int.tryParse(portController.text.trim()) ?? 0;

    await _saveLastUsedConfig(ip, portController.text.trim());

    try {
      socket = await Socket.connect(ip, port);
      setState(() => isConnected = true);
      print('✅ Connected to $ip:$port');

      // Switch to Home tab after successful connection
      Future.delayed(Duration.zero, () {
        DefaultTabController.of(context).animateTo(1);
      });

      socket!.listen(
        (data) {
          final chunk = String.fromCharCodes(data);
          final combined = _incomplete + chunk;
          final parts = combined.split('\n');
          _incomplete = parts.removeLast();
          for (final line in parts) {
            final response = line.trim();
            if (response.isEmpty) continue;
            print("📩 Server Line: '$response'");
            try {
              final jsonMsg = json.decode(response);
              final String? mac = (jsonMsg['mac_address'] ?? jsonMsg['mac'])
                  ?.toString();
              final dynamic cs = jsonMsg['call_status'];
              final String? battery = jsonMsg['battery']?.toString();
              if (mac != null && cs != null) {
                final int? callStatus = cs is int
                    ? cs
                    : int.tryParse(cs.toString());
                if (callStatus == null) continue;
                setState(() {
                  final idx = _findMessageIndex(messages, mac);
                  if (callStatus == 1) {
                    if (idx == -1) {
                      messages.insert(
                        0,
                        Message(
                          macAddress: mac,
                          battery: battery,
                          receivedAt: DateTime.now(),
                        ),
                      );
                    } else {
                      messages[idx] = Message(
                        macAddress: mac,
                        battery: battery ?? messages[idx].battery,
                        receivedAt: DateTime.now(),
                      );
                    }
                    _showNotification(
                      'Device Call',
                      'MAC: $mac${battery != null ? ' | Battery: $battery' : ''}',
                    );
                  } else if (callStatus == 0) {
                    if (idx != -1) {
                      messages.removeAt(idx);
                    }
                  }
                });
              } else {
                _showNotification(
                  'Device Message',
                  'Missing mac_address or call_status',
                );
              }
            } catch (e) {
              print('❌ JSON parse error: $e');
              _showNotification('Device Message', 'Invalid data received');
            }
          }
        },
        onDone: () {
          print("🔌 Disconnected");
          setState(() => isConnected = false);
        },
        onError: (err) {
          print("❌ Error: $err");
          setState(() => isConnected = false);
        },
      );
    } catch (e) {
      print("🚫 Could not connect: $e");
    }
  }

  @override
  void dispose() {
    socket?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: 0,
      child: Scaffold(
        appBar: AppBar(
          title: Text("Hotel Bell App"),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Configurations', icon: Icon(Icons.settings)),
              Tab(text: 'Home', icon: Icon(Icons.table_bar)),
            ],
          ),
        ),
        body: TabBarView(
          physics: NeverScrollableScrollPhysics(),
          children: [
            // Configurations Tab
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  TextField(
                    controller: ipController,
                    decoration: InputDecoration(labelText: "Server IP"),
                  ),
                  TextField(
                    controller: portController,
                    decoration: InputDecoration(labelText: "Port"),
                    keyboardType: TextInputType.number,
                  ),
                  SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: connectToServer,
                    child: Text("Connect"),
                  ),
                  SizedBox(height: 20),
                  Row(
                    children: [
                      Icon(
                        Icons.circle,
                        color: isConnected ? Colors.green : Colors.grey,
                        size: 16,
                      ),
                      SizedBox(width: 8),
                      Text(isConnected ? "Connected" : "Not Connected"),
                    ],
                  ),
                ],
              ),
            ),
            // Home Tab
            HomePage(messages: messages),
          ],
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final List<Message> messages;
  const HomePage({super.key, required this.messages});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Update UI every 30 seconds for 'minutes ago' text
    _timer = Timer.periodic(Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String timeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes == 0) {
      return 'Just now';
    } else if (diff.inMinutes == 1) {
      return '1 minute ago';
    } else {
      return '${diff.inMinutes} minutes ago';
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.messages;
    return Scaffold(
      appBar: AppBar(title: Text('Device Calls')),
      body: messages.isEmpty
          ? Center(child: Text('No device calls yet.'))
          : ListView.builder(
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final msg = messages[index];
                return ListTile(
                  leading: Icon(Icons.devices_other),
                  title: Text('MAC: ${msg.macAddress}'),
                  subtitle: Text(
                    '${timeAgo(msg.receivedAt)}' +
                        ((msg.battery != null && msg.battery!.isNotEmpty)
                            ? '  •  Battery: ${msg.battery}'
                            : ''),
                  ),
                );
              },
            ),
    );
  }
}
