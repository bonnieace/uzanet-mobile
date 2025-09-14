import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';
import 'package:router_os_client/router_os_client.dart';

class HotspotServersPage extends StatefulWidget {
  final RouterOSClient client;

  HotspotServersPage({required this.client});

  @override
  _HotspotServersPageState createState() => _HotspotServersPageState();
}

class _HotspotServersPageState extends State<HotspotServersPage> with SingleTickerProviderStateMixin {
  List<Map<String, String>> hotspotServers = [];
  List<Map<String, String>> serverProfiles = [];
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchData();
  }

  Future<void> _fetchData() async {
    bool isConnected = await widget.client.login();

    if (isConnected) {
      try {
        List<Map<String, String>> fetchedHotspotServers = await widget.client.talk(['/ip/hotspot/print']);
        List<Map<String, String>> fetchedServerProfiles = await widget.client.talk(['/ip/hotspot/profile/print']);

        setState(() {
          hotspotServers = fetchedHotspotServers;
          serverProfiles = fetchedServerProfiles;
        });
      } catch (e) {
        print('Error fetching data: $e');
      }
    } else {
      print('Failed to connect to RouterOS');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
               leading: IconButton(onPressed: Get.back, icon:Icon(Iconsax.arrow_circle_left,color: Colors.white,),
),
        title: Text('Hotspot Servers',style:TextStyle(color: Colors.white),),
        backgroundColor: Colors.redAccent,
        bottom: TabBar(
          labelColor: Colors.white,
          controller: _tabController,
          tabs: [
            Tab(text: 'Servers'),
            Tab(text: 'Profiles'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildHotspotServersView(),
          _buildServerProfilesView(),
        ],
      ),
    );
  }

  Widget _buildHotspotServersView() {
    return ListView.builder(
      itemCount: hotspotServers.length,
      itemBuilder: (context, index) {
        final server = hotspotServers[index];
        final name = server['name'] ?? 'Unknown';
        final interface = server['interface'] ?? 'Unknown';
        final address = server['address-pool'] ?? 'Unknown';
        final profile = server['profile'] ?? 'Unknown';

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.green,
            child: Icon(Icons.router, color: Colors.white),
          ),
          title: Text(name),
          subtitle: Text('Interface: $interface\nAddress pool: $address\nProfile: $profile'),
        );
      },
    );
  }

  Widget _buildServerProfilesView() {
    return ListView.builder(
      itemCount: serverProfiles.length,
      itemBuilder: (context, index) {
        final profile = serverProfiles[index];
        final profileName = profile['name'] ?? 'Unknown';
        final hotspotAddress = profile['hotspot-address'] ?? 'Unknown';
        final dnsName = profile['dns-name'] ?? 'Unknown';
        final htmlDirectory = profile['html-directory'] ?? 'Unknown';

        return ListTile(
          leading: Icon(Icons.cloud_upload_rounded, color: Colors.blue),
          title: Text(profileName),
          subtitle: Text('Hotspot Address: $hotspotAddress\nDNS Name: $dnsName\nHTML Directory: $htmlDirectory'),
        );
      },
    );
  }
}
