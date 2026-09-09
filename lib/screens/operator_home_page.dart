import 'package:flutter/material.dart';

import '../api/uzanet_api.dart';
import 'router_onboarding_page.dart';

class OperatorHomePage extends StatefulWidget {
  const OperatorHomePage({
    super.key,
    required this.api,
    required this.onSignedOut,
  });

  final UzanetApi api;
  final VoidCallback onSignedOut;

  @override
  State<OperatorHomePage> createState() => _OperatorHomePageState();
}

class _OperatorHomePageState extends State<OperatorHomePage> {
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _routers = const [];
  Map<String, Map<String, dynamic>> _statusByUid = const {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await widget.api.me();
      final routers = await widget.api.routers();
      List<Map<String, dynamic>> statuses = const [];
      try {
        statuses = await widget.api.routerStatuses();
      } catch (_) {
        // Router list remains useful even when live probing is unavailable.
      }
      final statusByUid = <String, Map<String, dynamic>>{};
      for (final status in statuses) {
        final uid = status['router_uid']?.toString();
        if (uid != null) statusByUid[uid] = status;
      }
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _routers = routers;
        _statusByUid = statusByUid;
      });
    } on UzanetApiException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 401) {
        await widget.api.clearSession();
        widget.onSignedOut();
        return;
      }
      setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to load your Uzanet account.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    await widget.api.logout();
    if (mounted) widget.onSignedOut();
  }

  Future<void> _onboard() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RouterOnboardingPage(api: widget.api)),
    );
    if (mounted) await _load();
  }

  String _statusFor(Map<String, dynamic> router) {
    final uid = router['uid']?.toString() ?? '';
    final live = _statusByUid[uid]?['status']?.toString();
    if (live != null) return live;
    return router['onboarding_status']?.toString() ?? 'unknown';
  }

  Color _statusColor(BuildContext context, String status) {
    if (status == 'online' || status == 'claimed') return Colors.green;
    if (status == 'offline' || status.contains('failed')) {
      return Theme.of(context).colorScheme.error;
    }
    return Colors.orange;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Uzanet'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') _logout();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'logout', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      floatingActionButton: _routers.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _onboard,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add router'),
            ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          children: [
            Text(
              _profile == null ? 'Operator workspace' : 'Hello, ${_profile!['username']}',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Your routers and onboarding state come from the same Uzanet API used by the web portal.',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            if (_loading && _routers.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null && _routers.isEmpty)
              _ErrorCard(message: _error!, onRetry: _load)
            else if (_routers.isEmpty)
              _FirstRouterCard(onStart: _onboard)
            else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Routers',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    '${_routers.length}',
                    style: TextStyle(color: colors.onSurfaceVariant, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final router in _routers) ...[
                _RouterCard(
                  router: router,
                  status: _statusFor(router),
                  statusColor: _statusColor(context, _statusFor(router)),
                ),
                const SizedBox(height: 12),
              ],
              if (_error != null) _ErrorCard(message: _error!, onRetry: _load),
            ],
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withOpacity(.45),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Legacy mobile tools retained', style: TextStyle(fontWeight: FontWeight.w800)),
                  SizedBox(height: 6),
                  Text(
                    'The previous direct RouterOS screens remain in the codebase during migration, but the production entry point no longer uses hardcoded local router credentials.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FirstRouterCard extends StatelessWidget {
  const _FirstRouterCard({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.primary, colors.primary.withOpacity(.78)],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.router_rounded, color: Colors.white, size: 34),
          const SizedBox(height: 18),
          Text(
            'Connect your first MikroTik',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Generate a secure one-line setup command, paste it into RouterOS, and let the router claim itself.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 18),
          FilledButton.tonalIcon(
            onPressed: onStart,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('Start onboarding'),
          ),
        ],
      ),
    );
  }
}

class _RouterCard extends StatelessWidget {
  const _RouterCard({
    required this.router,
    required this.status,
    required this.statusColor,
  });

  final Map<String, dynamic> router;
  final String status;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.router_rounded, color: colors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    router['name']?.toString() ?? 'MikroTik router',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    router['portal_slug']?.toString() ?? '',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                  if (router['routeros_version'] != null)
                    Text(
                      'RouterOS ${router['routeros_version']}',
                      style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                status,
                style: TextStyle(color: statusColor, fontWeight: FontWeight.w800, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: colors.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(color: colors.onErrorContainer))),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
