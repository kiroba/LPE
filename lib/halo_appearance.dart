// HaloAppearance — the Slice 2 free-basics look of a Halo (spec:
// lpe-halo-customization-spec-2026-11-15.md §2/§3 P4). Pure Dart: no
// Flutter imports, so the model, the display rule and the persistence
// codec are unit-testable without a widget tree.
//
// The look is a set of RECIPE parameters that were rebaked from the one
// master per model (P3, variants-bake/): skin tone, shirt / pants / shoe
// colour, hair colour, hair style. Nothing here tints or filters a
// finished render — every value names a bake.
//
// Defaults are each model's SHIPPED look, read off the P3 bake record
// (variants-bake/VARIANTS_NOTES.md): the male default skin is tone 1
// (light stock texture) and the female default skin is tone 5 (deep
// stock texture) — tones 2–4 are shader multiplies between those poles.
// Male stock: blue shirt, indigo pants, brown shoes, black hair,
// short01. Female stock: blue shirt, indigo pants, black shoes,
// dark-brown hair, long01. Stock-colour bakes are byte copies of the
// default render, so the default look needs no variant file.

/// Axis ids, in chooser order.
const List<String> kHaloAxes = [
  'skin',
  'shirt',
  'pants',
  'shoes',
  'hairColor',
  'hairStyle',
];

/// Human labels for the axes (chooser headings).
const Map<String, String> kHaloAxisLabels = {
  'skin': 'Skin tone',
  'shirt': 'Shirt colour',
  'pants': 'Pants colour',
  'shoes': 'Shoe colour',
  'hairColor': 'Hair colour',
  'hairStyle': 'Hair style',
};

/// The values each axis can take for a model, in chooser order.
List<String> haloAxisValues(String model, String axis) {
  switch (axis) {
    case 'skin':
      return const ['1', '2', '3', '4', '5'];
    case 'shirt':
      return const ['blue', 'forest', 'rust', 'plum', 'charcoal', 'cream'];
    case 'pants':
      return const ['indigo', 'black', 'khaki', 'grey', 'olive'];
    case 'shoes':
      return model == 'female'
          ? const ['black', 'brown', 'white', 'grey', 'red']
          : const ['brown', 'black', 'white', 'grey', 'red'];
    case 'hairColor':
      return const [
        'black',
        'darkbrown',
        'brown',
        'auburn',
        'blonde',
        'grey'
      ];
    case 'hairStyle':
      return model == 'female'
          ? const ['long01', 'bob01', 'short01']
          : const ['short01', 'short02', 'short03'];
    default:
      return const [];
  }
}

/// The shipped (default) value of an axis for a model.
String haloAxisDefault(String model, String axis) {
  switch (axis) {
    case 'skin':
      return model == 'female' ? '5' : '1';
    case 'shirt':
      return 'blue';
    case 'pants':
      return 'indigo';
    case 'shoes':
      return model == 'female' ? 'black' : 'brown';
    case 'hairColor':
      return model == 'female' ? 'darkbrown' : 'black';
    case 'hairStyle':
      return model == 'female' ? 'long01' : 'short01';
    default:
      return '';
  }
}

/// Chooser label for one axis value.
String haloAxisValueLabel(String axis, String value) {
  switch (axis) {
    case 'skin':
      return const {
            '1': '1 · Light',
            '2': '2 · Light medium',
            '3': '3 · Medium',
            '4': '4 · Deep medium',
            '5': '5 · Deep',
          }[value] ??
          value;
    case 'hairColor':
      return value == 'darkbrown' ? 'Dark brown' : _title(value);
    case 'hairStyle':
      return const {
            'short01': 'Short',
            'short02': 'Textured crop',
            'short03': 'Side part',
            'long01': 'Long',
            'bob01': 'Bob',
          }[value] ??
          value;
    default:
      return _title(value);
  }
}

