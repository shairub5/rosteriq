import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/yahoo_auth_service.dart';
import '../state/yahoo_connection_provider.dart';

/// Season-long roster-management feature area: live Yahoo sync, injury-
/// report/transaction change detection, trade evaluation. Only the Yahoo
/// login/connection step is built so far - it's the foundation those
/// features will be built on, not functional yet itself.
class RosterManagementScreen extends ConsumerWidget {
  const RosterManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(yahooConnectionProvider);
    final YahooAuthService service = ref.read(yahooAuthServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Roster')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.construction, size: 48, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 16),
              const Text(
                'Coming soon',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'This will pull your live Yahoo roster and flag injury-report '
                'and transaction changes since your last check. For now, use '
                'Draft Night to build your team.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 16),
              _buildYahooConnectionSection(context, ref, connection, service),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildYahooConnectionSection(
    BuildContext context,
    WidgetRef ref,
    YahooConnectionState connection,
    YahooAuthService service,
  ) {
    if (!service.isConfigured) {
      return Text(
        'Yahoo login not configured - missing YAHOO_CLIENT_ID.\n'
        'Run with --dart-define-from-file=secrets.json (see secrets.json.example).',
        textAlign: TextAlign.center,
        style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13),
      );
    }

    switch (connection.status) {
      case YahooConnectionStatus.connected:
        return Column(
          children: [
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 20),
                SizedBox(width: 8),
                Text('Connected to Yahoo', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => ref.read(yahooConnectionProvider.notifier).disconnect(),
              child: const Text('Disconnect'),
            ),
          ],
        );
      case YahooConnectionStatus.connecting:
        return const CircularProgressIndicator();
      case YahooConnectionStatus.error:
        return Column(
          children: [
            Text(
              'Connection failed: ${connection.errorMessage}',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => ref.read(yahooConnectionProvider.notifier).connect(),
              child: const Text('Try Again'),
            ),
          ],
        );
      case YahooConnectionStatus.notConnected:
      case YahooConnectionStatus.unknown:
        return FilledButton.icon(
          onPressed: () => ref.read(yahooConnectionProvider.notifier).connect(),
          icon: const Icon(Icons.login),
          label: const Text('Connect to Yahoo'),
        );
    }
  }
}
