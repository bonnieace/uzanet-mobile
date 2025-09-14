import 'dart:math';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:lottie/lottie.dart';
import 'package:router_os_client/router_os_client.dart';
import 'package:uzanet/constants/sizes.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';


class CreateHotspotUserPage extends StatefulWidget {
  final RouterOSClient client;

  CreateHotspotUserPage({required this.client});

  @override
  _CreateHotspotUserPageState createState() => _CreateHotspotUserPageState();
}

class _CreateHotspotUserPageState extends State<CreateHotspotUserPage> {
  final _formKey = GlobalKey<FormState>();
  final _countController = TextEditingController();
  final _profileController = TextEditingController();
  final _durationController = TextEditingController();
    List<String> _availableProfiles = [];
  @override
  void initState() {
    super.initState();
    _fetchAvailableProfiles();
  }

  @override
  void dispose() {
    _countController.dispose();
    _profileController.dispose();
    _durationController.dispose();
    super.dispose();
  }

   Future<void> _fetchAvailableProfiles() async {
    try {
      final result = await widget.client.talk('/ip/hotspot/user/profile/print');
      final profiles = (result as List).map((profile) => profile['name']).toList();
      setState(() {
        _availableProfiles = profiles.cast<String>();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching profiles: $e')),
      );
    }
  } 
Future<void> _createHotspotUsers() async {
  if (_formKey.currentState!.validate()) {
    final count = int.parse(_countController.text);
    final profile = _profileController.text;
    final duration = _durationController.text;

    try {
      List<Map<String, String>> vouchers = [];

      for (var i = 0; i < count; i++) {
        // Generate a unique username and password
        final username = _generateRandomString(8);
        final password = _generateRandomString(8);

        // Prepare parameters for adding a user
        final parameters = 
          '/ip/hotspot/user/add name=$username password=$password profile=$profile limit-uptime=$duration'
        ;

        // Create a new hotspot user
        await widget.client.talk(parameters);

        vouchers.add({'username': username, 'password': password});
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hotspot users created successfully')),
      );

      // Optionally display or handle vouchers
      print(vouchers);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error creating hotspot users: $e')),
      );
    }
  }
}

String _generateRandomString(int length) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final rand = Random();
  return List.generate(length, (_) => chars[rand.nextInt(chars.length)]).join();
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Create Hotspot Users',style: TextStyle(color: Colors.white,fontSize: TSizes.fontSizeLg),),
        backgroundColor: Colors.redAccent,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                 Container(
                  width: 250,
                  height: 250,
                  child: Lottie.asset('assets/worker.json'),
                ),
        
                TextFormField(
                  controller: _countController,
                  decoration: InputDecoration(
                    prefixIcon: Icon(Iconsax.ticket,color: Colors.red,),
                    labelText: 'Number of tickets',labelStyle: TextStyle(color: Colors.grey)),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter the number of users';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),
                                TypeAheadFormField(
                  textFieldConfiguration: TextFieldConfiguration(
                    controller: _profileController,
                    decoration: InputDecoration(
                      prefixIcon: Icon(Iconsax.wifi, color: Colors.red),
                      labelText: 'Profile Name',
                      labelStyle: TextStyle(color: Colors.grey),
                    ),
                  ),
                  suggestionsCallback: (pattern) {
                    return _availableProfiles.where((profile) =>
                        profile.toLowerCase().contains(pattern.toLowerCase()));
                  },
                  itemBuilder: (context, String suggestion) {
                    return ListTile(
                      title: Text(suggestion),
                    );
                  },
                  onSuggestionSelected: (String suggestion) {
                    _profileController.text = suggestion;
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please select a profile';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),
                TextFormField(
                  controller: _durationController,
                  
                  decoration: InputDecoration(
                    prefixIcon: Icon(Iconsax.timer,color: Colors.red,),
                    labelText: 'Duration (1h,1d,1w)',labelStyle: TextStyle(color: Colors.grey)),
                ),
                SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _createHotspotUsers,
                    child: Text('Create Vouchers'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      padding: EdgeInsets.symmetric(vertical: 16.0),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
