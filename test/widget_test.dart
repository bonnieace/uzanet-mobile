import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:uzanet/api/uzanet_api.dart';
import 'package:uzanet/screens/login_page.dart';
import 'package:uzanet/screens/router_onboarding_page.dart';

class FakeApi extends UzanetApi {
  bool loggedIn = false;
  Map<String, dynamic>? onboardingRequest;

  @override
  Future<void> login(String username, String password) async {
    loggedIn = username == 'operator' && password == 'correct-password';
    if (!loggedIn) {
      throw const UzanetApiException(
        'Incorrect username or password',
        statusCode: 401,
      );
    }
  }

  @override
  Future<Map<String, dynamic>> beginRouterOnboarding({
    required String name,
    required String portalSlug,
    String paymentProvider = 'mpesa',
    bool replaceManagedTunnel = false,
  }) async {
    onboardingRequest = {
      'name': name,
      'portal_slug': portalSlug,
      'payment_provider': paymentProvider,
      'replace_managed_tunnel': replaceManagedTunnel,
    };
    return {
      'router': {'name': name, 'portal_slug': portalSlug},
      'expires_at': '2026-09-10T00:30:00',
      'install_command': '/tool fetch url="https://api.uzanet.co.ke/setup"',
    };
  }
}

void main() {
  testWidgets('operator can sign in through the Uzanet API flow', (tester) async {
    final api = FakeApi();
    var signedIn = false;
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(api: api, onSignedIn: () => signedIn = true),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Username'),
      'operator',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'correct-password',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(api.loggedIn, isTrue);
    expect(signedIn, isTrue);
  });

  testWidgets('router onboarding sends the shared API contract', (tester) async {
    final api = FakeApi();
    await tester.pumpWidget(
      MaterialApp(home: RouterOnboardingPage(api: api)),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Router name'),
      'Westlands Branch',
    );
    await tester.pump();

    final slugField = tester.widget<TextFormField>(find.byType(TextFormField).at(1));
    expect(slugField.controller?.text, 'westlands-branch');

    await tester.tap(
      find.widgetWithText(FilledButton, 'Generate setup command'),
    );
    await tester.pumpAndSettle();

    expect(api.onboardingRequest?['name'], 'Westlands Branch');
    expect(api.onboardingRequest?['portal_slug'], 'westlands-branch');
    expect(find.text('Setup bundle ready'), findsOneWidget);
    expect(find.text('Copy setup command'), findsOneWidget);
  });
}
