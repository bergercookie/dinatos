import 'package:dinatos_frontend/core/api_config.dart';
import 'package:dinatos_frontend/core/dio_provider.dart';
import 'package:dinatos_frontend/core/server_url_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults to the compiled-in API_BASE_URL', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(serverUrlProvider), ApiConfig.baseUrl);
  });

  test('main() can seed a different starting value via overrideWith', () {
    final container = ProviderContainer(
      overrides: [serverUrlProvider.overrideWith((ref) => 'https://stored.example.com')],
    );
    addTearDown(container.dispose);

    expect(container.read(serverUrlProvider), 'https://stored.example.com');
  });

  test("dioProvider's baseUrl starts out matching serverUrlProvider", () {
    final container = ProviderContainer(
      overrides: [serverUrlProvider.overrideWith((ref) => 'https://one.example.com')],
    );
    addTearDown(container.dispose);

    expect(container.read(dioProvider).options.baseUrl, 'https://one.example.com');
  });

  test('changing serverUrlProvider rebuilds dioProvider with the new baseUrl', () {
    final container = ProviderContainer(
      overrides: [serverUrlProvider.overrideWith((ref) => 'https://one.example.com')],
    );
    addTearDown(container.dispose);

    final firstDio = container.read(dioProvider);
    expect(firstDio.options.baseUrl, 'https://one.example.com');

    container.read(serverUrlProvider.notifier).state = 'https://two.example.com';
    final secondDio = container.read(dioProvider);

    expect(secondDio.options.baseUrl, 'https://two.example.com');
    // Not just a mutated baseUrl on the same instance -- a genuinely new
    // Dio, which is what makes AuthNotifier (which watches dioProvider)
    // rebuild too, and re-run its own bootstrap against the new server.
    expect(identical(firstDio, secondDio), isFalse);
  });
}
