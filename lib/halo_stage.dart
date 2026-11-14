// HaloStage — Slice A of the LPE creator-screen redesign (brief:
// lpe-creator-screen-visual-brief.md). The hero stage where a person meets
// their Halo: a big portrait disc in their color, an elliptical halo ring
// above it that breathes on a slow cycle, an ambient gradient room tinted by
// the seed color, and a curated swatch row that re-tints the whole app live
// (the "theme wash"). The seed color is the person's favorite color — local
// to this phone for now; it later becomes the private-layer field that
// themes every Omni app through Omni-Core-UI.
import 'package:flutter/material.dart';

/// The app-local theme seed store key and its default (a deep violet-blue —
/// the night the first Halo was sealed).
const String kHaloColorKey = 'lpe_favorite_color';
const Color kDefaultHaloColor = Color(0xFF6C4DF6);

/// Curated swatches (brief section 8: a swatch ring first, full wheel later).
const List<(String, Color)> kHaloSwatches = [
  ('Violet', Color(0xFF6C4DF6)),
  ('Sky', Color(0xFF2979FF)),
  ('Teal', Color(0xFF00BFA5)),
  ('Moss', Color(0xFF43A047)),
  ('Amber', Color(0xFFFFAB00)),
  ('Ember', Color(0xFFFF6D00)),
  ('Rose', Color(0xFFF500A5)),
  ('Crimson', Color(0xFFE53935)),
];

ThemeData haloTheme(Color seed) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    );

/// A soft darkening of [c] for gradient depth.
Color haloShade(Color c, double f) => Color.fromARGB(
      c.alpha,
      (c.red * f).round(),
      (c.green * f).round(),
      (c.blue * f).round(),
    );

class HaloStage extends StatelessWidget {
  const HaloStage({
    super.key,
    required this.seed,
    required this.handle,
    required this.signName,
    required this.signGlyph,
    required this.onColorPicked,
    this.cosmetics = const [],
  });

  final Color seed;
  final String handle;
  final String signName;
  final String signGlyph;
  final ValueChanged<Color> onColorPicked;

