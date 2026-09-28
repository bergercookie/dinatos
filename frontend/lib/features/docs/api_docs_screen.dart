import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/server_url_provider.dart';
import 'api_docs_embed.dart';
import 'api_docs_url.dart';

/// Copies [text] and says so, or says that it couldn't.
///
/// The clipboard is a platform channel, and this app's own precedent is that
/// such a call can simply fail -- on a desktop target where the backing
/// service isn't available (`TokenStorage`/`ServerUrlStorage` catching
/// `PlatformException` from an unrun keyring, and `AGENTS.md`'s note about the
/// crash that came from not doing so), or with the channel missing entirely
/// (`MissingPluginException`, which is not a `PlatformException`). A copy
/// button that throws an unhandled async error is worse than one that reports
/// a failure, so the whole family is caught rather than one class of it, the
/// same reasoning as `services/exercise.py`'s deliberately broad `except`.
Future<void> _copyToClipboard(BuildContext context, String text) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await Clipboard.setData(ClipboardData(text: text));
  } on Exception {
    messenger?.showSnackBar(
      const SnackBar(content: Text('Could not copy -- the clipboard is unavailable')),
    );
    return;
  }
  messenger?.showSnackBar(const SnackBar(content: Text('Link copied')));
}

/// The API documentation, shown in place at this app's own `/docs` route.
///
/// The content is the backend's own Swagger UI, so it can't drift from the
/// API it describes: there's one source of truth (the FastAPI app's generated
/// OpenAPI schema) and this screen only decides where to put it.
///
/// On the web target that's an inline frame of `<server>/docs`. Everywhere
/// else -- and on the web when the browser won't allow the frame -- the screen
/// falls back to the URLs with a copy button, so the page is never just an
/// empty box.
class ApiDocsScreen extends ConsumerWidget {
  const ApiDocsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverUrl = ref.watch(serverUrlProvider);
    final docsUrl = apiDocsUrl(serverUrl);
    final embed = buildDocsEmbed(docsUrl);

    return Scaffold(
      appBar: AppBar(
        title: const Text('API documentation'),
        // Reached with `go`, not `push` (see the note in profile_screen.dart),
        // so there is no route stack entry for the AppBar to imply a back
        // button *from*; this is the way back, and `automaticallyImplyLeading`
        // is off so there is exactly one of them rather than two.
        automaticallyImplyLeading: false,
        leading: BackButton(onPressed: () => context.go('/profile')),
      ),
      body: embed ?? _LinkFallbackPanel(docsUrl: docsUrl, serverUrl: serverUrl),
    );
  }
}

class _LinkFallbackPanel extends StatelessWidget {
  const _LinkFallbackPanel({required this.docsUrl, required this.serverUrl});

  final String docsUrl;
  final String serverUrl;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'The API documentation is served by the backend at:',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        SelectableText(docsUrl, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.copy),
          label: const Text('Copy link'),
          onPressed: () => _copyToClipboard(context, docsUrl),
        ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 8),
        Text(
          'Swagger UI loads its own assets from a public CDN, so the page needs '
          'internet access to render. On a machine with no outbound network, '
          'use the raw schema instead.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        _AlternateLink(label: 'ReDoc (read-only view)', url: apiRedocUrl(serverUrl)),
        _AlternateLink(label: 'OpenAPI schema (JSON)', url: apiSchemaUrl(serverUrl)),
      ],
    );
  }
}

class _AlternateLink extends StatelessWidget {
  const _AlternateLink({required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: SelectableText(url),
      trailing: IconButton(
        tooltip: 'Copy $label link',
        icon: const Icon(Icons.copy),
        onPressed: () => _copyToClipboard(context, url),
      ),
    );
  }
}
