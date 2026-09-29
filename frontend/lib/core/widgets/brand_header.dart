import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// The app's mark and wordmark (`assets/branding/`), used above the
/// login/register forms in place of a generic icon-in-a-circle -- these are
/// the actual logo assets, not a theme-tinted placeholder, so they're kept
/// as fixed-color raster images rather than drawn with `Icon`/`Text`.
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Image.asset('assets/branding/icon.png', width: 72, height: 72),
        ),
        const SizedBox(height: AppSpacing.lg),
        Image.asset('assets/branding/wordmark.png', height: 36),
      ],
    );
  }
}
