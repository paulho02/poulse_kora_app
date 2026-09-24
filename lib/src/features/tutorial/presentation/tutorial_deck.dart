import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import 'tutorial_illustrations.dart';

/// One chapter: an animated drawing, a claim, and the paragraph behind it.
class _Chapter {
  const _Chapter({required this.title, required this.body});

  final String title;
  final String body;
}

/// The five chapters, in the order the idea only makes sense in.
///
/// Each one is a *consequence* of the one before it, which is why they are a
/// deck rather than a list of features: a post travels by hand (1), so no
/// ranking model is involved (2), so the decision is yours (3), which is
/// worth something and therefore priced (4), and the result is a feed that is
/// finite (5). Chapter 5 exists because a feed that runs dry is the single
/// most confusing thing about Peerkola for anyone arriving from an infinite
/// scroll — it looks broken, and it isn't.
List<_Chapter> _chapters(AppLocalizations l10n) => [
  _Chapter(
    title: l10n.tutorialChapter1Title,
    body: l10n.tutorialChapter1Body,
  ),
  _Chapter(
    title: l10n.tutorialChapter2Title,
    body: l10n.tutorialChapter2Body,
  ),
  _Chapter(
    title: l10n.tutorialChapter3Title,
    body: l10n.tutorialChapter3Body,
  ),
  _Chapter(
    title: l10n.tutorialChapter4Title,
    body: l10n.tutorialChapter4Body,
  ),
  _Chapter(
    title: l10n.tutorialChapter5Title,
    body: l10n.tutorialChapter5Body,
  ),
];

/// How many chapters the deck has, for anything that wants to say so before
/// building it.
int tutorialChapterCount(AppLocalizations l10n) => _chapters(l10n).length;

/// The "How Peerkola works" deck — the one place the concept is explained at
/// length, as opposed to the onboarding intro slides (three sentences, shown
/// to everyone) and `showEconomyExplainerSheet` (the token model only, opened
/// from a pill).
///
/// It is a widget rather than only a route because it has to run **inside**
/// the onboarding flow as well as on its own: `/onboarding` is redirect-owned,
/// so a route pushed from it while `onboardingCompleted` is still false would
/// be bounced straight back by `app_router.dart`'s gate chain. Onboarding
/// embeds this; [TutorialScreen] wraps it for Settings.
///
/// Note for tests: the visible chapter's illustration animates forever, so
/// `pumpAndSettle` on this widget times out. Use `pump(duration)`.
class TutorialDeck extends StatefulWidget {
  const TutorialDeck({
    super.key,
    required this.onFinish,
    this.onSkip,
    this.footnote,
  });

  /// Called when the last chapter is confirmed.
  final VoidCallback onFinish;

  /// Called by the "skip" affordance. When null there is none — the Settings
  /// route has an app bar with a back button, and a second way out one line
  /// under it would just be noise.
  final VoidCallback? onSkip;

  /// An optional line above the buttons on the last chapter. Onboarding puts
  /// the "you can watch this again from Settings" hint here, where it is read
  /// by exactly the people who have just finished and might want it later.
  final String? footnote;

  @override
  State<TutorialDeck> createState() => _TutorialDeckState();
}

class _TutorialDeckState extends State<TutorialDeck> {
  final _controller = PageController();
  var _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int delta, int count) {
    final target = _index + delta;
    if (target >= count) {
      widget.onFinish();
      return;
    }
    if (target < 0) return;
    _controller.animateToPage(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final chapters = _chapters(l10n);
    final accent = theme.brightness == Brightness.dark
        ? AppColors.accentDark
        : AppColors.accentLight;
    final isLast = _index == chapters.length - 1;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
            child: Row(
              children: [
                Text(
                  l10n.tutorialStepCounter(_index + 1, chapters.length),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (widget.onSkip != null)
                  TextButton(
                    onPressed: widget.onSkip,
                    child: Text(l10n.tutorialSkip),
                  ),
              ],
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: chapters.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => _ChapterPage(
                chapter: chapters[i],
                index: i,
                // Only the page on screen animates — a `PageView` builds its
                // neighbours, so without this three controllers tick for one
                // visible drawing.
                active: i == _index,
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              chapters.length,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: i == _index ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i == _index ? accent : theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          if (widget.footnote != null && isLast)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Text(
                widget.footnote!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
            child: Row(
              children: [
                // Kept in the layout while it does nothing, so the primary
                // button doesn't shift sideways between the first chapter and
                // the second.
                SizedBox(
                  width: 88,
                  child: _index == 0
                      ? const SizedBox.shrink()
                      : TextButton(
                          onPressed: () => _go(-1, chapters.length),
                          child: Text(l10n.tutorialBack),
                        ),
                ),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _go(1, chapters.length),
                    child: Text(
                      isLast ? l10n.tutorialDone : l10n.tutorialNext,
                    ),
                  ),
                ),
                const SizedBox(width: 88),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChapterPage extends StatelessWidget {
  const _ChapterPage({
    required this.chapter,
    required this.index,
    required this.active,
  });

  final _Chapter chapter;
  final int index;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // The drawing takes a share of what is left rather than a fixed
        // height: at the reader's largest text size the paragraph needs the
        // room more than the diagram does, and a hard 240 would push the
        // buttons off a small screen.
        final artHeight = (constraints.maxHeight * 0.40).clamp(140.0, 260.0);
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
          child: ConstrainedBox(
            // Centred when it fits, scrollable when it doesn't.
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: artHeight,
                  child: TutorialIllustration(chapter: index, active: active),
                ),
                const SizedBox(height: 28),
                Text(
                  chapter.title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  chapter.body,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The deck as a standalone route (`/tutorial`), reached from
/// Settings → How Peerkola works. The app bar's back button is the way out, so
/// the deck gets no skip of its own.
class TutorialScreen extends StatelessWidget {
  const TutorialScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tutorialTitle)),
      body: TutorialDeck(onFinish: () => Navigator.of(context).pop()),
    );
  }
}
