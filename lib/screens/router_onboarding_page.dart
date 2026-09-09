import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/uzanet_api.dart';

class RouterOnboardingPage extends StatefulWidget {
  const RouterOnboardingPage({super.key, required this.api});

  final UzanetApi api;

  @override
  State<RouterOnboardingPage> createState() => _RouterOnboardingPageState();
}

class _RouterOnboardingPageState extends State<RouterOnboardingPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _slug = TextEditingController();
  bool _busy = false;
  bool _replaceManagedTunnel = false;
  String _provider = 'mpesa';
  String? _error;
  Map<String, dynamic>? _bundle;

  @override
  void dispose() {
    _name.dispose();
    _slug.dispose();
    super.dispose();
  }

  String _slugify(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  Future<void> _generate() async {
    if (!_formKey.currentState!.validate() || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _bundle = null;
    });
    try {
      final result = await widget.api.beginRouterOnboarding(
        name: _name.text,
        portalSlug: _slug.text,
        paymentProvider: _provider,
        replaceManagedTunnel: _replaceManagedTunnel,
      );
      if (mounted) setState(() => _bundle = result);
    } on UzanetApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to create the onboarding bundle. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy(String value, String message) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final bundle = _bundle;
    final command = bundle?['install_command']?.toString() ?? '';
    final expiresAt = bundle?['expires_at']?.toString() ?? '';
    final router = bundle?['router'] is Map ? Map<String, dynamic>.from(bundle!['router'] as Map) : null;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Onboard MikroTik')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Connect a router', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            'Uzanet will generate the same one-line RouterOS setup command used by the web portal. Paste it into the MikroTik terminal; the router then claims itself over the control tunnel.',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 22),
          if (bundle == null)
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Router name', hintText: 'Westlands branch'),
                    onChanged: (value) {
                      if (_slug.text.isEmpty || _slug.text == _slugify(_name.text.substring(0, _name.text.length - (value.isNotEmpty ? 1 : 0)))) {
                        _slug.text = _slugify(value);
                      }
                    },
                    validator: (value) => value == null || value.trim().length < 2 ? 'Enter a router name.' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _slug,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Portal slug', hintText: 'westlands-branch'),
                    validator: (value) {
                      final slug = value?.trim() ?? '';
                      if (!RegExp(r'^[a-z0-9](?:[a-z0-9-]{1,58}[a-z0-9])$').hasMatch(slug)) {
                        return 'Use 3–60 lowercase letters, numbers and hyphens.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _provider,
                    decoration: const InputDecoration(labelText: 'Payment provider'),
                    items: const [
                      DropdownMenuItem(value: 'mpesa', child: Text('M-Pesa Direct')),
                      DropdownMenuItem(value: 'kopokopo', child: Text('Kopo Kopo')),
                    ],
                    onChanged: (value) => setState(() => _provider = value ?? 'mpesa'),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Replace existing Uzanet-managed tunnel'),
                    subtitle: const Text('Only enable this when this physical router was previously paired to another Uzanet router record.'),
                    value: _replaceManagedTunnel,
                    onChanged: (value) => setState(() => _replaceManagedTunnel = value),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: colors.errorContainer, borderRadius: BorderRadius.circular(12)),
                      child: Text(_error!, style: TextStyle(color: colors.onErrorContainer)),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _generate,
                      icon: _busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.router_rounded),
                      label: Text(_busy ? 'Generating…' : 'Generate setup command'),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: colors.primaryContainer, borderRadius: BorderRadius.circular(16)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_rounded, color: colors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Setup bundle ready', style: TextStyle(fontWeight: FontWeight.w800, color: colors.onPrimaryContainer)),
                        const SizedBox(height: 4),
                        Text(router?['name']?.toString() ?? _name.text, style: TextStyle(color: colors.onPrimaryContainer)),
                        if (expiresAt.isNotEmpty) Text('Run before $expiresAt', style: TextStyle(color: colors.onPrimaryContainer)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text('1. Open Terminal in WinBox, WebFig or the MikroTik app.'),
            const SizedBox(height: 8),
            const Text('2. Paste the complete command below and run it once.'),
            const SizedBox(height: 8),
            const Text('3. Return here and refresh the router list after the router reports success.'),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark ? Colors.black26 : const Color(0xFFF4F6F8),
                borderRadius: BorderRadius.circular(14),
              ),
              child: SelectableText(command, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.45)),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: command.isEmpty ? null : () => _copy(command, 'Setup command copied.'),
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy setup command'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => setState(() {
                _bundle = null;
                _error = null;
              }),
              child: const Text('Onboard another router'),
            ),
          ],
        ],
      ),
    );
  }
}
