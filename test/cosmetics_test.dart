// The crown equip contract: the hero stage renders the crown when
// (and only when) the profile's cosmetics list carries the pack item
// id head_socket_crown — the item declared by the signed pack
// omnimod.base.crown-01. Rendering is from the id; these tests pin
// the wiring, not the pixels (the painted capture is checked by eye
// in the pipeline workspace).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lpe/halo_appearance.dart';
import 'package:lpe/halo_render.dart';
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

  // -- P4: choosers + render wiring -------------------------------------
  // The Creator-tab choosers render every free axis and report
  // changes, and the stage's hero becomes the baked render when an
  // appearance is wired in (the reachability contract — these widgets
  // are what lib/main.dart's tabs actually mount).

  testWidgets('choosers show every axis and the free-basics note',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AppearanceChoosers(
            appearance: HaloAppearance.defaultFor('male'),
            onChanged: (_) {},
          ),
        ),
      ),
    ));
    expect(find.text('Base model'), findsOneWidget);
    for (final label in kHaloAxisLabels.values) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // Free means visibly free: no lock icons anywhere in the choosers.
    expect(find.byIcon(Icons.lock), findsNothing);
    expect(find.textContaining('most recent change'), findsOneWidget);
  });

  testWidgets('tapping a shirt chip reports the new appearance',
      (tester) async {
    HaloAppearance? next;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AppearanceChoosers(
            appearance: HaloAppearance.defaultFor('male'),
            onChanged: (a) => next = a,
          ),
        ),
      ),
    ));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Forest'));
    expect(next, isNotNull);
    expect(next!.shirt, 'forest');
    expect(resolveHaloDisplay(next!).stem, 'male_shirt_forest');
  });

  testWidgets('switching base model resets to that model\'s defaults',
      (tester) async {
    HaloAppearance? next;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AppearanceChoosers(
            appearance: HaloAppearance.defaultFor('male')
                .withAxis('shirt', 'rust'),
            onChanged: (a) => next = a,
          ),
        ),
      ),
    ));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Female'));
    expect(next, HaloAppearance.defaultFor('female'));
  });

  testWidgets('stage shows the baked render view when appearance is set',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: HaloStage(
            seed: const Color(0xFF6C4DF6),
            handle: '@test',
            signName: 'Aries',
            signGlyph: '♈',
            onColorPicked: (_) {},
            appearance: HaloAppearance.defaultFor('male'),
            framing: HaloFraming.fullBody,
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(HaloRenderView), findsOneWidget);
  });

  testWidgets('crown overlay appears on the render when equipped',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: HaloStage(
            seed: const Color(0xFF6C4DF6),
            handle: '@test',
            signName: 'Aries',
            signGlyph: '♈',
            onColorPicked: (_) {},
            cosmetics: const ['head_socket_crown'],
            appearance: HaloAppearance.defaultFor('female'),
            framing: HaloFraming.portrait,
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('halo_render_crown')), findsOneWidget);
  });
}
