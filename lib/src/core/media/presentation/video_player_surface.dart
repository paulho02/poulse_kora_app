import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../l10n/generated/app_localizations.dart';

/// How long the chrome stays up after a touch before fading away again. Only
/// ever runs while the clip is *playing* — a paused player keeps its controls,
/// since hiding them would leave a still frame with no visible way back in.
const _kAutoHide = Duration(milliseconds: 2200);

const _kFade = Duration(milliseconds: 180);

/// Playback chrome for an already-initialized [VideoPlayerController].
///
/// This replaces `chewie`'s stock material controls, which were three centred
/// buttons (seek back / play / seek forward), a full-surface `black54` scrim and
/// an options bar — all of it painted over a clip of at most a minute and,
/// because the scrim and the hit area both hang off chewie's `PlayerNotifier`,
/// re-appearing on every state change whether the clip was playing or paused.
/// The rules here are the ones a short clip actually wants:
///
/// - **Playing means nothing on screen.** The chrome fades out [_kAutoHide]
///   after the last touch and a tap brings it back; a paused clip keeps it.
/// - **Nothing is ever drawn over the picture.** Every control — play/pause
///   included — lives in one row along the bottom edge, so no button sits on
///   the frame itself. A centred play glyph is right on the *poster*, where it
///   is the only affordance there is, and wrong over moving video, where it
///   lands in the middle of the shot you are trying to watch.
/// - **One button, not three.** Ten-second seek buttons are for long-form video;
///   a 60-second post (`POST_VIDEO_MAX_DURATION_SECONDS`) is scrubbed, not
///   chaptered.
/// - **The scrim is a bottom gradient**, not a sheet over the whole frame — the
///   picture is the point, which is the same reason the poster frame exists.
///
/// The clip loops (`InlineMediaBlock._play` sets it), so there is no end state
/// to draw a replay button for; pausing is how it stops.
///
/// The screen is kept awake while a clip plays (chewie used to do this), which
/// a 60-second clip needs on a phone whose display times out in 15 or 30.
class VideoPlayerSurface extends StatefulWidget {
  const VideoPlayerSurface({super.key, required this.controller});

  final VideoPlayerController controller;

  @override
  State<VideoPlayerSurface> createState() => _VideoPlayerSurfaceState();
}

class _VideoPlayerSurfaceState extends State<VideoPlayerSurface> {
  Timer? _hideTimer;
  bool _controlsVisible = false;
  bool _muted = false;
  bool _playing = false;
  bool _holdsWakelock = false;

  VideoPlayerController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onPlayerValue);
    _playing = _controller.value.isPlaying;
    _muted = _controller.value.volume == 0;
    if (_playing) _setWakelock(true);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.removeListener(_onPlayerValue);
    _setWakelock(false);
    super.dispose();
  }

  /// Only the play/pause *transition* is handled here; position and buffering
  /// are read by the [ValueListenableBuilder]s below, so a ticking clip does not
  /// rebuild the whole surface many times a second.
  void _onPlayerValue() {
    final playing = _controller.value.isPlaying;
    if (playing == _playing) return;
    _playing = playing;
    _setWakelock(playing);
    if (playing) {
      _scheduleHide();
    } else {
      // Pausing, or reaching the end, always hands the controls back.
      _hideTimer?.cancel();
      if (mounted) setState(() => _controlsVisible = true);
    }
  }

  void _setWakelock(bool enabled) {
    if (enabled == _holdsWakelock) return;
    _holdsWakelock = enabled;
    _wakelockHolders += enabled ? 1 : -1;
    if (enabled && _wakelockHolders == 1) {
      unawaited(WakelockPlus.enable());
    } else if (!enabled && _wakelockHolders == 0) {
      unawaited(WakelockPlus.disable());
    }
  }

  void _toggleControls() {
    if (_controlsVisible) {
      _hideTimer?.cancel();
      setState(() => _controlsVisible = false);
    } else {
      _showControls();
    }
  }

  void _showControls() {
    setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_controller.value.isPlaying) return;
    _hideTimer = Timer(_kAutoHide, () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  Future<void> _togglePlayback() async {
    final value = _controller.value;
    if (value.isPlaying) {
      await _controller.pause();
      return;
    }
    if (_isFinished(value)) await _controller.seekTo(Duration.zero);
    await _controller.play();
  }

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    _scheduleHide();
    await _controller.setVolume(_muted ? 0 : 1);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleControls,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The parent block already sizes itself to the clip's aspect ratio,
          // so the raw player fills it exactly.
          VideoPlayer(_controller),
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: _controller,
            builder: (context, value, _) => value.isBuffering && value.isPlaying
                ? const Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          AnimatedOpacity(
            opacity: _controlsVisible ? 1 : 0,
            duration: _kFade,
            curve: Curves.easeOut,
            child: IgnorePointer(
              ignoring: !_controlsVisible,
              child: _chrome(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chrome(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        // Only the bottom strip is dimmed, and only enough to keep white
        // glyphs legible over a blown-out frame.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(0, 0.35),
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Color(0x8C000000)],
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _bottomBar(context, l10n),
        ),
      ],
    );
  }

  Widget _bottomBar(BuildContext context, AppLocalizations l10n) {
    const style = TextStyle(
      color: Colors.white,
      fontSize: 11,
      // Without tabular figures the row twitches sideways every time a digit
      // changes, once a second, for the whole clip.
      fontFeatures: [FontFeature.tabularFigures()],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 2),
      child: Row(
        children: [
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: _controller,
            builder: (context, value, _) => _GlyphButton(
              icon: value.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              label: value.isPlaying
                  ? l10n.postMediaPauseVideo
                  : l10n.postMediaPlayVideo,
              onPressed: _togglePlayback,
            ),
          ),
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: _controller,
            builder: (context, value, _) => Text(
              '${_formatDuration(value.position)} / '
              '${_formatDuration(value.duration)}',
              style: style,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: _ScrubBar(
                controller: _controller,
                // A drag is not a tap, so the auto-hide timer would otherwise
                // pull the bar out from under the finger holding it.
                onScrubStart: () => _hideTimer?.cancel(),
                onScrubEnd: _scheduleHide,
              ),
            ),
          ),
          _GlyphButton(
            icon: _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
            label: _muted ? l10n.postMediaUnmute : l10n.postMediaMute,
            onPressed: _toggleMute,
          ),
        ],
      ),
    );
  }
}

