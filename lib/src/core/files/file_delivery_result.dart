/// What became of a file handed to [deliverFile].
///
/// Its own file so both platform implementations can return the same type - a
/// conditional export cannot declare one they share.
enum FileDelivery {
  /// The file left the app: the browser downloaded it, or the person picked
  /// somewhere to put it.
  handedOff,

  /// The share sheet was dismissed without choosing anything, so nothing was
  /// saved. Not an error - there is nothing to apologise for and nothing to
  /// retry automatically - but the UI must not claim success either.
  dismissed,
}
