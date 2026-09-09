import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/backend_api.dart';
import '../core/models.dart';
import 'common.dart';
import 'checkout.dart';

String uid(dynamic value) {
  final text = value?.toString() ?? '';
  if (!RegExp(
    r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$',
  ).hasMatch(text)) {
    throw const AppFailure('Invalid record identifier. Refresh the list.');
  }
  return text;
}

List<RecordData> records(dynamic value) =>
    (value as List).map((x) => RecordData.from(x)).toList();
const providers = {'mpesa': 'M-Pesa', 'kopokopo': 'Kopo Kopo'};
String? slug(String value) =>
    RegExp(r'^[a-z0-9][a-z0-9-]{1,58}[a-z0-9]$').hasMatch(value)
    ? null
    : 'Use 3–60 lowercase letters, numbers or hyphens.';

class RemoteHome extends StatelessWidget {
  final BackendApi api;
  const RemoteHome({super.key, required this.api});
  Future<void> addRouter(BuildContext context) async {
    final mode = await showDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (context) => SimpleDialog(
        title: const Text('Add remote router'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'onboard'),
            child: const Text('Generate VPN onboarding script'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'direct'),
            child: const Text('Register an existing management connection'),
          ),
        ],
      ),
    );
    if (!context.mounted || mode == null) return;
    if (mode == 'onboard') {
      await onboarding(context);
      return;
    }
    await edit(
      context,
      title: 'Register remote router',
      help:
          'The backend must already be able to reach this management address. This does not copy your local device settings.',
      fields: [
        const InputSpec('name', 'Router name', min: 2, max: 125),
        const InputSpec('ip_address', 'Backend-reachable management address'),
        InputSpec(
          'port',
          'API port',
          initial: '8728',
          validate: (v) => positiveInt(v, max: 65535),
        ),
        const InputSpec('username', 'Router API username', max: 125),
        const InputSpec(
          'password',
          'Router API password',
          secret: true,
          min: 8,
          max: 256,
        ),
        InputSpec(
          'portal_slug',
          'Customer portal slug',
          min: 3,
          max: 60,
          validate: slug,
        ),
        const InputSpec(
          'payment_provider',
          'Payment provider',
          initial: 'mpesa',
          choices: providers,
        ),
      ],
      submit: (v) => api.call(
        'POST',
        'routers',
        body: {...v, 'port': int.parse(v['port'])},
      ),
    );
  }

  Future<void> onboarding(BuildContext context) async {
    final result = await edit(
      context,
      title: 'Onboard remote router',
      help:
          'Creates backend-managed VPN credentials and a RouterOS setup script. Run the script on the intended router to connect it to UzaNet.',
      submitLabel: 'Generate setup script',
      fields: [
        const InputSpec('name', 'Router name', min: 2, max: 125),
        InputSpec(
          'portal_slug',
          'Customer portal slug',
          min: 3,
          max: 60,
          validate: slug,
        ),
        const InputSpec(
          'payment_provider',
          'Payment provider',
          initial: 'mpesa',
          choices: providers,
        ),
        const InputSpec(
          'replace_managed_tunnel',
          'Replace existing UzaNet tunnel?',
          initial: 'no',
          choices: {
            'no': 'No — stop on conflict',
            'yes': 'Yes — disconnect previous UzaNet record',
          },
        ),
      ],
      submit: (v) => api.call(
        'POST',
        'routers/onboarding',
        body: {
          ...v,
          'replace_managed_tunnel': v['replace_managed_tunnel'] == 'yes',
        },
      ),
    );
    if (context.mounted && result is RecordData) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => OnboardingResult(result: result)),
      );
    }
  }

  @override
  Widget build(BuildContext context) => DataPage(
    title: 'Remote routers',
    load: () async => records(await api.call('GET', 'routers')),
    addLabel: 'Add router',
    add: () => addRouter(context),
    item: (context, row, refresh) => ListTile(
      leading: const Icon(Icons.router),
      title: Text(row['name'] ?? 'Router'),
      subtitle: Text(
        '${row['onboarding_status'] ?? row['connection_mode'] ?? ''} · ${row['portal_slug'] ?? ''}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RouterWorkspace(api: api, router: row),
        ),
      ),
    ),
  );
}

