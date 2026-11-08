import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:omni_core_ui/omni_core_ui.dart';

/// This install's Ed25519 seed store (flutter_secure_storage), the same pattern
/// KickBack uses: the seed lives in storage encrypted by the Android Keystore,
/// so the identity this app signs LPE profiles with is the install's own
/// StargateIdentity from Omni-Core-UI — the same identity the rest of the
/// Omniverse recognises.
///
/// Honest limits (same as KickBack's): signing happens in Dart memory because
/// Android Keystore has no Ed25519 signing on most devices, and the storage key
/// is not bound to a biometric prompt in this skeleton.
///
/// Migration: if an earlier build kept the seed in the shared omni_core SQLite
/// store, it is copied here on first read and the SQLite copy deleted, so the
/// public key (the person's identity) does not change.
class SecureStorageSeedStore implements IdentitySeedStore {
  static const String _key = 'lpe_ed25519_seed_v1';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  @override
  Future<List<int>?> read() async {
    final v = await _storage.read(key: _key);
    if (v != null) return base64Decode(v);

    final legacy = SqliteSeedStore();
    final old = await legacy.read();
    if (old == null) return null;
    await write(old);
    final check = await _storage.read(key: _key);
    if (check != null && check == base64Encode(old)) {
      await legacy.delete();
    }
    return old;
  }

  @override
  Future<void> write(List<int> seed) =>
      _storage.write(key: _key, value: base64Encode(seed));
}
