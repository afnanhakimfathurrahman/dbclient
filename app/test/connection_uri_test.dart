import 'package:db_client/drivers/connection_uri.dart';
import 'package:db_client/drivers/driver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('postgres with sslmode and encoded password', () {
    final p = parseConnectionUri(
      'postgresql://app:p%40ss@db.example.com:6543/shop?sslmode=require',
    );
    expect(p.engine, DatabaseEngine.postgres);
    expect(p.host, 'db.example.com');
    expect(p.port, 6543);
    expect(p.database, 'shop');
    expect(p.username, 'app');
    expect(p.password, 'p@ss');
    expect(p.tlsMode, TlsMode.require);
  });

  test('mongodb+srv sets srv and TLS, keeps auth source and options', () {
    final p = parseConnectionUri(
      'mongodb+srv://me:secret@cluster0.abc.mongodb.net/app'
      '?retryWrites=true&w=majority&authSource=admin',
    );
    expect(p.engine, DatabaseEngine.mongodb);
    expect(p.host, 'cluster0.abc.mongodb.net');
    expect(p.port, isNull);
    expect(p.database, 'app');
    expect(p.tlsMode, TlsMode.verifyFull);
    expect(p.options, {
      'srv': 'true',
      'authSource': 'admin',
      'params': 'retryWrites=true&w=majority',
    });
  });

  test('mongodb replica set keeps the host list', () {
    final p = parseConnectionUri(
      'mongodb://h1:27017,h2:27018/?replicaSet=rs0&tls=false',
    );
    expect(p.host, 'h1:27017,h2:27018');
    expect(p.port, isNull);
    expect(p.database, isNull);
    expect(p.tlsMode, TlsMode.disable);
    expect(p.options['params'], 'replicaSet=rs0');
  });

  test('rediss with password only and a database index', () {
    final p = parseConnectionUri('rediss://:hunter2@cache.local:6380/3');
    expect(p.engine, DatabaseEngine.redis);
    expect(p.username, isNull);
    expect(p.password, 'hunter2');
    expect(p.port, 6380);
    expect(p.database, '3');
    expect(p.tlsMode, TlsMode.verifyFull);
  });

  test('clickhouse with secure flag', () {
    final p = parseConnectionUri(
      'clickhouse://default@ch.local:8443/logs?secure=true',
    );
    expect(p.engine, DatabaseEngine.clickhouse);
    expect(p.database, 'logs');
    expect(p.tlsMode, TlsMode.verifyFull);
  });

  test('errors are readable', () {
    expect(
      () => parseConnectionUri('mysql://x@y/z'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Unsupported scheme'),
        ),
      ),
    );
    expect(() => parseConnectionUri('redis://host/abc'), throwsFormatException);
    expect(() => parseConnectionUri('not a uri'), throwsFormatException);
  });
}
