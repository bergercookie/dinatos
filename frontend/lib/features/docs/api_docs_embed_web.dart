import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/widgets.dart';

import 'api_docs_url.dart';

/// Embeds the backend's Swagger UI in a real `<iframe>`, so the documentation
/// renders in place at this app's own `/docs` route instead of the user having
/// to leave for the backend's origin.
///
/// `HtmlElementView` (a platform view) is how a DOM element gets into a
/// Flutter web widget tree; `fromTagName` builds the element for us, so
/// there's no `PlatformViewFactory` registration to keep in sync. Everything
/// it needs from the DOM goes through `dart:js_interop` rather than
/// `dart:html`, which is deprecated and unavailable under Wasm.
Widget? buildDocsEmbed(String url) {
  // A blank frame is a worse outcome than an honest "copy this link" panel,
  // and a page served over HTTPS silently refuses to frame an HTTP one.
  if (!canEmbedDocsInline(pageScheme: Uri.base.scheme, docsUrl: url)) return null;

  return HtmlElementView.fromTagName(
    tagName: 'iframe',
    onElementCreated: (Object element) => _configureIframe(element as JSObject, url),
  );
}

void _configureIframe(JSObject iframe, String url) {
  iframe
    ..setProperty('src'.toJS, url.toJS)
    // Not decorative: it's the entire content of the screen, so it needs an
    // accessible name for anyone navigating by screen reader.
    ..setProperty('title'.toJS, 'API documentation'.toJS)
    // A platform view is composited over the canvas, so Flutter's own
    // borders/scrollbars don't apply to it -- it has to be told to fill the
    // space it's given and to draw no chrome of its own.
    //
    // `setAttribute('style', ...)` and *not* `style = {...}` / setProperty on
    // the 'style' key: `style` is a read-only accessor returning a live
    // CSSStyleDeclaration, so handing it a plain object is silently ignored
    // (no error, no console warning). Measured in a browser, that leaves the
    // frame at the default 300x150 with its default 2px border -- a small box
    // in the corner where the documentation should be, which is exactly the
    // kind of bug `flutter analyze` and `flutter test` cannot see, since
    // neither one puts a real frame on a real page.
    ..callMethod('setAttribute'.toJS, 'style'.toJS, 'border: none; width: 100%; height: 100%'.toJS);
}
