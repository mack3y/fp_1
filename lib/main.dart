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

// Updated Message class to use id instead of strictly macAddress
class Message {
  final String id;
  final String? battery;
  final DateTime receivedAt;
  Message({required this.id, this.battery, required this.receivedAt});
}

int _findMessageIndex(List<Message> messages, String id) {
  return messages.indexWhere((msg) => msg.id == id);
}

class TcpClientPage extends StatefulWidget {
  const TcpClientPage({super.key});

  @override
  _TcpClientPageState createState() => _TcpClientPageState();
}

class _TcpClientPageState extends State<TcpClientPage>
    with SingleTickerProviderStateMixin {
  final ipController = TextEditingController();
  final portController = TextEditingController();

  Socket? socket;
  bool isConnected = false;
  String _incomplete = '';

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  final List<Message> messages = [];
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _requestNotificationPermission();
    _loadLastUsedConfig();
    _tabController = TabController(length: 2, vsync: this);
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
      const NotificationDetails platformChannelSpecifics =
          NotificationDetails(android: androidPlatformChannelSpecifics);
      await flutterLocalNotificationsPlugin.show(
        0,
        title,
        body,
        platformChannelSpecifics,
      );
      print('🔔 Notification shown: $title - $body');
    } catch (e) {
      print('❌ Notification error: $e');
    }
  }

  void connectToServer() async {
    final ip = ipController.text.trim();
    final port = int.tryParse(portController.text.trim()) ?? 0;

    if (ip.isEmpty || port == 0) {
      print("🚫 Please enter a valid IP and Port");
      return;
    }

    await _saveLastUsedConfig(ip, portController.text.trim());

    try {
      socket = await Socket.connect(ip, port, timeout: Duration(seconds: 5));
      setState(() => isConnected = true);
      print('✅ Connected to $ip:$port');

      // Switch to Home tab
      Future.delayed(Duration.zero, () {
        if (mounted) _tabController.animateTo(1);
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

              // Use mac_address/mac or fallback to table_id
              final String? id = (jsonMsg['mac_address'] ??
                      jsonMsg['mac'] ??
                      jsonMsg['table_id'])
                  ?.toString();
              final dynamic cs = jsonMsg['call_status'];
              final String? battery = jsonMsg['battery']?.toString();

              if (id != null && cs != null) {
                final int? callStatus =
                    cs is int ? cs : int.tryParse(cs.toString());
                if (callStatus == null) continue;

                setState(() {
                  final idx = _findMessageIndex(messages, id);
                  if (callStatus == 1) {
                    if (idx == -1) {
                      messages.insert(
                        0,
                        Message(
                          id: id,
                          battery: battery,
                          receivedAt: DateTime.now(),
                        ),
                      );
                    } else {
                      messages[idx] = Message(
                        id: id,
                        battery: battery ?? messages[idx].battery,
                        receivedAt: DateTime.now(),
                      );
                    }
                    _showNotification(
                      'Device Call',
                      'ID: $id${battery != null ? ' | Battery: $battery' : ''}',
                    );
                  } else if (callStatus == 0 && idx != -1) {
                    messages.removeAt(idx);
                  }
                });
              } else {
                _showNotification(
                    'Device Message', 'Missing id or call_status');
              }
            } catch (e) {
              print('❌ JSON parse error: $e');
              _showNotification('Device Message', 'Invalid data received');
            }
          }
        },
        onDone: () {
          print("🔌 Disconnected from server");
          setState(() => isConnected = false);
        },
        onError: (err) {
          print("❌ Socket error: $err");
          setState(() => isConnected = false);
        },
      );
    } catch (e) {
      print("🚫 Could not connect: $e");
      _showNotification("Connection Error", "Could not connect to $ip:$port");
    }
  }

  void disconnectFromServer() {
    socket?.destroy();
    setState(() => isConnected = false);
    print("🔌 Disconnected manually");
  }

  void clearMessages() {
    setState(() => messages.clear());
  }

  @override
  void dispose() {
    disconnectFromServer();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Hotel Bell App"),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Configurations', icon: Icon(Icons.settings)),
            Tab(text: 'Home', icon: Icon(Icons.table_bar)),
          ],
        ),
        actions: [
          if (isConnected)
            IconButton(
              icon: Icon(Icons.power_settings_new),
              onPressed: disconnectFromServer,
              tooltip: "Disconnect",
            ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
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
                  onPressed: isConnected ? null : connectToServer,
                  child: Text(isConnected ? "Connected" : "Connect"),
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
          HomePage(
            messages: messages,
            onClear: clearMessages,
          ),
        ],
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final List<Message> messages;
  final VoidCallback onClear;
  const HomePage({super.key, required this.messages, required this.onClear});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
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
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes == 1) return '1 minute ago';
    if (diff.inHours < 1) return '${diff.inMinutes} minutes ago';
    if (diff.inHours == 1) return '1 hour ago';
    if (diff.inDays < 1) return '${diff.inHours} hours ago';
    if (diff.inDays == 1) return '1 day ago';
    return '${diff.inDays} days ago';
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.messages;
    return messages.isEmpty
        ? Center(child: Text('No device calls yet.'))
        : Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: TextButton.icon(
                  onPressed: widget.onClear,
                  icon: Icon(Icons.clear_all),
                  label: Text("Clear All"),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    return Card(
                      margin:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      elevation: 2,
                      child: ListTile(
                        leading: Icon(Icons.devices_other, color: Colors.blue),
                        title: Text('ID: ${msg.id}'),
                        subtitle: Text(
                          '${timeAgo(msg.receivedAt)}'
                          '${(msg.battery != null && msg.battery!.isNotEmpty) ? '  •  Battery: ${msg.battery}' : ''}',
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
  }
}