import 'package:dinatos_frontend/features/docs/api_docs_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('apiUrl', () {
    test('appends the path to a plain base URL', () {
      expect(apiUrl('http://127.0.0.1:8000', 'docs'), 'http://127.0.0.1:8000/docs');
    });

    test('does not double a trailing slash', () {
      expect(apiUrl('http://127.0.0.1:8000/', 'docs'), 'http://127.0.0.1:8000/docs');
      expect(apiUrl('http://127.0.0.1:8000///', 'docs'), 'http://127.0.0.1:8000/docs');
    });

    test('preserves a path prefix on the base URL', () {
      // The trap this guards: `Uri.parse('https://host/api').resolve('docs')`
      // is 'https://host/docs', because resolve() treats the base's last
      // segment as a filename. An install serving the API under a prefix would
      // silently get a 404 from the docs page.
      expect(apiUrl('https://host/api', 'docs'), 'https://host/api/docs');
      expect(apiUrl('https://host/api/', 'docs'), 'https://host/api/docs');
    });

    test('ignores surrounding whitespace', () {
      expect(apiUrl('  https://host  ', 'docs'), 'https://host/docs');
    });
  });

  group('documentation URLs', () {
    test('point at the paths the FastAPI app actually serves', () {
      const base = 'http://127.0.0.1:8000';
      expect(apiDocsUrl(base), '$base/docs');
      expect(apiRedocUrl(base), '$base/redoc');
      expect(apiSchemaUrl(base), '$base/openapi.json');
    });
  });

  group('canEmbedDocsInline', () {
    test('allows a secure page to frame secure docs', () {
      expect(
        canEmbedDocsInline(pageScheme: 'https', docsUrl: 'https://api.example.com/docs'),
        isTrue,
      );
    });

    test('allows an insecure page to frame insecure docs', () {
      expect(canEmbedDocsInline(pageScheme: 'http', docsUrl: 'http://127.0.0.1:8000/docs'), isTrue);
    });

    test('allows an insecure page to frame secure docs', () {
      expect(
        canEmbedDocsInline(pageScheme: 'http', docsUrl: 'https://api.example.com/docs'),
        isTrue,
      );
    });

    test('refuses to frame insecure docs from a secure page (mixed content)', () {
      // The homelab case: the web build behind HTTPS, the backend still on
      // plain HTTP. The browser blocks it and renders a silently blank frame.
      expect(
        canEmbedDocsInline(pageScheme: 'https', docsUrl: 'http://127.0.0.1:8000/docs'),
        isFalse,
      );
    });

    test('compares case-insensitively', () {
      expect(
        canEmbedDocsInline(pageScheme: 'HTTPS', docsUrl: 'HTTP://127.0.0.1:8000/docs'),
        isFalse,
      );
      expect(
        canEmbedDocsInline(pageScheme: 'HTTPS', docsUrl: 'HTTPS://api.example.com/docs'),
        isTrue,
      );
    });
  });
}
