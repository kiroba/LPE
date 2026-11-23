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
