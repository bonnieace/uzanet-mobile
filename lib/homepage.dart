import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';
import 'package:lottie/lottie.dart';
import 'package:router_os_client/router_os_client.dart';
import 'package:uzanet/active.dart';
import 'package:uzanet/documents.dart';
import 'package:uzanet/hotspot.dart';
import 'package:uzanet/tickets.dart';
import 'package:uzanet/voucher.dart';

import 'internet_plan_status.dart';
import 'users.dart';

class StatusPage extends StatefulWidget {
  @override
  _StatusPageState createState() => _StatusPageState();
}

class _StatusPageState extends State<StatusPage> {
  RouterOSClient? client;

  @override
  void initState() {
    super.initState();
    client = RouterOSClient(
      address: '192.168.88.1',
      user: 'admin',
      password: 'twinkles',
      useSsl: false,
      verbose: true,
    );
  }
  @override
void dispose() {
  client?.close();  // Close the connection when the widget is disposed
  super.dispose();
}


  Stream<Map<String, String>> _routerStatsStream() async* {
    while (true) {
      await Future.delayed(Duration(seconds: 5)); // Adjust the delay as needed

      bool isConnected = await client!.login();

      if (isConnected) {
        try {
          // Fetch CPU and Memory Usage
          List<Map<String, String>> resource = await client!.talk(['/system/resource/print']);
          String cpu = (resource[0]['cpu-load'] ?? '0') + '%';
          String memory = '${(int.parse(resource[0]['free-memory'] ?? '0') / (1024 * 1024)).toStringAsFixed(2)} MiB';

          // Fetch Date and Time
          List<Map<String, String>> clock = await client!.talk(['/system/clock/print']);
          String date = clock[0]['date'] ?? 'Unknown';
          String time = clock[0]['time'] ?? 'Unknown';

          // Fetch Hotspots
          List<Map<String, String>> hotspotServers = await client!.talk(['/ip/hotspot/print']);
          String hotspotServersCount = hotspotServers.length.toString();

          // Fetch Users
          List<Map<String, String>> users = await client!.talk(['/ip/hotspot/user/print']);
          String usersCount = users.length.toString();

          // Fetch Active Users
          List<Map<String, String>> activeUsers = await client!.talk(['/ip/hotspot/active/print']);
          String activeUsersCount = activeUsers.length.toString();

          yield {
            'cpu': cpu,
            'memory': memory,
            'date': date,
            'time': time,
            'hotspotServers': hotspotServersCount,
            'users': usersCount,
            'activeUsers': activeUsersCount,
          };
        } catch (e) {
          print('Error fetching data: $e');
          yield {
            'cpu': 'Error',
            'memory': 'Error',
            'date': 'Error',
            'time': 'Error',
            'hotspotServers': 'Error',
            'users': 'Error',
            'activeUsers': 'Error',
          };
        }
      } else {
        print('Failed to connect to RouterOS');
        yield {
          'cpu': 'offline',
          'memory': 'offline',
          'date': 'offline',
          'time': 'offline',
          'hotspotServers': 'offline',
          'users': 'offline',
          'activeUsers': 'offline',
        };
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Status',style: TextStyle(fontSize: 20, color: Colors.white,fontWeight: FontWeight.bold),),
        backgroundColor: Colors.redAccent,
      ),
      body: StreamBuilder<Map<String, String>>(
        stream: _routerStatsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData) {
            return Center(child: Text('No data available'));
          }

          final stats = snapshot.data!;

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildMainInfoSection(stats),
                  SizedBox(height: 16),
                  _buildStatsSection(stats),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      // Handle button press
                      Get.to(CreateHotspotUserPage(client: client!));
                      
                      
                    },
                    child: Text('Create tickets'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: EdgeInsets.symmetric(vertical: 16.0),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMainInfoSection(Map<String, String> stats) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                  Container(
                  width: 120,
                  height: 120,
                  child: Lottie.asset('assets/router_animation.json'),
                ),
                
                
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                  

                    children: [
                    
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          
                          Text(
                            'MikroTik',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          Text('192.168.88.1 | hEX lite'),
                          Text('6.46.8 (long-term)'),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.settings),
              ],
            ),
            SizedBox(height: 16),
            Divider(color: Colors.grey[300]),
            Row(
              children: [
                Expanded(
                  child: _buildStatColumn(stats['cpu']!, 'CPU'),
                ),
                VerticalDivider(color: Colors.grey[300]),
                Expanded(
                  child: _buildStatColumn(stats['memory']!, 'Memory'),
                ),
              ],
            ),
            SizedBox(height: 16),
            Divider(color: Colors.grey[300]),
            Row(
              children: [
                Expanded(
                  child: _buildStatColumn(stats['date']!, 'Date'),
                ),
                VerticalDivider(color: Colors.grey[300]),
                Expanded(
                  child: _buildStatColumn(stats['time']!, 'Time'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsSection(Map<String, String> stats) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      
                      Get.to(()=>HotspotServersPage(client: client!));
                    },
                    child: _buildInfoColumn('Hotspots', stats['hotspotServers']!, Iconsax.wifi5)),
                ),
                VerticalDivider(color: Colors.grey[300]),
                Expanded(
                    child: InkWell(
                      onTap: () {
                        Get.to(() => InternetPlanStatusPage(client: client!));
                      },
                      child: _buildInfoColumn('Used/Expired', 'Check', Icons.access_time),
                    ),
                  ),
              ],
            ),
            SizedBox(height: 16),
            Divider(color: Colors.grey[300]),
            Row(
              children: [
                Expanded(
                      child: InkWell(
                      onTap: () {
                        Get.to(() => UsersPage(client: client!));
                      },
                      child: _buildInfoColumn('Users', stats['users']!, Icons.people),
                    )

                ),
                VerticalDivider(color: Colors.grey[300]),
                Expanded(
                  child: InkWell(
                    onTap: (){
                      Get.to(()=>ActiveUsersPage(client: client!));
                    },
                    child: _buildInfoColumn('Active', stats['activeUsers']!, Icons.people, active: true)),
                ),
              ],
            ),
            SizedBox(height: 16),
            Divider(color: Colors.grey[300]),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: (){
                      Get.to(()=>TicketsPage(client: client!));
                    },
                    child: _buildInfoColumn('Tickets', (int.parse(stats['users']!) - 2).toString(), Icons.confirmation_number)),
                ),
                VerticalDivider(color: Colors.grey[300]),
                Expanded(
                  child: 
                  InkWell(
                    child:  _buildInfoColumn('Documents', '0', Icons.picture_as_pdf),
                    onTap:(){
                      Get.to(()=>DocumentsPage(client: client!));
                    },
                  )
                 
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Column _buildStatColumn(String value, String label) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(value, textAlign: TextAlign.center,style: TextStyle(fontSize: 16,fontWeight: FontWeight.bold)),
        Text(label,textAlign: TextAlign.center),
      ],
    );
  }

  Column _buildInfoColumn(String title, String value, IconData icon, {bool active = false}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment:MainAxisAlignment.center,
          children: [
            Text(title),
            SizedBox(width: 10,),
            Icon(icon, size: 36, color: active ? Colors.green : Colors.black),
          ],
        ),
        
        SizedBox(height: 8),
        Text(value, style: TextStyle(fontSize: 16,fontWeight: FontWeight.bold)),
        
      ],
    );
  }
}
