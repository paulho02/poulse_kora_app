import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/errors/error_messages.dart';
import '../../../core/files/file_delivery.dart';
import '../../../core/files/file_delivery_provider.dart';
import '../application/profile_providers.dart';
import '../data/data_export.dart';

/// Settings → Account → Download my data.
///
/// The GDPR Art. 15 / Art. 20 affordance. It sits above the delete row rather
/// than beside it because the two belong to one sequence in practice: the copy
/// of your data is the thing you want *before* you erase the account, and an
/// export that is only discoverable after the deletion dialog has opened is an
/// export nobody takes.
///
/// Three things it does deliberately:
///
/// - **It says how long this takes before it starts.** The archive contains
///   every picture and clip the account ever uploaded, and on a phone connection
///   that is a wait with nothing on screen to explain it. The subtitle names
///   what is in the file; the row itself turns into a progress indicator.
/// - **It is not cancellable, and does not pretend to be.** There is no partial
///   export worth keeping, the request is already rate-limited server-side, and
///   a cancel button on a one-shot download is an invitation to spend the budget
///   twice.
/// - **A rate-limited refusal gets its own sentence.** The shared
///   `rate_limited` copy says "try again in N seconds", which is fine for the
///   posting budget and absurd for this one - N is most of a day.
class DataExportTile extends ConsumerStatefulWidget {
  const DataExportTile({super.key});

  @override
  ConsumerState<DataExportTile> createState() => _DataExportTileState();
}

class _DataExportTileState extends ConsumerState<DataExportTile> {
  bool _running = false;

  /// 0..1 while bytes are arriving, or null when the server has not said how
  /// big the archive is. It cannot: the ZIP is built as it is sent, so there is
  /// no `Content-Length` to divide by, and the indicator stays indeterminate
  /// rather than inventing a fraction.
  double? _progress;

  Future<void> _run() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // Captured before the await: on an iPad the share sheet anchors to the row
    // that started it, and by the time the download finishes the widget may no
    // longer be laid out.
    final origin = _tileOrigin();

    setState(() {
      _running = true;
      _progress = null;
    });
    try {
      final export = await ref
          .read(profileRepositoryProvider)
          .downloadDataExport(
            onProgress: (received, total) {
              if (!mounted || total <= 0) return;
              setState(() => _progress = received / total);
            },
          );
      final delivery = await ref.read(fileDeliveryProvider)(
        filename: export.filename,
        bytes: export.bytes,
        mimeType: DataExport.mimeType,
        shareOrigin: origin,
      );
      if (!mounted) return;
      // A dismissed share sheet is not a success and not a failure: nothing was
      // saved, and the person is the one who decided that. Saying anything at
      // all would be arguing with them.
      if (delivery == FileDelivery.handedOff) {
        _say(messenger, l10n.settingsExportDataDone);
      }
    } catch (error) {
      if (!mounted) return;
      _say(messenger, _messageFor(l10n, error));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  String _messageFor(AppLocalizations l10n, Object error) {
    final failure = asRelayException(error);
    return failure.error == 'rate_limited'
        ? l10n.settingsExportDataRateLimited
        : messageFor(l10n, error);
  }

  void _say(ScaffoldMessengerState messenger, String text) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
      );
  }

  Rect? _tileOrigin() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      leading: const Icon(Icons.download_outlined),
      title: Text(l10n.settingsExportData),
      subtitle: Text(
        _running ? l10n.settingsExportDataRunning : l10n.settingsExportDataSubtitle,
      ),
      trailing: _running
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: _progress,
              ),
            )
          : null,
      // Null while it runs, which disables the row: tapping again would start a
      // second download and spend another slot of a budget measured per day.
      onTap: _running ? null : _run,
    );
  }
}
