import 'package:flutter/material.dart';
import '../core/models.dart';

void notice(BuildContext context, Object error) {
  final text = error is AppFailure
      ? error.message
      : 'The operation could not be completed. Please try again.';
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    ) ??
    false;

class InputSpec {
  final String key, label;
  final String initial;
  final bool secret, optional;
  final int min, max;
  final Map<String, String>? choices;
  final String? Function(String)? validate;
  const InputSpec(
    this.key,
    this.label, {
    this.initial = '',
    this.secret = false,
    this.optional = false,
    this.min = 1,
    this.max = 255,
    this.choices,
    this.validate,
  });
}

class EditPage extends StatefulWidget {
  final String title, help, submitLabel;
  final List<InputSpec> fields;
  final Future<dynamic> Function(RecordData values) submit;
  const EditPage({
    super.key,
    required this.title,
    required this.fields,
    required this.submit,
    this.help = '',
    this.submitLabel = 'Save',
  });
  @override
  State<EditPage> createState() => _EditPageState();
}

class _EditPageState extends State<EditPage> {
  final form = GlobalKey<FormState>();
  late final controllers = {
    for (final f in widget.fields)
      f.key: TextEditingController(text: f.initial),
  };
  bool busy = false;
  String? error;
  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final values = <String, dynamic>{};
      for (final f in widget.fields) {
        final v = f.secret
            ? controllers[f.key]!.text
            : controllers[f.key]!.text.trim();
        if (v.isNotEmpty || !f.optional) values[f.key] = v;
      }
      final result = await widget.submit(values);
      if (mounted) Navigator.pop(context, result ?? true);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e is AppFailure
              ? e.message
              : 'Could not complete the request. Check your connection and refresh before retrying.';
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

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Form(
            key: form,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (widget.help.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Text(widget.help),
                  ),
                for (final f in widget.fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: f.choices == null
                        ? TextFormField(
                            controller: controllers[f.key],
                            enabled: !busy,
                            obscureText: f.secret,
                            autocorrect: !f.secret,
                            enableSuggestions: !f.secret,
                            maxLength: f.max,
                            decoration: InputDecoration(
                              labelText: f.label,
                              counterText: '',
                            ),
                            validator: (raw) {
                              final value = f.secret
                                  ? raw ?? ''
                                  : (raw ?? '').trim();
                              if (value.isEmpty && f.optional) return null;
                              if (value.length < f.min ||
                                  value.length > f.max) {
                                return 'Enter ${f.min}–${f.max} characters.';
                              }
                              return f.validate?.call(value);
                            },
                          )
                        : DropdownButtonFormField<String>(
                            initialValue:
                                f.choices!.containsKey(controllers[f.key]!.text)
                                ? controllers[f.key]!.text
                                : null,
                            isExpanded: true,
                            decoration: InputDecoration(labelText: f.label),
                            items: f.choices!.entries
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e.key,
                                    child: Text(
                                      e.value,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: busy
                                ? null
                                : (v) {
                                    controllers[f.key]!.text = v ?? '';
                                  },
                            validator: (v) => v == null && !f.optional
                                ? 'Choose an option.'
                                : null,
                          ),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                FilledButton(
                  onPressed: busy ? null : save,
                  child: Text(busy ? 'Please wait…' : widget.submitLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Future<dynamic> edit(
  BuildContext context, {
  required String title,
  required List<InputSpec> fields,
  required Future<dynamic> Function(RecordData) submit,
  String help = '',
  String submitLabel = 'Save',
}) => Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => EditPage(
      title: title,
      fields: fields,
      submit: submit,
      help: help,
      submitLabel: submitLabel,
    ),
  ),
);

class DataPage extends StatefulWidget {
  final String title;
  final Future<List<RecordData>> Function() load;
  final Widget Function(BuildContext, RecordData, VoidCallback) item;
  final Future<void> Function()? add;
  final String? addLabel;
  const DataPage({
    super.key,
    required this.title,
    required this.load,
    required this.item,
    this.add,
    this.addLabel,
  });
  @override
  State<DataPage> createState() => _DataPageState();
}

class _DataPageState extends State<DataPage> {
  List<RecordData> rows = [];
  bool loading = true;
  bool adding = false;
  String query = '';
  String? error;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    final epoch = ++generation;
    setState(() {
      loading = true;
      error = null;
      rows = [];
    });
    try {
      final result = await widget.load();
      if (mounted && epoch == generation) {
        setState(() {
          rows = result;
        });
      }
    } catch (e) {
      if (mounted && epoch == generation) {
        setState(() {
          error = e is AppFailure ? e.message : 'Could not load this list.';
        });
      }
    } finally {
      if (mounted && epoch == generation) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: loading ? null : reload,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    floatingActionButton: widget.add == null
        ? null
        : FloatingActionButton.extended(
            onPressed: adding
                ? null
                : () async {
                    setState(() {
                      adding = true;
                    });
                    try {
                      await widget.add!();
                      if (mounted) reload();
                    } catch (e) {
                      if (context.mounted) notice(context, e);
                    } finally {
                      if (mounted) {
                        setState(() {
                          adding = false;
                        });
                      }
                    }
                  },
            label: Text(widget.addLabel ?? 'Add'),
            icon: const Icon(Icons.add),
          ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(error!),
                  TextButton(onPressed: reload, child: const Text('Retry')),
                ],
              ),
            ),
          )
        : rows.isEmpty
        ? const Center(child: Text('No records yet.'))
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Search records',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() {
                    query = value.trim().toLowerCase();
                  }),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: reload,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: filteredRows.length,
                    itemBuilder: (context, i) =>
                        widget.item(context, filteredRows[i], reload),
                  ),
                ),
              ),
            ],
          ),
  );
  List<RecordData> get filteredRows => query.isEmpty
      ? rows
      : rows
            .where(
              (row) =>
                  [
                    'name',
                    'username',
                    'pppoe_username',
                    'user',
                    'phone_number',
                    'mobile_number',
                    'invoice',
                    'status',
                    'event_type',
                    'usage',
                    'address',
                  ].any(
                    (key) => (row[key]?.toString().toLowerCase() ?? '')
                        .contains(query),
                  ),
            )
            .toList();
}

String? positiveInt(String value, {int max = 525600}) {
  final n = int.tryParse(value);
  return n == null || n < 1 || n > max
      ? 'Enter a whole number from 1 to $max.'
      : null;
}

class RecordCard extends StatelessWidget {
  final String title;
  final RecordData values;
  final List<Widget> actions;
  const RecordCard({
    super.key,
    required this.title,
    required this.values,
    this.actions = const [],
  });
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final e in values.entries)
            if (e.value != null && e.value.toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('${e.key}: ${e.value}'),
              ),
          if (actions.isNotEmpty) Wrap(spacing: 8, children: actions),
        ],
      ),
    ),
  );
}
