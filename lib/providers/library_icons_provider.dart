import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../media/ids.dart';
import '../media/library_icons_client.dart';
import '../media/media_library.dart';
import '../mixins/disposable_change_notifier_mixin.dart';
import '../models/library_icons.dart';
import '../utils/app_logger.dart';
import '../utils/global_key_utils.dart';
import 'multi_server_provider.dart';

/// The library icons the user picked, read from each online server that
/// stores them, so the menus, library header and pickers all agree.
class LibraryIconsProvider extends ChangeNotifier with DisposableChangeNotifierMixin {
  LibraryIconsProvider(this._multiServer) {
    _multiServer.addOnlineServersListener(_onServersChanged);
    _onServersChanged(_multiServer.onlineServerIds.toSet());
  }

  final MultiServerProvider _multiServer;

  /// Saved icon ids by library global key.
  final Map<String, String> _saved = {};
  final Set<String> _loadedServers = {};

  @override
  void dispose() {
    _multiServer.removeOnlineServersListener(_onServersChanged);
    super.dispose();
  }

  /// The icon for [library]; null shows its name only.
  IconData? iconFor(MediaLibrary library) => LibraryIcons.resolve(library, _saved[library.globalKey]);

  /// The saved choice for [library], or null for the starting icon.
  String? savedFor(MediaLibrary library) => _saved[library.globalKey];

  bool canCustomize(MediaLibrary library) => _clientFor(library) != null;

  LibraryIconsClient? _clientFor(MediaLibrary library) {
    final serverId = library.serverId;
    if (serverId == null) return null;
    final client = _multiServer.getClientForServer(ServerId(serverId));
    return client is LibraryIconsClient && (client as LibraryIconsClient).supportsLibraryIcons
        ? client as LibraryIconsClient
        : null;
  }

  void _onServersChanged(Set<String> online) {
    for (final serverId in online) {
      if (_loadedServers.add(serverId)) _load(serverId);
    }
    _loadedServers.removeWhere((id) => !online.contains(id));
  }

  Future<void> _load(String serverId) async {
    final client = _multiServer.getClientForServer(ServerId(serverId));
    if (client is! LibraryIconsClient || !(client as LibraryIconsClient).supportsLibraryIcons) return;
    try {
      final icons = await (client as LibraryIconsClient).fetchLibraryIcons();
      if (isDisposed) return;
      for (final entry in icons.entries) {
        _saved[buildGlobalKey(ServerId(serverId), entry.key)] = entry.value;
      }
      safeNotifyListeners();
    } catch (e) {
      appLogger.w('Library icons: could not load from $serverId', error: e);
      _loadedServers.remove(serverId);
    }
  }

  /// Save [iconId] (a [LibraryIcons] id, [LibraryIcons.none], or null for
  /// the starting icon) and show it straight away.
  Future<void> setIcon(MediaLibrary library, String? iconId) async {
    final client = _clientFor(library);
    if (client == null) return;
    final key = library.globalKey;
    final previous = _saved[key];
    iconId == null ? _saved.remove(key) : _saved[key] = iconId;
    safeNotifyListeners();
    try {
      await client.saveLibraryIcon(library.id, iconId);
    } catch (e) {
      previous == null ? _saved.remove(key) : _saved[key] = previous;
      safeNotifyListeners();
      rethrow;
    }
  }
}

/// The icon for [library] from the nearest [LibraryIconsProvider], or the
/// starting icon where none is in scope (a sheet on the root navigator).
/// Null means the library shows its name only.
IconData? libraryIconOf(BuildContext context, MediaLibrary library, {bool listen = true}) {
  final provider = listen ? context.watch<LibraryIconsProvider?>() : context.read<LibraryIconsProvider?>();
  return provider == null ? LibraryIcons.defaultFor(library) : provider.iconFor(library);
}