class OnboardingResult extends StatelessWidget {
  final RecordData result;
  const OnboardingResult({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final command = result['install_command'] as String?;
    return Scaffold(
      appBar: AppBar(title: const Text('Connect router')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Expires: ${result['expires_at']}. Keep this setup bundle private.',
          ),
          if (result['l2tp_peer']?['provisioned'] != true)
            const Text(
              'The VPN account was not provisioned automatically. Configure the peer on the VPS before running setup.',
            ),
          if (command != null && command.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Paste the whole command into the router terminal. It downloads over HTTPS, imports the script and removes the downloaded file.',
            ),
            SelectableText(command),
            FilledButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('Copy setup command'),
              onPressed: () async {
                try {
                  await Clipboard.setData(ClipboardData(text: command));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Setup command copied.')),
                    );
                  }
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Select and copy the command manually.'),
                      ),
                    );
                  }
                }
              },
            ),
            const Text(
              'The download works once. Keep the fallback RSC privately if you need to retry before expiry. The router needs a correct clock and trusted HTTPS certificates.',
            ),
          ],
          const SizedBox(height: 16),
          ExpansionTile(
            title: const Text('Manual RSC fallback'),
            children: [
              SelectableText(
                result['script'] as String? ?? 'No script returned.',
              ),
            ],
          ),
          const Text(
            'The script saves a configuration backup. Existing hotspot files and their redirect need updating separately. Refresh router status after setup to confirm connection.',
          ),
        ],
      ),
    );
  }
}

