import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/presentation/slide_up_route.dart';
import '../../stats/presentation/trust_explainer.dart';

/// What the ways of forwarding do, in full sentences — opened from the last row
/// of the expanded Forward button, whose segments are one line each and so have
/// no room to explain themselves.
///
/// The same shape as `trust_explainer.dart` and `economy_explainer.dart`: a
/// full-screen [slideUpRoute], a title, a short list of points. One point per
/// forward variant, then what every variant shares (anonymity, reach). A new
/// variant on the button gets its point here.
Future<void> showForwardingExplainer(BuildContext context) {
  return Navigator.of(context).push<void>(
    slideUpRoute(builder: (context) => const _ForwardingExplainerPage()),
  );
}

class _ForwardingExplainerPage extends StatelessWidget {
  const _ForwardingExplainerPage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SlideDownDismissHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.forwardingExplainerTitle,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: l10n.commonClose,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Point(
                      icon: Icons.arrow_forward,
                      title: l10n.postForward,
                      text: l10n.forwardingExplainerForward,
                    ),
                    _Point(
                      icon: Icons.card_giftcard,
                      title: l10n.postForwardAndGift,
                      text: l10n.forwardingExplainerGift,
                    ),
                    _Point(
                      icon: Icons.visibility_off_outlined,
                      text: l10n.forwardingExplainerAnonymous,
                    ),
                    _Point(
                      icon: Icons.block,
                      text: l10n.forwardingExplainerNotAlways,
                    ),
                    _Point(
                      icon: Icons.podcasts_outlined,
                      text: l10n.forwardingExplainerReach,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 24),
                      child: TextButton(
                        onPressed: () => showTrustExplainer(context),
                        child: Text(l10n.trustExplainerTitle),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text, this.title});

  final IconData icon;
  final String? title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(text, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
