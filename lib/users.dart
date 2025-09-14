import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:iconsax/iconsax.dart';
import 'package:router_os_client/router_os_client.dart';
import 'package:uzanet/constants/sizes.dart';

class UsersPage extends StatefulWidget {
  final RouterOSClient client;

  UsersPage({required this.client});

  @override
  _UsersPageState createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  List<Map<String, String>> users = [];
  List<Map<String, String>> internetPlans = [];
  String selectedFilter = 'All'; // Filter option
  bool isFetchingPlans = true;
  

  @override
  void initState() {
    super.initState();
    _fetchUsers();
    _fetchInternetPlans();
  }

  Future<void> _fetchUsers() async {
    bool isConnected = await widget.client.login();

    if (isConnected) {
      try {
        List<Map<String, String>> fetchedUsers = await widget.client.talk(['/ip/hotspot/user/print']);
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

  Future<void> _fetchInternetPlans() async {
    try {
      List<Map<String, String>> fetchedUsers = await widget.client.talk(['/ip/hotspot/user/print']);
      List<Map<String, String>> usedPlans = [];
      List<Map<String, String>> expiredPlans = [];

      for (var user in fetchedUsers) {
        final uptime = user['uptime'];
        final uptimeLimit = user['limit-uptime'];

        if (uptime != null && uptime.isNotEmpty) {
          final uptimeSeconds = _convertUptimeToSeconds(uptime);
          final uptimeLimitSeconds = uptimeLimit != null ? _convertUptimeToSeconds(uptimeLimit) : null;

          if (uptimeLimitSeconds != null && uptimeSeconds >= uptimeLimitSeconds) {
            expiredPlans.add(user);
          } else if (uptimeSeconds !=uptimeLimitSeconds) {
            usedPlans.add(user);
          }
        }
      }

      setState(() {
        internetPlans = [
          {'type': 'All', 'count': fetchedUsers.length.toString()},
          {'type': 'Used', 'count': usedPlans.length.toString()},
          {'type': 'Expired', 'count': expiredPlans.length.toString()},
          
        ];
        isFetchingPlans = false;
      });
    } catch (e) {
      print('Error fetching internet plans: $e');
      setState(() {
        isFetchingPlans = false;
      });
    }
  }

  int _convertUptimeToSeconds(String uptime) {
    final regex = RegExp(r'(\d+)([dhms])');
    int totalSeconds = 0;

    for (var match in regex.allMatches(uptime)) {
      final value = int.parse(match.group(1)!);
      final unit = match.group(2);

      switch (unit) {
        case 'd':
          totalSeconds += value * 86400;
          break;
        case 'h':
          totalSeconds += value * 3600;
          break;
        case 'm':
          totalSeconds += value * 60;
          break;
        case 's':
          totalSeconds += value;
          break;
      }
    }

    return totalSeconds;
  }

  Future<void> _deleteUser(String userId) async {
    bool isConnected = await widget.client.login();

    if (isConnected) {
      try {
        List<Map<String, String>> activeUsers = await widget.client.talk(['/ip/hotspot/active/print']);
        var activeUser = activeUsers.firstWhere(
          (user) => user['user'] == userId,
          orElse: () => {},
        );

        if (activeUser.isNotEmpty) {
          await widget.client.talk(['/ip/hotspot/active/remove', '=.id=${activeUser['.id']}']);
        }

        await widget.client.talk(['/ip/hotspot/user/remove', '=.id=$userId']);
        setState(() {
          users.removeWhere((user) => user['.id'] == userId);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('User deleted and logged out successfully')),
        );
      } catch (e) {
        print('Error deleting user: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete user')),
        );
      }
    } else {
      print('Failed to connect to RouterOS');
    }
  }

  @override
  Widget build(BuildContext context) {
  double screenWidth = MediaQuery.of(context).size.width;

    List<Map<String, String>> filteredUsers = users;
    if (selectedFilter == 'Used') {
      filteredUsers = users.where((user) {
        final uptime = user['uptime'];
        final uptimeLimit = user['uptime-limit'];
        if (uptime != null && uptime.isNotEmpty) {
          final uptimeSeconds = _convertUptimeToSeconds(uptime);
          final uptimeLimitSeconds = uptimeLimit != null ? _convertUptimeToSeconds(uptimeLimit) : null;
          return uptimeSeconds > 0 && (uptimeLimitSeconds == null || uptimeSeconds < uptimeLimitSeconds);
        }
        return false;
      }).toList();
    } else if (selectedFilter == 'Expired') {
      filteredUsers = users.where((user) {
        final uptime = user['uptime'];
        final uptimeLimit = user['limit-uptime'];
        if (uptime != null && uptime.isNotEmpty) {
          final uptimeSeconds = _convertUptimeToSeconds(uptime);
          final uptimeLimitSeconds = uptimeLimit != null ? _convertUptimeToSeconds(uptimeLimit) : null;
          return uptimeLimitSeconds != null && uptimeSeconds >= uptimeLimitSeconds;
        }
        return false;
      }).toList();
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: Get.back, icon:Icon(Iconsax.arrow_circle_left,color: Colors.white,),
),
        title: Text('Users', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
        backgroundColor: Colors.redAccent,
      ),
      body: Column(
        children: [
          if (isFetchingPlans)
            Center(child: CircularProgressIndicator())
          else
            Column(
              children: [
                SizedBox(height: 12,),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: internetPlans.map((plan) {
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          selectedFilter = plan['type']!;
                        });
                      },
                      child: Card(
                        color: selectedFilter == plan['type']
                            ? (plan['type'] == 'Used' ? Colors.green : (plan['type'] == 'Expired' ? Colors.red : Colors.blue))
                            : Colors.white,
                        elevation: selectedFilter == plan['type'] ? 6 : 2,
                        shape: RoundedRectangleBorder(
                          side: BorderSide(color: selectedFilter == plan['type'] ? Colors.white : Colors.black),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        
                        child: Padding(
                          
                          padding:  screenWidth < 600
        ? const EdgeInsets.symmetric(vertical: 10.0, horizontal: 20.0)
        : const EdgeInsets.symmetric(vertical: 10.0, horizontal: 70.0),

                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                plan['type'] == 'Used' ? Icons.check_circle : plan['type'] == 'Expired' ? Icons.warning : Icons.all_inclusive,
                                color: selectedFilter == plan['type'] ? Colors.white : Colors.black,
                                size: 40,
                              ),
                              SizedBox(height: 8),
                              Text(
                                plan['type']!,
                                style: TextStyle(
                                  color: selectedFilter == plan['type'] ? Colors.white : Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                plan['count']!,
                                style: TextStyle(
                                  color: selectedFilter == plan['type'] ? Colors.white : Colors.black,
                                  fontSize: 24,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                SizedBox(height: 20,),
                


              ],
            ),
          Expanded(
            child: SingleChildScrollView(
              child: Container(
                width: double.infinity,
                child: DataTable(
                  columnSpacing: 16.0,
                  headingRowColor: MaterialStateColor.resolveWith((states) => Colors.grey.shade200),
                  columns: [
                    DataColumn(
                          label: Text('Name', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    DataColumn(
                          label: Text('Uptime', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    DataColumn(
                          label: Text('Limit', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    DataColumn(
                          label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                  rows: filteredUsers.map((user) {
                    var uptime = user['uptime'] ?? 'N/A';
                    var limitUptime = user['limit-uptime'] ?? 'N/A';
                    var userName = user['name'] ?? 'Unnamed';
                          
                    return DataRow(cells: [
                          DataCell(
                            Row(
                children: [

                 screenWidth>600? CircleAvatar(
                    backgroundColor: Colors.green,
                    child: Text(
                      userName.substring(0, 1),
                      style: TextStyle(color: Colors.white),
                    ),
                  ):SizedBox(width: 8),
                  SizedBox(width: 8),
                  
                  Text(userName),
                ],
                            ),
                          ),
                          DataCell(Text(uptime)),
                          DataCell(Text(limitUptime)),
                          DataCell(
                            IconButton(
                icon: Icon(Icons.delete, color: Colors.red),
                onPressed: () async {
                  bool confirmed = await _showConfirmationDialog(userName);
                  if (confirmed) {
                    _deleteUser(user['.id']!);
                  }
                },
                            ),
                          ),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          ),

        ],
      ),
    );
  }

  Future<bool> _showConfirmationDialog(String userName) async {
    return (await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Delete User'),
            content: Text('Are you sure you want to delete $userName?'),
            actions: [
              TextButton(
                child: Text('Cancel'),
                onPressed: () {
                  Navigator.of(context).pop(false);
                },
              ),
              TextButton(
                child: Text('Delete', style: TextStyle(color: Colors.red)),
                onPressed: () {
                  Navigator.of(context).pop(true);
                },
              ),
            ],
          ),
        )) ??
        false;
  }
}
