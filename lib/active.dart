import 'package:flutter/material.dart';
import 'package:router_os_client/router_os_client.dart';

class ActiveUsersPage extends StatefulWidget {
  final RouterOSClient client;

  ActiveUsersPage({required this.client});

  @override
  _ActiveUsersPageState createState() => _ActiveUsersPageState();
}

class _ActiveUsersPageState extends State<ActiveUsersPage> {
  List<Map<String, String>> activeUsers = [];

  @override
  void initState() {
    super.initState();
    _fetchActiveUsers();
  }

  Future<void> _fetchActiveUsers() async {
    bool isConnected = await widget.client.login();

    if (isConnected) {
      try {
        List<Map<String, String>> fetchedActiveUsers = await widget.client.talk(['/ip/hotspot/active/print']);
        setState(() {
          activeUsers = fetchedActiveUsers;
        });
      } catch (e) {
        print('Error fetching active users: $e');
      }
    } else {
      print('Failed to connect to RouterOS');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Active Users',style: TextStyle(color: Colors.white),),
        backgroundColor: Colors.redAccent,
      ),
      body: ListView.builder(
        itemCount: activeUsers.length,
        itemBuilder: (context, index) {
          final user = activeUsers[index];
          final username = user['user'] ?? 'Unknown';
          final address = user['address'] ?? 'Unknown';

          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blue,
              child: Icon(Icons.person, color: Colors.white),
            ),
            title: Text(username),
            subtitle: Text('Address: $address'),
          );
        },
      ),
    );
  }
}
