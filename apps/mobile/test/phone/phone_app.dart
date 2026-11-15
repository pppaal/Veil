import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../layout/support/layout_world.dart';
import '../layout/support/phone_layout_probe.dart';

export '../layout/support/layout_world.dart';
export '../layout/support/phone_layout_probe.dart';

// The app on a phone-sized screen for behaviour tests: the layout gate's
// world (real routes, theme and strings over the fake relay) with a body
// that taps through it.

/// Opens the app at [location] on a phone of [size], runs [body], and takes
/// the app down again before the test ends, so no timer of the messenger
/// outlives it. [prepare] changes the seeded world before the app opens;
/// what it returns is what the route is opened with. [withGroup] adds the
/// seeded group to the account's conversations. [sessionError] is the
/// failure the session reports when the app opens.
Future<void> withPhoneApp(
  WidgetTester tester,
  LayoutIdentities identities, {
  required String location,
  required Future<void> Function(LayoutWorld world) body,
  Future<Object?> Function(LayoutWorld world)? prepare,
  PhoneSize size = phoneSmall,
  double keyboardHeight = 0,
  double textScale = 1,
  String locale = 'en',
  LayoutAccount account = LayoutAccount.signedIn,
  ChatAttention attention = const ChatAttention(),
  bool transferStarted = false,
  bool withGroup = false,
  String? sessionError,
}) async {
  usePhoneView(tester, size, keyboardHeight: keyboardHeight, textScale: textScale);
  final world = await LayoutWorld.create(
    identities: identities,
    account: account,
    locale: locale,
    attention: attention,
    transferStarted: transferStarted,
    withGroup: withGroup,
    sessionError: sessionError,
  );
  try {
    final extra = await prepare?.call(world);
    await tester.pumpWidget(world.app(location: location, extra: extra));
    await pumpFrames(tester);
    await body(world);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    world.dispose();
  }
}

/// Scrolls the screen to its end a screenful at a time and returns every
/// text that was on screen in the language the run is not in (see
/// [otherLanguageTextsOnScreen]): names and values included.
Future<Set<String>> otherLanguageTextsOfScreen(WidgetTester tester, String locale) async {
  final texts = otherLanguageTextsOnScreen(tester, locale);
  await scrollToEnd(tester, onPage: (_) async => texts.addAll(otherLanguageTextsOnScreen(tester, locale)));
  return texts;
}

/// The part of [finder]'s first widget that is on screen.
Rect onScreen(WidgetTester tester, Finder finder) =>
    visibleRect(tester, tester.renderObject<RenderBox>(finder.first));
