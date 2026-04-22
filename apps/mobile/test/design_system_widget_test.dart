import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

void main() {
  testWidgets('design system primitives render with premium dark semantics', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _DesignTestApp(
        child: Scaffold(
          body: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                VeilHeroPanel(
                  eyebrow: 'SYSTEM',
                  title: 'VEIL',
                  body: 'Cold, restrained, and privacy-first.',
                  bottom: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      VeilStatusPill(label: 'Primary'),
                      VeilStatusPill(label: 'Warn', tone: VeilBannerTone.warn),
                    ],
                  ),
                ),
                SizedBox(height: VeilSpace.md),
                VeilInlineBanner(
                  title: 'Notice',
                  message: 'State changes stay explicit and readable.',
                ),
                SizedBox(height: VeilSpace.md),
                VeilConversationCard(
                  title: 'Atlas',
                  handle: 'atlas',
                  subtitle: 'Encrypted message',
                  timestamp: '08:45',
                  selected: true,
                  meta: Wrap(
                    spacing: 8,
                    children: [
                      VeilStatusPill(label: 'Direct'),
                      VeilStatusPill(label: 'Queued', tone: VeilBannerTone.warn),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('VEIL'), findsOneWidget);
    expect(find.text('Cold, restrained, and privacy-first.'), findsOneWidget);
    expect(find.text('Notice'), findsOneWidget);
    expect(find.text('Atlas'), findsOneWidget);
    expect(find.text('Queued'), findsOneWidget);
  });

  testWidgets('composer and action buttons keep accessible touch targets', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Draft');
    final focusNode = FocusNode();
    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    await tester.pumpWidget(
      _DesignTestApp(
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                VeilComposer(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: true,
                  onSubmit: () {},
                  trailing: VeilButton(
                    expanded: false,
                    label: 'Send',
                    onPressed: () {},
                    icon: Icons.arrow_upward_rounded,
                  ),
                ),
                const SizedBox(height: VeilSpace.md),
                const VeilActionRow(
                  children: [
                    VeilButton(
                      label: 'Primary',
                      onPressed: null,
                    ),
                    VeilButton(
                      label: 'Secondary',
                      onPressed: null,
                      tone: VeilButtonTone.secondary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final composerField = tester.widget<TextField>(find.byType(TextField).first);

    expect(composerField.maxLines, 5);
    expect(find.text('Send'), findsOneWidget);
    expect(find.text('Draft'), findsOneWidget);
  });

  testWidgets('skeleton and error states stay renderable under larger text scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(1.4)),
        child: _DesignTestApp(
          child: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                children: [
                  VeilErrorState(
                    title: 'Connection blocked',
                    body: 'Review runtime configuration and try again.',
                  ),
                  SizedBox(height: VeilSpace.md),
                  VeilSurfaceCard(
                    toned: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        VeilSkeletonLine(width: 96),
                        SizedBox(height: VeilSpace.sm),
                        VeilSkeletonLine(width: 220, height: 18),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Connection blocked'), findsOneWidget);
    expect(find.text('Review runtime configuration and try again.'), findsOneWidget);
    expect(find.byType(VeilSkeletonLine), findsNWidgets(2));
  });

  testWidgets('list tile card supports richer subtitle content', (tester) async {
    await tester.pumpWidget(
      const _DesignTestApp(
        child: Scaffold(
          body: Padding(
            padding: EdgeInsets.all(24),
            child: VeilListTileCard(
              eyebrow: 'Peer | Text',
              title: 'Selene',
              subtitle: 'fallback',
              subtitleWidget: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Peer | Text | Apr 3'),
                  SizedBox(height: 4),
                  Text('... orbit relay window ...'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Selene'), findsOneWidget);
    expect(find.text('Peer | Text'), findsOneWidget);
    expect(find.text('Peer | Text | Apr 3'), findsOneWidget);
    expect(find.text('... orbit relay window ...'), findsOneWidget);
  });

  testWidgets('metric strip and destructive notice remain readable', (tester) async {
    await tester.pumpWidget(
      const _DesignTestApp(
        child: Scaffold(
          body: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                VeilMetricStrip(
                  items: [
                    VeilMetricItem(label: 'Relay', value: 'Linked'),
                    VeilMetricItem(label: 'Recovery', value: 'None'),
                  ],
                ),
                SizedBox(height: VeilSpace.md),
                VeilDestructiveNotice(
                  title: 'No recovery path',
                  body: 'If this device is lost, VEIL cannot restore access.',
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Linked'), findsOneWidget);
    expect(find.text('None'), findsOneWidget);
    expect(find.text('No recovery path'), findsOneWidget);
  });
}

class _DesignTestApp extends StatelessWidget {
  const _DesignTestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: VeilTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );
  }
}
