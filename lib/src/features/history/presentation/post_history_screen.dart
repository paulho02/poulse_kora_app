import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/presentation/error_state_view.dart';
import '../../feed/data/post.dart';
import '../application/history_providers.dart';
import '../data/reviewed_post.dart';
import 'history_post_detail_view.dart';

enum HistoryMode { posted, reviewed }

/// One post shown in the history list, normalized from either a plain [Post]
/// (posted mode, sorted by [Post.created]) or a [ReviewedPost] (reviewed
/// mode, sorted by the review's own timestamp) so the rest of the screen
/// doesn't need to branch on mode.
class _Entry {
  _Entry({required this.post, required this.date, this.kindLabel});

  final Post post;
  final DateTime date;
  final String? kindLabel;
}

class _HeaderItem {
  _HeaderItem(this.label);
  final String label;
}

DateTime _dayOf(DateTime d) {
  final local = d.toLocal();
  return DateTime(local.year, local.month, local.day);
}

List<_Entry> _entriesFromPosted(List<Post> posts) =>
    posts.map((p) => _Entry(post: p, date: p.created)).toList();

List<_Entry> _entriesFromReviewed(
  List<ReviewedPost> reviews,
  AppLocalizations l10n,
) => reviews
    .map(
      (r) => _Entry(
        post: r.post,
        date: r.reviewedAt,
        kindLabel: r.isForward
            ? l10n.historyReviewKindForward
            : l10n.historyReviewKindDrop,
      ),
    )
    .toList();

String _dateGroupLabel(DateTime day, AppLocalizations l10n, String localeName) {
  final todayDay = _dayOf(DateTime.now());
  final yesterdayDay = todayDay.subtract(const Duration(days: 1));
  if (day == todayDay) return l10n.historyDateToday;
  if (day == yesterdayDay) return l10n.historyDateYesterday;
  return DateFormat.yMMMMd(localeName).format(day);
}

/// Entries are already sorted newest-first by the backend; this just inserts
/// a header row whenever the calendar day changes.
List<Object> _buildRows(
  List<_Entry> entries,
  AppLocalizations l10n,
  String localeName,
) {
  final rows = <Object>[];
  DateTime? lastDay;
  for (final entry in entries) {
    final day = _dayOf(entry.date);
    if (lastDay == null || day != lastDay) {
      rows.add(_HeaderItem(_dateGroupLabel(day, l10n, localeName)));
      lastDay = day;
    }
    rows.add(entry);
  }
  return rows;
}

List<int> _computeMatches(List<Object> rows, String query) {
  if (query.isEmpty) return const [];
  final lowerQuery = query.toLowerCase();
  final matches = <int>[];
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    if (row is _Entry &&
        row.post.previewText.toLowerCase().contains(lowerQuery)) {
      matches.add(i);
    }
  }
  return matches;
}

class PostHistoryScreen extends ConsumerStatefulWidget {
  const PostHistoryScreen({super.key, required this.mode});

  final HistoryMode mode;

  @override
  ConsumerState<PostHistoryScreen> createState() => _PostHistoryScreenState();
}

class _PostHistoryScreenState extends ConsumerState<PostHistoryScreen> {
  final _itemScrollController = ItemScrollController();
  final _itemPositionsListener = ItemPositionsListener.create();
  final _searchController = TextEditingController();

  /// Lets the app bar's refresh button drive the *same* indicator a pull does,
  /// so both gestures produce one spinner in one place rather than the button
  /// inventing a second kind of loading state.
  final _refreshKey = GlobalKey<RefreshIndicatorState>();

  bool _searchActive = false;
  String _query = '';
  int _currentMatchPointer = -1;
  bool _isBusyLoading = false;

  // Guards against the bug that caused ANRs: with no debounce, every
  // keystroke queued its own `_goToMatch` call. Two of those running at once
  // could busy-spin each other — the second call's `_pager.loadMore()`
  // returns instantly (a no-op, since the notifier is already mid-fetch)
  // while the first's real fetch is still in flight, so its `while (true)`
  // loop kept re-checking with no actual yield to the frame scheduler in
  // between. `_searchBusy` keeps only one `_goToMatch` running at a time;
  // the debounce timer below keeps typing from queuing one per character.
  bool _searchBusy = false;
  Timer? _searchDebounce;

