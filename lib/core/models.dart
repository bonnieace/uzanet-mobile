import 'dart:convert';
import 'dart:io';

typedef RecordData = Map<String, dynamic>;

class AppFailure implements Exception {
  final String message;
  const AppFailure(this.message);
  @override
  String toString() => message;
}

class ApiFailure extends AppFailure {
  final int statusCode;
  const ApiFailure(this.statusCode, super.message);
}

bool isLocalAddress(String value) {
  final ip = InternetAddress.tryParse(value);
  if (ip == null || ip.type != InternetAddressType.IPv4) return false;
  final b = ip.rawAddress;
  return b[0] == 10 ||
      (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
      (b[0] == 192 && b[1] == 168);
}

class LocalRouter {
  final String name, address, username, password;
  final int port;
  final bool tls;
  const LocalRouter({
    required this.name,
    required this.address,
    required this.username,
    required this.password,
    required this.port,
    required this.tls,
  });
  void validate() {
    if (name.trim().isEmpty ||
        username.trim().isEmpty ||
        password.isEmpty ||
        !isLocalAddress(address) ||
        port < 1 ||
        port > 65535) {
      throw const AppFailure(
        'Enter a name, private IPv4 address, valid port and router credentials.',
      );
    }
  }

  String encode() => jsonEncode({
    'name': name,
    'address': address,
    'username': username,
    'password': password,
    'port': port,
    'tls': tls,
  });
  factory LocalRouter.decode(String value) {
    final m = jsonDecode(value) as RecordData;
    final router = LocalRouter(
      name: m['name'],
      address: m['address'],
      username: m['username'],
      password: m['password'],
      port: m['port'],
      tls: m['tls'],
    );
    router.validate();
    return router;
  }
}

int routerDuration(String? value) {
  if (value == null || value.isEmpty) return 0;
  if (RegExp(r'^\d+:\d{2}:\d{2}$').hasMatch(value)) {
    final p = value.split(':').map(int.parse).toList();
    return p[0] * 3600 + p[1] * 60 + p[2];
  }
  var seconds = 0;
  for (final m in RegExp(r'(\d+)([wdhms])').allMatches(value)) {
    seconds +=
        int.parse(m[1]!) *
        const {'w': 604800, 'd': 86400, 'h': 3600, 'm': 60, 's': 1}[m[2]]!;
  }
  return seconds;
}

String usageState(RecordData user) {
  final used = routerDuration(user['uptime']);
  final limit = routerDuration(user['limit-uptime']);
  if (limit > 0 && used >= limit) return 'Expired';
  return used > 0 ? 'Used' : 'Unused';
}
