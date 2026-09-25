import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the session token lives: the Keychain on iOS, the Keystore on
/// Android, encrypted storage on the web.
abstract interface class TokenStore {
  Future<String?> read();

  /// Stores [token], or forgets it when null.
  Future<void> write(String? token);
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  static const _key = 'jobwalk.session';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() async {
    try {
      return await _storage.read(key: _key);
    } on Object {
      // A keychain that can't be read (e.g. restored to a new device) just
      // means signing in again.
      return null;
    }
  }

  @override
  Future<void> write(String? token) async {
    if (token == null) {
      await _storage.delete(key: _key);
    } else {
      await _storage.write(key: _key, value: token);
    }
  }
}

class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([this.token]);

  String? token;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String? token) async => this.token = token;
}