/// Surfaces hold the wakelock as a group: two inline blocks can be playing at
/// once, and the first one disposed must not let the screen dim under the other.
int _wakelockHolders = 0;

/// The clip loops (see `InlineMediaBlock._play`), so this should not come up;
/// it is the guard for a platform that stops dead on the last frame anyway, so
/// that the play button restarts the clip rather than doing nothing.
bool _isFinished(VideoPlayerValue value) =>
    value.duration > Duration.zero && value.position >= value.duration;

String _formatDuration(Duration d) {
  final seconds = d.inSeconds.clamp(0, 5999);
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// A control in the bottom row: a 20px white glyph in a 36px tap target, with a
/// drop shadow rather than the translucent disc the poster's play badge wears —
/// the gradient behind the row already does that job, and a second dark shape on
/// top of it would read as chrome stacked on chrome.
class _GlyphButton extends StatelessWidget {
  const _GlyphButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            icon,
            size: 20,
            color: Colors.white,
            semanticLabel: label,
            shadows: const [Shadow(color: Color(0x8C000000), blurRadius: 4)],
          ),
        ),
      ),
    );
  }
}

/// Slim rounded progress bar with a knob, scrubbable by drag or by tapping a
/// point on the track.
///
/// Hand-built rather than `VideoProgressIndicator` because that widget is three
/// stacked square-ended [LinearProgressIndicator]s with no handle — fine as a
/// read-out, but it gives no sign that it can be dragged, and a 4px hit area is
/// barely touchable. This bar paints at 3px but takes a 24px row, so the target
/// is a thumb rather than a hairline.
class _ScrubBar extends StatefulWidget {
  const _ScrubBar({
    required this.controller,
    required this.onScrubStart,
    required this.onScrubEnd,
  });

  final VideoPlayerController controller;
  final VoidCallback onScrubStart;
  final VoidCallback onScrubEnd;

  @override
  State<_ScrubBar> createState() => _ScrubBarState();
}

class _ScrubBarState extends State<_ScrubBar> {
  /// Where the finger is, while it is down. Held separately from the player's
  /// own position so the knob follows the drag instead of stuttering back to
  /// whichever frame the decoder has actually reached.
  double? _dragFraction;

  static const _trackHeight = 3.0;
  static const _knobRadius = 6.0;
  static const _rowHeight = 24.0;

  void _seekToFraction(double fraction) {
    final duration = widget.controller.value.duration;
    if (duration <= Duration.zero) return;
    widget.controller.seekTo(duration * fraction);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void scrub(double dx) {
          final fraction = width <= 0 ? 0.0 : (dx / width).clamp(0.0, 1.0);
          setState(() => _dragFraction = fraction);
          _seekToFraction(fraction);
        }

        void endScrub() {
          setState(() => _dragFraction = null);
          widget.onScrubEnd();
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            widget.onScrubStart();
            scrub(details.localPosition.dx);
          },
          onTapUp: (_) => endScrub(),
          onTapCancel: endScrub,
          onHorizontalDragStart: (details) {
            widget.onScrubStart();
            scrub(details.localPosition.dx);
          },
          onHorizontalDragUpdate: (details) => scrub(details.localPosition.dx),
          onHorizontalDragEnd: (_) => endScrub(),
          onHorizontalDragCancel: endScrub,
          child: SizedBox(
            height: _rowHeight,
            child: ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: widget.controller,
              builder: (context, value, _) {
                final total = value.duration.inMilliseconds;
                final played =
                    _dragFraction ??
                    (total <= 0
                        ? 0.0
                        : (value.position.inMilliseconds / total).clamp(
                            0.0,
                            1.0,
                          ));
                final buffered = value.buffered.isEmpty || total <= 0
                    ? 0.0
                    : (value.buffered.last.end.inMilliseconds / total).clamp(
                        0.0,
                        1.0,
                      );
                return Stack(
                  alignment: Alignment.centerLeft,
                  clipBehavior: Clip.none,
                  children: [
                    _bar(width, Colors.white24),
                    _bar(width * buffered, Colors.white38),
                    _bar(width * played, Colors.white),
                    Positioned(
                      left: (width * played - _knobRadius).clamp(
                        0.0,
                        math.max(0.0, width - _knobRadius * 2),
                      ),
                      child: Container(
                        width: _knobRadius * 2,
                        height: _knobRadius * 2,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Color(0x66000000), blurRadius: 3),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _bar(double width, Color color) => Container(
    height: _trackHeight,
    width: width.isFinite ? math.max(0.0, width) : 0,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(_trackHeight),
    ),
  );
}
