import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:omni_core_ui/omni_core_ui.dart';

/// Client for the Omni Node's LPE API (Omni-Daemon Admin/docs/LPE_API.md,
/// daemon 8.25+). Reads are plain GETs; the profile write is a person-signed
/// event, exactly the envelope the daemon verifies:
///
///   {action: lpe_profile, author_pubkey, previous_hash, ts (int ms),
///    payload: {schema: 1, handle, avatar, cosmetics, ambient_activity},
///    signature} — signed over the canonical JSON (Omni-Core-UI matches the
///    daemon byte for byte).
///
/// Two honest skeleton limits:
/// - The daemon's profile payload schema is strict and has NO sign field yet,
///   so the creator's sign stays a phone-local choice for now (the same
///   fallback Plaza-Brawler already uses). Carrying the sign in the profile
///   needs a small daemon schema extension, tracked in the README.
/// - previous_hash chains from the stored profile's event_id when one exists,
///   else the zero hash; profiles are latest-wins per author on the node.
class LpeApi {
  final String host;
  final int ipcPort;
  final int telemetryPort;
  final String token;

  const LpeApi({
    this.host = '127.0.0.1',
    this.ipcPort = 5000,
    this.telemetryPort = 9100,
    this.token = '',
  });

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  Uri _uri(int port, String path, [Map<String, String>? query]) => Uri(
        scheme: 'http',
        host: host,
        port: port,
        path: path,
        queryParameters: query,
      );

  /// Node health via the telemetry port, like OmniHubClient's check.
  Future<bool> nodeHealthy() async {
    try {
      final res = await http
          .get(_uri(telemetryPort, '/api/v1/telemetry/node-health'))
          .timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// The stored profile for [pubkey], or null (no node, no profile, refused).
  Future<Map<String, dynamic>?> getProfile(String pubkey) async {
    try {
      final res = await http
          .get(
            _uri(ipcPort, '/api/lpe/profile',
                {'pubkey': pubkey, 'viewer': pubkey}),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is! Map<String, dynamic>) return null;
      final p = body['profile'];
      return p is Map<String, dynamic> ? p : null;
    } catch (_) {
      return null;
    }
  }

  /// Signs and posts a profile for [identity]. [previousEventId] is the stored
  /// profile's event_id when updating, null on first creation.
  /// Returns (ok, message) — the message is what the node answered, verbatim
  /// enough to debug a refusal (400 schema, 401 signature, 429 rate limit).
  Future<(bool, String)> postProfile({
    required StargateIdentity identity,
    required String handle,
    required String avatar,
    required List<String> cosmetics,
    required String ambientActivity,
    String? previousEventId,
  }) async {
    final payload = <String, dynamic>{
      'schema': 1,
      'handle': handle,
      'avatar': avatar,
      'cosmetics': cosmetics,
      'ambient_activity': ambientActivity,
    };
    final unsigned = <String, dynamic>{
      'action': 'lpe_profile',
      'author_pubkey': identity.pubkeyHex,
      'previous_hash': previousEventId ?? '0x${'0' * 64}',
      'ts': DateTime.now().millisecondsSinceEpoch,
      'payload': payload,
    };
    try {
      final signature = await identity.sign(unsigned);
      final body = {...unsigned, 'signature': signature};
      final res = await http
          .post(
            _uri(ipcPort, '/api/lpe/profile'),
            headers: {..._headers, 'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 8));
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      final status = decoded is Map ? '${decoded['status'] ?? ''}' : '';
      if (res.statusCode == 200 && status == 'SUCCESS') {
        return (true, 'Saved to your Omni Node.');
      }
      return (false, 'Node answered ${res.statusCode}: $status');
    } catch (e) {
      return (false, 'Could not reach the node: $e');
    }
  }
}
