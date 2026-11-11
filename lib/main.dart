// LPE — the Live Persona Engine app. Skeleton (v0.1).
//
// Your identity home for The Omniverse: today it creates and edits the LPE
// profile (your Halo) that the rest of the ecosystem already reads —
// Plaza-Brawler builds your fighter from this exact profile
// (GET /api/lpe/profile on your Omni Node), KickBack shows it as your persona.
// Later this home becomes the personal space injected into the Omni-Hub.
//
// The profile lives on the user's own Omni Node (daemon 8.25+), written as a
// person-signed event (POST /api/lpe/profile). This app holds no server and
// phones nothing home: it talks to 127.0.0.1, or to the hub the user names.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:omni_core_ui/omni_core_ui.dart';

import 'halo_stage.dart';
import 'lpe_api.dart';
import 'lpe_identity.dart';

const List<(String, String, String)> kSigns = [
  ('aries', 'Aries', '♈'),
  ('taurus', 'Taurus', '♉'),
  ('gemini', 'Gemini', '♊'),
  ('cancer', 'Cancer', '♋'),
  ('leo', 'Leo', '♌'),
  ('virgo', 'Virgo', '♍'),
  ('libra', 'Libra', '♎'),
  ('scorpio', 'Scorpio', '♏'),
  ('sagittarius', 'Sagittarius', '♐'),
  ('capricorn', 'Capricorn', '♑'),
  ('aquarius', 'Aquarius', '♒'),
  ('pisces', 'Pisces', '♓'),
  ('ophiuchus', 'Ophiuchus', '⛎'),
];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  StargateIdentity.seedStore = SecureStorageSeedStore();
  runApp(const LpeApp());
}

/// Slice A: the whole app lives inside the person's color. The seed starts
/// at the default and [_LpeHomeState] lifts the stored favorite color into
/// it on load; picking a swatch re-themes the app with a wash (AnimatedTheme
/// in the home scaffold).
class LpeApp extends StatefulWidget {
  const LpeApp({super.key});

  @override
  State<LpeApp> createState() => _LpeAppState();
}

class _LpeAppState extends State<LpeApp> {
  Color _seed = kDefaultHaloColor;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LPE',
      theme: haloTheme(_seed),
      home: LpeHome(
        onSeedChanged: (c) {
          if (c != _seed) setState(() => _seed = c);
        },
      ),
    );
  }
}

class LpeHome extends StatefulWidget {
  const LpeHome({super.key, required this.onSeedChanged});

  /// Lifts the current favorite color up to the app so the Material theme
  /// itself follows the stage (Slice A theme wash).
  final ValueChanged<Color> onSeedChanged;

  @override
  State<LpeHome> createState() => _LpeHomeState();
}

class _LpeHomeState extends State<LpeHome> {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  int _tab = 0;
  StargateIdentity? _identity;
  Map<String, dynamic>? _profile;
  String _status = 'Loading your identity…';
  bool _busy = false;

  String _host = '127.0.0.1';
  String _sign = 'aries';
  Color _favorite = kDefaultHaloColor;

  final _tokenCtrl = TextEditingController();
  final _handleCtrl = TextEditingController();
  final _ambientCtrl = TextEditingController();

