import 'package:flutter/material.dart';
import 'package:router_os_client/router_os_client.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart' show rootBundle;


class DocumentsPage extends StatefulWidget {
  final RouterOSClient client;

  DocumentsPage({required this.client});

  @override
  _DocumentsPageState createState() => _DocumentsPageState();
}

class _DocumentsPageState extends State<DocumentsPage> {
  List<Map<String, String>> hotspotUsers = [];
  List<Map<String, String>> loginHistories = [];

  @override
  void initState() {
    super.initState();  
    _fetchData();
  }

  Future<void> _fetchData() async {
    bool isConnected = await widget.client.login();

    if (isConnected) {
      try {
        // Fetch hotspot users
        List<Map<String, String>> fetchedUsers = await widget.client.talk(['/ip/hotspot/user/print']);
        // Fetch login histories
        List<Map<String, String>> fetchedLoginHistories = await widget.client.talk(['/ip/hotspot/active/print']);

        setState(() {
          hotspotUsers = fetchedUsers;
          loginHistories = fetchedLoginHistories;
        });
      } catch (e) {
        print('Error fetching data: $e');
      }
    } else {
      print('Failed to connect to RouterOS');
    }
  }

  Future<void> _viewHotspotUsersPdf() async {
  final pdf = pw.Document();
  final groupedUsers = _groupUsersByUptimeLimit(hotspotUsers);

  // Load the logo image from assets
  final logoData = await rootBundle.load('assets/a.png');
  final logo = pw.MemoryImage(logoData.buffer.asUint8List());

  groupedUsers.forEach((uptimeLimit, users) {
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            pw.Wrap(
              spacing: 10,
              runSpacing: 10,
              children: users.map((user) {
                return _buildTicket(user, uptimeLimit, logo);
              }).toList(),
            ),
          ];
        },
      ),
    );
  });

  await Printing.layoutPdf(
    onLayout: (PdfPageFormat format) async => pdf.save(),
  );
}
pw.Widget _buildTicket(Map<String, dynamic> user, String uptimeLimit, pw.ImageProvider logo) {
  return pw.Container(
    width: 150, // Define the width of each ticket
    height: 110, // Define the height of each ticket
    padding: pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.black, width: 1),
      borderRadius: pw.BorderRadius.circular(8),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Image(logo, height: 30), // Display the logo
        pw.SizedBox(height: 5),
        pw.Text(
          'Ticket for Tabby T wifi',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          'Uptime Limit: $uptimeLimit',
          style: pw.TextStyle(fontSize: 10),
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          'Username: ${user['name'] ?? 'Unknown'}',
          style: pw.TextStyle(fontSize: 10),
        ),
        pw.Text(
          'Password: ${user['password'] ?? 'Unknown'}',
          style: pw.TextStyle(fontSize: 10),
        ),
      ],
    ),
  );
}

  Future<void> _viewLoginHistoriesPdf() async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Login Histories', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              ...loginHistories.map(
                (history) => pw.Text(
                  'User: ${history['user'] ?? 'Unknown'}, Address: ${history['address'] ?? 'Unknown'}, MAC: ${history['mac-address'] ?? 'Unknown'}',
                ),
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  Map<String, List<Map<String, String>>> _groupUsersByUptimeLimit(List<Map<String, String>> users) {
    final Map<String, List<Map<String, String>>> groupedUsers = {};

    for (var user in users) {
      final uptimeLimit = user['limit-uptime'] ?? 'No Limit';
      if (!groupedUsers.containsKey(uptimeLimit)) {
        groupedUsers[uptimeLimit] = [];
      }
      groupedUsers[uptimeLimit]!.add(user);
    }

    return groupedUsers;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Documents'),
        backgroundColor: Colors.redAccent,
      ),
      body: ListView(
        children: [
          ListTile(
            title: Text('Hotspot Users'),
            subtitle: Text('View a PDF list of all hotspot users grouped by uptime limit'),
            trailing: Icon(Icons.picture_as_pdf),
            onTap: _viewHotspotUsersPdf,
          ),
          ListTile(
            title: Text('Login Histories'),
            subtitle: Text('View a PDF showing recent login histories'),
            trailing: Icon(Icons.picture_as_pdf),
            onTap: _viewLoginHistoriesPdf,
          ),
          // Add more PDF viewing options here
        ],
      ),
    );
  }
}
