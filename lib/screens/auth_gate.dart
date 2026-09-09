import 'package:flutter/material.dart';

import '../api/uzanet_api.dart';
import 'login_page.dart';
import 'operator_home_page.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.api});

  final UzanetApi api;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _checking = true;
  bool _signedIn = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    await widget.api.restoreSession();
    var signedIn = false;
    if (widget.api.hasToken) {
      try {
        await widget.api.me();
        signedIn = true;
      } on UzanetApiException catch (error) {
        if (error.statusCode == 401) await widget.api.clearSession();
      } catch (_) {
        // Keep the stored session when the API is temporarily unreachable.
        signedIn = widget.api.hasToken;
      }
    }
    if (!mounted) return;
    setState(() {
      _signedIn = signedIn;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_signedIn) {
      return LoginPage(
        api: widget.api,
        onSignedIn: () => setState(() => _signedIn = true),
      );
    }
    return OperatorHomePage(
      api: widget.api,
      onSignedOut: () => setState(() => _signedIn = false),
    );
  }
}
