import 'dart:async';
import 'package:flutter/material.dart';
import '../core/backend_api.dart';
import '../core/checkout.dart';
import '../core/models.dart';
import 'common.dart';
import 'remote.dart' show records;

class CheckoutPage extends StatefulWidget {
  final BackendApi api;
  final String slug;
  final String? routerUid;
  const CheckoutPage({
    super.key,
    required this.api,
    required this.slug,
    this.routerUid,
  });
  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage>
    with WidgetsBindingObserver {
  Checkout? checkout;
  RecordData? portal;
  bool busy = true, visible = true;
  String? error;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    init();
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    visible = state == AppLifecycleState.resumed;
    if (!visible) {
      timer?.cancel();
    } else {
      schedule();
    }
  }

  Future<void> init() async {
    await run(() async {
      checkout = Checkout(widget.api, widget.slug, routerUid: widget.routerUid);
      await checkout!.load();
      portal = RecordData.from(
        await widget.api.call(
          'GET',
          'public/portals/${widget.slug}',
          authenticated: false,
        ),
      );
      if (checkout!.journal != null) await checkout!.refresh();
    });
  }

  Future<void> run(Future<void> Function() fn) async {
    timer?.cancel();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await fn();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e is AppFailure
              ? e.message
              : 'Could not recover payment. Keep this record and check payment recovery.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
        schedule();
      }
    }
  }

  void schedule() {
    timer?.cancel();
    if (!mounted || !visible || busy || error != null) return;
    final c = checkout;
    if (c?.journal == null ||
        ![
          'created',
          'pending',
          'paid',
          'provisioning',
        ].contains(c?.status?['status'])) {
      return;
    }
    final started = DateTime.tryParse(c!.journal!['created'] ?? '');
    if (started == null ||
        DateTime.now().difference(started) > const Duration(minutes: 10)) {
      return;
    }
    timer = Timer(const Duration(seconds: 5), () {
      if (mounted) run(c.refresh);
    });
  }

  Future<void> purchase(RecordData plan) async {
    if (busy) return;
    final ppp = plan['service_type'] == 'pppoe';
    await edit(
      context,
      title: ppp ? 'Renew PPPoE' : 'Buy hotspot access',
      help:
          '${plan['name']} · ${plan['currency'] ?? 'KES'} ${plan['price']} via ${portal?['payment_provider']}. A payment request will be sent to this phone.',
      submitLabel: 'Send payment request',
      fields: [
        const InputSpec(
          'phone_number',
          'M-Pesa phone number',
          min: 10,
          max: 20,
        ),
        if (ppp)
          const InputSpec(
            'customer_reference',
            'Existing PPPoE username',
            max: 125,
          ),
      ],
      submit: (v) async {
        await checkout!.start({...v, 'package_uid': plan['uid']});
        return true;
      },
    );
    if (mounted) setState(() {});
    schedule();
  }

  @override
  Widget build(BuildContext context) {
    final c = checkout;
    final result = c?.status;
    return Scaffold(
      appBar: AppBar(title: Text(portal?['name'] ?? 'Customer checkout')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null) ...[
            Text(error!),
            TextButton(
              onPressed: busy
                  ? null
                  : () => c?.journal != null ? run(c!.refresh) : init(),
              child: const Text('Retry / recover'),
            ),
          ],
          if (c?.journal != null) ...[
            Text(
              'Payment ${result?['status'] ?? 'unconfirmed'}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              result?['message'] ??
                  'The request may have reached the provider. Recover it before starting another payment.',
            ),
            if (result != null)
              Text(
                '${result['currency']} ${result['amount']} · ${result['phone_number'] ?? ''}',
              ),
            if (c!.journal!['payment_id'] != null)
              SelectableText('Payment ID: ${c.journal!['payment_id']}'),
            const SizedBox(height: 16),
            if (result?['status'] == 'provisioned' &&
                result?['credentials'] is Map)
              SelectableText(
                'Username: ${result!['credentials']['username']}\nPassword: ${result['credentials']['password']}',
              ),
            if (result?['account'] != null)
              Text('Renewed account: ${result!['account']}'),
            if ([
              'provisioning_failed',
              'manual_review',
            ].contains(result?['status']))
              const Text(
                'Do not pay again. Use Payment recovery or contact your operator.',
              ),
            FilledButton(
              onPressed: busy ? null : () => run(c.refresh),
              child: const Text('Check existing payment'),
            ),
            if (['provisioned', 'failed'].contains(result?['status']))
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        if (await confirm(
                          context,
                          'Close payment record?',
                          'This payment has a final outcome. Clear its saved device record to allow another purchase?',
                        )) {
                          await run(c.clear);
                        }
                      },
                child: const Text('Close this payment record'),
              ),
          ] else if (portal != null) ...[
            const Text(
              'Hotspot purchases and PPPoE renewals. The backend determines the price and payment provider.',
            ),
            for (final plan in records(portal!['packages']))
              RecordCard(
                title: plan['name'],
                values: {
                  'Price': '${plan['currency'] ?? 'KES'} ${plan['price']}',
                  'Service': plan['service_type'],
                  'Minutes': plan['validity_minutes'],
                  'Speed': plan['rate_limit'],
                },
                actions: [
                  FilledButton(
                    onPressed: busy ? null : () => purchase(plan),
                    child: Text(
                      plan['service_type'] == 'pppoe' ? 'Renew' : 'Buy access',
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}
