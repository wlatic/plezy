import 'media_hub.dart';

/// A server that can supply the user's own, server-configured home rows (for
/// example Jellyfin with the Home Screen Sections plugin).
abstract interface class ServerHomeRowsClient {
  /// The user's home rows in display order, or null when the server has none
  /// configured, in which case home builds its default rows.
  Future<List<MediaHub>?> fetchServerHomeRows({required int limit});
}
