import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/settings/price_display_settings.dart';
import '../../../core/tips/presentation/view_tip.dart';
import '../../channels/presentation/channels_screen.dart';
import 'content_languages_tab.dart';

/// Everything that shapes what the feed sends you, in one place: which
/// channels you follow and which languages you read.
///
/// This used to be just the "Channels" screen. It grew a second tab because
/// accepting a language and subscribing to a channel are the same *kind* of
/// decision — both are filters on delivery, applied server-side before a post
/// ever reaches your queue — and the language half had been sitting in Settings,
/// where it read as an account preference next to the app's own interface
/// language. Two rows a line apart, both saying "language", meaning different
/// things: someone switching the app to German and seeing no change in the feed
/// had no way to tell which one they had touched.
///
/// Named "Filters" — short enough to sit in the bottom nav next to Feed,
/// Create, Stats and Profile, and accurate: both tabs *filter* what gets
/// delivered rather than search or curate it. Generic on purpose, too — a
/// third filter (a topic mute, a content rating) belongs here as another tab,
/// not as another Settings entry, and "Channels" would have made that landing
/// look arbitrary.
///
/// The `ViewTip` here is deliberately one card for both tabs, not one per
/// tab: it explains the screen's *purpose* ("these two things shape your
/// feed"), which is true before either tab is opened, rather than explaining
/// one tab's mechanics while the other sits unintroduced.
class FeedPreferencesScreen extends ConsumerStatefulWidget {
  const FeedPreferencesScreen({super.key});

  @override
  ConsumerState<FeedPreferencesScreen> createState() =>
      _FeedPreferencesScreenState();
}

class _FeedPreferencesScreenState extends ConsumerState<FeedPreferencesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)
    // The price switch is chrome *about the channel list*, so the bar has to
    // rebuild when the tab changes — otherwise a control with no subject sits
    // over the languages tab.
    ..addListener(_onTabChanged);

  void _onTabChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _tabs
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final showPrices = ref.watch(showChannelPricesProvider);
    // `index` flips once a swipe passes its midpoint, so the switch appears and
    // disappears with the tab it belongs to rather than after the animation.
    final onChannels = _tabs.index == 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.feedPrefsTitle),
        actions: [
          if (onChannels)
            ChannelPriceSwitchAction(
              value: showPrices,
              onChanged: (value) =>
                  ref.read(showChannelPricesProvider.notifier).set(value),
            ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: l10n.feedPrefsTabChannels),
            Tab(text: l10n.feedPrefsTabLanguages),
          ],
        ),
      ),
      body: ViewTip(
        tipKey: 'tip.feedPreferences',
        message: l10n.feedPrefsTipMessage,
        child: TabBarView(
          controller: _tabs,
          children: const [ChannelsTab(), ContentLanguagesTab()],
        ),
      ),
    );
  }
}