String _title(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// One person's Halo look: a base model plus one value per axis, and the
/// recency order in which axes were changed (most recent first). The
/// recency order is part of the value because the display rule needs it
/// (see [resolveHaloDisplay]).
class HaloAppearance {
  const HaloAppearance({
    required this.baseModel,
    required this.skinTone,
    required this.shirt,
    required this.pants,
    required this.shoes,
    required this.hairColor,
    required this.hairStyle,
    this.changedOrder = const [],
  });

  /// 'male' (reference-male-01) or 'female' (reference-female-01).
  final String baseModel;

  /// 1–5. Which tone is the default depends on the model (see header).
  final int skinTone;
  final String shirt;
  final String pants;
  final String shoes;
  final String hairColor;
  final String hairStyle;

  /// Axis ids, most recently changed first. Axes absent from this list
  /// are at their default by construction ([withAxis] is the only way
  /// values move). May contain axes whose value has since returned to
  /// default — the display rule skips those.
  final List<String> changedOrder;

  /// The shipped look of a model: every axis at its default.
  factory HaloAppearance.defaultFor(String model) {
    final m = model == 'female' ? 'female' : 'male';
    return HaloAppearance(
      baseModel: m,
      skinTone: int.parse(haloAxisDefault(m, 'skin')),
      shirt: haloAxisDefault(m, 'shirt'),
      pants: haloAxisDefault(m, 'pants'),
      shoes: haloAxisDefault(m, 'shoes'),
      hairColor: haloAxisDefault(m, 'hairColor'),
      hairStyle: haloAxisDefault(m, 'hairStyle'),
    );
  }

  /// The current value of an axis, as the string the bake files use.
  String valueOf(String axis) {
    switch (axis) {
      case 'skin':
        return '$skinTone';
      case 'shirt':
        return shirt;
      case 'pants':
        return pants;
      case 'shoes':
        return shoes;
      case 'hairColor':
        return hairColor;
      case 'hairStyle':
        return hairStyle;
      default:
        return '';
    }
  }

  bool isAxisDefault(String axis) =>
      valueOf(axis) == haloAxisDefault(baseModel, axis);

  /// True when every axis is at the model's shipped look.
  bool get isDefaultLook => kHaloAxes.every(isAxisDefault);

  /// Returns a copy with [axis] set to [value] and moved to the front of
  /// the recency order. Unknown axes/values are ignored (returns this).
  HaloAppearance withAxis(String axis, String value) {
    if (!haloAxisValues(baseModel, axis).contains(value)) return this;
    final order = [axis, ...changedOrder.where((a) => a != axis)];
    switch (axis) {
      case 'skin':
        return _copy(skinTone: int.parse(value), changedOrder: order);
      case 'shirt':
        return _copy(shirt: value, changedOrder: order);
      case 'pants':
        return _copy(pants: value, changedOrder: order);
      case 'shoes':
        return _copy(shoes: value, changedOrder: order);
      case 'hairColor':
        return _copy(hairColor: value, changedOrder: order);
      case 'hairStyle':
        return _copy(hairStyle: value, changedOrder: order);
      default:
        return this;
    }
  }

  HaloAppearance _copy({
    int? skinTone,
    String? shirt,
    String? pants,
    String? shoes,
    String? hairColor,
    String? hairStyle,
    List<String>? changedOrder,
  }) =>
      HaloAppearance(
        baseModel: baseModel,
        skinTone: skinTone ?? this.skinTone,
        shirt: shirt ?? this.shirt,
        pants: pants ?? this.pants,
        shoes: shoes ?? this.shoes,
        hairColor: hairColor ?? this.hairColor,
        hairStyle: hairStyle ?? this.hairStyle,
        changedOrder: changedOrder ?? this.changedOrder,
      );

  // -- Persistence codec -------------------------------------------------
  // Compact single-string form for flutter_secure_storage (the
  // lpe_cosmetics pattern: one key, one string):
  //   v1|<model>|<skin>|<shirt>|<pants>|<shoes>|<hairColor>|<hairStyle>|<axis,axis,…>
  // The trailing field is the recency order, most recent first.
  // Appearance NEVER rides the node profile — the daemon profile schema
  // is strict and has no appearance fields; this is phone-local only.

  String encode() => [
        'v1',
        baseModel,
        '$skinTone',
        shirt,
        pants,
        shoes,
        hairColor,
        hairStyle,
        changedOrder.join(','),
      ].join('|');

  /// Tolerant decode: a malformed string yields the male default look;
  /// an unknown value falls back to that axis's default for the model;
  /// unknown axes in the recency field are dropped.
  factory HaloAppearance.decode(String? raw) {
    if (raw == null || raw.isEmpty) return HaloAppearance.defaultFor('male');
    final parts = raw.split('|');
    if (parts.length < 8 || parts[0] != 'v1') {
      return HaloAppearance.defaultFor('male');
    }
    final model = parts[1] == 'female' ? 'female' : 'male';
    var a = HaloAppearance.defaultFor(model);
    const fields = ['skin', 'shirt', 'pants', 'shoes', 'hairColor', 'hairStyle'];
    for (var i = 0; i < fields.length; i++) {
      final v = parts[2 + i];
      if (haloAxisValues(model, fields[i]).contains(v)) {
        a = a.withAxis(fields[i], v);
      }
    }
    // withAxis rebuilt the recency order from field order; restore the
    // stored order instead (validated, de-duplicated).
    if (parts.length > 8) {
      final seen = <String>{};
      final order = <String>[];
      for (final ax in parts[8].split(',')) {
        if (kHaloAxes.contains(ax) && seen.add(ax)) order.add(ax);
      }
      a = a._copy(changedOrder: order);
    }
    return a;
  }

  @override
  bool operator ==(Object other) =>
      other is HaloAppearance &&
      other.baseModel == baseModel &&
      other.skinTone == skinTone &&
      other.shirt == shirt &&
      other.pants == pants &&
      other.shoes == shoes &&
      other.hairColor == hairColor &&
      other.hairStyle == hairStyle &&
      _listEq(other.changedOrder, changedOrder);

  @override
  int get hashCode => Object.hash(baseModel, skinTone, shirt, pants, shoes,
      hairColor, hairStyle, Object.hashAll(changedOrder));

  @override
  String toString() => 'HaloAppearance(${encode()})';
}

bool _listEq(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The bake file stem for one axis at its current value, e.g.
/// `male_skin_tone3`, `female_hairstyle_bob01`. Matches the P3 bake
/// filenames under variants-bake/renders/.
String haloVariantStem(HaloAppearance a, String axis) {
  final v = a.valueOf(axis);
  switch (axis) {
    case 'skin':
      return '${a.baseModel}_skin_tone$v';
    case 'hairColor':
      return '${a.baseModel}_hair_$v';
    case 'hairStyle':
      return '${a.baseModel}_hairstyle_$v';
    default:
      return '${a.baseModel}_${axis}_$v';
  }
}

/// What the stage should show for an appearance.
class HaloDisplay {
  const HaloDisplay.idle()
      : isIdle = true,
        stem = null;
  const HaloDisplay.still(this.stem) : isIdle = false;

  /// True when the look is the model's default: the idle loop plays.
  final bool isIdle;

  /// For a still: the bake stem to show (framing picks the suffix).
  final String? stem;
}

/// THE DISPLAY RULE (v1, spec §3 P4 as implemented):
///
/// P3 baked variants ONE AXIS AT A TIME — there is no bake of
/// "forest shirt AND black pants". So the stage shows the variant bake
/// of the MOST RECENTLY CHANGED axis that is currently non-default;
/// axes changed earlier (or changed back to default) are not visible
/// until they become the most recent change again. When every axis is
/// at the model's default, the default look shows as the idle loop.
///
/// This is a known v1 limitation, not a silent shortcut: layered
/// part-bakes (shirt bake composited over pants bake from the same
/// pass) are the future fix and are NOT part of P4.
HaloDisplay resolveHaloDisplay(HaloAppearance a) {
  for (final axis in a.changedOrder) {
    if (!a.isAxisDefault(axis)) {
      return HaloDisplay.still(haloVariantStem(a, axis));
    }
  }
  return const HaloDisplay.idle();
}

/// Asset path for a still of [stem]; portrait framing is the bust bake,
/// full-body framing the three-quarter bake.
String haloStillAsset(String stem, {required bool portrait}) =>
    'assets/halo/$stem${portrait ? '_portrait' : ''}.jpg';

/// Asset path for idle frame [frame] (1–40) of a model's default look.
String haloIdleAsset(String model, int frame) =>
    'assets/halo/${model}_idle_${frame.toString().padLeft(3, '0')}.jpg';

/// Number of baked idle frames per model (40 frames at 8 fps = 5 s).
const int kHaloIdleFrames = 40;