  /// Equipped cosmetic item ids from the profile (e.g.
  /// 'head_socket_crown'). The stage renders the ones it knows,
  /// from the id — the profile carries ids, apps render them.
  final List<String> cosmetics;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            haloShade(seed, 0.55),
            haloShade(seed, 0.22),
            const Color(0xFF101018),
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BreathingHalo(seed: seed, glyph: signGlyph, cosmetics: cosmetics),
          const SizedBox(height: 14),
          Text(
            handle,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Chip(
            avatar: Text(signGlyph),
            label: Text(signName),
            backgroundColor: seed.withOpacity(0.25),
            side: BorderSide(color: seed.withOpacity(0.6)),
          ),
          const SizedBox(height: 18),
          Text(
            'YOUR COLOR',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 2.2,
                  color: Colors.white70,
                ),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final s in kHaloSwatches)
                _SwatchDot(
                  color: s.$2,
                  name: s.$1,
                  selected: s.$2.value == seed.value,
                  onTap: () => onColorPicked(s.$2),
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Pick your color — the whole room follows. It lives on this '
            'phone; your apps will wear it.',
            style: TextStyle(fontSize: 12, color: Colors.white60),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SwatchDot extends StatelessWidget {
  const _SwatchDot({
    required this.color,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: name,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(
              color: selected ? Colors.white : Colors.white24,
              width: selected ? 2.5 : 1,
            ),
            boxShadow: selected
                ? [BoxShadow(color: color.withOpacity(0.7), blurRadius: 14)]
                : null,
          ),
          child: selected
              ? const Icon(Icons.check, size: 18, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}

/// The portrait disc with the elliptical halo ring floating above it. The
/// ring breathes — a slow scale + opacity cycle (4s) — and stills itself
/// when the system asks for reduced motion.
class _BreathingHalo extends StatefulWidget {
  const _BreathingHalo(
      {required this.seed, required this.glyph, required this.cosmetics});

  final Color seed;
  final String glyph;
  final List<String> cosmetics;

  @override
  State<_BreathingHalo> createState() => _BreathingHaloState();
}

class _BreathingHaloState extends State<_BreathingHalo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _ctrl.stop();
      _ctrl.value = 0.35;
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      height: 178,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = Curves.easeInOut.transform(_ctrl.value);
          return Stack(
            alignment: Alignment.topCenter,
            children: [
              // The ring — a flattened ellipse above the portrait.
              Transform.translate(
                offset: Offset(0, 6 - 4 * t),
                child: Transform.scale(
                  scale: 0.97 + 0.05 * t,
                  child: Container(
                    width: 118,
                    height: 30,
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.all(
                          Radius.elliptical(59, 15)),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.55 + 0.4 * t),
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: widget.seed.withOpacity(0.35 + 0.3 * t),
                          blurRadius: 18 + 10 * t,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // The portrait disc.
              Positioned(
                top: 34,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeInOut,
                  width: 132,
                  height: 132,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        haloShade(widget.seed, 0.95),
                        haloShade(widget.seed, 0.55),
                      ],
                    ),
                    border:
                        Border.all(color: Colors.white.withOpacity(0.35)),
                    boxShadow: [
                      BoxShadow(
                        color: widget.seed.withOpacity(0.45),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      widget.glyph,
                      style:
                          const TextStyle(fontSize: 62, color: Colors.white),
                    ),
                  ),
                ),
              ),
              // Equipped head-socket cosmetic: the crown, worn on the
              // portrait disc under the floating ring.
              if (widget.cosmetics.contains('head_socket_crown'))
                Positioned(
                  top: 23,
                  child: Transform.rotate(
                    angle: -0.05,
                    child: CustomPaint(
                      key: const Key('cosmetic_head_socket_crown'),
                      size: const Size(80, 46),
                      painter: CrownPainter(gemColor: widget.seed),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Paints the reference head-socket cosmetic — the crown from the
/// signed pack omnimod.base.crown-01 (item head_socket_crown).
/// Code-drawn from the cosmetic id, the way Plaza-Brawler paints
/// fighter layers from their asset ids: the profile carries the id,
/// the app renders it. The centre gem wears the person's own colour.
class CrownPainter extends CustomPainter {
  const CrownPainter({required this.gemColor});

  final Color gemColor;

  static const Color _gold = Color(0xFFE3B341);
  static const Color _goldDark = Color(0xFFA8740A);
  static const Color _goldLight = Color(0xFFF6D47A);
  static const Color _teal = Color(0xFF35C4B5);
  static const Color _rose = Color(0xFFF2547D);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final cx = w / 2;

    Path triangle(double centerX, double halfWidth, double base, double tip) =>
        Path()
          ..moveTo(centerX - halfWidth, base)
          ..lineTo(centerX, tip)
          ..lineTo(centerX + halfWidth, base)
          ..close();

    // Points, behind the band: centre tallest, sides shorter.
    final points = Path()
      ..addPath(triangle(cx, 12, 32, 6), Offset.zero)
      ..addPath(triangle(cx - 24, 9.5, 32, 13), Offset.zero)
      ..addPath(triangle(cx + 24, 9.5, 32, 13), Offset.zero);
    canvas.drawPath(points, Paint()..color = _gold);
    canvas.drawPath(
        points,
        Paint()
          ..color = _goldDark
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..strokeJoin = StrokeJoin.round);

    // Orb tips on the three points.
    final orb = Paint()..color = _goldLight;
    canvas.drawCircle(Offset(cx, 6.5), 3.4, orb);
    canvas.drawCircle(Offset(cx - 24, 13.5), 2.7, orb);
    canvas.drawCircle(Offset(cx + 24, 13.5), 2.7, orb);

    // The band: a shallow trapezoid, wider at the base, with a lit
    // top rim and a shaded foot.
    final band = Path()
      ..moveTo(9, 30)
      ..lineTo(w - 9, 30)
      ..lineTo(w - 5, 44)
      ..quadraticBezierTo(w - 5, 46, w - 9, 46)
      ..lineTo(9, 46)
      ..quadraticBezierTo(5, 46, 5, 44)
      ..close();
    canvas.drawPath(band, Paint()..color = _gold);
    canvas.drawPath(
        band,
        Paint()
          ..color = _goldDark
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..strokeJoin = StrokeJoin.round);
    final foot = Path()
      ..moveTo(6.2, 41.5)
      ..lineTo(w - 6.2, 41.5)
      ..lineTo(w - 5, 44)
      ..quadraticBezierTo(w - 5, 46, w - 9, 46)
      ..lineTo(9, 46)
      ..quadraticBezierTo(5, 46, 5, 44)
      ..close();
    canvas.drawPath(foot, Paint()..color = _goldDark.withOpacity(0.55));
    canvas.drawLine(const Offset(10, 31.2), Offset(w - 10, 31.2),
        Paint()..color = _goldLight..strokeWidth = 1.6);

    // Gems: the centre stone is a diamond in the person's colour,
    // flanked by teal and rose.
    final gem = Path()
      ..moveTo(cx, 31.5)
      ..lineTo(cx + 5.5, 37)
      ..lineTo(cx, 42.5)
      ..lineTo(cx - 5.5, 37)
      ..close();
    canvas.drawPath(gem, Paint()..color = gemColor);
    canvas.drawCircle(Offset(cx - 1.6, 35.2), 1.1,
        Paint()..color = Colors.white.withOpacity(0.85));
    canvas.drawCircle(Offset(cx - 21, 37), 3.1, Paint()..color = _teal);
    canvas.drawCircle(Offset(cx + 21, 37), 3.1, Paint()..color = _rose);
  }

  @override
  bool shouldRepaint(CrownPainter oldDelegate) =>
      oldDelegate.gemColor != gemColor;
}
