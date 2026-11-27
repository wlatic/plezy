import 'media_hub.dart';
import 'media_kind.dart';

/// A server that can supply the user's own, server-configured home rows (for
/// example Jellyfin with the Home Screen Sections plugin).
abstract interface class ServerHomeRowsClient {
  /// The user's home rows in display order, or null when the server has none
  /// configured, in which case home builds its default rows.
  Future<List<MediaHub>?> fetchServerHomeRows({required int limit});

  /// The server's own Discover row for [kind] (titles it can request but
  /// does not have), or null when it has none.
  Future<MediaHub?> fetchServerDiscoverRow(MediaKind kind, {required int limit});
}
