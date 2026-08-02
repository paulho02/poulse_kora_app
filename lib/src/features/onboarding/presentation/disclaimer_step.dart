import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';

List<(IconData, String)> _points(AppLocalizations l10n) => [
  (Icons.public, l10n.onboardingDisclaimerPoint1),
  (Icons.favorite_border, l10n.onboardingDisclaimerPoint2),
  (Icons.forward_outlined, l10n.onboardingDisclaimerPoint3),
  (Icons.lock_outline, l10n.onboardingDisclaimerPoint4),
  (Icons.gpp_maybe_outlined, l10n.onboardingDisclaimerPoint5),
];

/// The onboarding flow's third and final, mandatory step. Confirmed with a
/// single "Got it!" button — there is no way to dismiss it unread.
class DisclaimerStep extends StatelessWidget {
  const DisclaimerStep({
    super.key,
    required this.onConfirm,
    required this.isSubmitting,
  });

  final VoidCallback onConfirm;
  final bool isSubmitting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final points = _points(l10n);

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 40,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.onboardingDisclaimerTitle,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              itemCount: points.length,
              separatorBuilder: (context, _) => const SizedBox(height: 18),
              itemBuilder: (context, i) {
                final (icon, text) = points[i];
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      icon,
                      size: 22,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(text, style: theme.textTheme.bodyLarge),
                    ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: isSubmitting ? null : onConfirm,
                child: isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.onboardingDisclaimerConfirm),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