  List<Object> _rows = [];
  List<int> _matches = [];

  @override
  void initState() {
    super.initState();
    _itemPositionsListener.itemPositions.addListener(_onScroll);
  }

  @override
  void dispose() {
    _itemPositionsListener.itemPositions.removeListener(_onScroll);
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  HistoryPager get _pager => widget.mode == HistoryMode.posted
      ? ref.read(postedHistoryProvider.notifier)
      : ref.read(reviewedHistoryProvider.notifier);

  List<_Entry> _currentEntries(AppLocalizations l10n) {
    if (widget.mode == HistoryMode.posted) {
      return _entriesFromPosted(
        ref.read(postedHistoryProvider).value ?? const [],
      );
    }
    return _entriesFromReviewed(
      ref.read(reviewedHistoryProvider).value ?? const [],
      l10n,
    );
  }

  void _onScroll() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty || _rows.isEmpty) return;
    final maxIndex = positions
        .map((p) => p.index)
        .reduce((a, b) => a > b ? a : b);
    if (maxIndex >= _rows.length - 3 &&
        _pager.hasMore &&
        !_pager.isLoadingMore) {
      _pager.loadMore();
    }
  }

  /// Throws away every loaded page and re-reads the first one — the pager's
  /// `hasMore` resets with it, so a history that had been paged to the end can
  /// be paged again. Errors are deliberately swallowed *here*: the provider
  /// keeps them, and the list below already renders that through
  /// [ErrorStateView]; letting one escape would only hang the spinner.
  Future<void> _onRefresh() async {
    try {
      if (widget.mode == HistoryMode.posted) {
        ref.invalidate(postedHistoryProvider);
        await ref.read(postedHistoryProvider.future);
      } else {
        ref.invalidate(reviewedHistoryProvider);
        await ref.read(reviewedHistoryProvider.future);
      }
    } catch (_) {
      // Rendered by the `error:` branch of the list below.
    }
    if (!mounted) return;
    setState(() => _currentMatchPointer = -1);
  }

  /// The app bar button hands the work to the pull-to-refresh indicator so the
  /// feedback is identical either way. It is only absent before the first page
  /// has ever loaded (the spinner and the error view have no list to attach to),
  /// and refreshing straight from the provider covers that case.
  void _onRefreshPressed() {
    final indicator = _refreshKey.currentState;
    if (indicator == null) {
      unawaited(_onRefresh());
      return;
    }
    indicator.show();
  }

  Future<void> _onJumpToDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDate: now,
    );
    if (picked == null || !mounted) return;
    await _scrollToDateOrLoadMore(picked);
  }

  Future<void> _scrollToDateOrLoadMore(DateTime target) async {
    final l10n = AppLocalizations.of(context);
    final localeName = Localizations.localeOf(context).toString();
    final targetDay = _dayOf(target);
    while (true) {
      final rows = _buildRows(_currentEntries(l10n), l10n, localeName);
      final idx = rows.indexWhere(
        (r) => r is _Entry && !_dayOf(r.date).isAfter(targetDay),
      );
      if (idx != -1) {
        _itemScrollController.scrollTo(
          index: idx,
          duration: const Duration(milliseconds: 300),
        );
        return;
      }
      if (!_pager.hasMore) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.historyNoPostsOnOrBeforeDate)),
        );
        return;
      }
      if (mounted) setState(() => _isBusyLoading = true);
      await _pager.loadMore();
      if (!mounted) return;
      setState(() => _isBusyLoading = false);
    }
  }

  /// Steps to the next (`direction: 1`) or previous (`direction: -1`) match,
  /// transparently loading further pages — without ever hiding a non-match —
  /// when stepping past the last one currently loaded. Wraps around once the
  /// full history has been loaded and searched.
  Future<void> _goToMatch(int direction) async {
    // Only one search walk at a time — see the `_searchBusy` doc comment.
    // Whichever call is already running always reads `_query` fresh each
    // iteration below, so it self-corrects to a query typed after it started
    // without a second call needing to run concurrently.
    if (_searchBusy) return;
    _searchBusy = true;
    try {
      final l10n = AppLocalizations.of(context);
      final localeName = Localizations.localeOf(context).toString();
      while (true) {
        final rows = _buildRows(_currentEntries(l10n), l10n, localeName);
        final matches = _computeMatches(rows, _query);
        if (matches.isEmpty) {
          // Nothing in what's loaded yet — keep paging in until a match
          // turns up or the history is exhausted, rather than giving up on
          // whatever happened to already be in memory.
          if (_pager.hasMore) {
            if (mounted) setState(() => _isBusyLoading = true);
            await _pager.loadMore();
            if (!mounted) return;
            setState(() => _isBusyLoading = false);
            continue;
          }
          return;
        }

        if (_currentMatchPointer == -1) {
          _currentMatchPointer = direction >= 0 ? 0 : matches.length - 1;
        } else {
          final next = _currentMatchPointer + direction;
          if (next >= matches.length) {
            if (_pager.hasMore) {
              if (mounted) setState(() => _isBusyLoading = true);
              await _pager.loadMore();
              if (!mounted) return;
              setState(() => _isBusyLoading = false);
              continue;
            }
            _currentMatchPointer = 0;
          } else if (next < 0) {
            _currentMatchPointer = matches.length - 1;
          } else {
            _currentMatchPointer = next;
          }
        }

        if (mounted) setState(() {});
        _itemScrollController.scrollTo(
          index: matches[_currentMatchPointer],
          duration: const Duration(milliseconds: 300),
        );
        return;
      }
    } finally {
      _searchBusy = false;
      // The last state-changing update inside the loop above can predate
      // this flag flipping back to false (it runs in this `finally`, after
      // that last `setState`) — one more empty `setState` so anything keyed
      // off `_searchBusy` (the next/prev buttons' disabled state) reflects
      // it without waiting on an unrelated rebuild.
      if (mounted) setState(() {});
    }
  }

  void _closeSearch() {
    _searchDebounce?.cancel();
    setState(() {
      _searchActive = false;
      _query = '';
      _currentMatchPointer = -1;
      _searchController.clear();
    });
  }

  void _onQueryChanged(String value) {
    setState(() {
      _query = value;
      _currentMatchPointer = -1;
    });
    // Debounced: firing `_goToMatch` straight off every keystroke used to
    // queue up one call per character, which could pile up concurrent
    // searches (see `_searchBusy`). Waiting for a short pause in typing
    // means a fast typist only triggers one search walk, not one per key.
    _searchDebounce?.cancel();
    if (value.isEmpty) return;
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _goToMatch(1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeName = Localizations.localeOf(context).toString();

    final asyncEntries = widget.mode == HistoryMode.posted
        ? ref.watch(postedHistoryProvider).whenData(_entriesFromPosted)
        : ref
              .watch(reviewedHistoryProvider)
              .whenData((reviews) => _entriesFromReviewed(reviews, l10n));

    final title = widget.mode == HistoryMode.posted
        ? l10n.historyPostedTitle
        : l10n.historyReviewedTitle;
    final emptyLabel = widget.mode == HistoryMode.posted
        ? l10n.historyEmptyPosted
        : l10n.historyEmptyReviewed;

    // Computed up front, not inside `body:`'s `data:` callback below: Dart
    // evaluates named-argument expressions in source order, so `appBar:`
    // (which reads `_matches` for the match counter) would otherwise be
    // built from last frame's stale `_rows`/`_matches` since it appears
    // before `body:` in this Scaffold(...) call.
    final entries = asyncEntries.value ?? const [];
    _rows = _buildRows(entries, l10n, localeName);
    _matches = _computeMatches(_rows, _query);
    if (_currentMatchPointer >= _matches.length) {
      _currentMatchPointer = _matches.isEmpty ? -1 : _matches.length - 1;
    }

    return Scaffold(
      appBar: _buildAppBar(l10n, title),
      body: asyncEntries.when(
        data: (_) {
          return Stack(
            children: [
              RefreshIndicator(
                key: _refreshKey,
                onRefresh: _onRefresh,
                // The empty state is inside the indicator, not instead of it:
                // "you haven't posted anything yet" is exactly when someone
                // pulls to check again, and a bare `Center` cannot be pulled.
                child: _rows.isEmpty
                    ? _EmptyHistory(label: emptyLabel)
                    : ScrollablePositionedList.builder(
                        itemScrollController: _itemScrollController,
                        itemPositionsListener: _itemPositionsListener,
                        itemCount: _rows.length,
                        itemBuilder: (context, index) => _buildRow(index),
                        // Without this a history short enough to fit on screen
                        // refuses the drag altogether, so the shortest lists —
                        // the ones most likely to be waiting on new items —
                        // were the ones that could not be refreshed.
                        physics: const AlwaysScrollableScrollPhysics(),
                      ),
              ),
              if (_isBusyLoading)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(),
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorStateView(
          error: error,
          onRetry: () => widget.mode == HistoryMode.posted
              ? ref.invalidate(postedHistoryProvider)
              : ref.invalidate(reviewedHistoryProvider),
        ),
      ),
    );
  }

  Widget _buildRow(int index) {
    final row = _rows[index];
    if (row is _HeaderItem) {
      return _DateHeader(label: row.label);
    }
    final entry = row as _Entry;
    final matchPosition = _matches.indexOf(index);
    final isCurrentMatch =
        matchPosition != -1 && matchPosition == _currentMatchPointer;
    return _HistoryTile(
      entry: entry,
      query: _query,
      isCurrentMatch: isCurrentMatch,
    );
  }

  PreferredSizeWidget _buildAppBar(AppLocalizations l10n, String title) {
    if (_searchActive) {
      return AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: l10n.historySearchHint,
            border: InputBorder.none,
          ),
          onChanged: _onQueryChanged,
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                _matches.isEmpty
                    ? '0/0'
                    : '${_currentMatchPointer + 1}/${_matches.length}',
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_up),
            onPressed: (_query.isEmpty || _searchBusy)
                ? null
                : () => _goToMatch(-1),
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: (_query.isEmpty || _searchBusy)
                ? null
                : () => _goToMatch(1),
          ),
          IconButton(icon: const Icon(Icons.close), onPressed: _closeSearch),
        ],
      );
    }
    return AppBar(
      title: Text(title),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: l10n.historySearchTooltip,
          onPressed: () => setState(() => _searchActive = true),
        ),
        IconButton(
          icon: const Icon(Icons.calendar_month_outlined),
          tooltip: l10n.historyJumpToDateTooltip,
          onPressed: _onJumpToDate,
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: l10n.historyRefreshTooltip,
          onPressed: _onRefreshPressed,
        ),
      ],
    );
  }
}

