/// The "continue with Google" affordance, which is a genuinely different widget
/// per platform.
///
/// On Android we draw our own button and call `authenticate()`. On web Google
/// requires *its* rendered button (`supportsAuthenticate()` is false there and
/// `authenticate()` throws), and that lives in `package:google_sign_in_web`'s
/// `web_only.dart` - a library that does not compile for Android. Hence the
/// conditional export rather than a `kIsWeb` branch inside one file.
library;

export 'google_sign_in_button_stub.dart'
    if (dart.library.js_interop) 'google_sign_in_button_web.dart';
