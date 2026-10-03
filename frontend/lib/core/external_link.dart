import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [uri] outside the app and says whether it worked. On the web that is
/// a new browser tab; elsewhere the system browser. A provider so tests can
/// replace it -- the real one is a platform channel.
final urlOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank'),
);

/// Opens [url] in a new browser tab (see [urlOpenerProvider]), or says that it
/// couldn't -- never an unhandled error: the launcher can fail on a platform
/// with no handler for the link, same reasoning as the clipboard in
/// `api_docs_screen.dart`.
Future<void> openExternalLink(BuildContext context, WidgetRef ref, String url) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  var opened = false;
  try {
    final uri = Uri.tryParse(url);
    opened = uri != null && await ref.read(urlOpenerProvider)(uri);
  } on Exception {
    opened = false;
  }
  if (!opened) {
    messenger?.showSnackBar(SnackBar(content: Text('Could not open $url')));
  }
}
