/// Handing a file the app has in memory to the person using it.
///
/// A genuinely different act per platform, which is why this is a conditional
/// export rather than a `kIsWeb` branch: the web implementation imports
/// `package:web`, which does not compile for Android, and the Android one
/// imports `dart:io` through `path_provider`, which does not compile for web.
/// Same shape as `features/auth/presentation/google_sign_in_button.dart`.
///
/// On **web** there is one obvious answer - the browser's own download - and no
/// share sheet worth preferring to it. On **Android** there is no download
/// folder an app may simply write to, so the file goes to the app's cache and
/// the system share sheet is what moves it somewhere the person can find it
/// (Drive, Files, a mail draft). Both are "the file is now yours"; only one of
/// them can be cancelled halfway, which is why [FileDelivery] has two values.
library;

export 'file_delivery_result.dart';
export 'file_delivery_io.dart'
    if (dart.library.js_interop) 'file_delivery_web.dart';
