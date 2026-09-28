// Building the URLs the API-documentation screen points at, and deciding
// whether the browser will let us show the docs in place.
//
// Pure Dart with no Flutter or `dart:io` import, so the decision logic is
// unit-testable on the VM (see `test/features/api_docs_url_test.dart`) rather
// than only observable by loading the real web build in a browser -- the
// conditional-import half of this feature can't be reached from `flutter
// test` at all.

/// Joins [path] onto the configured backend base URL.
///
/// Deliberately string concatenation rather than `Uri.resolve`: that resolves
/// a relative reference against the base *as a URI*, where a base without a
/// trailing slash has its last segment treated as a filename -- so
/// `Uri.parse('https://host/api').resolve('docs')` is `https://host/docs`, not
/// `https://host/api/docs`. An install that serves the API under a path
/// prefix would silently get a 404 from the docs page.
String apiUrl(String baseUrl, String path) {
  final base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
  return '$base/$path';
}

/// The backend's Swagger UI (`docs_url` on the FastAPI app).
String apiDocsUrl(String baseUrl) => apiUrl(baseUrl, 'docs');

/// The backend's ReDoc view of the same schema -- a read-only, better-
/// formatted rendering of the identical OpenAPI document.
String apiRedocUrl(String baseUrl) => apiUrl(baseUrl, 'redoc');

/// The raw OpenAPI document itself, for generating a client or diffing.
String apiSchemaUrl(String baseUrl) => apiUrl(baseUrl, 'openapi.json');

/// Whether a page served over [pageScheme] is allowed to frame [docsUrl] in
/// an `<iframe>`.
///
/// Browsers block a secure page from framing an insecure one (mixed
/// content), and the result is a silently blank frame -- no console error
/// visible to the user, just an empty box where the documentation should be.
/// That is exactly the shape of a homelab deploy (the web build behind HTTPS
/// on a reverse proxy, the backend still on plain HTTP on localhost), so it's
/// worth catching rather than shipping a blank page. The reverse direction is
/// fine: an insecure page may frame a secure one.
bool canEmbedDocsInline({required String pageScheme, required String docsUrl}) {
  final docsScheme = Uri.tryParse(docsUrl)?.scheme.toLowerCase() ?? '';
  return !(pageScheme.toLowerCase() == 'https' && docsScheme == 'http');
}
