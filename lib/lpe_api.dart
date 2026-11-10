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
        // The Android node runs its daemon with the local token required
        // (daemon v8.19.0): loopback callers must send it as
        // X-Omni-Local-Token; the daemon also accepts it as a Bearer token.
        if (token.isNotEmpty) 'X-Omni-Local-Token': token,
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
  /// The phone node requires the local token on :9100 too (the daemon's
  /// remote_gate covers both servers), so the probe sends it.
  Future<bool> nodeHealthy() async => await probeNode() == NodeProbe.ok;

  /// Three honest answers, not one misleading one: a node that answers 401
  /// is RUNNING — it is the token it is rejecting, and the UI must say so.
  Future<NodeProbe> probeNode() async {
    try {
      final res = await http
          .get(_uri(telemetryPort, '/api/v1/telemetry/node-health'),
              headers: _headers)
          .timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) return NodeProbe.ok;
      if (res.statusCode == 401 || res.statusCode == 403) {
        return NodeProbe.unauthorized;
      }
      return NodeProbe.unreachable;
    } catch (_) {
      return NodeProbe.unreachable;
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
      // Show the node's own reason, not just its status word: the daemon
      // answers refusals as {status: ERROR, message: "..."} and the message
      // is the actionable part (e.g. the handle rule the profile broke).
      final message = decoded is Map ? '${decoded['message'] ?? ''}' : '';
      return (
        false,
        message.isNotEmpty
            ? 'Node answered ${res.statusCode}: $message'
            : 'Node answered ${res.statusCode}: $status'
      );
    } catch (e) {
      return (false, 'Could not reach the node: $e');
    }
  }
}

/// Result of [LpeApi.probeNode]: the node answered, the node answered but
/// rejected the local token, or nothing is listening at all.
enum NodeProbe { ok, unauthorized, unreachable }
