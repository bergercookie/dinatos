import 'package:flutter/widgets.dart';

/// Native targets (Android, Linux desktop) have no browser to frame the
/// Swagger UI in: there's no iframe equivalent Flutter can put in the widget
/// tree without pulling in a whole webview plugin, and a webview wouldn't
/// help anyway -- the docs are already a web page, and this app's native
/// targets only reach the API as an HTTP client, not a browsing session.
///
/// So on those platforms [buildDocsEmbed] returns null and the screen falls
/// back to showing the URL with a copy button. See api_docs_embed_web.dart for
/// the real, browser-backed version.
Widget? buildDocsEmbed(String url) => null;
