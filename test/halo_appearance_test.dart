// P4 contract tests: the appearance model, the v1 display rule and
// the persistence codec. The defaults pinned here are the models'
// SHIPPED looks from the P3 bake record (variants-bake/
// VARIANTS_NOTES.md) — male skin tone 1 / female skin tone 5 are the
// two stock-texture poles, not a symmetric guess.
import 'package:flutter_test/flutter_test.dart';
import 'package:lpe/halo_appearance.dart';

void main() {
  group('defaults are the shipped looks', () {
    test('male default', () {
      final a = HaloAppearance.defaultFor('male');
      expect(a.skinTone, 1);
      expect(a.shirt, 'blue');
      expect(a.pants, 'indigo');
      expect(a.shoes, 'brown');
      expect(a.hairColor, 'black');
      expect(a.hairStyle, 'short01');
      expect(a.isDefaultLook, isTrue);
    });

    test('female default', () {
      final a = HaloAppearance.defaultFor('female');
      expect(a.skinTone, 5);
      expect(a.shirt, 'blue');
      expect(a.pants, 'indigo');
      expect(a.shoes, 'black');
      expect(a.hairColor, 'darkbrown');
      expect(a.hairStyle, 'long01');
      expect(a.isDefaultLook, isTrue);
    });
  });

  group('display rule (most recent non-default axis wins)', () {
    test('all default shows the idle loop', () {
      final d = resolveHaloDisplay(HaloAppearance.defaultFor('male'));
      expect(d.isIdle, isTrue);
      expect(d.stem, isNull);
    });

    test('one changed axis shows its bake', () {
      final a =
          HaloAppearance.defaultFor('male').withAxis('shirt', 'forest');
      final d = resolveHaloDisplay(a);
      expect(d.isIdle, isFalse);
      expect(d.stem, 'male_shirt_forest');
    });

    test('the most recent change wins over an earlier one', () {
      final a = HaloAppearance.defaultFor('female')
          .withAxis('shirt', 'rust')
          .withAxis('pants', 'black');
      expect(resolveHaloDisplay(a).stem, 'female_pants_black');
    });

    test('changing the winner back to default revives the earlier axis',
        () {
      final a = HaloAppearance.defaultFor('male')
          .withAxis('shirt', 'forest')
          .withAxis('pants', 'black')
          .withAxis('pants', 'indigo');
      expect(resolveHaloDisplay(a).stem, 'male_shirt_forest');
    });

    test('changing everything back returns to idle', () {
      final a = HaloAppearance.defaultFor('male')
          .withAxis('shirt', 'forest')
          .withAxis('shirt', 'blue');
      expect(resolveHaloDisplay(a).isIdle, isTrue);
    });

    test('skin and hair stems follow the bake filenames', () {
      final m = HaloAppearance.defaultFor('male').withAxis('skin', '3');
      expect(resolveHaloDisplay(m).stem, 'male_skin_tone3');
      final f =
          HaloAppearance.defaultFor('female').withAxis('hairStyle', 'bob01');
      expect(resolveHaloDisplay(f).stem, 'female_hairstyle_bob01');
      final h =
          HaloAppearance.defaultFor('female').withAxis('hairColor', 'blonde');
      expect(resolveHaloDisplay(h).stem, 'female_hair_blonde');
    });

    test('unknown axes and values are ignored', () {
      final a = HaloAppearance.defaultFor('male');
      expect(a.withAxis('wings', 'big'), same(a));
      expect(a.withAxis('shirt', 'polka-dot'), same(a));
    });
  });

  group('persistence codec', () {
    test('round-trips a changed look including recency', () {
      final a = HaloAppearance.defaultFor('female')
          .withAxis('shirt', 'plum')
          .withAxis('skin', '2')
          .withAxis('hairStyle', 'short01');
      final back = HaloAppearance.decode(a.encode());
      expect(back, a);
      expect(resolveHaloDisplay(back).stem, 'female_hairstyle_short01');
    });

    test('round-trips a default look', () {
      final a = HaloAppearance.defaultFor('male');
      expect(HaloAppearance.decode(a.encode()), a);
    });

    test('null / empty / garbage decode to the male default', () {
      final d = HaloAppearance.defaultFor('male');
      expect(HaloAppearance.decode(null), d);
      expect(HaloAppearance.decode(''), d);
      expect(HaloAppearance.decode('nonsense'), d);
      expect(HaloAppearance.decode('v2|female|1|blue|x|x|x|x|'), d);
    });

    test('unknown values fall back per-axis, model survives', () {
      final a = HaloAppearance.decode(
          'v1|female|9|polka-dot|black|black|darkbrown|long01|pants');
      expect(a.baseModel, 'female');
      expect(a.skinTone, 5); // invalid tone -> female default
      expect(a.shirt, 'blue'); // invalid shirt -> default
      expect(a.pants, 'black'); // valid value kept
      expect(resolveHaloDisplay(a).stem, 'female_pants_black');
    });
  });

  group('asset paths', () {
    test('still and idle paths', () {
      expect(haloStillAsset('male_shirt_forest', portrait: true),
          'assets/halo/male_shirt_forest_portrait.jpg');
      expect(haloStillAsset('male_shirt_forest', portrait: false),
          'assets/halo/male_shirt_forest.jpg');
      expect(haloIdleAsset('female', 7), 'assets/halo/female_idle_007.jpg');
      expect(haloIdleAsset('male', 40), 'assets/halo/male_idle_040.jpg');
    });
  });
}