class SensitiveResult extends StatelessWidget {
  final String title, help, value;
  const SensitiveResult({
    super.key,
    required this.title,
    required this.help,
    required this.value,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(help),
        const SizedBox(height: 24),
        SelectableText(value),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

class RouterWorkspace extends StatelessWidget {
  final BackendApi api;
  final RecordData router;
  const RouterWorkspace({super.key, required this.api, required this.router});
  String get root => 'routers/${uid(router['uid'])}';
  void push(BuildContext context, Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  Future<void> settings(BuildContext context) async {
    final result = await edit(
      context,
      title: 'Router settings',
      fields: [
        InputSpec(
          'name',
          'Name',
          initial: router['name'] ?? '',
          min: 2,
          max: 125,
        ),
        InputSpec(
          'portal_slug',
          'Customer portal slug',
          initial: router['portal_slug'] ?? '',
          min: 3,
          max: 60,
          validate: slug,
        ),
        InputSpec(
          'payment_provider',
          'Payment provider',
          initial: router['payment_provider'] ?? 'mpesa',
          choices: providers,
        ),
        InputSpec(
          'portal_enabled',
          'Customer checkout',
          initial: '${router['portal_enabled'] == true}',
          choices: const {'true': 'Enabled', 'false': 'Disabled'},
        ),
        InputSpec(
          'ip_address',
          'Management address',
          initial: router['ip_address'] ?? '',
          optional: true,
        ),
        InputSpec(
          'port',
          'API port',
          initial: '${router['port'] ?? 8728}',
          validate: (v) => positiveInt(v, max: 65535),
        ),
        InputSpec(
          'username',
          'API username',
          initial: router['username'] ?? '',
          max: 125,
        ),
        const InputSpec(
          'password',
          'New router password (optional)',
          optional: true,
          secret: true,
          min: 8,
          max: 256,
        ),
      ],
      submit: (v) => api.call(
        'PATCH',
        root,
        body: {
          ...v,
          'port': int.parse(v['port']),
          'portal_enabled': v['portal_enabled'] == 'true',
        },
      ),
    );
    if (result is RecordData) {
      router.addAll(result);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(router['name'] ?? 'Router')),
    body: ListView(
      children: [
        for (final item in <(String, IconData, String)>[
          ('Connection status', Icons.monitor_heart, 'status'),
          ('Traffic', Icons.speed, 'traffic'),
          ('Plans', Icons.inventory_2, 'packages'),
          ('Hotspot customers', Icons.wifi, 'hotspot-users'),
          ('PPPoE customers', Icons.cable, 'pppoe-users'),
          ('Active sessions', Icons.people, 'active-users'),
          ('Payments', Icons.receipt_long, 'payments'),
          ('Payment recovery', Icons.sync, 'payment-sessions'),
          ('Activity log', Icons.history, 'logs'),
        ])
          ListTile(
            leading: Icon(item.$2),
            title: Text(item.$1),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => push(
              context,
              RemoteResource(
                api: api,
                router: router,
                resource: item.$3,
                title: item.$1,
              ),
            ),
          ),
        ListTile(
          leading: const Icon(Icons.shopping_cart_checkout),
          title: const Text('Customer checkout / renewal'),
          onTap: () => push(
            context,
            CheckoutPage(
              api: api,
              slug: router['portal_slug'] ?? '',
              routerUid: uid(router['uid']),
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.settings),
          title: const Text('Router settings'),
          onTap: () => settings(context),
        ),
        ListTile(
          leading: const Icon(Icons.delete_outline),
          title: const Text('Delete router'),
          onTap: () async {
            if (!await confirm(
              context,
              'Delete router?',
              'The backend prevents deletion while related records remain, including retired plans.',
            )) {
              return;
            }
            try {
              await api.call('DELETE', root);
              if (context.mounted) Navigator.pop(context);
            } catch (e) {
              if (context.mounted) notice(context, e);
            }
          },
        ),
      ],
    ),
  );
}

class RemoteResource extends StatelessWidget {
  final BackendApi api;
  final RecordData router;
  final String resource, title;
  const RemoteResource({
    super.key,
    required this.api,
    required this.router,
    required this.resource,
    required this.title,
  });
  String get root => 'routers/${uid(router['uid'])}/$resource';
  bool get customer => resource == 'hotspot-users' || resource == 'pppoe-users';
  Future<void> change(BuildContext context, [RecordData? row]) async {
    final fields = <InputSpec>[];
    if (resource == 'packages') {
      fields.addAll([
        InputSpec(
          'name',
          'Plan name',
          initial: row?['name'] ?? '',
          min: 2,
          max: 125,
        ),
        InputSpec(
          'description',
          'Description',
          initial: row?['description'] ?? '',
          optional: true,
          max: 1000,
        ),
        InputSpec(
          'price',
          'Price (KES)',
          initial: '${row?['price'] ?? ''}',
          validate: (v) =>
              RegExp(r'^\d{1,8}(\.\d{1,2})?$').hasMatch(v) &&
                  (double.tryParse(v) ?? 0) > 0
              ? null
              : 'Enter a positive KES amount, up to 2 decimal places.',
        ),
        if (row == null)
          const InputSpec(
            'service_type',
            'Service',
            initial: 'hotspot',
            choices: {'hotspot': 'Hotspot', 'pppoe': 'PPPoE'},
          ),
        InputSpec(
          'validity_minutes',
          'Validity in minutes',
          initial: '${row?['validity_minutes'] ?? 60}',
          validate: positiveInt,
        ),
        InputSpec(
          'router_profile',
          'Existing RouterOS profile',
          initial: row?['router_profile'] ?? 'default',
          max: 125,
        ),
        InputSpec(
          'rate_limit',
          'Rate label (optional)',
          initial: row?['rate_limit'] ?? '',
          optional: true,
          max: 64,
        ),
        InputSpec(
          'is_active',
          'Availability',
          initial: '${row?['is_active'] ?? true}',
          choices: const {'true': 'Active', 'false': 'Retired'},
        ),
      ]);
    } else if (customer) {
      final plans = records(
        await api.call('GET', 'routers/${uid(router['uid'])}/packages'),
      );
      final service = resource == 'hotspot-users' ? 'hotspot' : 'pppoe';
      final choices = {
        for (final p in plans)
          if (p['service_type'] == service && p['is_active'] == true)
            uid(p['uid']): '${p['name']} · KES ${p['price']}',
      };
      if (choices.isEmpty) {
        throw const AppFailure('Create an active plan for this service first.');
      }
      fields.add(InputSpec('package_uid', 'Plan', choices: choices));
      if (service == 'hotspot') {
        fields.addAll(const [
          InputSpec('phone_number', 'Customer phone', min: 10, max: 20),
          InputSpec(
            'username',
            'Username (optional)',
            optional: true,
            min: 4,
            max: 125,
          ),
          InputSpec(
            'password',
            'Password (optional)',
            optional: true,
            secret: true,
            min: 8,
            max: 128,
          ),
        ]);
      } else {
        fields.addAll(const [
          InputSpec('name', 'Customer name', min: 2, max: 125),
          InputSpec('pppoe_username', 'PPPoE username', min: 3, max: 125),
          InputSpec(
            'pppoe_password',
            'PPPoE password',
            secret: true,
            min: 8,
            max: 128,
          ),
          InputSpec('mobile_number', 'Customer phone', min: 10, max: 20),
          InputSpec('email', 'Email (optional)', optional: true, max: 125),
          InputSpec(
            'location',
            'Location (optional)',
            optional: true,
            max: 125,
          ),
          InputSpec(
            'apartment',
            'Apartment (optional)',
            optional: true,
            max: 125,
          ),
        ]);
      }
    }
    if (!context.mounted) return;
    final result = await edit(
      context,
      title:
          '${row == null ? 'Add' : 'Edit'} ${resource == 'packages' ? 'plan' : 'customer'}',
      fields: fields,
      help: resource == 'packages'
          ? 'RouterOS profile must already exist. The rate label describes the plan; speed is controlled by that router profile.'
          : 'This provisions access directly. It does not charge the customer. Use checkout for a paid purchase or renewal.',
      submit: (v) => api.call(
        row == null ? 'POST' : 'PATCH',
        row == null ? root : '$root/${uid(row['uid'])}',
        body: {
          ...v,
          if (resource == 'packages')
            'validity_minutes': int.parse(v['validity_minutes']),
          if (resource == 'packages') 'is_active': v['is_active'] == 'true',
        },
      ),
    );
    if (context.mounted &&
        result is RecordData &&
        result['credentials'] is Map) {
      final c = result['credentials'];
      pushSecret(
        context,
        'Hotspot credentials',
        'Shown once. Give these to the customer.',
        'Username: ${c['username']}\nPassword: ${c['password']}',
      );
    }
  }

  void pushSecret(
    BuildContext context,
    String title,
    String help,
    String value,
  ) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => SensitiveResult(title: title, help: help, value: value),
    ),
  );
  @override
  Widget build(BuildContext context) => DataPage(
    title: title,
    load: () async {
      final data = await api.call('GET', root);
      if (resource == 'status' || resource == 'traffic') {
        return [RecordData.from(data)];
      }
      if (resource == 'active-users') {
        return [
          ...records(data['hotspot']).map((r) => {...r, 'service': 'hotspot'}),
          ...records(data['pppoe']).map((r) => {...r, 'service': 'pppoe'}),
        ];
      }
      return records(data);
    },
    add: resource == 'packages' || customer
        ? () async {
            try {
              await change(context);
            } catch (e) {
              if (context.mounted) notice(context, e);
            }
          }
        : null,
    item: (context, row, refresh) => RemoteRecord(
      api: api,
      root: root,
      resource: resource,
      row: row,
      refresh: refresh,
      edit: resource == 'packages' ? () => change(context, row) : null,
    ),
  );
}

class RemoteRecord extends StatefulWidget {
  final BackendApi api;
  final String root, resource;
  final RecordData row;
  final VoidCallback refresh;
  final Future<void> Function()? edit;
  const RemoteRecord({
    super.key,
    required this.api,
    required this.root,
    required this.resource,
    required this.row,
    required this.refresh,
    this.edit,
  });
  @override
  State<RemoteRecord> createState() => _RemoteRecordState();
}

class _RemoteRecordState extends State<RemoteRecord> {
  bool busy = false;
  Future<void> act(String action) async {
    if (busy) return;
    if (!await confirm(
      context,
      action == 'retry' ? 'Retry access provisioning?' : '$action record?',
      action == 'retry'
          ? 'Retries delivering paid access. Does not charge the customer again.'
          : 'Apply this change to the selected record?',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      busy = true;
    });
    try {
      if (action == 'Edit') {
        await widget.edit!();
      } else if (action == 'retry') {
        await widget.api.call(
          'POST',
          'payments/${uid(widget.row['payment_id'])}/retry-provisioning',
        );
      } else {
        await widget.api.call(
          action == 'Delete' || action == 'Retire' ? 'DELETE' : 'POST',
          '${widget.root}/${uid(widget.row['uid'])}${action == 'Enable'
              ? '/enable'
              : action == 'Disable'
              ? '/disable'
              : ''}',
        );
      }
      widget.refresh();
    } catch (e) {
      if (mounted) notice(context, e);
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final resource = widget.resource;
    final actions = <String>[
      if (widget.edit != null) ...['Edit', 'Retire'],
      if (resource == 'hotspot-users' || resource == 'pppoe-users') ...[
        row['is_active'] == true ? 'Disable' : 'Enable',
        'Delete',
      ],
      if (resource == 'payment-sessions' && row['can_retry'] == true) 'retry',
    ];
    // Explicit display allowlist: never dump a backend response containing credentials.
    const fields = [
      'username',
      'pppoe_username',
      'phone_number',
      'mobile_number',
      'email',
      'location',
      'apartment',
      'is_active',
      'expires_at',
      'expires_on',
      'profile',
      'description',
      'price',
      'service_type',
      'validity_minutes',
      'router_profile',
      'rate_limit',
      'status',
      'authenticated',
      'version',
      'uptime',
      'rx_bits_per_second',
      'tx_bits_per_second',
      'address',
      'caller_id',
      'mac_address',
      'service',
      'amount',
      'currency',
      'provider',
      'provider_receipt',
      'invoice',
      'message',
      'customer_reference',
      'masked_phone',
      'created_at',
      'timestamp',
      'level',
      'event_type',
    ];
    return RecordCard(
      title:
          '${row['name'] ?? row['username'] ?? row['pppoe_username'] ?? row['user'] ?? row['invoice'] ?? row['status'] ?? row['event_type'] ?? 'Details'}',
      values: {
        for (final key in fields)
          if (row.containsKey(key)) key.replaceAll('_', ' '): row[key],
      },
      actions: actions
          .map(
            (a) => TextButton(
              onPressed: busy ? null : () => act(a),
              child: Text(a == 'retry' ? 'Retry provisioning' : a),
            ),
          )
          .toList(),
    );
  }
}
