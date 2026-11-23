// LPE QoL helpers (Nov 22, 2026 pass) — pure Dart, no Flutter imports,
// so the randomize rule and the Node tab's plain-language line are
// unit-testable without a widget tree (same pattern as
// halo_appearance.dart).
import 'dart:math';

import 'halo_appearance.dart';

/// A random look for [current]'s base model: every axis re-rolled from
/// its existing chooser option set (haloAxisValues). The model itself
/// never changes — randomize is about the look, not the body. Built
/// through withAxis, so the recency order follows kHaloAxes order and
/// the stage's display rule behaves exactly as if the person had tapped
/// the chips in that order.
HaloAppearance randomizedAppearance(HaloAppearance current, Random random) {
  var next = HaloAppearance.defaultFor(current.baseModel);
  for (final axis in kHaloAxes) {
    final values = haloAxisValues(current.baseModel, axis);
    next = next.withAxis(axis, values[random.nextInt(values.length)]);
  }
  return next;
}

/// How reachable the person's Omni Node is, in the app's own terms —
/// main.dart maps the wiring's HubConnectionState onto this so the
/// plain-language line below stays free of Core-UI types.
enum NodeReach {
  /// No probe has finished yet.
  unknown,

  /// A probe is in flight.
  searching,

  /// The node answered node-health.
  connected,

  /// The node answered but refused us (bad token / remote mode off).
  rejected,

  /// Nothing answered, or the answer was unrecognisable.
  unreachable,
}

/// 'just now' / '2 min ago' / '1 h ago' / '3 d ago' for a past instant.
String relativeAgo(DateTime then, DateTime now) {
  final d = now.difference(then);
  if (d.isNegative || d.inSeconds < 45) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

/// How long the Halo waits between unprompted (ambient) lines, and how
/// long a speech bubble — tapped or ambient — stays up. Ambient speech
/// is deliberately sparse: a place feels alive when its characters
/// talk occasionally, not constantly.
const Duration kAmbientSpeechInterval = Duration(seconds: 45);
const Duration kSpeechBubbleVisible = Duration(milliseconds: 4500);

/// The node clause of the Halo's speech, in its own voice — how the
/// connection feels from inside the persona. [reach] / [isLoopback]
/// mean the same as in [nodePlainLine]; every variant states only what
/// the last probe actually established.
String haloNodeBit({required NodeReach reach, required bool isLoopback}) {
  switch (reach) {
    case NodeReach.connected:
      return isLoopback
          ? 'Your node is right here with me — we\'re synced.'
          : 'Your laptop node is humming — we\'re synced.';
    case NodeReach.searching:
      return 'Listening for your node…';
    case NodeReach.rejected:
      return 'Your node answered, but it doesn\'t trust this app yet.';
    case NodeReach.unreachable:
      return 'No node in earshot right now.';
    case NodeReach.unknown:
      return 'Still waking up…';
  }
}

/// The Halo's ambient (unprompted) lines, in rotation order. Every line
/// is built from real state only: the Halo's sign and the node clause
/// (see [haloNodeBit]), the ambient activity the person themselves set
/// for the Plaza (included only when set), and the crown (included
/// only when it is actually equipped). Nothing here claims an event or
/// a status the app has not established.
List<String> haloAmbientLines({
  required String signName,
  required String nodeBit,
  required String ambientActivity,
  required bool crownEquipped,
}) {
  final activity = ambientActivity.trim();
  return [
    '$signName sign, standing by. $nodeBit',
    if (activity.isNotEmpty) 'Plaza status: $activity',
    if (crownEquipped) 'The crown still suits me.',
    'I\'m here whenever you need me.',
  ];
}

/// Picks the ambient line for rotation step [tick]: cycles through
/// [lines] in order and wraps. An empty pool yields an empty line
/// (the caller treats that as "stay quiet").
String pickAmbientLine(List<String> lines, int tick) =>
    lines.isEmpty ? '' : lines[tick % lines.length];

/// The Node tab's headline, in plain language. [lastOkAt] is when a
/// probe last succeeded (null if none has); [isLoopback] distinguishes
/// the on-device node from a hub the person named (their laptop).
/// The raw probe detail stays available under this line in the UI —
/// this replaces nothing diagnostic.
String nodePlainLine({
  required NodeReach reach,
  required bool isLoopback,
  required DateTime? lastOkAt,
  required DateTime now,
}) {
  switch (reach) {
    case NodeReach.searching:
      return 'Searching for your node…';
    case NodeReach.connected:
      final where = isLoopback ? 'the node on this device' : 'your laptop node';
      final synced =
          lastOkAt == null ? '' : ' · synced ${relativeAgo(lastOkAt, now)}';
      return 'Connected to $where$synced';
    case NodeReach.rejected:
      return 'Your node answered, but rejected this app — check the '
          'node token below.';
    case NodeReach.unreachable:
      return 'No node found — is Omni Node running?';
    case NodeReach.unknown:
      return 'Not checked yet — tap Test connection.';
  }
}
