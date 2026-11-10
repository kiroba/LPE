import 'dart:convert';

import 'package:crypto/crypto.dart';
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

/// An identity transfer code: this install's seed, encoded so the SAME person
/// can carry their Ed25519 identity into another Omni app on the same phone.
///
/// Why this exists: Android sandboxes every app's storage, so apps cannot
/// literally share a seed store — each app that must act as the person needs
/// the seed handed to it once. The code is the hand-off: LPE (the identity
/// home) shows it; the receiving app imports it into its own secure store.
///
/// Format: `omni-seed-v1.<base64 seed>.<check>` where <check> is the first 8
/// hex chars of sha256(seed) — enough to catch paste damage before anything
/// is overwritten. THE CODE IS THE IDENTITY: anyone holding it can sign as
/// the person. Show it only on a deliberate tap, never log or send it.
String identityTransferCode(List<int> seed) {
  if (seed.length != 32) {
    throw ArgumentError('Ed25519 seed must be 32 bytes');
  }
  final check = sha256.convert(seed).toString().substring(0, 8);
  return 'omni-seed-v1.${base64Encode(seed)}.$check';
}

/// Parses a transfer code produced by [identityTransferCode] in any Omni app.
/// Returns the 32-byte seed, or null for anything malformed — wrong prefix,
/// bad base64, wrong length, or a checksum mismatch (damaged paste).
List<int>? seedFromIdentityTransferCode(String code) {
  final parts = code.trim().split('.');
  if (parts.length != 3 || parts[0] != 'omni-seed-v1') return null;
  try {
    final seed = base64Decode(parts[1]);
    if (seed.length != 32) return null;
    if (sha256.convert(seed).toString().substring(0, 8) != parts[2]) {
      return null;
    }
    return seed;
  } catch (_) {
    return null;
  }
}
