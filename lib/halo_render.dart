// HaloRenderView — shows the baked render of a HaloAppearance (spec §3
// P4). One master, baked renders, no real-time 3D (Render Rule, Nov 14).
//
// Framing: portrait shows the bust bake (Home tab — top half only,
// Slice 1); fullBody shows the three-quarter bake (Creator tab). The
// default look plays the baked idle loop (40 frames at 8 fps, a 5 s
// breathe/settle cycle, P2); on the Home tab the full-body idle frame
// is cropped to its top half so tab 1 still never shows a full body.
// Any non-default look is a still — see resolveHaloDisplay for the v1
// one-axis-at-a-time display rule. Reduced motion
// (MediaQuery.disableAnimations) stills the loop on frame 1.
//
// If an asset fails to load, [fallback] (the code-drawn stage hero)
// takes the panel — a missing bake must never blank the Halo.
// widgets.dart, not material.dart: this file needs no Material
// widgets, and under the local 3.50 SDK every material.dart import
// adds a split-package deprecation info (the repo pins 3.47.9, where
// it does not exist — but new files keep the local analyze clean).
import 'package:flutter/widgets.dart';

import 'halo_appearance.dart';

enum HaloFraming { portrait, fullBody }

class HaloRenderView extends StatefulWidget {
  const HaloRenderView({
    super.key,
    required this.appearance,
    required this.framing,
    required this.crownEquipped,
    required this.fallback,
  });

  final HaloAppearance appearance;
  final HaloFraming framing;

  /// True when the profile's cosmetics carry head_socket_crown: the
  /// crown pack's sprite is overlaid at the head (see _crownPlacement).
  final bool crownEquipped;

  /// Shown in place of any render that fails to load.
  final Widget fallback;

  @override
  State<HaloRenderView> createState() => _HaloRenderViewState();
}

class _HaloRenderViewState extends State<HaloRenderView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5), // 40 frames at 8 fps
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(HaloRenderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appearance != widget.appearance) _syncAnimation();
  }

  void _syncAnimation() {
    final idle = resolveHaloDisplay(widget.appearance).isIdle;
    if (idle && !MediaQuery.of(context).disableAnimations) {
      if (!_ctrl.isAnimating) _ctrl.repeat();
    } else {
      _ctrl.stop();
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _imgError(BuildContext context, Object error, StackTrace? stack) =>
      Center(child: widget.fallback);

  @override
  Widget build(BuildContext context) {
    final display = resolveHaloDisplay(widget.appearance);
    // Portrait framing only applies to stills: the idle frames are
    // three-quarter full-body bakes, shown top-cropped instead.
    final portraitStill =
        widget.framing == HaloFraming.portrait && !display.isIdle;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cropped =
            widget.framing == HaloFraming.portrait && display.isIdle;
        final h = cropped ? w * 0.66 : w;
        return ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            width: w,
            height: h,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  width: w,
                  height: w,
                  child: _canvas(display, w, portraitStill),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _canvas(HaloDisplay display, double w, bool portraitStill) {
    final Widget img;
    if (display.isIdle) {
      img = AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final frame =
              (_ctrl.value * kHaloIdleFrames).floor().clamp(0, kHaloIdleFrames - 1) + 1;
          return Image.asset(
            haloIdleAsset(widget.appearance.baseModel, frame),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: _imgError,
          );
        },
      );
    } else {
      img = Image.asset(
        haloStillAsset(display.stem!, portrait: portraitStill),
        fit: BoxFit.cover,
        errorBuilder: _imgError,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        img,
        if (widget.crownEquipped) _crown(w, portraitStill),
      ],
    );
  }

  /// The crown overlay. Placement was tuned by compositing the pack
  /// sprite over the bakes and reading the composites back (pipeline
  /// workspace, Nov 16): fractions of the square bake canvas —
  /// (centre x, band bottom y, width). The portrait bakes are FRONT
  /// views, so they take the pack's front sprite; the three-quarter
  /// bakes (and idle frames) take the three-quarter sprite. Both
  /// shipped sprites are pre-trimmed to their alpha bounding box, so
  /// the fractions describe the crown itself, not its canvas.
  Widget _crown(double w, bool portraitStill) {
    final (cx, band, widthFrac) =
        _crownPlacement(widget.appearance.baseModel, portraitStill);
    final cw = widthFrac * w;
    final ch = cw * 0.852; // trimmed sprite aspect (h/w), both views
    return Positioned(
      left: cx * w - cw / 2,
      top: band * w - ch,
      width: cw,
      height: ch,
      child: Image.asset(
        portraitStill
            ? 'assets/halo/crown_front.png'
            : 'assets/halo/crown_tq.png',
        key: const Key('halo_render_crown'),
        fit: BoxFit.fill,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
  }

  (double, double, double) _crownPlacement(String model, bool portrait) {
    if (portrait) {
      return model == 'female'
          ? (0.500, 0.355, 0.303)
          : (0.500, 0.328, 0.371);
    }
    return model == 'female'
        ? (0.475, 0.105, 0.121)
        : (0.504, 0.113, 0.125);
  }
}
