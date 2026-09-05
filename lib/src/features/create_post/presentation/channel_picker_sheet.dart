import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/settings/price_display_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../channels/data/channel.dart';
import '../../channels/presentation/channel_price_label.dart';

/// Opens a searchable channel picker as a modal bottom sheet and resolves to
/// the chosen channel, or `null` if the sheet was dismissed without a choice.
Future<Channel?> showChannelPickerSheet(
  BuildContext context, {
  required List<Channel> channels,
  int? selectedId,
}) {
  return showModalBottomSheet<Channel>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) =>
        _ChannelPickerSheet(channels: channels, selectedId: selectedId),
  );
}

class _ChannelPickerSheet extends ConsumerStatefulWidget {
  const _ChannelPickerSheet({required this.channels, required this.selectedId});

  final List<Channel> channels;
  final int? selectedId;

  @override
  ConsumerState<_ChannelPickerSheet> createState() => _ChannelPickerSheetState();
}

class _ChannelPickerSheetState extends ConsumerState<_ChannelPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // Behind the same switch as the channels list. This is where the choice is
    // actually made, so someone in price-watching mode wants the figures here
    // too — and someone who isn't still gets a picker that is only about
    // channels.
    final showPrices = ref.watch(showChannelPricesProvider);
    final filtered = _query.isEmpty
        ? widget.channels
        : widget.channels
              .where(
                (c) =>
                    c.name.toLowerCase().contains(_query) ||
                    c.description.toLowerCase().contains(_query),
              )
              .toList();

    // Cap the sheet just below full screen so it feels like a sheet, not a page.
    final maxHeight = MediaQuery.of(context).size.height * 0.85;

    return Padding(
      // Lift the content above the keyboard when the search field is focused.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: l10n.channelsSearchHint,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) =>
                    setState(() => _query = value.toLowerCase()),
              ),
            ),
            Flexible(
              child: filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(l10n.channelsNoneFound),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final channel = filtered[index];
                        final color = AppColors.channelColor(channel.name);
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: color.withValues(alpha: 0.15),
                            child: Text(
                              channel.name.isNotEmpty ? channel.name[0] : '?',
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          isThreeLine: showPrices,
                          title: Text(channel.name),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                channel.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (showPrices)
                                ChannelPriceLabel(channel: channel),
                            ],
                          ),
                          trailing: channel.id == widget.selectedId
                              ? Icon(
                                  Icons.check,
                                  color: theme.colorScheme.primary,
                                )
                              : null,
                          onTap: () => Navigator.of(context).pop(channel),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
