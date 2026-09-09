import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'models.dart';

// RouterOS API framing. Buffer boundaries are unrelated to word boundaries.
List<int> encodeSentence(List<String> words) {
  final result = <int>[];
  for (final word in words) {
    final bytes = utf8.encode(word);
    final n = bytes.length;
    if (n < 0x80) {
      result.add(n);
    } else if (n < 0x4000) {
      result.addAll([(n >> 8) | 0x80, n & 255]);
    } else if (n < 0x200000) {
      result.addAll([(n >> 16) | 0xc0, (n >> 8) & 255, n & 255]);
    } else {
      throw const AppFailure('Router command is too large.');
    }
    result.addAll(bytes);
  }
  return [...result, 0];
}

class RouterReader {
  final StreamIterator<List<int>> input;
  List<int> _chunk = [];
  int _offset = 0;
  int _total = 0;
  RouterReader(Stream<List<int>> stream) : input = StreamIterator(stream);
  Future<int> _byte() async {
    if (++_total > 8 * 1024 * 1024) {
      throw const AppFailure('Router response is too large.');
    }
    while (_offset == _chunk.length) {
      if (!await input.moveNext()) {
        throw const AppFailure('Router disconnected. Refresh before retrying.');
      }
      _chunk = input.current;
      _offset = 0;
    }
    return _chunk[_offset++];
  }

  Future<List<String>> sentence() async {
    final words = <String>[];
    while (true) {
      final first = await _byte();
      int n, extra;
      if (first < 0x80) {
        n = first;
        extra = 0;
      } else if (first < 0xc0) {
        n = first & 0x3f;
        extra = 1;
      } else if (first < 0xe0) {
        n = first & 0x1f;
        extra = 2;
      } else if (first < 0xf0) {
        n = first & 0x0f;
        extra = 3;
      } else if (first == 0xf0) {
        n = 0;
        extra = 4;
      } else {
        throw const AppFailure('Unsupported router response.');
      }
      for (var i = 0; i < extra; i++) {
        n = (n << 8) | await _byte();
      }
      if (n == 0) return words;
      if (n > 1024 * 1024 || words.length > 1024) {
        throw const AppFailure('Router response is too large.');
      }
      final bytes = <int>[];
      for (var i = 0; i < n; i++) {
        bytes.add(await _byte());
      }
      words.add(utf8.decode(bytes));
    }
  }

  Future<List<RecordData>> reply() async {
    final records = <RecordData>[];
    while (true) {
      final words = await sentence();
      if (words.isEmpty) continue;
      if (words.first == '!trap' || words.first == '!fatal') {
        // Router error text can echo a command containing a password.
        throw const AppFailure(
          'Router rejected the request. Check permissions, profile and input.',
        );
      }
      if (words.first == '!done') {
        if (words.any((w) => w.startsWith('=ret='))) {
          throw const AppFailure(
            'Use RouterOS 6.43 or newer for secure credential handling.',
          );
        }
        return records;
      }
      if (words.first != '!re' && words.first != '!empty') {
        throw const AppFailure('Unexpected router response.');
      }
      if (words.first == '!re') {
        final row = <String, dynamic>{};
        for (final word in words.skip(1)) {
          if (!word.startsWith('=')) continue;
          final split = word.indexOf('=', 1);
          if (split > 1) {
            row[word.substring(1, split)] = word.substring(split + 1);
          }
        }
        records.add(row);
      }
    }
  }
}

abstract interface class RouterApi {
  Future<List<RecordData>> run(LocalRouter router, List<String> words);
}

class SocketRouterApi implements RouterApi {
  final Duration timeout;
  const SocketRouterApi({this.timeout = const Duration(seconds: 20)});
  @override
  Future<List<RecordData>> run(LocalRouter router, List<String> words) async {
    router.validate();
    Socket? socket;
    RouterReader? reader;
    var closed = false;
    Future<List<RecordData>> operation() async {
      final connected = router.tls
          ? await SecureSocket.connect(
              router.address,
              router.port,
              timeout: timeout,
            )
          : await Socket.connect(router.address, router.port, timeout: timeout);
      if (closed) {
        connected.destroy();
        throw const AppFailure('Connection timed out.');
      }
      socket = connected;
      reader = RouterReader(connected);
      connected.add(
        encodeSentence([
          '/login',
          '=name=${router.username}',
          '=password=${router.password}',
        ]),
      );
      await reader!.reply();
      connected.add(encodeSentence(words));
      return reader!.reply();
    }

    try {
      return await operation().timeout(timeout);
    } on AppFailure {
      rethrow;
    } on TimeoutException {
      throw const AppFailure(
        'Router timed out. A change may have succeeded; refresh before retrying.',
      );
    } catch (_) {
      throw const AppFailure(
        'Cannot connect. Check Wi-Fi, router API service, credentials and TLS certificate.',
      );
    } finally {
      closed = true;
      socket?.destroy();
      await reader?.input.cancel();
    }
  }
}
