import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';
import 'package:veil_mobile/src/features/stories/data/story_feed_providers.dart';

// The relay takes a story only as an end-to-end encrypted envelope for a
// named audience. This build has no story sealer, so posting is refused on
// the device instead of sending the text in the clear.
void main() {
  testWidgets('posting a text story sends nothing', (tester) async {
    final requests = <String>[];
    final api = VeilApiClient(
      baseUrl: 'http://relay.invalid/v1',
      client: MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        return http.Response('{}', 201);
      }),
    );
    late StoryMutationResult result;
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api)],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () async => result = await createTextStory(ref, body: 'meet at the station at nine'),
            child: const Text('post'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('post'));
    await tester.pumpAndSettle();

    expect(result.success, isFalse);
    expect(result.errorMessage, contains('not end-to-end encrypted'));
    expect(requests, isEmpty);
  });
}
