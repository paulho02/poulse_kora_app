import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/server_config.dart';
import '../application/auth_providers.dart';

/// Entry point for pointing the app at a self-hosted backend instead of the
/// official server. Deliberately a small, muted icon rather than a field on
/// the form itself — the overwhelming majority of installs never touch this,
/// and it must not read as "something you're supposed to fill in" to them.
///
/// Native-app-only: a browser tab can't be trusted the way an installed app
/// can (anyone can point a stock browser at a lookalike page), so the web
/// build never offers this. `kIsWeb` is a compile-time constant, so this
/// branch — and the sheet it would open — is dead-code-eliminated from the
/// web bundle rather than merely hidden at runtime.
class ServerSettingsButton extends ConsumerWidget {
  const ServerSettingsButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb) return const SizedBox.shrink();

    final server = ref.watch(serverConfigProvider);
    return IconButton(
      icon: Icon(server.isCustom ? Icons.dns : Icons.dns_outlined),
      iconSize: 20,
      color: server.isCustom
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.outline,
      tooltip: server.isCustom
          ? 'Server: ${server.customBaseUrl}'
          : 'Server settings',
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => const _ServerSettingsSheet(),
      ),
    );
  }
}

class _ServerSettingsSheet extends ConsumerStatefulWidget {
  const _ServerSettingsSheet();

  @override
  ConsumerState<_ServerSettingsSheet> createState() =>
      _ServerSettingsSheetState();
}

class _ServerSettingsSheetState extends ConsumerState<_ServerSettingsSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _urlController;
  late bool _useCustom;

  @override
  void initState() {
    super.initState();
    final current = ref.read(serverConfigProvider);
    _useCustom = current.isCustom;
    _urlController = TextEditingController(text: current.customBaseUrl ?? '');
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_useCustom && !(_formKey.currentState?.validate() ?? false)) return;

    final current = ref.read(serverConfigProvider);
    final target = _useCustom ? normalizeServerUrl(_urlController.text) : null;

    // No actual change (e.g. the sheet was opened and saved without editing
    // anything): skip the session wipe below entirely, so idly opening this
    // doesn't cost the user their local theme/cache for nothing.
    if (target == current.customBaseUrl) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    // Switching servers means a different backend - possibly a different
    // account entirely - so anything scoped to the previous one (token,
    // cached responses, local settings) must not carry over.
    await ref.read(authNotifierProvider.notifier).logout();
    final notifier = ref.read(serverConfigProvider.notifier);
    if (_useCustom) {
      await notifier.useCustomServer(_urlController.text);
    } else {
      await notifier.useOfficialServer();
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Server', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Most people should leave this on the official server. Only '
              'change it if you were given a different one to connect to.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            RadioGroup<bool>(
              groupValue: _useCustom,
              onChanged: (v) => setState(() => _useCustom = v!),
              child: const Column(
                children: [
                  RadioListTile<bool>(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Official server'),
                    value: false,
                  ),
                  RadioListTile<bool>(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Custom server'),
                    value: true,
                  ),
                ],
              ),
            ),
            if (_useCustom) ...[
              const SizedBox(height: 8),
              TextFormField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'https://backend.example.com',
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _save(),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Server URL is required';
                  }
                  if (!isValidServerUrl(v)) {
                    return 'Enter a valid http(s) URL';
                  }
                  return null;
                },
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(onPressed: _save, child: const Text('Save')),
          ],
        ),
      ),
    );
  }
}
