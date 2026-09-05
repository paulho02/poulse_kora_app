import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../application/economy_providers.dart';
import '../data/economy.dart';
import 'economy_explainer_sheet.dart';

/// Which screen the pill is on — and therefore which single number it states.
enum EconomyBarVariant {
  /// Earning. The balance, with the bar filling toward the price of a post.
  feed,

  /// Spending. What *this* post costs.
  composer,
}

/// The token economy, compressed into one tappable pill that lives in the app
/// bar.
///
/// It used to be a full-width bar stacked under the app bar on both screens: a
/// whole row of chrome restating a number that changes a few times an hour, on
/// the two screens with the least room to spare — the feed, where every pixel
/// is a post card, and the composer, where it is the text being written. The
/// pill keeps the one fact each screen acts on and gives the row back. The
/// progress bar survives the move because it is what makes the price
/// unnecessary as a number: a full bar means "you can post".
///
/// Everything longer than a glyph is one tap away in
/// [showEconomyExplainerSheet], which is now also where the live numbers are
/// spelled out, since no bar states them any more.
class EconomyHeaderStatus extends ConsumerWidget {
  const EconomyHeaderStatus({
    super.key,
    this.variant = EconomyBarVariant.feed,
    this.priceOverride,
  });

  final EconomyBarVariant variant;

  /// The price of the channel being posted to, once one is chosen.
  ///
  /// `GET /posts/economy` quotes the *global* price — a reference rate, and the
  /// right number for the feed, which is about the balance rather than about
  /// any one channel. The composer is the opposite case: it is spending, into a
  /// named channel, and what it will actually be charged is that channel's own
  /// price (see the backend's `service.channel_prices`). Null until a channel
  /// is picked, when the global figure is the only honest answer available.
  final int? priceOverride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cached = ref.watch(economyProvider);
    if (cached == null) return const SizedBox.shrink();

    final price = priceOverride;
    final economy = price == null
        ? cached.data
        : cached.data.copyWith(postPrice: price);

    // `AppBar` lays its actions out with `CrossAxisAlignment.stretch`, which
    // would draw the pill as a toolbar-tall lozenge; the width factor keeps the
    // centring from claiming an unbounded row's whole width in return.
    return Center(
      widthFactor: 1,
      child: switch (variant) {
        EconomyBarVariant.feed => _FeedPill(economy: economy),
        EconomyBarVariant.composer => _ComposerPill(
          economy: economy,
          isStale: cached.isStale,
        ),
      },
    );
  }
}

/// Reviewing: "you have N tokens, and here's how close that is to a post."
class _FeedPill extends StatelessWidget {
  const _FeedPill({required this.economy});

  final Economy economy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final needed = (economy.postPrice - economy.tokenBalance).clamp(
      0,
      economy.postPrice,
    );

    // The sentence is the whole point of the bar next to it: "12" alone is a
    // score, "12 · 2 more tokens to post" is a thing to do.
    final label = economy.canAffordPost
        ? l10n.economyReadyToPost
        : l10n.economyTokensToGo(needed);

    return _EconomyPill(
      value: '${economy.tokenBalance}',
      label: label,
      progress: _progressFor(economy),
      tone: _PillTone.neutral,
      semanticsLabel: label,
    );
  }
}

/// Composing: what publishing this will cost, and how long that price holds.
///
/// The clause beside the price is the countdown, because the composer is the
/// one screen where the quote's window actually runs out — you sit in it for
/// minutes, writing. It is worded as the promise it is ("held for 4:32", not a
/// bare `4:32`): the price cannot move out from under a draft, and a naked
/// timer says the opposite. The clause gives way to "2 more needed" when the
/// balance can't cover the post at all, since how long an unaffordable price
/// holds is nobody's question.
///
/// Hence the state: a per-second tick to render the countdown, and a re-fetch
/// once it lapses. That re-fetch deliberately keeps retrying —
/// `EconomyNotifier.refresh` swallows connectivity failures, so a fire-once
/// attempt would leave an author who was briefly offline sitting on a price
/// nothing would ever update.
class _ComposerPill extends ConsumerStatefulWidget {
  const _ComposerPill({required this.economy, required this.isStale});

  final Economy economy;

  /// Read off disk after the network was unreachable — the price is then a
  /// remembered one and its countdown means nothing.
  final bool isStale;

  @override
  ConsumerState<_ComposerPill> createState() => _ComposerPillState();
}

class _ComposerPillState extends ConsumerState<_ComposerPill> {
  Timer? _timer;
  Duration _remaining = Duration.zero;
  DateTime? _lastRefreshAttempt;

  @override
  void initState() {
    super.initState();
    _remaining = _timeLeft();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    if (_isExpired) _maybeRefresh();
  }

