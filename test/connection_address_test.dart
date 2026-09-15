import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/connection_address.dart';
import 'package:wing/core/models/connection.dart';

void main() {
  test(
    'scheme ports, explicit ports and proxy paths have one source of truth',
    () {
      for (final (input, port, path, socket) in [
        (
          'https://hermes.example.com',
          443,
          '',
          'wss://hermes.example.com/api/ws',
        ),
        ('http://hermes.home:9119', 9119, '', 'ws://hermes.home:9119/api/ws'),
        ('http://hermes.home', 80, '', 'ws://hermes.home/api/ws'),
        (
          ' https://hermes.home:8443/agent/ ',
          8443,
          '/agent',
          'wss://hermes.home:8443/agent/api/ws',
        ),
        (
          'https://[fd00::12]:8443/agent',
          8443,
          '/agent',
          'wss://[fd00::12]:8443/agent/api/ws',
        ),
      ]) {
        final address = ConnectionAddress.parse(input);
        expect(address.port, port);
        expect(address.path, path);
        expect(address.socketUrl, socket);
        final normalized = SavedConnection.normalizeHostAndPort(
          address.url,
          address.port,
        );
        expect(normalized.host, address.host);
        expect(normalized.port, address.port);
        expect(normalized.useHttps, address.useHttps);
      }
    },
  );

  test('invalid or ambiguous addresses fail without exposing credentials', () {
    for (final input in [
      '',
      'hermes.home:9119',
      'ws://hermes.home',
      'https://',
      'https://hermes.home:0',
      'https://hermes.home:65536',
      'https://user:secret@hermes.home',
      'https://hermes.home?token=secret',
      'https://hermes.home/#secret',
      'https://hermes.home/api/ws',
      'https://hermes.home/v1/chat/completions',
      'http://localhost:9119',
      'http://127.0.0.2:9119',
      'http://[::1]:9119',
      'http://0.0.0.0:9119',
      'https://hermes .home',
    ]) {
      expect(
        () => ConnectionAddress.parse(input),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message.contains('secret'),
            'redacts secret',
            isFalse,
          ),
        ),
        reason: input,
      );
    }
  });
}
