import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/presentation/error_state_view.dart';
import '../../../core/presentation/slide_up_route.dart';
import '../application/feed_providers.dart';
import '../data/feed_repository.dart' show PostReviewResult;
import '../data/post.dart';
import 'forward_score_badge.dart';
import 'probe_result_badge.dart';
import 'post_detail_scaffold.dart';

/// Opens a post for review, full screen.
///
/// Was a `showModalBottomSheet` + `DraggableScrollableSheet`: the motion was
/// right but the size never was, since a sheet tops out short of the screen and
/// keeps a barrier and rounded corners over the top of whatever photo or video
/// the post is actually about. [slideUpRoute] keeps the slide-from-bottom and
/// gives the post the whole screen.
void showPostDetail(BuildContext context, WidgetRef ref, Post post) {
  Navigator.of(context)
      .push(slideUpRoute<void>(builder: (_) => _PostDetailPage(post: post)))
      .whenComplete(() => ref.read(expandedPostIdProvider.notifier).set(null));
}

class _PostDetailPage extends ConsumerStatefulWidget {
  const _PostDetailPage({required this.post});

  final Post post;

  @override
  ConsumerState<_PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends ConsumerState<_PostDetailPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scorePop = AnimationController(
    vsync: this,
    duration: kForwardScorePopIn,
  );

  bool _leaving = false;
  int? _score;

  /// See the same pair in `post_card.dart`: a trust check reveals whether it
  /// was answered correctly, where an ordinary post reveals its score.
  bool _wasProbe = false;
  bool? _probeCorrect;

  @override
  void dispose() {
    _scorePop.dispose();
    super.dispose();
  }

  /// Reviews, shows the score, then closes.
  ///
  /// This used to pop first and review afterwards, which is a beat this page no
  /// longer has anywhere to put the score into. So the order is inverted: the
  /// page stays up until the server confirms, which also means a *failed*
  /// review now leaves the reader on the post they were trying to act on
  /// instead of dropping them back on the feed with a snackbar.
  Future<void> _review(String kind) async {
    if (_leaving) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);

    setState(() => _leaving = true);

    final PostReviewResult result;
    try {
      result = await ref
          .read(feedNotifierProvider.notifier)
          .reviewPost(widget.post.id, kind);
    } catch (error) {
      showErrorSnackBarOn(messenger, l10n, error);
      if (!mounted) return;
      setState(() => _leaving = false);
      return;
    }

    if (!mounted) return;
    setState(() {
      _wasProbe = result.isProbe;
      _probeCorrect = result.probeCorrect;
      _score = result.isProbe ? null : result.postForwardedCount;
    });
    await _scorePop.forward();
    await Future<void>.delayed(kForwardScoreHold);
    if (!mounted) return;
    // The page slides away as the exit animation, so the removal is committed
    // after the pop rather than sequenced around one of this page's own.
    navigator.pop();
    ref
        .read(feedNotifierProvider.notifier)
        .applyReviewResult(widget.post.id, result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final post = widget.post;
    final hoursLeft = post.timeRemaining.inHours;
    final postedAgo = post.timeAgo == 'now'
        ? l10n.postJustNow
        : l10n.postTimeAgoSuffix(post.timeAgo);

    return Stack(
      children: [
        // Sealed once a review is in flight, which the disabled footer buttons
        // alone do not do: the scaffold's own close button would otherwise pop
        // the page during the score's beat, and the removal this method still
        // owes the feed would go with it — leaving a post that is reviewed
        // server-side but still on the list, good for one 409 and nothing else.
        AbsorbPointer(
          absorbing: _leaving,
          child: PostDetailScaffold(
            post: post,
            metaLine:
                '${post.channelName} · ${l10n.postDetailPostedAgo(postedAgo)} · '
                '${l10n.postDetailHoursLeft(hoursLeft)}',
            progress: post.deadlineProgress,
            footer: Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _leaving ? null : () => _review('drop'),
                    icon: const Icon(Icons.close),
                    label: Text(l10n.postDrop),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _leaving ? null : () => _review('forward'),
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(l10n.postForward),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_wasProbe)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: ProbeResultBadge(
                  correct: _probeCorrect,
                  animation: _scorePop,
                ),
              ),
            ),
          )
        else if (_score != null)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: ForwardScoreBadge(count: _score!, animation: _scorePop),
              ),
            ),
          ),
      ],
    );
  }
}
