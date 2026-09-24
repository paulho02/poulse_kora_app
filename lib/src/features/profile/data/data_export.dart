import 'dart:typed_data';

/// The ZIP `GET /users/me/export` answers with, in memory, plus the name the
/// server wants it saved under.
///
/// The filename is the server's rather than the client's on purpose: it carries
/// the date the export was taken, which is the one thing about the file a person
/// will want to read off it later, and the server is where that date is true.
class DataExport {
  const DataExport({required this.filename, required this.bytes});

  final String filename;
  final Uint8List bytes;

  static const mimeType = 'application/zip';

  /// Used when the response carries no `Content-Disposition` a filename can be
  /// read out of - a proxy that strips it, or a future server that forgets it.
  /// Deliberately not dated: a wrong date would be worse than no date.
  static const fallbackFilename = 'peerkola-export.zip';

  /// The filename out of a `Content-Disposition` header, or [fallbackFilename].
  ///
  /// Only the plain `filename="..."` form is read. RFC 5987's `filename*` is not
  /// parsed because nothing here ever produces one - the server's name is ASCII
  /// by construction - and a half-implemented percent-decoder would be a way to
  /// get a surprising string into a file path.
  static String filenameFrom(String? contentDisposition) {
    if (contentDisposition == null) return fallbackFilename;
    final match = RegExp(
      r'filename="?([^";]+)"?',
      caseSensitive: false,
    ).firstMatch(contentDisposition);
    final name = match?.group(1)?.trim();
    if (name == null || name.isEmpty) return fallbackFilename;
    // Never let a header decide a path. A server that sent `../` would be a
    // broken server, but this is the one place its output becomes a file name.
    final sanitized = name.split(RegExp(r'[\\/]')).last;
    return sanitized.isEmpty ? fallbackFilename : sanitized;
  }
}
