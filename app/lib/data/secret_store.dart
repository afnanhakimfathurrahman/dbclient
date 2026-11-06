import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Connection passwords in the OS secure store (Keychain, Keystore,
/// Windows Credential Locker, libsecret).
class SecretStore {
  SecretStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // The data protection keychain needs a signed app with a team
            // entitlement; downloaded builds are unsigned.
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );

  final FlutterSecureStorage _storage;

  String _key(String connectionId) => 'connection.$connectionId.password';

  Future<String?> readPassword(String connectionId) =>
      _storage.read(key: _key(connectionId));

  Future<void> writePassword(String connectionId, String password) =>
      _storage.write(key: _key(connectionId), value: password);

  Future<void> deletePassword(String connectionId) =>
      _storage.delete(key: _key(connectionId));
}
