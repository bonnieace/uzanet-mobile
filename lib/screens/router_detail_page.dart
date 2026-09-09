import 'package:flutter/material.dart';

import '../api/uzanet_api.dart';

class RouterDetailPage extends StatefulWidget {
  const RouterDetailPage({
    super.key,
    required this.api,
    required this.router,
  });

  final UzanetApi api;
  final Map<String, dynamic> router;

  @override
  State<RouterDetailPage> createState() => _RouterDetailPageState();
}

class _RouterDetailPageState extends State<RouterDetailPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _status;
  Map<String, dynamic>? _active;
  Map<String, dynamic>? _traffic;
  List<Map<String, dynamic>> _packages = const [];
  List<Map<String, dynamic>> _hotspotUsers = const [];
  List<Map<String, dynamic>> _pppoeUsers = const [];
  List<Map<String, dynamic>> _payments = const [];

  String get _uid => widget.router['uid']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<T?> _optional<T>(Future<T> future) async {
    try {
      return await future;
    } on UzanetApiException catch (error) {
      if (error.statusCode == 401) rethrow;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    if (_uid.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'This router record is missing its identifier.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await _optional(widget.api.routerStatus(_uid));
      final packages = await _optional(widget.api.packages(_uid));
      final hotspotUsers = await _optional(widget.api.hotspotUsers(_uid));
      final pppoeUsers = await _optional(widget.api.pppoeUsers(_uid));
      final active = await _optional(widget.api.activeUsers(_uid));
      final payments = await _optional(widget.api.payments(_uid));
      final traffic = await _optional(widget.api.traffic(_uid));
      if (!mounted) return;
      setState(() {
        _status = status;
        _packages = packages ?? const [];
        _hotspotUsers = hotspotUsers ?? const [];
        _pppoeUsers = pppoeUsers ?? const [];
        _active = active;
        _payments = payments ?? const [];
        _traffic = traffic;
      });
    } on UzanetApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to load this router.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _activeCount {
    final hotspot = _active?['hotspot'];
    final pppoe = _active?['pppoe'];
    return (hotspot is List ? hotspot.length : 0) + (pppoe is List ? pppoe.length : 0);
  }

  String _formatBits(Object? raw) {
    final value = raw is num ? raw.toDouble() : double.tryParse(raw?.toString() ?? '') ?? 0;
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)} Mbps';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)} Kbps';
    return '${value.toStringAsFixed(0)} bps';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final name = widget.router['name']?.toString() ?? 'MikroTik';
    final state = _status?['status']?.toString() ?? widget.router['onboarding_status']?.toString() ?? 'unknown';
    final online = state == 'online' || state == 'claimed';
    final recentPayments = _payments.take(5).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: online ? Colors.green.withAlpha(24) : colors.surfaceContainerHighest.withAlpha(110),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 25,
                    backgroundColor: online ? Colors.green.withAlpha(35) : colors.primaryContainer,
                    child: Icon(Icons.router_rounded, color: online ? Colors.green : colors.primary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                        const SizedBox(height: 3),
                        Text(widget.router['portal_slug']?.toString() ?? '', style: TextStyle(color: colors.onSurfaceVariant)),
                        if (widget.router['routeros_version'] != null)
                          Text('RouterOS ${widget.router['routeros_version']}', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
                      ],
                    ),
                  ),
                  _StatusPill(label: state, online: online),
                ],
              ),
            ),
            if (_loading) ...[
              const SizedBox(height: 24),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: colors.errorContainer, borderRadius: BorderRadius.circular(12)),
                child: Text(_error!, style: TextStyle(color: colors.onErrorContainer)),
              ),
            ],
            const SizedBox(height: 22),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.55,
              children: [
                _MetricCard(icon: Icons.sell_outlined, label: 'Packages', value: '${_packages.length}'),
                _MetricCard(icon: Icons.people_outline_rounded, label: 'Hotspot users', value: '${_hotspotUsers.length}'),
                _MetricCard(icon: Icons.home_work_outlined, label: 'PPPoE users', value: '${_pppoeUsers.length}'),
                _MetricCard(icon: Icons.wifi_tethering_rounded, label: 'Active now', value: '$_activeCount'),
              ],
            ),
            const SizedBox(height: 22),
            Text('Live traffic', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _TrafficCard(label: 'Download', value: _formatBits(_traffic?['rx_bits_per_second']), icon: Icons.south_rounded)),
                const SizedBox(width: 12),
                Expanded(child: _TrafficCard(label: 'Upload', value: _formatBits(_traffic?['tx_bits_per_second']), icon: Icons.north_rounded)),
              ],
            ),
            if (_traffic?['interface'] != null) ...[
              const SizedBox(height: 7),
              Text('Interface: ${_traffic!['interface']}', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Recent payments', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                Text('${_payments.length} total', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 10),
            if (recentPayments.isEmpty)
              Text('No payments recorded for this router yet.', style: TextStyle(color: colors.onSurfaceVariant))
            else
              for (final payment in recentPayments)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: colors.primaryContainer,
                    child: Icon(Icons.payments_outlined, color: colors.primary),
                  ),
                  title: Text('KES ${payment['amount'] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(payment['provider_receipt']?.toString() ?? payment['invoice']?.toString() ?? payment['provider']?.toString() ?? 'Payment'),
                  trailing: Text(payment['status']?.toString() ?? 'completed', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
                ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.online});
  final String label;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final color = online ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: color.withAlpha(28), borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11)),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: colors.primary, size: 21),
          Text(value, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          Text(label, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
        ],
      ),
    );
  }
}

class _TrafficCard extends StatelessWidget {
  const _TrafficCard({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: colors.primaryContainer.withAlpha(100), borderRadius: BorderRadius.circular(15)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.primary),
          const SizedBox(height: 12),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          Text(label, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
        ],
      ),
    );
  }
}
