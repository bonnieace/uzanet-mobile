import 'dart:convert';
import 'dart:math';
import 'models.dart';
import 'router_api.dart';
import 'vault.dart';

class VoucherBatch {
  final Vault vault;
  final RouterApi api;
  final LocalRouter router;
  List<RecordData> tickets = [];
  bool busy = false;
  bool loaded = false;
  VoucherBatch(this.vault, this.api, this.router);
  String get key =>
      'vouchers:${router.address}:${router.port}:${router.username}';
  Future<void> load() async {
    loaded = false;
    final value = await vault.read(key);
    if (value != null) {
      tickets = (jsonDecode(value) as List)
          .map((x) => RecordData.from(x))
          .toList();
    }
    loaded = true;
  }

  Future<void> _save() => vault.write(key, jsonEncode(tickets));
  Future<void> prepare(int count, String profile, String duration) async {
    if (!loaded || busy || tickets.isNotEmpty) {
      throw const AppFailure('Finish or clear the current batch first.');
    }
    if (count < 1 ||
        count > 50 ||
        profile.isEmpty ||
        !RegExp(r'^(\d+[wdhms])+$').hasMatch(duration) ||
        routerDuration(duration) <= 0) {
      throw const AppFailure(
        'Choose 1–50 tickets, a router profile and a positive duration such as 1h.',
      );
    }
    final rng = Random.secure();
    const alphabet = 'abcdefghjkmnpqrstuvwxyz23456789';
    String secret() =>
        List.generate(12, (_) => alphabet[rng.nextInt(alphabet.length)]).join();
    tickets = List.generate(
      count,
      (_) => <String, dynamic>{
        'name': 'uz${secret()}',
        'password': secret(),
        'profile': profile,
        'limit-uptime': duration,
        'state': 'planned',
      },
    );
    try {
      await _save();
    } catch (_) {
      tickets = [];
      rethrow;
    }
  }

  Future<void> provision() async {
    if (busy) return;
    busy = true;
    try {
      for (final ticket in tickets) {
        if (ticket['state'] == 'confirmed') continue;
        if (ticket['state'] == 'uncertain') {
          final found = await api.run(router, [
            '/ip/hotspot/user/print',
            '?name=${ticket['name']}',
          ]);
          if (found.isEmpty) {
            // An earlier request could still be finishing; never automatically replay it.
            throw const AppFailure(
              'An unconfirmed ticket was not found. Check the router before clearing this batch.',
            );
          }
          if (found.length != 1 ||
              found.single['password'] != ticket['password'] ||
              found.single['profile'] != ticket['profile'] ||
              routerDuration(found.single['limit-uptime']) !=
                  routerDuration(ticket['limit-uptime'])) {
            throw const AppFailure(
              'A ticket could not be verified. Check router permissions and the existing user.',
            );
          }
        } else {
          ticket['state'] = 'uncertain';
          await _save(); // Durable credentials and intent before touching the router.
          await api.run(router, [
            '/ip/hotspot/user/add',
            '=name=${ticket['name']}',
            '=password=${ticket['password']}',
            '=profile=${ticket['profile']}',
            '=limit-uptime=${ticket['limit-uptime']}',
            '=comment=UzaNet local voucher',
          ]);
        }
        ticket['state'] = 'confirmed';
        try {
          await _save();
        } catch (_) {
          ticket['state'] = 'uncertain';
          rethrow;
        }
      }
    } finally {
      busy = false;
    }
  }

  Future<void> clear() async {
    if (busy) throw const AppFailure('Wait for voucher creation to finish.');
    await vault.delete(key);
    tickets = [];
  }
}
