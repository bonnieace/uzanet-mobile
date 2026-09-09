import 'dart:convert';
import 'dart:math';
import 'backend_api.dart';
import 'models.dart';

class Checkout {
  final BackendApi api;
  final String slug;
  final String owner;
  final String? routerUid;
  RecordData? journal;
  RecordData? status;
  bool busy = false;
  Checkout(this.api, this.slug, {this.routerUid})
    : owner = '${api.user?['id']}' {
    if (!RegExp(r'^[a-z0-9][a-z0-9-]{1,58}[a-z0-9]$').hasMatch(slug)) {
      throw const AppFailure('Invalid customer portal slug.');
    }
  }
  String get key => 'checkout:${api.base}:$owner:$slug';
  Future<void> load() async {
    final value = await api.vault.read(key);
    if (value != null) journal = RecordData.from(jsonDecode(value));
  }

  Future<void> _save() => api.vault.write(key, jsonEncode(journal));
  Future<void> start(RecordData body) async {
    if (busy || journal != null) {
      throw const AppFailure('Recover the existing payment first.');
    }
    final random = Random.secure();
    journal = {
      'idempotency': List.generate(
        24,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join(),
      'body': body,
      'created': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      await _save();
    } catch (_) {
      journal = null;
      rethrow;
    }
    await refresh();
  }

  Future<void> refresh() async {
    if (busy || journal == null) return;
    if (!api.signedIn || '${api.user?['id']}' != owner) {
      throw const AppFailure(
        'Sign in to the same operator account to recover this payment.',
      );
    }
    busy = true;
    try {
      final epoch = api.generation;
      final saved = journal!;
      RecordData result;
      if (saved['payment_id'] == null || saved['status_token'] == null) {
        result = RecordData.from(
          await api.call(
            'POST',
            'public/portals/$slug/payments',
            authenticated: false,
            body: RecordData.from(saved['body']),
            paymentHeaders: {'Idempotency-Key': saved['idempotency']},
          ),
        );
        // Persist the response capability even if the screen/session changed while in flight.
        journal = {
          ...saved,
          'payment_id': result['payment_id'],
          'status_token': result['status_token'],
        };
        await _save();
      } else {
        try {
          result = RecordData.from(
            await api.call(
              'GET',
              'public/payments/${saved['payment_id']}',
              authenticated: false,
              paymentHeaders: {'X-Payment-Token': saved['status_token']},
            ),
          );
        } on ApiFailure catch (error) {
          if (![401, 403].contains(error.statusCode) || routerUid == null) {
            rethrow;
          }
          final payments =
              await api.call('GET', 'routers/$routerUid/payment-sessions')
                  as List;
          final matches = payments.where(
            (row) => row['payment_id'] == saved['payment_id'],
          );
          if (matches.length != 1) rethrow;
          result = RecordData.from(matches.single);
          result['message'] =
              'Outcome verified using your operator account. Any original hotspot credential link may have expired.';
        }
      }
      if (epoch != api.generation) {
        throw const AppFailure(
          'Session changed. Recover the payment after signing in.',
        );
      }
      status = result;
    } finally {
      busy = false;
    }
  }

  Future<void> clear() async {
    if (busy) return;
    if (!['provisioned', 'failed'].contains(status?['status'])) {
      throw const AppFailure(
        'Verify the existing payment outcome before starting another purchase.',
      );
    }
    await api.vault.delete(key);
    journal = null;
    status = null;
  }
}
