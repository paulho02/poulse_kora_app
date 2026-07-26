import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../channels/data/channel.dart';

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

class _ChannelPickerSheet extends StatefulWidget {
  const _ChannelPickerSheet({required this.channels, required this.selectedId});

  final List<Channel> channels;
  final int? selectedId;

  @override
  State<_ChannelPickerSheet> createState() => _ChannelPickerSheetState();
}

class _ChannelPickerSheetState extends State<_ChannelPickerSheet> {
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
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search channels',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) =>
                    setState(() => _query = value.toLowerCase()),
              ),
            ),
            Flexible(
              child: filtered.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('No channels found'),
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
                          title: Text(channel.name),
                          subtitle: Text(
                            channel.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
