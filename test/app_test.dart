import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uzanet/app.dart';
import 'package:uzanet/core/backend_api.dart';
import 'package:uzanet/ui/common.dart';
import 'core_test.dart' show MemoryVault, FakeTransport, FakeRouter;

void main() {
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
