import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../mixins/disposable_change_notifier_mixin.dart';
import '../profiles/profile.dart';
import '../services/base_shared_preferences_service.dart';
import '../services/credential_vault.dart';
import '../services/holyarrs/holyarrs_client.dart';
import '../utils/app_logger.dart';
import '../utils/serial_future_queue.dart';

/// Stores the active profile's HolyArrs connection; the API key is kept
/// encrypted by [CredentialVault], like the Seerr session.
class HolyArrsCredentialsStore {
  const HolyArrsCredentialsStore();

  static const String _baseKey = 'holyarrs_connection';
  static final SerialFutureQueue _persistence = SerialFutureQueue();

  String _scopedKey(String userUuid) => profileScopedPrefsKey(userUuid, _baseKey);

  Future<HolyArrsCredentials?> load(String userUuid) => _persistence.run(() async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final raw = prefs.getString(_scopedKey(userUuid));
    if (raw == null) return null;
    try {
      final stored = HolyArrsCredentials.fromJson(jsonDecode(raw));
      if (stored == null) return null;
      final key = await CredentialVault.reveal(stored.apiKey);
      return key == null || key.isEmpty ? null : stored.copyWith(apiKey: key);
    } catch (e) {
      appLogger.w('HolyArrs: stored connection unreadable', error: e);
      return null;
    }
  });

  Future<void> save(String userUuid, HolyArrsCredentials credentials) => _persistence.run(() async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final protected = credentials.copyWith(apiKey: await CredentialVault.protect(credentials.apiKey));
    await prefs.setString(_scopedKey(userUuid), jsonEncode(protected.toJson()));
  });

  Future<void> clear(String userUuid) => _persistence.run(() async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.remove(_scopedKey(userUuid));
  });
}

/// Owns the active profile's HolyArrs connection and the client built from
/// it; the catalog sources rebuild the HolyArrs source when [client] changes.
class HolyArrsAccountProvider extends ChangeNotifier with DisposableChangeNotifierMixin {
  HolyArrsAccountProvider({this.store = const HolyArrsCredentialsStore()});

  final HolyArrsCredentialsStore store;
  String _activeUserUuid = '';
  int _generation = 0;
  HolyArrsCredentials? _credentials;
  HolyArrsClient? _client;

  bool get isConnected => _credentials != null;
  HolyArrsCredentials? get credentials => _credentials;
  String? get displayName => _credentials?.displayName;

  /// Client for the catalog and request surfaces; null when disconnected.
  HolyArrsClient? get client => _client;

  Future<void> onActiveProfileChanged(String? newUserUuid) async {
    if (isDisposed) return;
    final userUuid = newUserUuid ?? '';
    final generation = ++_generation;
    _activeUserUuid = userUuid;
    _bind(null);
    final loaded = await store.load(userUuid);
    if (isDisposed || generation != _generation) return;
    _bind(loaded);
  }

  /// Persist and use a connection the connect screen established.
  Future<void> connect(HolyArrsCredentials credentials) async {
    if (isDisposed) return;
    final userUuid = _activeUserUuid;
    final generation = ++_generation;
    await store.save(userUuid, credentials);
    if (isDisposed || generation != _generation) return;
    _bind(credentials);
  }

  Future<void> disconnect() async {
    if (isDisposed) return;
    final userUuid = _activeUserUuid;
    ++_generation;
    _bind(null);
    await store.clear(userUuid);
  }

  void _bind(HolyArrsCredentials? credentials) {
    _credentials = credentials;
    _client = credentials == null ? null : HolyArrsClient(credentials);
    safeNotifyListeners();
  }
}
