import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// A channel's badge: a glyph for what the channel is *about*, in the channel's
/// own colour.
///
/// It used to be the name's first letter on a coloured disc, which is the
/// convention for *people* — a contact list, an avatar with no picture. Applied
/// to a topic it read as an address book, and "T" told a reader nothing "#"
/// wouldn't have. An icon says something about the channel before its name is
/// read, which is the whole job of the thing sitting left of a name.
///
/// [channelIcon] falls back to a hash glyph rather than to a letter: channels
/// are backend rows, so a new one can exist that this map has never heard of,
/// and a generic channel mark is honest where a wrong-but-confident icon is
/// not.
class ChannelAvatar extends StatelessWidget {
  const ChannelAvatar({super.key, required this.name, this.radius = 22});

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.channelColor(name);
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.15),
      child: Icon(channelIcon(name), size: radius * 1.05, color: color),
    );
  }
}

/// The glyph for a channel, by name. See [ChannelAvatar] for why this is not a
/// letter, and why the fallback is deliberately generic.
IconData channelIcon(String name) => switch (name) {
  'General' => Icons.forum_outlined,
  'Technology' => Icons.memory_outlined,
  'Outdoors' => Icons.terrain_outlined,
  'Memes' => Icons.mood_outlined,
  'Politics' => Icons.account_balance_outlined,
  'Local' => Icons.place_outlined,
  _ => Icons.tag,
};
