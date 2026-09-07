import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../core/models.dart';
import '../core/router_api.dart';
import '../core/vault.dart';
import '../core/vouchers.dart';
import 'common.dart';

Future<void> printTickets(String name, List<RecordData> tickets) async {
  if (tickets.isEmpty) {
    throw const AppFailure('No confirmed vouchers to print.');
  }
  final document = pw.Document();
  for (var start = 0; start < tickets.length; start += 18) {
    final group = tickets.skip(start).take(18);
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) => pw.Wrap(
          spacing: 8,
          runSpacing: 8,
          children: group
              .map(
                (ticket) => pw.Container(
                  width: 165,
                  height: 110,
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(border: pw.Border.all()),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        name,
                        maxLines: 1,
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text('Username: ${ticket['name']}'),
                      pw.Text('Password: ${ticket['password']}'),
                      pw.Text(
                        'Online time: ${ticket['limit-uptime'] ?? 'No limit'}',
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
  final bytes = await document.save();
  await Printing.layoutPdf(
    name: 'UzaNet vouchers',
    onLayout: (_) async => bytes,
  );
}

class LocalPage extends StatefulWidget {
  final Vault vault;
  final RouterApi api;
  const LocalPage({super.key, required this.vault, required this.api});
  @override
  State<LocalPage> createState() => _LocalPageState();
}

class _LocalPageState extends State<LocalPage> {
  LocalRouter? router;
  bool loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await widget.vault.read('local_router');
      if (mounted) {
        setState(() {
          router = value == null ? null : LocalRouter.decode(value);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          error =
              'Could not read saved router settings. Unlock your device and retry.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  Future<void> setup() async {
    final current = router;
    final result = await edit(
      context,
      title: current == null ? 'Add local router' : 'Edit local router',
      help:
          'Connect this device to the router’s Wi-Fi or LAN. Settings stay on this device. Enable the RouterOS API service first. TLS requires a certificate trusted by this device.',
      submitLabel: 'Test connection and save',
      fields: [
        InputSpec('name', 'Router name', initial: current?.name ?? '', max: 60),
        InputSpec(
          'address',
          'Private IPv4 address',
          initial: current?.address ?? '',
          validate: (v) => isLocalAddress(v)
              ? null
              : 'Use a private address such as 192.168.88.1.',
        ),
        InputSpec(
          'port',
          'API port',
          initial: '${current?.port ?? 8729}',
          validate: (v) => positiveInt(v, max: 65535),
        ),
        InputSpec(
          'tls',
          'Connection security',
          initial: current?.tls == false ? 'false' : 'true',
          choices: const {
            'true': 'TLS (API-SSL)',
            'false': 'Plain API on trusted LAN only',
          },
        ),
        InputSpec(
          'username',
          'Router username',
          initial: current?.username ?? '',
          max: 125,
        ),
        const InputSpec('password', 'Router password', secret: true, max: 256),
      ],
      submit: (v) async {
        final next = LocalRouter(
          name: v['name'],
          address: v['address'],
          port: int.parse(v['port']),
          tls: v['tls'] == 'true',
          username: v['username'],
          password: v['password'],
        );
        await widget.api.run(next, ['/system/resource/print']);
        await widget.vault.write('local_router', next.encode());
        return next;
      },
    );
    if (mounted && result is LocalRouter) {
      setState(() {
        router = result;
      });
    }
  }

  void open(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  void list(String title, String path, {bool users = false}) {
    final selected = router!;
    open(
      DataPage(
        title: title,
        load: () async => (await widget.api.run(
          selected,
          [path],
        )).map((row) => {...row, if (users) 'usage': usageState(row)}).toList(),
        item: (context, row, refresh) => LocalRecord(
          row: row,
          users: users,
          router: selected,
          api: widget.api,
          refresh: refresh,
        ),
      ),
    );
  }

  Future<void> forget() async {
    if (!await confirm(
      context,
      'Forget local router?',
      'Removes its connection details and saved voucher batch from this device. Users on the router remain.',
    )) {
      return;
    }
    try {
      if (router != null) {
        await VoucherBatch(widget.vault, widget.api, router!).clear();
      }
      await widget.vault.delete('local_router');
      if (mounted) {
        setState(() {
          router = null;
        });
      }
    } catch (e) {
      if (mounted) notice(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Local tools')),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Your router. Your device.',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Free local management and printed vouchers. No UzaNet account needed.',
              ),
              const SizedBox(height: 24),
              if (error != null) ...[
                Text(error!),
                TextButton(onPressed: load, child: const Text('Retry')),
              ] else if (router == null)
                FilledButton.icon(
                  onPressed: setup,
                  icon: const Icon(Icons.router),
                  label: const Text('Add local router'),
                )
              else ...[
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.router),
                    title: Text(router!.name),
                    subtitle: Text(
                      '${router!.address}:${router!.port} · ${router!.tls ? 'TLS' : 'Trusted LAN'}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Edit local settings',
                      icon: const Icon(Icons.settings),
                      onPressed: setup,
                    ),
                  ),
                ),
                _tile(
                  'Router status',
                  Icons.monitor_heart,
                  () => list('Router status', '/system/resource/print'),
                ),
                _tile(
                  'Hotspot servers',
                  Icons.wifi,
                  () => list('Hotspot servers', '/ip/hotspot/print'),
                ),
                _tile(
                  'Hotspot server profiles',
                  Icons.settings_input_antenna,
                  () => list('Server profiles', '/ip/hotspot/profile/print'),
                ),
                _tile(
                  'Hotspot user profiles',
                  Icons.speed,
                  () => list('User profiles', '/ip/hotspot/user/profile/print'),
                ),
                _tile(
                  'Users and usage',
                  Icons.people,
                  () => list(
                    'Hotspot users',
                    '/ip/hotspot/user/print',
                    users: true,
                  ),
                ),
                _tile(
                  'Active hotspot sessions',
                  Icons.online_prediction,
                  () => list('Active sessions', '/ip/hotspot/active/print'),
                ),
                _tile(
                  'PPPoE sessions',
                  Icons.cable,
                  () => list('PPPoE sessions', '/ppp/active/print'),
                ),
                _tile(
                  'Create and print vouchers',
                  Icons.confirmation_number,
                  () => open(
                    VouchersPage(
                      batch: VoucherBatch(widget.vault, widget.api, router!),
                    ),
                  ),
                ),
                _tile(
                  'Print existing vouchers',
                  Icons.print,
                  () => open(ExistingTickets(router: router!, api: widget.api)),
                ),
                _tile(
                  'Print active-session report',
                  Icons.description,
                  () => open(SessionReport(router: router!, api: widget.api)),
                ),
                TextButton(
                  onPressed: forget,
                  child: const Text('Forget router and local voucher batch'),
                ),
              ],
            ],
          ),
  );
  Widget _tile(String text, IconData icon, VoidCallback onTap) => ListTile(
    leading: Icon(icon),
    title: Text(text),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}

class LocalRecord extends StatefulWidget {
  final RecordData row;
  final bool users;
  final LocalRouter router;
  final RouterApi api;
  final VoidCallback refresh;
  const LocalRecord({
    super.key,
    required this.row,
    required this.users,
    required this.router,
    required this.api,
    required this.refresh,
  });
  @override
  State<LocalRecord> createState() => _LocalRecordState();
}

class _LocalRecordState extends State<LocalRecord> {
  bool busy = false;
  Future<void> remove() async {
    if (busy ||
        !await confirm(
          context,
          'Delete hotspot user?',
          'Remove ${widget.row['name']} from ${widget.router.name}?',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      busy = true;
    });
    try {
      await widget.api.run(widget.router, [
        '/ip/hotspot/user/remove',
        '=.id=${widget.row['.id']}',
      ]);
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
  Widget build(BuildContext context) => RecordCard(
    title: '${widget.row['name'] ?? widget.row['user'] ?? widget.router.name}',
    values: {
      for (final key in [
        'version',
        'board-name',
        'uptime',
        'cpu-load',
        'free-memory',
        'total-memory',
        'interface',
        'address-pool',
        'profile',
        'address',
        'mac-address',
        'rate-limit',
        'shared-users',
        'limit-uptime',
        'disabled',
        'dns-name',
        'hotspot-address',
      ])
        if (widget.row.containsKey(key))
          key.replaceAll('-', ' '): widget.row[key],
      if (widget.users) 'Usage': usageState(widget.row),
    },
    actions: widget.users && widget.row['.id'] != null
        ? [
            TextButton(
              onPressed: busy ? null : remove,
              child: const Text('Delete'),
            ),
          ]
        : [],
  );
}

class VouchersPage extends StatefulWidget {
  final VoucherBatch batch;
  const VouchersPage({super.key, required this.batch});
  @override
  State<VouchersPage> createState() => _VouchersPageState();
}

class _VouchersPageState extends State<VouchersPage> {
  bool busy = true;
  String? error;
  @override
  void initState() {
    super.initState();
    perform(widget.batch.load);
  }

  Future<void> perform(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e is AppFailure
              ? e.message
              : 'Could not save or load the voucher batch.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  Future<void> create() async {
    await perform(() async {
      final profiles = await widget.batch.api.run(widget.batch.router, [
        '/ip/hotspot/user/profile/print',
      ]);
      if (!mounted) return;
      await edit(
        context,
        title: 'Prepare vouchers',
        help:
            'Duration is total online time, not calendar expiry. Print only after creation is confirmed.',
        fields: [
          InputSpec(
            'count',
            'Number of vouchers',
            initial: '1',
            validate: (v) => positiveInt(v, max: 50),
          ),
          InputSpec(
            'profile',
            'Router profile',
            choices: {
              for (final row in profiles)
                if (row['name'] != null) row['name']: row['name'],
            },
          ),
          InputSpec(
            'duration',
            'Online time (e.g. 1h or 1d)',
            initial: '1h',
            validate: (v) =>
                RegExp(r'^(\d+[wdhms])+$').hasMatch(v) && routerDuration(v) > 0
                ? null
                : 'Enter a positive RouterOS duration.',
          ),
        ],
        submit: (v) async {
          await widget.batch.prepare(
            int.parse(v['count']),
            v['profile'],
            v['duration'],
          );
          return true;
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Voucher batch')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.batch.router.name,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text(
            'Saved securely on this device. Reprinting does not create more users.',
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(error!),
            ),
          if (widget.batch.tickets.isEmpty)
            FilledButton(
              onPressed: busy || !widget.batch.loaded ? null : create,
              child: const Text('Prepare a batch'),
            )
          else ...[
            FilledButton(
              onPressed: busy ? null : () => perform(widget.batch.provision),
              child: const Text('Create / verify remaining vouchers'),
            ),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () => perform(
                      () => printTickets(
                        widget.batch.router.name,
                        widget.batch.tickets
                            .where((t) => t['state'] == 'confirmed')
                            .toList(),
                      ),
                    ),
              child: const Text('Print confirmed vouchers'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (await confirm(
                        context,
                        'Clear saved batch?',
                        'Make sure confirmed tickets are printed. Unconfirmed users may exist on the router. This only clears the device copy.',
                      )) {
                        await perform(widget.batch.clear);
                      }
                    },
              child: const Text('Clear batch'),
            ),
            for (final ticket in widget.batch.tickets)
              ListTile(
                title: Text(ticket['name']),
                subtitle: Text(
                  '${ticket['state']} · ${ticket['profile']} · ${ticket['limit-uptime']}',
                ),
              ),
          ],
        ],
      ),
    ),
  );
}

class ExistingTickets extends StatelessWidget {
  final LocalRouter router;
  final RouterApi api;
  const ExistingTickets({super.key, required this.router, required this.api});
  Future<List<RecordData>> fetch() async =>
      (await api.run(router, ['/ip/hotspot/user/print']))
          .where(
            (t) =>
                t['name'] != 'default-trial' &&
                t['password'] != null &&
                (t['password'] as String).isNotEmpty,
          )
          .toList();
  @override
  Widget build(BuildContext context) => DataPage(
    title: 'Existing vouchers',
    load: fetch,
    addLabel: 'Print all vouchers',
    addIcon: Icons.print,
    add: () async {
      final tickets = await fetch();
      if (tickets.length > 500) {
        throw const AppFailure(
          'This router has more than 500 vouchers. Print individual tickets or smaller new batches.',
        );
      }
      await printTickets(router.name, tickets);
    },
    item: (context, row, refresh) => RecordCard(
      title: row['name'] ?? 'Voucher',
      values: {'Usage': usageState(row), 'Online time': row['limit-uptime']},
      actions: [
        TextButton(
          onPressed: () async {
            try {
              await printTickets(router.name, [row]);
            } catch (e) {
              if (context.mounted) notice(context, e);
            }
          },
          child: const Text('Print voucher'),
        ),
      ],
    ),
  );
}

class SessionReport extends StatelessWidget {
  final LocalRouter router;
  final RouterApi api;
  const SessionReport({super.key, required this.router, required this.api});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Session report')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Text(
            'Print a snapshot of active hotspot sessions. This is not historical login activity.',
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              try {
                final sessions = await api.run(router, [
                  '/ip/hotspot/active/print',
                ]);
                final doc = pw.Document();
                doc.addPage(
                  pw.MultiPage(
                    build: (_) => [
                      pw.Text('${router.name} — active hotspot sessions'),
                      pw.Text(DateTime.now().toUtc().toIso8601String()),
                      ...sessions.map(
                        (s) => pw.Text(
                          '${s['user']} | ${s['address']} | ${s['uptime']}',
                        ),
                      ),
                    ],
                  ),
                );
                final bytes = await doc.save();
                await Printing.layoutPdf(onLayout: (_) async => bytes);
              } catch (e) {
                if (context.mounted) notice(context, e);
              }
            },
            child: const Text('Load and print'),
          ),
        ],
      ),
    ),
  );
}
