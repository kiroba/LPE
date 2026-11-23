// QoL pass (Nov 22, 2026) contract tests: the Customize randomize
// rule (item 2) and the Node tab's plain-language line (item 4).
// Item 0/1/3 are interaction + persistence wiring in main.dart and
// are covered by the analyze pass and on-device verdict, not here.
// The refinements (same day) add the ambient-speech pool
// (haloNodeBit / haloAmbientLines / pickAmbientLine) below.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lpe/halo_appearance.dart';
import 'package:lpe/lpe_qol.dart';

void main() {
  group('randomizedAppearance', () {
    test('every axis lands on a valid chooser value for the model', () {
      for (final model in ['male', 'female']) {
        final a =
            randomizedAppearance(HaloAppearance.defaultFor(model), Random(42));
        expect(a.baseModel, model);
        for (final axis in kHaloAxes) {
          expect(haloAxisValues(model, axis), contains(a.valueOf(axis)),
              reason: '$model/$axis');
        }
      }
    });

    test('is deterministic for a seeded Random', () {
      final a =
          randomizedAppearance(HaloAppearance.defaultFor('female'), Random(7));
      final b =
          randomizedAppearance(HaloAppearance.defaultFor('female'), Random(7));
      expect(a, b);
    });

    test('keeps the base model even from a customised look', () {
      final start =
          HaloAppearance.defaultFor('female').withAxis('shirt', 'rust');
      final a = randomizedAppearance(start, Random(1));
      expect(a.baseModel, 'female');
    });
  });

  group('relativeAgo', () {
    final now = DateTime(2026, 11, 22, 12, 0);
    test('buckets', () {
      expect(relativeAgo(now, now), 'just now');
      expect(relativeAgo(now.subtract(const Duration(minutes: 2)), now),
          '2 min ago');
      expect(
          relativeAgo(now.subtract(const Duration(hours: 3)), now), '3 h ago');
      expect(
          relativeAgo(now.subtract(const Duration(days: 2)), now), '2 d ago');
    });
  });

  group('nodePlainLine', () {
    final now = DateTime(2026, 11, 22, 12, 0);
    test('connected remote reads as the laptop node, with sync age', () {
      expect(
        nodePlainLine(
          reach: NodeReach.connected,
          isLoopback: false,
          lastOkAt: now.subtract(const Duration(minutes: 2)),
          now: now,
        ),
        'Connected to your laptop node · synced 2 min ago',
      );
    });

    test('connected loopback names the on-device node', () {
      expect(
        nodePlainLine(
          reach: NodeReach.connected,
          isLoopback: true,
          lastOkAt: now,
          now: now,
        ),
        'Connected to the node on this device · synced just now',
      );
    });

  });

  group('haloNodeBit', () {
    test('connected names where the node lives', () {
      expect(haloNodeBit(reach: NodeReach.connected, isLoopback: false),
          contains('laptop node'));
      expect(haloNodeBit(reach: NodeReach.connected, isLoopback: true),
          contains('right here with me'));
    });

    test('other reaches state only what the probe established', () {
      expect(haloNodeBit(reach: NodeReach.searching, isLoopback: false),
          contains('Listening'));
      expect(haloNodeBit(reach: NodeReach.rejected, isLoopback: false),
          contains('doesn\'t trust'));
      expect(haloNodeBit(reach: NodeReach.unreachable, isLoopback: false),
          contains('No node in earshot'));
      expect(haloNodeBit(reach: NodeReach.unknown, isLoopback: false),
          contains('waking up'));
    });
  });

  group('haloAmbientLines', () {
    test('always carries the identity line and the presence line', () {
      final lines = haloAmbientLines(
        signName: 'Virgo',
        nodeBit: 'No node in earshot right now.',
        ambientActivity: '',
        crownEquipped: false,
      );
      expect(lines.first, 'Virgo sign, standing by. No node in earshot right now.');
      expect(lines.last, contains('whenever you need me'));
      expect(lines, hasLength(2));
    });

    test('the Plaza status line appears only when the person set one', () {
      final withActivity = haloAmbientLines(
        signName: 'Leo',
        nodeBit: 'x',
        ambientActivity: '  Training in Plaza Center  ',
        crownEquipped: false,
      );
      expect(withActivity, contains('Plaza status: Training in Plaza Center'));
      final without = haloAmbientLines(
        signName: 'Leo',
        nodeBit: 'x',
        ambientActivity: '   ',
        crownEquipped: false,
      );
      expect(without.any((l) => l.startsWith('Plaza status')), isFalse);
    });

    test('the crown line appears only when the crown is equipped', () {
      final crowned = haloAmbientLines(
        signName: 'Leo',
        nodeBit: 'x',
        ambientActivity: '',
        crownEquipped: true,
      );
      expect(crowned.any((l) => l.contains('crown')), isTrue);
      final bare = haloAmbientLines(
        signName: 'Leo',
        nodeBit: 'x',
        ambientActivity: '',
        crownEquipped: false,
      );
      expect(bare.any((l) => l.contains('crown')), isFalse);
    });
  });

  group('pickAmbientLine', () {
    test('rotates in order and wraps', () {
      const pool = ['a', 'b', 'c'];
      expect(pickAmbientLine(pool, 0), 'a');
      expect(pickAmbientLine(pool, 1), 'b');
      expect(pickAmbientLine(pool, 2), 'c');
      expect(pickAmbientLine(pool, 3), 'a');
      expect(pickAmbientLine(pool, 7), 'b');
    });

    test('an empty pool stays quiet', () {
      expect(pickAmbientLine(const [], 0), '');
      expect(pickAmbientLine(const [], 5), '');
    });
  });

  group('nodePlainLine states', () {
    final now = DateTime(2026, 11, 22, 12, 0);
    test('searching / unreachable / rejected / unknown', () {
      expect(
          nodePlainLine(
              reach: NodeReach.searching,
              isLoopback: false,
              lastOkAt: null,
              now: now),
          'Searching for your node…');
      expect(
          nodePlainLine(
              reach: NodeReach.unreachable,
              isLoopback: false,
              lastOkAt: null,
              now: now),
          contains('No node found'));
      expect(
          nodePlainLine(
              reach: NodeReach.rejected,
              isLoopback: false,
              lastOkAt: null,
              now: now),
          contains('rejected'));
      expect(
          nodePlainLine(
              reach: NodeReach.unknown,
              isLoopback: false,
              lastOkAt: null,
              now: now),
          contains('Not checked yet'));
    });
  });
}
