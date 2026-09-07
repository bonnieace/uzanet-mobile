import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'models.dart';
import 'vault.dart';

abstract interface class ApiTransport {
  Future<(int, dynamic)> send(
    String method,
    Uri url,
    Map<String, String> headers,
    String? body,
  );
}

class HttpTransport implements ApiTransport {
  @override
  Future<(int, dynamic)> send(
    String method,
    Uri url,
    Map<String, String> headers,
    String? body,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    Future<(int, dynamic)> request() async {
      final req = await client.openUrl(method, url);
      req.followRedirects = false;
      headers.forEach(req.headers.set);
      if (body != null) req.write(body);
      final response = await req.close();
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length > 8 * 1024 * 1024) {
          throw const AppFailure('Server response is too large.');
        }
      }
      final text = utf8.decode(bytes);
      return (response.statusCode, text.isEmpty ? null : jsonDecode(text));
    }

    try {
      return await request().timeout(const Duration(seconds: 40));
    } finally {
      client.close(force: true);
    }
  }
}

class BackendApi extends ChangeNotifier {
  final Vault vault;
  final ApiTransport transport;
  final Uri base;
  String? _token;
  DateTime? _expires;
  RecordData? user;
  String? authMessage;
  int generation = 0;
  int sessionSerial = 0;
  Timer? _expiryTimer;
  bool _authBusy = false;
  BackendApi(this.vault, {ApiTransport? transport, String? baseUrl})
    : transport = transport ?? HttpTransport(),
      base = Uri.parse(
        baseUrl ??
            const String.fromEnvironment(
              'UZANET_API_URL',
              defaultValue: 'https://api.uzanet.co.ke/api/v1/',
            ),
      ) {
    if (base.scheme != 'https' ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        !base.path.endsWith('/api/v1/')) {
      throw const AppFailure(
        'Backend must be an HTTPS URL ending in /api/v1/.',
      );
    }
  }
  bool get signedIn =>
      user != null && _token != null && _expires!.isAfter(DateTime.now());
  Future<void> restore() async {
    final saved = await vault.read('operator_session');
    if (saved == null) return;
    try {
      final m = jsonDecode(saved);
      if (m['origin'] != base.toString()) {
        await clear();
        return;
      }
      _token = m['token'];
      _expires = DateTime.parse(m['expires']);
      if (!_expires!.isAfter(DateTime.now())) {
        await clear();
        return;
      }
      final epoch = generation;
      final me = await call('GET', 'me');
      if (epoch != generation) return;
      _acceptUser(me);
      _scheduleExpiry();
      sessionSerial++;
      notifyListeners();
    } catch (_) {
      await clear();
    }
  }

  void _acceptUser(dynamic me) {
    if (me is! RecordData || !['isp', 'superadmin'].contains(me['role'])) {
      throw const AppFailure('An operator account is required.');
    }
    user = me;
  }

  Future<void> login(String username, String password) async {
    if (_authBusy) throw const AppFailure('Sign-in is already in progress.');
    _authBusy = true;
    authMessage = null;
    try {
      await clear();
      final result = await call(
        'POST',
        'auth/token',
        authenticated: false,
        form: {
          'username': username.trim(),
          'password': password,
          'grant_type': 'password',
        },
      );
      _token = result['access_token'];
      _expires = DateTime.now().add(
        Duration(seconds: (result['expires_in'] as num).toInt()),
      );
      _acceptUser(await call('GET', 'me'));
      await vault.write(
        'operator_session',
        jsonEncode({
          'token': _token,
          'expires': _expires!.toIso8601String(),
          'origin': base.toString(),
        }),
      );
      _scheduleExpiry();
      sessionSerial++;
      notifyListeners();
    } catch (_) {
      await clear();
      rethrow;
    } finally {
      _authBusy = false;
    }
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    _expiryTimer = Timer(_expires!.difference(DateTime.now()), () {
      authMessage =
          'Session expired. Sign in again to continue remote management.';
      unawaited(
        clear().catchError((Object _) {
          authMessage =
              'Session expired. Saved credentials could not be removed; unlock your device and sign in again.';
        }),
      );
    });
  }

  Future<void> clear() async {
    generation++;
    _token = null;
    _expires = null;
    user = null;
    _expiryTimer?.cancel();
    notifyListeners();
    await vault.delete('operator_session');
  }

  Future<void> logout() async {
    try {
      await call('POST', 'auth/logout');
    } catch (_) {
      authMessage =
          'Signed out locally. Server revocation could not be confirmed; sign in again and retry logout when connected.';
      rethrow;
    } finally {
      await clear();
    }
  }

  Future<dynamic> call(
    String method,
    String path, {
    RecordData? body,
    Map<String, String>? form,
    bool authenticated = true,
    Map<String, String> paymentHeaders = const {},
  }) async {
    if (path.startsWith('/') ||
        path.contains('..') ||
        path.contains('?') ||
        path.contains('#') ||
        path.contains(':')) {
      throw const AppFailure('Invalid API path.');
    }
    if (authenticated &&
        (_token == null ||
            _expires == null ||
            !_expires!.isAfter(DateTime.now()))) {
      authMessage =
          'Session expired. Sign in again to continue remote management.';
      await clear();
      throw const AppFailure('Session expired. Sign in again.');
    }
    final epoch = generation;
    final headers = {
      'Accept': 'application/json',
      for (final e in paymentHeaders.entries)
        if (e.key == 'Idempotency-Key' || e.key == 'X-Payment-Token')
          e.key: e.value,
      if (authenticated) 'Authorization': 'Bearer $_token',
      if (form != null)
        'Content-Type': 'application/x-www-form-urlencoded'
      else if (body != null)
        'Content-Type': 'application/json',
    };
    (int, dynamic) response;
    try {
      response = await transport.send(
        method,
        base.resolve(path),
        headers,
        form != null
            ? Uri(queryParameters: form).query
            : body != null
            ? jsonEncode(body)
            : null,
      );
    } catch (_) {
      throw AppFailure(
        method == 'GET'
            ? 'Cannot reach UzaNet. Check your connection and retry.'
            : 'Request could not be confirmed. Refresh the list before trying again.',
      );
    }
    if (authenticated && epoch != generation) {
      throw const AppFailure('Session changed. Sign in again.');
    }
    final (status, data) = response;
    if (status == 401 && authenticated) {
      authMessage = 'Session expired or revoked. Sign in again.';
      await clear();
    }
    if (status < 200 || status >= 300) {
      final detail = data is Map ? data['detail'] : null;
      const safe = ['Account is disabled', 'Incorrect username or password'];
      throw ApiFailure(
        status,
        safe.contains(detail)
            ? detail as String
            : switch (status) {
                401 => 'Incorrect credentials or expired session.',
                403 => 'Your account cannot perform this action.',
                404 => 'This record is no longer available. Refresh the list.',
                409 =>
                  'This conflicts with an existing record. Refresh before retrying.',
                422 => 'Check the form fields and selected plan.',
                429 => 'Too many requests. Wait before trying again.',
                _ =>
                  'Server could not confirm the request. Refresh before retrying.',
              },
      );
    }
    return data;
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }
}