  LpeApi get _api => LpeApi(host: _host, token: _tokenCtrl.text.trim());

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _handleCtrl.dispose();
    _ambientCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final host = await _storage.read(key: 'lpe_node_host');
    final token = await _storage.read(key: 'lpe_node_token');
    final sign = await _storage.read(key: 'lpe_sign');
    final fav = await _storage.read(key: kHaloColorKey);
    if (fav != null) {
      final v = int.tryParse(fav);
      if (v != null) {
        _favorite = Color(v);
        widget.onSeedChanged(_favorite);
      }
    }
    if (host != null && host.isNotEmpty) _host = host;
    if (token != null) _tokenCtrl.text = token;
    if (sign != null && kSigns.any((s) => s.$1 == sign)) _sign = sign;
    final identity = await StargateIdentity.load();
    if (!mounted) return;
    setState(() {
      _identity = identity;
      _status = 'Identity loaded. Checking your node…';
    });
    await _refreshProfile();
  }

  Future<void> _refreshProfile() async {
    final identity = _identity;
    if (identity == null) return;
    final profile = await _api.getProfile(identity.pubkeyHex);
    if (!mounted) return;
    setState(() {
      _profile = profile;
      if (profile != null) {
        _handleCtrl.text = '${profile['handle'] ?? ''}';
        _ambientCtrl.text = '${profile['ambient_activity'] ?? ''}';
        _status = 'Profile loaded from your node.';
      } else {
        _status = 'No profile on this node yet — create yours.';
      }
    });
  }

  Future<void> _saveSettings() async {
    await _storage.write(key: 'lpe_node_host', value: _host);
    await _storage.write(key: 'lpe_node_token', value: _tokenCtrl.text.trim());
    if (!mounted) return;
    setState(() => _status = 'Node settings saved.');
  }

  Future<void> _testNode() async {
    setState(() {
      _busy = true;
      _status = 'Pinging your node…';
    });
    final probe = await _api.probeNode();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = switch (probe) {
        NodeProbe.ok => 'Node is answering on $_host.',
        NodeProbe.unauthorized =>
          'Node is running on $_host but rejected the token — paste the local token from Omni Node, Save settings, then test again.',
        NodeProbe.unreachable =>
          'Node not answering — is Omni Node running on $_host?',
      };
    });
    if (probe == NodeProbe.ok) await _refreshProfile();
  }

  /// Copies this identity's transfer code to the clipboard, after a warning:
  /// the code IS the identity, so it only moves on a deliberate confirmation.
  /// Another Omni app on this phone (Plaza-Brawler's Settings) imports it to
  /// act as the same person — Android gives apps no shared storage to do it
  /// automatically.
  Future<void> _copyTransferCode() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Copy your identity transfer code?'),
        content: const Text(
            'This code is your private identity key in disguise — anyone who '
            'has it can sign as you. Only paste it into your own Omni apps '
            'on this phone (Plaza-Brawler: Settings > Identity transfer), '
            'and never send it to anyone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Copy code'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final seed = await SecureStorageSeedStore().read();
    if (!mounted) return;
    if (seed == null) {
      setState(() => _status = 'No identity seed found to export.');
      return;
    }
    await Clipboard.setData(
        ClipboardData(text: identityTransferCode(seed)));
    setState(() => _status =
        'Transfer code copied — paste it into Plaza-Brawler > Settings > Identity transfer.');
  }

  /// Imports a transfer code (from this app's own export on another install,
  /// or any Omni app) and adopts that identity as this install's own. This is
  /// LPE's recovery path: if a reinstall ever wipes this app's seed, the code
  /// the person already carried into their other apps restores the SAME
  /// identity here — the profile on the node never notices. Replaces this
  /// install's current key, so it demands the same deliberate confirmation as
  /// exporting. Takes effect on restart: StargateIdentity caches its load.
  Future<void> _importTransferCode() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import an identity transfer code?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'This REPLACES the identity this install signs with. Any '
                'profile this install\'s current key made stays on the node '
                'under that old key. Paste only your own code.'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'Transfer code',
                hintText: 'omni-seed-v1.…',
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Import identity'),
          ),
        ],
      ),
    );
    if (code == null || !mounted) return;
    final seed = seedFromIdentityTransferCode(code);
    if (seed == null) {
      setState(() => _status =
          'That code did not check out — wrong format or a damaged paste. Nothing was changed.');
      return;
    }
    await SecureStorageSeedStore().write(seed);
    if (!mounted) return;
    setState(() => _status =
        'Identity imported. Restart LPE to sign as the imported identity.');
  }

  Future<void> _saveProfile() async {
    final identity = _identity;
    final handle = _handleCtrl.text.trim();
    if (identity == null) return;
    if (handle.isEmpty) {
      setState(() => _status = 'Pick a handle first.');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Signing and saving your profile…';
    });
    await _storage.write(key: 'lpe_sign', value: _sign);
    final (ok, message) = await _api.postProfile(
      identity: identity,
      handle: handle,
      avatar: 'default_m_01',
      cosmetics: const [],
      ambientActivity: _ambientCtrl.text.trim(),
      previousEventId: _profile?['event_id'] as String?,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = message;
    });
    if (ok) await _refreshProfile();
  }

  /// Slice A: the swatch tap. Updates the stage, the whole app theme, and
  /// local storage in one go. (Later this color also rides the private
  /// profile layer — for now it never leaves this phone.)
  Future<void> _pickColor(Color c) async {
    setState(() => _favorite = c);
    widget.onSeedChanged(c);
    await _storage.write(key: kHaloColorKey, value: '${c.value}');
  }

  String get _stageHandle {
    final display = _profile?['handle_display'] as String?;
    if (display != null && display.isNotEmpty) return display;
    final typed = _handleCtrl.text.trim();
    if (typed.isNotEmpty) return '@$typed';
    return 'Your Halo';
  }

  Color get _auraColor {
    final aura = _profile?['aura'];
    final hex = aura is Map ? '${aura['aura_color_hex'] ?? ''}' : '';
    if (hex.length == 7 && hex.startsWith('#')) {
      final v = int.tryParse(hex.substring(1), radix: 16);
      if (v != null) return Color(0xFF000000 | v);
    }
    return const Color(0xFF3A86EF);
  }

  (String, String, String) get _signData =>
      kSigns.firstWhere((s) => s.$1 == _sign, orElse: () => kSigns.first);

  @override
  Widget build(BuildContext context) {
    final pages = [_homePage(), _creatorPage(), _connectPage()];
    return AnimatedTheme(
      data: haloTheme(_favorite),
      duration: const Duration(milliseconds: 600),
      child: Scaffold(
      appBar: AppBar(title: const Text('LPE — your Halo')),
      body: pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.auto_fix_high), label: 'Creator'),
          NavigationDestination(icon: Icon(Icons.hub), label: 'Node'),
        ],
      ),
      ),
    );
  }

  Widget _statusLine() => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(_status, style: Theme.of(context).textTheme.bodySmall),
      );

  Widget _homePage() {
    final identity = _identity;
    final profile = _profile;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _statusLine(),
        HaloStage(
          seed: _favorite,
          handle: _stageHandle,
          signName: _signData.$2,
          signGlyph: _signData.$3,
          onColorPicked: _pickColor,
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _auraColor,
              child: Text(_signData.$3,
                  style: const TextStyle(color: Colors.white)),
            ),
            title: Text(profile?['handle_display'] as String? ??
                (identity == null ? '…' : 'No handle yet')),
            subtitle: Text(identity == null
                ? 'Loading identity…'
                : 'Identity ${identity.shortId} · ${profile?['aura'] is Map ? (profile!['aura'] as Map)['tier'] ?? '' : 'no profile'}'),
          ),
        ),
        const SizedBox(height: 12),
        if (profile == null)
          const Text(
              'You have no Halo on this node yet. Open the Creator tab, pick a handle and a sign, and save — Plaza-Brawler will offer your own character as your fighter.')
        else
          Text(
              'XP ${profile['xp'] ?? 0} · Plaza credits ${profile['plaza_credits'] ?? 0}\n'
              'Your fighter in Plaza-Brawler is built from this profile: your handle, your aura, stats from $_sign.'),
        const SizedBox(height: 16),
        FilledButton.tonal(
          onPressed: _busy ? null : _refreshProfile,
          child: const Text('Refresh from node'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _busy ? null : _copyTransferCode,
          child: const Text('Copy identity transfer code'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _busy ? null : _importTransferCode,
          child: const Text('Import identity transfer code'),
        ),
        const SizedBox(height: 6),
        const Text(
          'Carries this identity into your other Omni apps on this phone — '
          'Plaza-Brawler imports it in Settings, then fights as this Halo.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 6),
        const Text(
          'Import restores an identity here — the recovery path if a reinstall '
          'ever wipes this app and you hold the code in another app.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }

  Widget _creatorPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _statusLine(),
        HaloStage(
          seed: _favorite,
          handle: _stageHandle,
          signName: _signData.$2,
          signGlyph: _signData.$3,
          onColorPicked: _pickColor,
        ),
        const SizedBox(height: 16),
        Center(
          child: CircleAvatar(
            radius: 44,
            backgroundColor: _auraColor,
            child: Text(_signData.$3,
                style: const TextStyle(fontSize: 40, color: Colors.white)),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _handleCtrl,
          decoration: const InputDecoration(
            labelText: 'Handle',
            hintText: 'e.g. kiro_b',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _sign,
          decoration: const InputDecoration(
            labelText: 'Sign (your fighter\'s stats come from it)',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final s in kSigns)
              DropdownMenuItem(value: s.$1, child: Text('${s.$3}  ${s.$2}')),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _sign = v);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _ambientCtrl,
          decoration: const InputDecoration(
            labelText: 'Ambient activity (shown in the Plaza)',
            hintText: 'e.g. Training in Plaza Center',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Skeleton scope: one avatar (default_m_01), no cosmetics yet. '
          'Handles are lowercase — 3–20 chars of a–z, 0–9 or _ (the node '
          'adds the @ itself). Your sign is kept on this phone for now — '
          'the node profile schema gains a sign field in a later daemon '
          'update.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _saveProfile,
          child: const Text('Save my Halo to the node'),
        ),
      ],
    );
  }

  Widget _connectPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _statusLine(),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Node host',
            hintText: '127.0.0.1',
            border: OutlineInputBorder(),
          ),
          controller: TextEditingController(text: _host),
          onChanged: (v) => _host = v.trim().isEmpty ? '127.0.0.1' : v.trim(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _tokenCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Node token',
            hintText: 'Omni Node > Connect apps',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            FilledButton.tonal(
              onPressed: _busy ? null : _saveSettings,
              child: const Text('Save settings'),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: _busy ? null : _testNode,
              child: const Text('Test connection'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Loopback is open on your own device; the token matters for remote '
          'hub mode. Ports are the standard Omni ones: 5000 (API) and 9100 '
          '(telemetry).',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}