  @override
  void didUpdateWidget(covariant _ComposerPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The perpetual timer below re-derives `_remaining` from the expiry every
    // tick, so nothing needs restarting here — this only avoids up to a 1s
    // stale flash right after a fetch lands.
    if (oldWidget.economy.postPriceExpiresAt !=
        widget.economy.postPriceExpiresAt) {
      setState(() => _remaining = _timeLeft());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  DateTime? get _expiresAt => widget.economy.postPriceExpiresAt;

  bool get _isExpired => _expiresAt != null && _remaining <= Duration.zero;

  Duration _timeLeft() {
    final expiresAt = _expiresAt;
    if (expiresAt == null) return Duration.zero;
    final left = expiresAt.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  void _tick() {
    if (!mounted) return;
    setState(() => _remaining = _timeLeft());
    if (_isExpired) _maybeRefresh();
  }

  /// Throttled rather than fire-once, for the offline case above.
  void _maybeRefresh() {
    final now = DateTime.now();
    if (_lastRefreshAttempt != null &&
        now.difference(_lastRefreshAttempt!) < const Duration(seconds: 5)) {
      return;
    }
    _lastRefreshAttempt = now;
    ref.read(economyProvider.notifier).refresh();
  }

  String _countdown() {
    final minutes = _remaining.inMinutes;
    final seconds = _remaining.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _label(AppLocalizations l10n) {
    final economy = widget.economy;
    if (!economy.canAffordPost) {
      final needed = (economy.postPrice - economy.tokenBalance).clamp(
        0,
        economy.postPrice,
      );
      return l10n.economyPillShort(needed);
    }
    if (_isExpired || widget.isStale) return l10n.economyPillCheckingPrice;
    // A quote cached before the backend sent an expiry has no window to state,
    // so it falls back to the other thing worth saying about the price.
    if (_expiresAt == null) {
      return l10n.economyPillOfBalance(economy.tokenBalance);
    }
    return l10n.economyPillHeldFor(_countdown());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final economy = widget.economy;
    final needed = (economy.postPrice - economy.tokenBalance).clamp(
      0,
      economy.postPrice,
    );

    return _EconomyPill(
      // A minus sign: the number is what this post takes off the balance, not
      // the balance itself.
      value: '−${economy.postPrice}',
      label: _label(l10n),
      progress: _progressFor(economy),
      tone: economy.canAffordPost ? _PillTone.neutral : _PillTone.short,
      // The full sentence the clause is shorthand for — it names the balance,
      // which the clause gives up in order to state the countdown.
      semanticsLabel: economy.canAffordPost
          ? l10n.economyComposerCost(economy.postPrice, economy.tokenBalance)
          : l10n.economyComposerShort(needed),
    );
  }
}

double _progressFor(Economy economy) => economy.postPrice <= 0
    ? 1.0
    : (economy.tokenBalance / economy.postPrice).clamp(0.0, 1.0);

/// How much of the screen the pill's sentence may claim, leaving room for the
/// screen title on its left and the reload button on its right. Bounded at both
/// ends: a phone in German shouldn't ellipsize at the third word, and a tablet
/// shouldn't hand one clause half the toolbar.
double _labelCap(BuildContext context) =>
    (MediaQuery.sizeOf(context).width * 0.42).clamp(96.0, 200.0);

enum _PillTone { neutral, short }

/// A number, the line that says what it means, and a bar — sized to sit among
/// an app bar's actions.
///
/// The label is width-capped against the screen rather than left to wrap or
/// overflow: app bar actions are laid out with unbounded width, so nothing
/// downstream would stop a long translation from pushing the title off the
/// left edge. Capped, the worst case is an ellipsis with the full sentence
/// still on the tooltip.
class _EconomyPill extends StatelessWidget {
  const _EconomyPill({
    required this.value,
    required this.label,
    required this.progress,
    required this.tone,
    required this.semanticsLabel,
  });

  final String value;

  /// The short line beside [value] — one clause, never a paragraph.
  final String label;

  final double progress;
  final _PillTone tone;

  /// The sentence the pill is shorthand for — a tooltip on a long press, and
  /// what a screen reader announces instead of a bare digit.
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isShort = tone == _PillTone.short;
    final background = isShort
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.surfaceContainerHigh;
    final foreground = isShort
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onSurface;
    final accent = isShort
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.primary;

    return Tooltip(
      message: semanticsLabel,
      child: Semantics(
        button: true,
        label: semanticsLabel,
        excludeSemantics: true,
        child: Material(
          color: background,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => showEconomyExplainerSheet(context),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 5, 12, 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.toll_outlined, size: 16, color: accent),
                  const SizedBox(width: 6),
                  // Intrinsic width so the bar spans exactly the line above it
                  // — a fixed width would either clip the sentence or leave the
                  // bar floating short of it.
                  IntrinsicWidth(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          textBaseline: TextBaseline.alphabetic,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          children: [
                            Text(
                              value,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: foreground,
                                fontWeight: FontWeight.w700,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(width: 6),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: _labelCap(context),
                              ),
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: isShort
                                      ? foreground
                                      : theme.colorScheme.onSurfaceVariant,
                                  height: 1.1,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 3,
                            color: accent,
                            backgroundColor: isShort
                                ? theme.colorScheme.onErrorContainer.withValues(
                                    alpha: 0.25,
                                  )
                                : theme.colorScheme.outlineVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
