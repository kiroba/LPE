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
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:omni_core_ui/omni_core_ui.dart';

import 'halo_appearance.dart';
import 'halo_render.dart';
import 'halo_stage.dart';
import 'lpe_api.dart';
import 'lpe_identity.dart';
import 'lpe_qol.dart';

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

/// Cosmetics this build knows how to render, as (item id, label,
/// socket label). The ids are the pack item ids from the importer
/// design — the crown is the signed pack omnimod.base.crown-01's
/// head_socket_crown. The profile carries the ids in its cosmetics
/// list; the stage renders them from the id (see halo_stage.dart).
const List<(String, String, String)> kCosmeticCatalog = [
  ('head_socket_crown', 'Crown', 'Head socket'),
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

  StargateIdentity? _identity;

  /// Node tab plain-language state (QoL item 4): how the last probe
  /// went and when one last succeeded, mapped from the wiring's
  /// HubConnectionState by [_recordProbe].
  NodeReach _nodeReach = NodeReach.unknown;
  DateTime? _lastNodeOkAt;

  /// Tap-the-Halo speech (Item 0, Masters EX reference): whether the
  /// name tag + dialogue line is showing, and a sequence counter so a
  /// stale auto-hide timer never dismisses a newer line.
  bool _haloSpeaking = false;
  int _speechSeq = 0;

  /// The line the speech bubble is currently showing, set when the
  /// bubble opens (a tap speaks [_haloLine]; ambient speech speaks a
  /// rotated line from the pool — see [_ambientSpeak]).
  String _speechLine = '';

  /// Ambient speech (Masters refinement 1): a periodic timer that lets
  /// the Halo speak unprompted, the way Masters' lobby characters
  /// bubble-talk on their own. [_ambientTick] is the rotation step
  /// into the line pool; [_sheetOpen] suppresses ambient lines while
  /// any modal sheet is up.
  Timer? _ambientTimer;
  int _ambientTick = 0;
  bool _sheetOpen = false;

  /// The standard node wiring (Omni-Core-UI v0.1.4). L1 landed it; L2
  /// routes the node check through it (see [_testNode]). The profile
  /// endpoints stay LpeApi's (a dedicated person-signed contract, not the
  /// delegate append).
  OmniNodeWiring? wiring;
  final LocalEventStore _eventStore = LocalEventStore();

  /// (Re)builds the wiring from the CURRENT settings fields, so a probe
  /// never runs against a stale host/token: the hub is swapped in place
  /// when the wiring already exists (the KickBack stale-probe lesson —
  /// the app drives the wiring's freshness, the wiring does not guess).
  OmniNodeWiring _wireUp() {
    final t = _tokenCtrl.text.trim();
    final hub = OmniHubClient(host: _host, token: t.isEmpty ? null : t);
    final w = wiring;
    if (w == null) {
      return wiring =
          OmniNodeWiring(appContext: 'lpe', store: _eventStore, hub: hub);
    }
    w.hub = hub;
    return w;
  }

  Map<String, dynamic>? _profile;
  String _status = 'Loading your identity…';
  bool _busy = false;

  String _host = '127.0.0.1';
  String _sign = 'aries';
  Color _favorite = kDefaultHaloColor;
  List<String> _cosmetics = [];

  /// The Slice 2 look (skin / hair / clothing variants). Phone-local
  /// only: the daemon profile schema is strict and carries no
  /// appearance fields, so this never rides the profile payload — it
  /// persists beside the cosmetics fallback under its own storage key.
  HaloAppearance _appearance = HaloAppearance.defaultFor('male');

  final _tokenCtrl = TextEditingController();
  final _handleCtrl = TextEditingController();
  final _ambientCtrl = TextEditingController();

  LpeApi get _api => LpeApi(host: _host, token: _tokenCtrl.text.trim());

  @override
  void initState() {
    super.initState();
    _load();
    _ambientTimer = Timer.periodic(kAmbientSpeechInterval, (_) {
      _ambientSpeak();
    });
  }

  @override
  void dispose() {
    _ambientTimer?.cancel();
    _tokenCtrl.dispose();
    _handleCtrl.dispose();
    _ambientCtrl.dispose();
    super.dispose();
  }

  /// One ambient-speech beat. Gentle by design: it stays quiet unless
  /// the full-screen Halo is simply sitting there — never while a
  /// modal sheet is open, never over a line already showing, never
  /// before the identity has loaded, and never when the system asks
  /// for reduced motion (the same MediaQuery switch the stage's idle
  /// loop honours). The line itself comes from the honest pool in
  /// lpe_qol.dart — sign, node state, the person's own Plaza status,
  /// the crown if worn.
  void _ambientSpeak() {
    if (!mounted || _sheetOpen || _haloSpeaking || _identity == null) {
      return;
    }
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return;
    final lines = haloAmbientLines(
      signName: _signData.$2,
      nodeBit: haloNodeBit(reach: _nodeReach, isLoopback: _isLoopback),
      ambientActivity: _ambientCtrl.text,
      crownEquipped: _cosmetics.contains('head_socket_crown'),
    );
    final line = pickAmbientLine(lines, _ambientTick++);
    if (line.isEmpty) return;
    _showSpeech(line);
  }

  Future<void> _load() async {
    final host = await _storage.read(key: 'lpe_node_host');
    final token = await _storage.read(key: 'lpe_node_token');
    final sign = await _storage.read(key: 'lpe_sign');
    final fav = await _storage.read(key: kHaloColorKey);
    final cos = await _storage.read(key: 'lpe_cosmetics');
    if (cos != null && cos.isNotEmpty) {
      _cosmetics = cos.split(',').where((s) => s.isNotEmpty).toList();
    }
    final app = await _storage.read(key: 'lpe_appearance');
    if (app != null && app.isNotEmpty) {
      _appearance = HaloAppearance.decode(app);
    }
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
    await _wireUp().initializeNode();
    final conn = wiring?.lastConnection;
    if (conn != null && mounted) {
      setState(() => _recordProbe(conn));
    }
    await _refreshProfile();
  }

  /// Maps a wiring probe result onto the plain-language Node state
  /// (QoL item 4). A success also stamps [_lastNodeOkAt], which the
  /// node pill turns into "synced N min ago".
  void _recordProbe(HubConnection conn) {
    _nodeReach = switch (conn.state) {
      HubConnectionState.connected => NodeReach.connected,
      HubConnectionState.unauthorized ||
      HubConnectionState.forbidden =>
        NodeReach.rejected,
      HubConnectionState.unreachable ||
      HubConnectionState.error =>
        NodeReach.unreachable,
    };
    if (conn.connected) _lastNodeOkAt = DateTime.now();
  }

  bool get _isLoopback =>
      _host == '127.0.0.1' || _host == 'localhost' || _host == '::1';

  /// The Node pill / Node sheet headline (QoL item 4).
  String get _nodeHeadline => _busy && _nodeReach == NodeReach.searching
      ? 'Searching for your node…'
      : nodePlainLine(
          reach: _nodeReach,
          isLoopback: _isLoopback,
          lastOkAt: _lastNodeOkAt,
          now: DateTime.now(),
        );

  /// The raw probe detail kept under the plain-language headline, so
  /// nothing diagnostic is lost (QoL item 4).
  String get _nodeRawDetail {
    final probe = wiring?.lastProbe;
    final conn = wiring?.lastConnection;
    if (probe == null && conn == null) return 'No probe has run yet.';
    final lines = <String>[
      'Host: $_host',
      if (conn != null) 'Probe state: ${conn.state.name}',
      if (probe != null) probe.statusMessage,
      if (probe?.daemonVersion != null)
        'Daemon version: ${probe!.daemonVersion}',
      if (probe?.nodeId != null) 'Node id: ${probe!.nodeId}',
      if (probe != null) 'Peers: ${probe.peerCount}',
    ];
    return lines.join('\n');
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
        final cos = profile['cosmetics'];
        if (cos is List) {
          // The node's profile is the source of truth once it exists;
          // the phone-local copy below is the offline fallback.
          _cosmetics = cos.map((e) => '$e').toList();
          _persistCosmetics();
        }
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
      _nodeReach = NodeReach.searching;
      _status = 'Pinging your node…';
    });
    final conn = await _wireUp().probeConnection();
    if (!mounted) return;
    setState(() {
      _recordProbe(conn);
      _busy = false;
      _status = switch (conn.state) {
        HubConnectionState.connected => 'Node is answering on $_host.',
        HubConnectionState.unauthorized ||
        HubConnectionState.forbidden =>
          'Node is running on $_host but rejected the token — paste the local token from Omni Node, Save settings, then test again.',
        HubConnectionState.unreachable ||
        HubConnectionState.error =>
          'Node not answering — is Omni Node running on $_host?',
      };
    });
    if (conn.connected) await _refreshProfile();
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
    await Clipboard.setData(ClipboardData(text: identityTransferCode(seed)));
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
        content: StatefulBuilder(
          builder: (ctx, setDialogState) => Column(
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
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.content_paste),
                  label: const Text('Paste from clipboard'),
                  onPressed: () async {
                    final data = await Clipboard.getData('text/plain');
                    final text = data?.text?.trim() ?? '';
                    if (text.isEmpty) return;
                    setDialogState(() => ctrl.text = text);
                  },
                ),
              ),
            ],
          ),
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
    ctrl.dispose();
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
    await _offerRestartAfterImport();
  }

  /// After a successful import the app itself offers the restart the
  /// import needs (QoL item 3): StargateIdentity caches its load, so
  /// the imported seed only takes over on a fresh start. "Close LPE
  /// now" exits the app so the person can reopen it as the imported
  /// identity; "Later" leaves them where they are.
  Future<void> _offerRestartAfterImport() async {
    final close = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Identity imported — restart LPE?'),
        content: const Text(
            'The imported identity takes over the next time LPE starts. '
            'Close LPE now and reopen it to sign as the imported '
            'identity, or keep browsing and restart later.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Close LPE now'),
          ),
        ],
      ),
    );
    if (close == true) {
      await SystemNavigator.pop();
    }
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
    _persistCosmetics();
    final (ok, message) = await _api.postProfile(
      identity: identity,
      handle: handle,
      avatar: 'default_m_01',
      cosmetics: _cosmetics,
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

  /// Keeps the phone-local cosmetics copy in step, so the stage can
  /// render equipment before (or without) a node round-trip — the same
  /// fallback pattern as the sign. The node's profile wins on load.
  void _persistCosmetics() {
    _storage.write(key: 'lpe_cosmetics', value: _cosmetics.join(','));
  }

  /// Applies a new Slice 2 look from the choosers and persists it
  /// phone-locally (see [_appearance]).
  void _setAppearance(HaloAppearance next) {
    setState(() => _appearance = next);
    _storage.write(key: 'lpe_appearance', value: next.encode());
  }

  /// Equips or unequips a cosmetic by its pack item id. The change is
  /// local until the next profile save posts the cosmetics list.
  void _toggleCosmetic(String id, bool on) {
    setState(() {
      _cosmetics =
          on ? [..._cosmetics, id] : _cosmetics.where((c) => c != id).toList();
    });
    _persistCosmetics();
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

  // -- Item 0: full-screen Halo first, everything else behind modals --
  //
  // The landing surface is the Halo itself, full screen (Kiro's ruling,
  // Nov 22, 2026 — it supersedes the old three-tab layout). Customize,
  // Profile and Node live in modal bottom sheets opened from overlay
  // controls; the app never navigates away to a settings page, and on
  // launch it always lands here — Item 1's "reopen where you left off"
  // restores the Halo's state (appearance, sign, color — all persisted
  // phone-locally as before), never a sheet.

  @override
  Widget build(BuildContext context) {
    return AnimatedTheme(
      data: haloTheme(_favorite),
      duration: const Duration(milliseconds: 600),
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _tapHalo,
                child: HaloStage(
                  seed: _favorite,
                  handle: _stageHandle,
                  signName: _signData.$2,
                  signGlyph: _signData.$3,
                  onColorPicked: _pickColor,
                  cosmetics: _cosmetics,
                  appearance: _appearance,
                  framing: HaloFraming.fullBody,
                ),
              ),
            ),
            // The Halo's speech bubble (name tag + one line), shown
            // over the lower stage when the Halo is tapped.
            if (_haloSpeaking)
              Positioned(
                left: 24,
                right: 24,
                bottom: 118,
                child: _speechBubble(),
              ),
            // Top overlay: the plain-language node pill (Item 4). It
            // taps open to the Node sheet with the full detail.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    children: [
                      Expanded(child: _nodePill()),
                    ],
                  ),
                ),
              ),
            ),
            // Bottom overlay: status line + the modal openers.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _status,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: _showCustomizeSheet,
                            icon: const Icon(Icons.auto_fix_high),
                            label: const Text('Customize'),
                          ),
                          const SizedBox(width: 10),
                          FilledButton.tonalIcon(
                            onPressed: _showProfileSheet,
                            icon: const Icon(Icons.person),
                            label: const Text('Profile'),
                          ),
                          const SizedBox(width: 10),
                          IconButton.filledTonal(
                            onPressed: _busy ? null : _importTransferCode,
                            icon: const Icon(Icons.swap_horiz),
                            tooltip: 'Import identity transfer code',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tapping the Halo (Item 0, Masters EX dialogue style): surface
  /// its name tag + one line in its own voice, then let it fade.
  void _tapHalo() => _showSpeech(_haloLine);

  /// Shows the speech bubble with [line] for the standard bubble
  /// duration, then lets it fade. Shared by the tap and by ambient
  /// speech; the sequence counter keeps a stale auto-hide timer from
  /// dismissing a newer line.
  void _showSpeech(String line) {
    final seq = ++_speechSeq;
    setState(() {
      _speechLine = line;
      _haloSpeaking = true;
    });
    Future.delayed(kSpeechBubbleVisible, () {
      if (mounted && seq == _speechSeq) {
        setState(() => _haloSpeaking = false);
      }
    });
  }

  /// The Halo's tap dialogue line: who it is, and how the node feels
  /// from inside the persona. Plain status, spoken as the Halo. (The
  /// node clause also leads the ambient pool — see haloAmbientLines.)
  String get _haloLine =>
      '${_signData.$2} sign, standing by. '
      '${haloNodeBit(reach: _nodeReach, isLoopback: _isLoopback)}';

  Widget _speechBubble() {
    return Material(
      color: const Color(0xB8000000),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _stageHandle,
              style: TextStyle(
                color: _favorite,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              _speechLine,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  /// The node status pill: a colored dot + the plain-language headline.
  Widget _nodePill() {
    final dotColor = switch (_nodeReach) {
      NodeReach.connected => Colors.greenAccent,
      NodeReach.searching => Colors.amberAccent,
      NodeReach.rejected => Colors.orangeAccent,
      NodeReach.unreachable => Colors.redAccent,
      NodeReach.unknown => Colors.white38,
    };
    return Material(
      color: Colors.black45,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: _showNodeSheet,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 10, color: dotColor),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _nodeHeadline,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.hub, size: 16, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusLine() => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(_status, style: Theme.of(context).textTheme.bodySmall),
      );

  /// Opens a modal bottom sheet at a fixed fraction of the screen, so
  /// the Halo stays visible above it and keeps updating live while the
  /// person works in the sheet.
  void _openSheet(Widget Function(StateSetter setSheet) builder) {
    _sheetOpen = true;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.78,
          child: builder(setSheet),
        ),
      ),
    ).whenComplete(() => _sheetOpen = false);
  }

  // -- Customize sheet (the old Creator tab, behind a modal) ----------

  void _showCustomizeSheet() {
    // The selected chooser tab is sheet-local state, captured here so
    // it survives the sheet's own rebuilds (Masters refinement 3).
    var tab = 0;
    _openSheet((setSheet) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            _statusLine(),
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
                  DropdownMenuItem(
                      value: s.$1, child: Text('${s.$3}  ${s.$2}')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _sign = v);
                setSheet(() {});
                // Item 1: the Customize state persists as it changes,
                // not only when the profile is saved.
                _storage.write(key: 'lpe_sign', value: v);
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
            const SizedBox(height: 16),
            Text('Appearance', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              'Your Halo\'s basic look — baked renders of the default '
              'characters, customised by recipe. Kept on this phone; the '
              'node profile carries your cosmetics, not your look (yet).',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            _appearancePanel(
              tab: tab,
              setSheet: setSheet,
              onTab: (t) {
                tab = t;
                setSheet(() {});
              },
            ),
            const SizedBox(height: 16),
            // Item 2: the fun buttons over the existing chooser sets.
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: () {
                    _setAppearance(randomizedAppearance(_appearance, Random()));
                    setSheet(() {});
                  },
                  icon: const Icon(Icons.casino),
                  label: const Text('Randomize'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _appearance.isDefaultLook
                      ? null
                      : () {
                          _setAppearance(
                              HaloAppearance.defaultFor(_appearance.baseModel));
                          setSheet(() {});
                        },
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Reset to default'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Cosmetics', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            const Text(
              'Equipment renders on your Halo from its pack item id and '
              'saves with your profile. The crown is the reference cosmetic '
              'from the signed pack omnimod.base.crown-01.',
              style: TextStyle(fontSize: 12),
            ),
            for (final c in kCosmeticCatalog)
              SwitchListTile(
                title: Text(c.$2),
                subtitle: Text(c.$3),
                value: _cosmetics.contains(c.$1),
                onChanged: (on) {
                  _toggleCosmetic(c.$1, on);
                  setSheet(() {});
                },
              ),
            const SizedBox(height: 8),
            const Text(
              'Skeleton scope: the profile still posts avatar '
              'default_m_01; your appearance above is rendered locally '
              'from the bakes and kept on this phone. Handles are '
              'lowercase — 3–20 chars of a–z, 0–9 '
              'or _ (the node adds the @ itself). Your sign is kept on '
              'this phone for now — the node profile schema gains a sign '
              'field in a later daemon update.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () async {
                      await _saveProfile();
                      setSheet(() {});
                    },
              child: const Text('Save my Halo to the node'),
            ),
          ],
        ));
  }

  /// The Customize sheet's appearance panel, Masters Trainer Settings
  /// style (refinement 3): category tabs across the top — Model, Skin,
  /// Hair, Top, Bottom, Shoes, using the app's own axis names — and
  /// the selected category's choosers in a panel below, instead of one
  /// long scroll of every axis. The sections are the same
  /// ModelChooser / AxisChooser widgets the full chooser stack uses,
  /// and every change flows through [_setAppearance], so the Halo
  /// above the sheet keeps updating live and the phone-local
  /// persistence is untouched.
  Widget _appearancePanel({
    required int tab,
    required StateSetter setSheet,
    required ValueChanged<int> onTab,
  }) {
    const tabLabels = ['Model', 'Skin', 'Hair', 'Top', 'Bottom', 'Shoes'];
    void changed(HaloAppearance a) {
      _setAppearance(a);
      setSheet(() {});
    }

    final Widget section;
    switch (tab) {
      case 1:
        section = AxisChooser(
            appearance: _appearance, axis: 'skin', onChanged: changed);
      case 2:
        section = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AxisChooser(
                appearance: _appearance,
                axis: 'hairColor',
                onChanged: changed),
            const SizedBox(height: 16),
            AxisChooser(
                appearance: _appearance,
                axis: 'hairStyle',
                onChanged: changed),
          ],
        );
      case 3:
        section = AxisChooser(
            appearance: _appearance, axis: 'shirt', onChanged: changed);
      case 4:
        section = AxisChooser(
            appearance: _appearance, axis: 'pants', onChanged: changed);
      case 5:
        section = AxisChooser(
            appearance: _appearance, axis: 'shoes', onChanged: changed);
      default:
        section = ModelChooser(appearance: _appearance, onChanged: changed);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < tabLabels.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(tabLabels[i]),
                  selected: tab == i,
                  onSelected: (_) => onTab(i),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: section,
        ),
        const SizedBox(height: 12),
        const Text(
          'Every option here is free — these are the basic recipe '
          'variants of your Halo, baked from the same master. One bake '
          'shows one change at a time: the stage shows your most '
          'recent change (layered bakes come later).',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  // -- Profile sheet (identity, progress, transfer codes) -------------

  void _showProfileSheet() {
    _openSheet((setSheet) {
      final identity = _identity;
      final profile = _profile;
      final aura = profile?['aura'];
      final tier = aura is Map ? '${aura['tier'] ?? ''}' : 'no profile';
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _statusLine(),
          // Header band (Masters Profile layout, refinement 2): the
          // sign-glyph avatar, handle and sign, and the identity short
          // id this sheet has always shown — now with the copy
          // affordance Masters puts beside the id. It copies the
          // PUBLIC key, which is safe to share; the seed-bearing
          // transfer code stays behind its warning dialog below.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _auraColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: Colors.black26,
                  child: Text(_signData.$3,
                      style:
                          const TextStyle(fontSize: 30, color: Colors.white)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile?['handle_display'] as String? ??
                            (identity == null ? '…' : 'No handle yet'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_signData.$3} ${_signData.$2} · $tier',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        identity == null
                            ? 'Loading identity…'
                            : 'Identity ${identity.shortId}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                if (identity != null)
                  IconButton(
                    icon: const Icon(Icons.copy, color: Colors.white),
                    tooltip: 'Copy identity id (public key)',
                    onPressed: () async {
                      await Clipboard.setData(
                          ClipboardData(text: identity.pubkeyHex));
                      if (!mounted) return;
                      setState(() => _status =
                          'Identity id copied — it is your public key, safe to share.');
                      setSheet(() {});
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Edit Look sits on the Profile screen in Masters; here it
          // closes Profile and opens the Customize sheet.
          FilledButton.tonalIcon(
            onPressed: () {
              Navigator.of(context).pop();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _showCustomizeSheet();
              });
            },
            icon: const Icon(Icons.auto_fix_high),
            label: const Text('Edit Look'),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Progress',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  if (profile == null)
                    const Text(
                        'You have no Halo on this node yet. Open Customize, pick a handle and a sign, and save — Plaza-Brawler will offer your own character as your fighter.')
                  else
                    Text(
                        'XP ${profile['xp'] ?? 0} · Plaza credits ${profile['plaza_credits'] ?? 0}\n'
                        'Your fighter in Plaza-Brawler is built from this profile: your handle, your aura, stats from $_sign.'),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: _busy
                        ? null
                        : () async {
                            await _refreshProfile();
                            setSheet(() {});
                          },
                    child: const Text('Refresh from node'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Identity transfer',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  const Text(
                    'Carries this identity into your other Omni apps on this phone — '
                    'Plaza-Brawler imports it in Settings, then fights as this Halo.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _busy ? null : _copyTransferCode,
                      child: const Text('Copy identity transfer code'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _busy ? null : _importTransferCode,
                      child: const Text('Import identity transfer code'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Import restores an identity here — the recovery path if a reinstall '
                    'ever wipes this app and you hold the code in another app.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }

  // -- Node sheet (plain language first, raw detail underneath) -------

  void _showNodeSheet() {
    _openSheet((setSheet) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            _statusLine(),
            Text(_nodeHeadline, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            // Item 4: the raw probe detail stays, underneath.
            Text(_nodeRawDetail, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Node host',
                hintText: '127.0.0.1',
                border: OutlineInputBorder(),
              ),
              controller: TextEditingController(text: _host),
              onChanged: (v) =>
                  _host = v.trim().isEmpty ? '127.0.0.1' : v.trim(),
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
                  onPressed: _busy
                      ? null
                      : () async {
                          await _saveSettings();
                          setSheet(() {});
                        },
                  child: const Text('Save settings'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          await _testNode();
                          setSheet(() {});
                        },
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
        ));
  }
}
