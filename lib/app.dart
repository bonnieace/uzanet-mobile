import 'package:flutter/material.dart';
import 'core/backend_api.dart';
import 'core/models.dart';
import 'core/router_api.dart';
import 'core/vault.dart';
import 'ui/common.dart';
import 'ui/local.dart';
import 'ui/remote.dart';

class UzaNetApp extends StatefulWidget {
  final Vault? vault;
  final BackendApi? api;
  final RouterApi? routerApi;
  const UzaNetApp({super.key, this.vault, this.api, this.routerApi});
  @override
  State<UzaNetApp> createState() => _UzaNetAppState();
}

class _UzaNetAppState extends State<UzaNetApp> {
  late final vault = widget.vault ?? const DeviceVault();
  late final api = widget.api ?? BackendApi(vault);
  bool restoring = true;
  int tab = 0;
  String? startupError;
  @override
  void initState() {
    super.initState();
    restore();
  }

  Future<void> restore() async {
    try {
      await api.restore();
    } catch (_) {
      startupError =
          'Saved sign-in could not be read. Local tools are still available.';
    }
    if (mounted) {
      setState(() {
        restoring = false;
      });
    }
  }

  @override
  void dispose() {
    if (widget.api == null) api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'UzaNet',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xffd84232)),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    ),
    darkTheme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xffd84232),
        brightness: Brightness.dark,
      ),
    ),
    home: ListenableBuilder(
      listenable: api,
      builder: (context, _) => Scaffold(
        body: IndexedStack(
          index: tab,
          children: [
            WorkspaceNavigator(
              active: tab == 0,
              home: LocalPage(
                vault: vault,
                api: widget.routerApi ?? const SocketRouterApi(),
              ),
            ),
            WorkspaceNavigator(
              active: tab == 1,
              key: ValueKey(
                'remote-$restoring-${api.signedIn}-${api.sessionSerial}',
              ),
              home: restoring
                  ? const Center(child: CircularProgressIndicator())
                  : api.signedIn
                  ? RemoteShell(api: api)
                  : SignIn(api: api, message: api.authMessage ?? startupError),
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() {
            tab = i;
          }),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.router_outlined),
              selectedIcon: Icon(Icons.router),
              label: 'Local tools',
            ),
            NavigationDestination(
              icon: Icon(Icons.cloud_outlined),
              selectedIcon: Icon(Icons.cloud),
              label: 'Remote workspace',
            ),
          ],
        ),
      ),
    ),
  );
}

class WorkspaceNavigator extends StatefulWidget {
  final Widget home;
  final bool active;
  const WorkspaceNavigator({
    super.key,
    required this.home,
    required this.active,
  });
  @override
  State<WorkspaceNavigator> createState() => _WorkspaceNavigatorState();
}

class _WorkspaceNavigatorState extends State<WorkspaceNavigator> {
  final navigator = GlobalKey<NavigatorState>();
  @override
  Widget build(BuildContext context) => NavigatorPopHandler<Object?>(
    enabled: widget.active,
    onPopWithResult: (_) => navigator.currentState?.maybePop(),
    child: Navigator(
      key: navigator,
      onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => widget.home),
    ),
  );
}

class SignIn extends StatelessWidget {
  final BackendApi api;
  final String? message;
  const SignIn({super.key, required this.api, this.message});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Remote workspace')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.cloud_outlined, size: 64),
        const SizedBox(height: 24),
        Text(
          'Your ISP, wherever you are',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        const Text(
          'Sign in with your UzaNet operator account to manage remote routers, hotspot and PPPoE customers, plans and payments.',
        ),
        if (message != null) Text(message!),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => edit(
            context,
            title: 'Operator sign-in',
            fields: const [
              InputSpec('username', 'Username', max: 125),
              InputSpec('password', 'Password', secret: true, max: 128),
            ],
            submitLabel: 'Sign in',
            submit: (v) async {
              await api.login(v['username'], v['password']);
              return true;
            },
          ),
          child: const Text('Sign in'),
        ),
        const SizedBox(height: 12),
        const Text(
          'Local router tools remain free and do not require sign-in.',
        ),
      ],
    ),
  );
}

class RemoteShell extends StatelessWidget {
  final BackendApi api;
  const RemoteShell({super.key, required this.api});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${api.user?['username']}'),
      actions: [
        PopupMenuButton<String>(
          onSelected: (value) async {
            if (value == 'logout') {
              if (!await confirm(
                context,
                'Sign out?',
                'This revokes the account’s sessions on other devices too. Local router settings remain on this device.',
              )) {
                return;
              }
              try {
                await api.logout();
              } catch (_) {
                if (context.mounted) {
                  notice(
                    context,
                    const AppFailure(
                      'Signed out locally. Server revocation could not be confirmed.',
                    ),
                  );
                }
              }
            } else {
              await edit(
                context,
                title: 'Change password',
                help: 'Changing your password signs out all sessions.',
                fields: const [
                  InputSpec(
                    'current_password',
                    'Current password',
                    secret: true,
                    max: 128,
                  ),
                  InputSpec(
                    'new_password',
                    'New password',
                    secret: true,
                    min: 12,
                    max: 128,
                  ),
                ],
                submit: (v) async {
                  await api.call('POST', 'users/change-password', body: v);
                  await api.clear();
                  return true;
                },
              );
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'password', child: Text('Change password')),
            PopupMenuItem(value: 'logout', child: Text('Sign out')),
          ],
        ),
      ],
    ),
    body: RemoteHome(api: api),
  );
}
