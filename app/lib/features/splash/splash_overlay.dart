import 'dart:math' as math;

import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';

/// The boot animation: the club's logo flips over into the strapline "The
/// championing independent journalism" in Jost, then fades out onto the real
/// app underneath. Drawn as an overlay via MaterialApp.router's `builder`
/// (see app.dart), rather than a separate route, so it sits on top of
/// whatever the router is already doing underneath and needs no special
/// handling to "navigate away from" — it simply removes itself.
class SplashOverlay extends StatefulWidget {
  const SplashOverlay({required this.onFinished, super.key});

  final VoidCallback onFinished;

  @override
  State<SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends State<SplashOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000));

  // Logo shown 0-35%, flips over 35-65%, text holds 65-85%, everything
  // fades 85-100% — one controller driving every stage, nothing to
  // coordinate by hand.
  late final Animation<double> _flip = CurvedAnimation(parent: _controller, curve: const Interval(0.35, 0.65, curve: Curves.easeInOutCubic));
  late final Animation<double> _fadeOut = CurvedAnimation(parent: _controller, curve: const Interval(0.85, 1.0, curve: Curves.easeIn));

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(widget.onFinished);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      // Blocks nothing once fully faded, but stays interactive-proof while
      // any part of the animation is still visible.
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? _) {
          if (_controller.isCompleted) return const SizedBox.shrink();

          final bool showingText = _flip.value >= 0.5;
          final Matrix4 transform = Matrix4.identity()
            ..setEntry(3, 2, 0.0018) // perspective
            ..rotateY(_flip.value * math.pi);

          return Opacity(
            opacity: 1 - _fadeOut.value,
            child: ColoredBox(
              color: FlcColors.brand,
              child: Center(
                child: Transform(
                  alignment: Alignment.center,
                  transform: transform,
                  child: showingText
                      // Counter-rotated so the text reads the right way round
                      // once the flip has passed the halfway point — the
                      // standard "card flip" trick.
                      ? Transform(alignment: Alignment.center, transform: Matrix4.identity()..rotateY(math.pi), child: const _TextFace())
                      : const _LogoFace(),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LogoFace extends StatelessWidget {
  const _LogoFace();

  @override
  Widget build(BuildContext context) {
    // The source wordmark is already on the exact brand-olive background
    // (no transparency needed) and wide — roughly 2.5:1, not square.
    return SizedBox(
      width: 260,
      child: AspectRatio(
        aspectRatio: 2.48,
        child: Image.asset(
          'assets/images/brand/frontline_logo.jpg',
          fit: BoxFit.contain,
          errorBuilder: (BuildContext c, Object e, StackTrace? s) => const Icon(Icons.menu_book_outlined, size: 96, color: Colors.white),
        ),
      ),
    );
  }
}

class _TextFace extends StatelessWidget {
  const _TextFace();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: FlcSpace.lg),
      child: Text(
        'CHAMPIONING\nINDEPENDENT JOURNALISM',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Jost',
          fontWeight: FontWeight.w600,
          fontSize: 25,
          height: 1.4,
          letterSpacing: 1.6,
          color: Colors.white,
          decoration: TextDecoration.none, // explicit: no underline, whatever the ambient style is
        ),
      ),
    );
  }
}
