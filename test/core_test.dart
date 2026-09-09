import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:uzanet/core/backend_api.dart';
import 'package:uzanet/core/checkout.dart';
import 'package:uzanet/core/models.dart';
import 'package:uzanet/core/router_api.dart';
import 'package:uzanet/core/vault.dart';
import 'package:uzanet/core/vouchers.dart';

class MemoryVault implements Vault {
  final values = <String, String>{};
  bool failWrites = false;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('storage unavailable');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class FakeRouter implements RouterApi {
  final calls = <List<String>>[];
  final Future<List<RecordData>> Function(List<String>)? handler;
  FakeRouter([this.handler]);
  @override
  Future<List<RecordData>> run(LocalRouter router, List<String> words) async {
    calls.add(words);
    return handler == null ? [] : handler!(words);
  }
}

class FakeTransport implements ApiTransport {
  final calls = <RecordData>[];
  Future<(int, dynamic)> Function(String, Uri, Map<String, String>, String?)?
  handler;
  @override
  Future<(int, dynamic)> send(
    String method,
    Uri url,
    Map<String, String> headers,
    String? body,
  ) async {
    calls.add({'method': method, 'url': url, 'headers': headers, 'body': body});
    if (url.path.endsWith('/auth/token')) {
      return (200, {'access_token': 'test-token', 'expires_in': 3600});
    }
    if (url.path.endsWith('/me')) {
      return (200, {'id': 1, 'username': 'operator', 'role': 'isp'});
    }
    return handler == null ? (200, []) : handler!(method, url, headers, body);
  }
}

const local = LocalRouter(
  name: 'Test router',
  address: '192.168.88.1',
  username: 'operator',
  password: 'test-password',
  port: 8729,
  tls: true,
);

void main() {
  group('Router protocol', () {
    test(
      'decodes every byte fragmented, unicode and equals in values',
      () async {
        final bytes =
            encodeSentence(['!re', '=name=Jirani café', '=value=a=b']) +
            encodeSentence(['!done']);
        final reader = RouterReader(Stream.fromIterable(bytes.map((x) => [x])));
        expect(await reader.reply(), [
          {'name': 'Jirani café', 'value': 'a=b'},
        ]);
        await reader.input.cancel();
      },
    );
    test('handles two-byte length across packets', () async {
      final text = List.filled(400, 'ü').join();
      final reader = RouterReader(
        Stream.fromIterable(
          (encodeSentence(['!re', '=name=$text']) + encodeSentence(['!done']))
              .map((b) => [b]),
        ),
      );
      expect((await reader.reply()).single['name'], text);
      await reader.input.cancel();
    });
    test('trap never exposes echoed password', () async {
      final reader = RouterReader(
        Stream.value(
          encodeSentence(['!trap', '=message=password=secret-value']),
        ),
      );
      try {
        await reader.reply();
        fail('expected error');
      } catch (e) {
        expect('$e', isNot(contains('secret-value')));
      }
      await reader.input.cancel();
    });
    test('disconnect mid-word fails instead of hanging', () async {
      final reader = RouterReader(Stream.value([5, 65, 66]));
      await expectLater(reader.reply(), throwsA(isA<AppFailure>()));
      await reader.input.cancel();
    });
    test('rejects legacy challenge login', () async {
      final reader = RouterReader(
        Stream.value(encodeSentence(['!done', '=ret=challenge'])),
      );
      await expectLater(reader.reply(), throwsA(isA<AppFailure>()));
      await reader.input.cancel();
    });
    test('only private IPv4 addresses accepted for local onboarding', () {
      for (final value in [
        '10.1.0.1',
        '172.16.0.1',
        '172.31.255.1',
        '192.168.1.1',
      ]) {
        expect(isLocalAddress(value), isTrue);
      }
      for (final value in [
        '8.8.8.8',
        '127.0.0.1',
        '169.254.169.254',
        '172.32.0.1',
        'https://example.com',
        '::1',
      ]) {
        expect(isLocalAddress(value), isFalse);
      }
    });
    test('unlimited users are not expired and weeks/clock durations work', () {
      expect(usageState({'uptime': '2d', 'limit-uptime': '0s'}), 'Used');
      expect(
        usageState({'uptime': '01:00:00', 'limit-uptime': '1h'}),
        'Expired',
      );
      expect(routerDuration('1w2d3h'), 788400);
    });
  });
  group('Voucher durability', () {
    test('failed persistence cannot provision any user', () async {
      final vault = MemoryVault()..failWrites = true;
      final router = FakeRouter();
      final batch = VoucherBatch(vault, router, local);
      await batch.load();
      await expectLater(batch.prepare(1, 'default', '1h'), throwsStateError);
      expect(router.calls, isEmpty);
      expect(batch.tickets, isEmpty);
    });
    test(
      'timeout after router commit recovers by read without duplicate add',
      () async {
        final vault = MemoryVault();
        RecordData? created;
        final router = FakeRouter((words) async {
          if (words.first.endsWith('/add')) {
            created = {
              for (final w in words.skip(1))
                w.substring(1, w.indexOf('=', 1)): w.substring(
                  w.indexOf('=', 1) + 1,
                ),
            };
            throw const AppFailure('timeout');
          }
          return [created!];
        });
        final batch = VoucherBatch(vault, router, local);
        await batch.load();
        await batch.prepare(1, 'café profile', '1h');
        await expectLater(batch.provision(), throwsA(isA<AppFailure>()));
        final recovered = VoucherBatch(vault, router, local);
        await recovered.load();
        await recovered.provision();
        expect(recovered.tickets.single['state'], 'confirmed');
        expect(
          router.calls.where((c) => c.first.endsWith('/add')),
          hasLength(1),
        );
      },
    );
    test('unconfirmed missing user is not automatically recreated', () async {
      final vault = MemoryVault();
      final router = FakeRouter();
      final batch = VoucherBatch(vault, router, local);
      await batch.load();
      await batch.prepare(1, 'default', '1h');
      batch.tickets.single['state'] = 'uncertain';
      await expectLater(batch.provision(), throwsA(isA<AppFailure>()));
      expect(router.calls.single.first, '/ip/hotspot/user/print');
    });
    test('double provision tap creates only one batch', () async {
      final gate = Completer<List<RecordData>>();
      final router = FakeRouter((_) => gate.future);
      final batch = VoucherBatch(MemoryVault(), router, local);
      await batch.load();
      await batch.prepare(1, 'default', '1h');
      final first = batch.provision();
      await batch.provision();
      gate.complete([]);
      await first;
      expect(router.calls, hasLength(1));
    });
  });
  group('Backend session', () {
    test('login uses OAuth form and /me, saves no account password', () async {
      final vault = MemoryVault();
      final transport = FakeTransport();
      final api = BackendApi(vault, transport: transport);
      addTearDown(api.dispose);
      await api.login(' operator ', 'p&ss=word');
      expect(transport.calls.first['body'], contains('password=p%26ss%3Dword'));
      expect((transport.calls[1]['url'] as Uri).path, '/api/v1/me');
      expect(vault.values.toString(), isNot(contains('p&ss=word')));
      expect(api.signedIn, isTrue);
    });
    test('401 clears remote session but preserves local router', () async {
      final vault = MemoryVault();
      await vault.write('local_router', local.encode());
      final transport = FakeTransport();
      final api = BackendApi(vault, transport: transport);
      addTearDown(api.dispose);
      await api.login('operator', 'password');
      transport.handler = (_, _, _, _) async => (401, null);
      await expectLater(api.call('GET', 'routers'), throwsA(isA<AppFailure>()));
      expect(api.signedIn, isFalse);
      expect(vault.values['local_router'], isNotNull);
      expect(vault.values['operator_session'], isNull);
    });
    test(
      'late response from old session cannot expose data or clear new session',
      () async {
        final transport = FakeTransport();
        final api = BackendApi(MemoryVault(), transport: transport);
        addTearDown(api.dispose);
        await api.login('operator', 'password');
        final gate = Completer<(int, dynamic)>();
        transport.handler = (_, _, _, _) => gate.future;
        final old = api.call('GET', 'routers');
        final expectation = expectLater(old, throwsA(isA<AppFailure>()));
        await api.login('operator', 'new-password');
        gate.complete((401, null));
        await expectation;
        expect(api.signedIn, isTrue);
      },
    );
    test('non-HTTPS backend is rejected', () {
      expect(
        () => BackendApi(
          MemoryVault(),
          baseUrl: 'http://api.example.com/api/v1/',
        ),
        throwsA(isA<AppFailure>()),
      );
    });
    test('logout failure still clears saved token', () async {
      final vault = MemoryVault();
      final transport = FakeTransport();
      final api = BackendApi(vault, transport: transport);
      addTearDown(api.dispose);
      await api.login('operator', 'password');
      transport.handler = (_, _, _, _) async =>
          throw TimeoutException('offline');
      await expectLater(api.logout(), throwsA(isA<AppFailure>()));
      expect(api.signedIn, isFalse);
      expect(vault.values['operator_session'], isNull);
    });
  });
  group('Payment recovery', () {
    test(
      'expired capability is reconciled through owned payment sessions',
      () async {
        final vault = MemoryVault();
        final transport = FakeTransport();
        final api = BackendApi(vault, transport: transport);
        addTearDown(api.dispose);
        await api.login('operator', 'password');
        final c = Checkout(
          api,
          'test-router',
          routerUid: 'a0f75827-7c94-4e9f-b7ab-6fb39a84a002',
        );
        await vault.write(
          c.key,
          jsonEncode({
            'payment_id': 'a0f75827-7c94-4e9f-b7ab-6fb39a84a001',
            'status_token': 'expired',
          }),
        );
        await c.load();
        transport.handler = (method, url, headers, body) async {
          if (url.path.contains('/public/')) return (403, null);
          expect(headers['Authorization'], 'Bearer test-token');
          return (
            200,
            [
              {
                'payment_id': 'a0f75827-7c94-4e9f-b7ab-6fb39a84a001',
                'status': 'provisioned',
              },
            ],
          );
        };
        await c.refresh();
        expect(c.status!['status'], 'provisioned');
        expect(api.signedIn, isTrue);
        await c.clear();
        expect(c.journal, isNull);
      },
    );
    test(
      'unconfirmed payment cannot be cleared for another purchase',
      () async {
        final api = BackendApi(MemoryVault(), transport: FakeTransport());
        addTearDown(api.dispose);
        final c = Checkout(api, 'test-router');
        c.journal = {'payment_id': 'existing'};
        await expectLater(c.clear(), throwsA(isA<AppFailure>()));
        expect(c.journal, isNotNull);
      },
    );
    test(
      'lost initiation response replays same body/key without operator token',
      () async {
        final vault = MemoryVault();
        final transport = FakeTransport();
        final api = BackendApi(vault, transport: transport);
        addTearDown(api.dispose);
        await api.login('operator', 'password');
        var attempts = 0;
        transport.handler = (method, url, headers, body) async {
          expect(headers.containsKey('Authorization'), isFalse);
          if (++attempts == 1) throw TimeoutException('lost response');
          return (
            202,
            {
              'payment_id': 'a0f75827-7c94-4e9f-b7ab-6fb39a84a001',
              'status_token': 'capability',
              'status': 'pending',
            },
          );
        };
        final checkout = Checkout(api, 'test-router');
        await checkout.load();
        await expectLater(
          checkout.start({'package_uid': 'plan', 'phone_number': '0712345678'}),
          throwsA(isA<AppFailure>()),
        );
        final recovered = Checkout(api, 'test-router');
        await recovered.load();
        await recovered.refresh();
        final posts = transport.calls
            .where((c) => (c['url'] as Uri).path.endsWith('/payments'))
            .toList();
        expect(posts, hasLength(2));
        expect(posts[0]['body'], posts[1]['body']);
        expect(posts[0]['headers'], posts[1]['headers']);
        expect(recovered.status!['status'], 'pending');
        expect(
          jsonDecode(vault.values[recovered.key]!)['status_token'],
          'capability',
        );
      },
    );
    test(
      'known payment uses capability status GET, never creates another',
      () async {
        final vault = MemoryVault();
        final transport = FakeTransport();
        final api = BackendApi(vault, transport: transport);
        addTearDown(api.dispose);
        await api.login('operator', 'password');
        final c = Checkout(api, 'test-router');
        await vault.write(
          c.key,
          jsonEncode({
            'payment_id': 'a0f75827-7c94-4e9f-b7ab-6fb39a84a001',
            'status_token': 'capability',
          }),
        );
        await c.load();
        transport.handler = (method, url, headers, body) async {
          expect(method, 'GET');
          expect(headers['X-Payment-Token'], 'capability');
          return (200, {'status': 'provisioned', 'account': 'test-pppoe'});
        };
        await c.refresh();
        expect(c.status!['account'], 'test-pppoe');
      },
    );
  });
}
