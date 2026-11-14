// The crown equip contract: the hero stage renders the crown when
// (and only when) the profile's cosmetics list carries the pack item
// id head_socket_crown — the item declared by the signed pack
// omnimod.base.crown-01. Rendering is from the id; these tests pin
// the wiring, not the pixels (the painted capture is checked by eye
// in the pipeline workspace).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lpe/halo_stage.dart';

Widget stage(List<String> cosmetics) => MaterialApp(
      home: Scaffold(
        body: HaloStage(
          seed: const Color(0xFF6C4DF6),
          handle: '@test',
          signName: 'Aries',
          signGlyph: '♈',
          onColorPicked: (_) {},
          cosmetics: cosmetics,
        ),
      ),
    );

void main() {
  testWidgets('crown renders on the stage when equipped', (tester) async {
    await tester.pumpWidget(stage(const ['head_socket_crown']));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('cosmetic_head_socket_crown')),
        findsOneWidget);
  });

  testWidgets('no crown without the cosmetic equipped', (tester) async {
    await tester.pumpWidget(stage(const []));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('cosmetic_head_socket_crown')),
        findsNothing);
  });

  testWidgets('unknown cosmetic ids render nothing extra', (tester) async {
    await tester.pumpWidget(stage(const ['aura_socket_mystery']));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('cosmetic_head_socket_crown')),
        findsNothing);
  });
}