/// "Nothing here yet", as a scrollable — the whole point is that it can be
/// pulled down. [ConstrainedBox] against the viewport height keeps the message
/// centred rather than pinned under the app bar, which is what a plain
/// [SingleChildScrollView] would do.
class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(label, textAlign: TextAlign.center),
            ),
          ),
        ),
      ),
    );
  }
}

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.entry,
    required this.query,
    required this.isCurrentMatch,
  });

  final _Entry entry;
  final String query;
  final bool isCurrentMatch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: isCurrentMatch
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
          : null,
      child: InkWell(
        onTap: () => showHistoryPostDetail(
          context,
          post: entry.post,
          reviewKindLabel: entry.kindLabel,
          reviewedAt: entry.kindLabel != null ? entry.date : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.post.channelName,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (entry.kindLabel != null) ...[
                    Text(
                      entry.kindLabel!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    DateFormat.jm().format(entry.date.toLocal()),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              _HighlightedText(text: entry.post.previewText, query: query),
            ],
          ),
        ),
      ),
    );
  }
}

class _HighlightedText extends StatelessWidget {
  const _HighlightedText({required this.text, required this.query});

  final String text;
  final String query;

  @override
  Widget build(BuildContext context) {
    final baseStyle = DefaultTextStyle.of(context).style;
    if (query.isEmpty) return Text(text, style: baseStyle);

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + query.length),
          style: TextStyle(
            backgroundColor: Colors.amber.withValues(alpha: 0.6),
            fontWeight: FontWeight.bold,
          ),
        ),
      );
      start = index + query.length;
    }
    return RichText(
      text: TextSpan(style: baseStyle, children: spans),
    );
  }
}
