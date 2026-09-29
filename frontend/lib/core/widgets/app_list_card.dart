import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// A leading icon in a rounded, tinted square -- the "what kind of thing is
/// this row" glance every row in the list screens was missing (a bare
/// `ListTile` gives a workout, an activity and an exercise the exact same
/// silhouette; only the text tells them apart).
class AppIconAvatar extends StatelessWidget {
  const AppIconAvatar({super.key, required this.icon, this.color, this.background});

  final IconData icon;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background ?? scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Icon(icon, color: color ?? scheme.onPrimaryContainer, size: 22),
    );
  }
}

/// The card-based row every list screen (Workouts, Exercises, Activities)
/// now uses in place of a plain `ListTile` -- gives each entry a visible
/// boundary and enough room for a second line of detail (date, set count,
/// duration) instead of squeezing everything onto one.
class AppListCard extends StatelessWidget {
  const AppListCard({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final Widget leading;
  final String title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              leading,
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: DefaultTextStyle.merge(
                          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                          child: subtitle!,
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: AppSpacing.sm), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}
