import 'package:flutter/material.dart';
import 'package:router_os_client/router_os_client.dart';

class InternetPlanStatusPage extends StatelessWidget {
  final RouterOSClient client;

  InternetPlanStatusPage({required this.client});

  Future<List<Map<String, String>>> fetchInternetPlans() async {
    try {
      // Fetch hotspot users
      List<Map<String, String>> users = await client.talk(['/ip/hotspot/user/print']);

      // Separate users into used and expired based on uptime
      final now = DateTime.now();
      List<Map<String, String>> usedPlans = [];
      List<Map<String, String>> expiredPlans = [];

      for (var user in users) {
        if (user['uptime'] != null && user['uptime']!.isNotEmpty) {
          // Mock logic to determine if a user is expired or used
          // You can replace this with your actual uptime validation logic
          if (user['uptime']!.contains('d')) {
            expiredPlans.add(user);
          } else {
            usedPlans.add(user);
          }
        }
      }

      return [
        {'type': 'Used', 'count': usedPlans.length.toString()},
        {'type': 'Expired', 'count': expiredPlans.length.toString()},
      ];
    } catch (e) {
      print('Error fetching internet plans: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Internet Plan Status'),
        backgroundColor: Colors.redAccent,
      ),
      body: FutureBuilder<List<Map<String, String>>>(
        future: fetchInternetPlans(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(child: Text('No data available'));
          }

          final plans = snapshot.data!;
          return ListView.builder(
            itemCount: plans.length,
            itemBuilder: (context, index) {
              final plan = plans[index];
              return ListTile(
                leading: Icon(plan['type'] == 'Used' ? Icons.check_circle : Icons.error, color: plan['type'] == 'Used' ? Colors.green : Colors.red),
                title: Text(plan['type']!),
                trailing: Text(plan['count']!),
              );
            },
          );
        },
      ),
    );
  }
}
