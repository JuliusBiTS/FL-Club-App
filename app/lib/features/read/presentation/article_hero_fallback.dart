import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';

/// What an article shows in place of a photo: the club's own logo on its
/// brand background, so a post that hasn't had an image added yet still
/// looks deliberate rather than broken — feedback: "make sure every blog
/// post has a pic, even if its a FC logo placeholder." Mirrors
/// EventHeroFallback's job for events, just with the literal logo instead
/// of a category icon, since an article has no equivalent category set.
class ArticleHeroFallback extends StatelessWidget {
  const ArticleHeroFallback({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: FlcColors.brand,
      child: Padding(
        padding: const EdgeInsets.all(FlcSpace.xl),
        child: Center(
          child: Image.asset(
            'assets/images/brand/app_icon_source.png',
            fit: BoxFit.contain,
            errorBuilder: (BuildContext c, Object e, StackTrace? s) => const Icon(Icons.article_outlined, color: Colors.white54, size: 48),
          ),
        ),
      ),
    );
  }
}
