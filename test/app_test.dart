import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uzanet/app.dart';
import 'package:uzanet/core/backend_api.dart';
import 'package:uzanet/ui/common.dart';
import 'package:uzanet/ui/remote.dart';
import 'package:flutter/services.dart';
import 'core_test.dart' show MemoryVault, FakeTransport, FakeRouter;

void main() {
  testWidgets(
    'onboarding copies command and retains the legacy script fallback',
    (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = call.arguments['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: OnboardingResult(
            result: {
              'install_command': ':do { /tool fetch }',
              'script': 'fallback-rsc',
              'expires_at': '2030-01-01T00:00:00',
              'l2tp_peer': {'provisioned': true},
            },
          ),
        ),
      );
      await tester.tap(find.text('Copy setup command'));
      await tester.pumpAndSettle();
      expect(copied, ':do { /tool fetch }');
      await tester.pumpWidget(
        const MaterialApp(
          home: OnboardingResult(
            result: {
              'script': 'legacy-rsc',
              'expires_at': '2030-01-01T00:00:00',
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Copy setup command'), findsNothing);
      await tester.tap(find.text('Manual RSC fallback'));
      await tester.pumpAndSettle();
      expect(find.text('legacy-rsc'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('free local setup is available without authentication', (
    tester,
  ) async {
    final vault = MemoryVault();
    final transport = FakeTransport();
    final api = BackendApi(vault, transport: transport);
    addTearDown(api.dispose);
    await tester.pumpWidget(
      UzaNetApp(vault: vault, api: api, routerApi: FakeRouter()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Add local router'), findsOneWidget);
    expect(transport.calls, isEmpty);
    await tester.tap(find.text('Add local router'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Test connection and save'),
      250,
      scrollable: find
          .descendant(
            of: find.byType(EditPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Test connection and save'), findsOneWidget);
    expect(find.text('Operator sign-in'), findsNothing);
  });
  testWidgets('remote tab presents sign-in and completes a login', (
    tester,
  ) async {
    final vault = MemoryVault();
    final api = BackendApi(vault, transport: FakeTransport());
    addTearDown(api.dispose);
    await tester.pumpWidget(UzaNetApp(vault: vault, api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remote workspace').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'operator');
    await tester.enterText(find.byType(TextFormField).at(1), 'password');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Remote routers'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await api.clear();
    await tester.pumpAndSettle();
    expect(find.text('Remote routers'), findsNothing);
    expect(find.text('Sign in'), findsOneWidget);
  });
  testWidgets('form locks duplicate submit while waiting', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: EditPage(
          title: 'Test',
          fields: const [InputSpec('name', 'Name')],
          submit: (v) async {
            calls++;
            await Future<void>.delayed(const Duration(seconds: 2));
            return true;
          },
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField), 'value');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });
}
