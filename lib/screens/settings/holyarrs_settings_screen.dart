import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../focus/focusable_button.dart';
import '../../focus/focusable_text_field.dart';
import '../../providers/holyarrs_account_provider.dart';
import '../../services/holyarrs/holyarrs_client.dart';
import '../../utils/dialogs.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/loading_indicator_box.dart';
import '../../widgets/settings_page.dart';
import '../../widgets/settings_section.dart';

enum _HolyArrsSignIn { apiKey, password, jellyfin }

/// Connect Plezy to HolyArrs, or show and end the connection.
class HolyArrsSettingsScreen extends StatefulWidget {
  const HolyArrsSettingsScreen({super.key});

  @override
  State<HolyArrsSettingsScreen> createState() => _HolyArrsSettingsScreenState();
}

class _HolyArrsSettingsScreenState extends State<HolyArrsSettingsScreen> {
  final _url = TextEditingController(text: 'http://10.0.10.100:6262');
  final _name = TextEditingController();
  final _secret = TextEditingController();
  var _method = _HolyArrsSignIn.apiKey;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _name.dispose();
    _secret.dispose();
    super.dispose();
  }

  Future<void> _connect(HolyArrsAccountProvider account) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final base = HolyArrsClient.normalizeBaseUrl(_url.text);
      HolyArrsCredentials credentials;
      if (_method == _HolyArrsSignIn.apiKey) {
        credentials = HolyArrsCredentials(baseUrl: base, apiKey: _secret.text.trim());
      } else {
        credentials = await HolyArrsClient.signIn(
          baseUrl: base,
          name: _name.text.trim(),
          password: _secret.text,
          throughJellyfin: _method == _HolyArrsSignIn.jellyfin,
          keyLabel: 'Plezy Home',
        );
      }
      // Proves the address and key work, and names the person.
      final name = await HolyArrsClient(credentials).whoAmI();
      await account.connect(credentials.copyWith(displayName: name));
    } on HolyArrsException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not reach HolyArrs: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect(HolyArrsAccountProvider account) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Disconnect HolyArrs?',
      message: 'Explore and requests go back to Seerr, if it is connected.',
      confirmText: 'Disconnect',
      isDestructive: true,
    );
    if (confirmed) await account.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<HolyArrsAccountProvider>(
      builder: (context, account, _) {
        final credentials = account.credentials;
        return SettingsPage(
          title: const Text('HolyArrs'),
          children: credentials != null ? _connected(account, credentials) : _form(account),
        );
      },
    );
  }

  List<Widget> _connected(HolyArrsAccountProvider account, HolyArrsCredentials credentials) => [
    SettingsGroup(
      children: [
        ListTile(
          leading: const AppIcon(Symbols.account_circle_rounded, fill: 1),
          title: Text('Connected as ${credentials.displayName ?? 'HolyArrs user'}'),
          subtitle: const Text('Explore, badges and requests use HolyArrs'),
        ),
        ListTile(
          leading: const AppIcon(Symbols.dns_rounded, fill: 1),
          title: const Text('Server'),
          subtitle: Text(credentials.baseUrl),
        ),
      ],
    ),
    const SizedBox(height: 24),
    FocusableButton(
      useBackgroundFocus: true,
      onPressed: () => _disconnect(account),
      child: OutlinedButton.icon(
        onPressed: () => _disconnect(account),
        icon: const AppIcon(Symbols.link_off_rounded, fill: 1),
        label: const Text('Disconnect'),
      ),
    ),
  ];

  List<Widget> _form(HolyArrsAccountProvider account) {
    final theme = Theme.of(context);
    Widget methodButton(_HolyArrsSignIn method, String label) {
      final selected = _method == method;
      void pick() => setState(() {
        _method = method;
        _error = null;
      });
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: FocusableButton(
            useBackgroundFocus: true,
            onPressed: _busy ? null : pick,
            child: selected
                ? FilledButton(onPressed: _busy ? null : pick, child: Text(label))
                : OutlinedButton(onPressed: _busy ? null : pick, child: Text(label)),
          ),
        ),
      );
    }

    return [
      Text(
        'Use HolyArrs for Explore, availability badges and requests. '
        'Requests are filed under the HolyArrs person you sign in as.',
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: 16),
      FocusableTextFormField(
        controller: _url,
        enabled: !_busy,
        keyboardType: TextInputType.url,
        autocorrect: false,
        enableSuggestions: false,
        decoration: const InputDecoration(
          labelText: 'HolyArrs address',
          prefixIcon: AppIcon(Symbols.link_rounded, fill: 1),
        ),
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          methodButton(_HolyArrsSignIn.apiKey, 'API key'),
          methodButton(_HolyArrsSignIn.password, 'HolyArrs password'),
          methodButton(_HolyArrsSignIn.jellyfin, 'Jellyfin'),
        ],
      ),
      const SizedBox(height: 16),
      if (_method != _HolyArrsSignIn.apiKey) ...[
        FocusableTextFormField(
          controller: _name,
          enabled: !_busy,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: _method == _HolyArrsSignIn.jellyfin ? 'Jellyfin username' : 'HolyArrs username',
            prefixIcon: const AppIcon(Symbols.person_rounded, fill: 1),
          ),
        ),
        const SizedBox(height: 12),
      ],
      FocusableTextFormField(
        controller: _secret,
        enabled: !_busy,
        obscureText: _method != _HolyArrsSignIn.apiKey,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: _method == _HolyArrsSignIn.apiKey ? 'API key (HolyArrs → My account → API keys)' : 'Password',
          prefixIcon: AppIcon(_method == _HolyArrsSignIn.apiKey ? Symbols.key_rounded : Symbols.lock_rounded, fill: 1),
        ),
      ),
      const SizedBox(height: 16),
      FocusableButton(
        useBackgroundFocus: true,
        onPressed: _busy ? null : () => _connect(account),
        child: FilledButton.icon(
          onPressed: _busy ? null : () => _connect(account),
          icon: _busy ? const LoadingIndicatorBox() : const AppIcon(Symbols.login_rounded, fill: 1),
          label: const Text('Connect'),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
      ],
    ];
  }
}
