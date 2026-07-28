import 'package:flutter/material.dart';

const _points = [
  (
    Icons.public,
    'Posts are public — anything you publish can be forwarded on to any other '
        'user on the platform.',
  ),
  (
    Icons.favorite_border,
    'Act responsibly. No misinformation, hate speech, harassment, or illegal '
        'content.',
  ),
  (
    Icons.forward_outlined,
    "Once forwarded, a post is out of your control — deleting it doesn't undo "
        "what's already spread.",
  ),
  (
    Icons.lock_outline,
    "Don't share other people's private information without their consent.",
  ),
  (
    Icons.gpp_maybe_outlined,
    'Violating these guidelines can get your account suspended.',
  ),
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
                  'Before you dive in',
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
              itemCount: _points.length,
              separatorBuilder: (context, _) => const SizedBox(height: 18),
              itemBuilder: (context, i) {
                final (icon, text) = _points[i];
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
                    : const Text('Got it!'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
