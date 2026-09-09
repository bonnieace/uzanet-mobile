import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class UzanetApiException implements Exception {
  const UzanetApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class UzanetApi {
  UzanetApi({
    http.Client? client,
    FlutterSecureStorage? storage,
    String? baseUrl,
  })  : _client = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage(),
        baseUrl = (baseUrl ?? const String.fromEnvironment(
          'UZANET_API_BASE',
          defaultValue: 'https://api.uzanet.co.ke/api/v1',
        ))
            .replaceAll(RegExp(r'/+$'), '');

  static const _tokenKey = 'uzanet_access_token';

  final http.Client _client;
  final FlutterSecureStorage _storage;
  final String baseUrl;
  String? _token;

  bool get hasToken => _token != null && _token!.isNotEmpty;

  Future<void> restoreSession() async {
    _token = await _storage.read(key: _tokenKey);
  }

  Future<void> clearSession() async {
    _token = null;
    await _storage.delete(key: _tokenKey);
  }

  Future<void> login(String username, String password) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/auth/token'),
          headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {'username': username.trim(), 'password': password},
        )
        .timeout(const Duration(seconds: 30));

    final data = _decode(response);
    if (response.statusCode != 200) {
      throw UzanetApiException(
        _detail(data, 'Unable to sign in.'),
        statusCode: response.statusCode,
      );
    }

    final token = data['access_token'];
    if (token is! String || token.isEmpty) {
      throw const UzanetApiException('The server returned an invalid session.');
    }
    _token = token;
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<void> logout() async {
    if (hasToken) {
      try {
        await _client
            .post(Uri.parse('$baseUrl/auth/logout'), headers: _authHeaders())
            .timeout(const Duration(seconds: 15));
      } catch (_) {
        // Local logout must still complete when the network is unavailable.
      }
    }
    await clearSession();
  }

  Future<Map<String, dynamic>> me() => _getMap('/me');
  Future<List<Map<String, dynamic>>> routers() => _getList('/routers');

  Future<List<Map<String, dynamic>>> routerStatuses() async {
    final data = await _getMap('/routers/status');
    final rows = data['routers'];
    if (rows is! List) return const [];
    return rows.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<Map<String, dynamic>> routerStatus(String routerUid) =>
      _getMap('/routers/${Uri.encodeComponent(routerUid)}/status');

  Future<List<Map<String, dynamic>>> packages(String routerUid) =>
      _getList('/routers/${Uri.encodeComponent(routerUid)}/packages');

  Future<List<Map<String, dynamic>>> hotspotUsers(String routerUid) =>
      _getList('/routers/${Uri.encodeComponent(routerUid)}/hotspot-users');

  Future<List<Map<String, dynamic>>> pppoeUsers(String routerUid) =>
      _getList('/routers/${Uri.encodeComponent(routerUid)}/pppoe-users');

  Future<Map<String, dynamic>> activeUsers(String routerUid) =>
      _getMap('/routers/${Uri.encodeComponent(routerUid)}/active-users');

  Future<List<Map<String, dynamic>>> payments(String routerUid) =>
      _getList('/routers/${Uri.encodeComponent(routerUid)}/payments');

  Future<Map<String, dynamic>> traffic(String routerUid) =>
      _getMap('/routers/${Uri.encodeComponent(routerUid)}/traffic');

  Future<Map<String, dynamic>> beginRouterOnboarding({
    required String name,
    required String portalSlug,
    String paymentProvider = 'mpesa',
    bool replaceManagedTunnel = false,
  }) {
    return _postMap('/routers/onboarding', {
      'name': name.trim(),
      'portal_slug': portalSlug.trim().toLowerCase(),
      'payment_provider': paymentProvider,
      'replace_managed_tunnel': replaceManagedTunnel,
    });
  }

  Future<Map<String, dynamic>> _getMap(String path) async {
    final response = await _client
        .get(Uri.parse('$baseUrl$path'), headers: _authHeaders())
        .timeout(const Duration(seconds: 35));
    final data = _decode(response);
    _throwIfUnauthorized(response, data);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw UzanetApiException(
        _detail(data, 'Request failed.'),
        statusCode: response.statusCode,
      );
    }
    return data;
  }

  Future<List<Map<String, dynamic>>> _getList(String path) async {
    final response = await _client
        .get(Uri.parse('$baseUrl$path'), headers: _authHeaders())
        .timeout(const Duration(seconds: 35));
    final decoded = _decodeAny(response);
    _throwIfUnauthorized(response, decoded);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final map = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      throw UzanetApiException(
        _detail(map, 'Request failed.'),
        statusCode: response.statusCode,
      );
    }
    if (decoded is! List) {
      throw const UzanetApiException('The server returned an invalid list response.');
    }
    return decoded
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<Map<String, dynamic>> _postMap(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl$path'),
          headers: _authHeaders(json: true),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 45));
    final data = _decode(response);
    _throwIfUnauthorized(response, data);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw UzanetApiException(
        _detail(data, 'Request failed.'),
        statusCode: response.statusCode,
      );
    }
    return data;
  }

  Map<String, String> _authHeaders({bool json = false}) {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw const UzanetApiException('Sign in to continue.', statusCode: 401);
    }
    return {
      'Authorization': 'Bearer $token',
      if (json) 'Content-Type': 'application/json',
    };
  }

  void _throwIfUnauthorized(http.Response response, Object? data) {
    if (response.statusCode != 401) return;
    _token = null;
    _storage.delete(key: _tokenKey);
    final map = data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
    throw UzanetApiException(
      _detail(map, 'Your session has expired.'),
      statusCode: 401,
    );
  }

  Map<String, dynamic> _decode(http.Response response) {
    final decoded = _decodeAny(response);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return <String, dynamic>{};
  }

  Object? _decodeAny(http.Response response) {
    if (response.body.trim().isEmpty) return <String, dynamic>{};
    try {
      return jsonDecode(response.body);
    } catch (_) {
      return <String, dynamic>{
        'detail': 'The server returned an unreadable response.',
      };
    }
  }

  String _detail(Map<String, dynamic> data, String fallback) {
    final detail = data['detail'];
    if (detail is String && detail.trim().isNotEmpty) return detail.trim();
    if (detail is List && detail.isNotEmpty) {
      final first = detail.first;
      if (first is Map && first['msg'] is String) return first['msg'] as String;
    }
    return fallback;
  }

  void dispose() => _client.close();
}
