import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:router_os_client/router_os_client.dart';

class TicketsPage extends StatefulWidget {
  final RouterOSClient client;

  TicketsPage({required this.client});

  @override
  _TicketsPageState createState() => _TicketsPageState();
}

class _TicketsPageState extends State<TicketsPage> {
  List<Map<String, String>> users = [];

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    bool isConnected = await widget.client.login();

    if (isConnected) {
      try {
        List<Map<String, String>> fetchedUsers = await widget.client.talk(['/ip/hotspot/user/print']);

        // Filter out users with username "default-trial" or "admin"
        fetchedUsers = fetchedUsers.where((user) {
          final username = user['name'] ?? '';
          return username != 'default-trial' && username != 'admin';
        }).toList();

        setState(() {
          users = fetchedUsers;
        });
      } catch (e) {
        print('Error fetching users: $e');
      }
    } else {
      print('Failed to connect to RouterOS');
    }
  }

  void _copyToClipboard(String username, String password) {
    Clipboard.setData(ClipboardData(text: 'Username: $username\nPassword: $password'));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Username and password copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Tickets',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
        ),
        backgroundColor: Colors.redAccent,
      ),
      body: ListView.builder(
        itemCount: users.length,
        itemBuilder: (context, index) {
          final user = users[index];
          final username = user['name'] ?? 'Unknown';
          final password = user['password'] ?? 'Unknown';
          final uptimeLimit = user['limit-uptime'] ?? 'No Limit';

          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.green,
              child: Icon(Icons.person, color: Colors.white),
            ),
            title: Text('username : $username'),
            subtitle: Text('Password: $password\nUptime Limit: $uptimeLimit'),
            trailing: IconButton(
              icon: Icon(Icons.copy, color: Colors.grey),
              onPressed: () => _copyToClipboard(username, password),
            ),
          );
        },
      ),
    );
  }
}
