import 'package:flutter/foundation.dart';

import '../../utils/external_ids.dart';
import '../../media/media_kind.dart';
import '../../models/catalog/catalog_item.dart';
import '../../models/catalog/catalog_metadata.dart';
import '../holyarrs/holyarrs_client.dart';
import 'catalog_source.dart';

/// HolyArrs as an Explore source: its own personalised Explore rows (Top
/// picks, Because you have …, New seasons, …) for movies and shows, search,
/// and per-title library/request state for the availability badges.
/// Requests go through [client]; HolyArrs has no watchlist to mirror.
class HolyArrsCatalogSource implements CatalogSource, CatalogHubSource {
  HolyArrsCatalogSource(this.client);

  final HolyArrsClient client;
  final ValueNotifier<int> _watchlistChanges = ValueNotifier(0);

  @override
  CatalogSourceId get id => CatalogSourceId.holyarrs;

  @override
  String get displayName => 'HolyArrs';

  @override
  List<CatalogRowId> get supportedRows => const [];

  @override
  bool get supportsWatchlist => false;

  /// Whether a Request action can be offered for [kind].
  bool canRequest(MediaKind kind) => kind == MediaKind.movie || kind == MediaKind.show;

  /// Explore rows for one kind, already mapped to catalog items.
  Future<List<CatalogHub>> fetchKindHubs(MediaKind kind, {int limit = 25}) async {
    final type = kind == MediaKind.movie ? 'movies' : 'shows';
    final rows = await client.exploreRows(type);
    return [
      for (final row in rows)
        if (row.items.isNotEmpty)
          CatalogHub(
            id: '$type:${row.id}',
            title: row.title,
            page: CatalogPage(items: [for (final title in row.items.take(limit)) toCatalogItem(title)]),
          ),
    ];
  }

  @override
  Future<List<CatalogHub>> fetchHubs({int limit = 25}) async {
    final kinds = await Future.wait([
      fetchKindHubs(MediaKind.movie, limit: limit),
      fetchKindHubs(MediaKind.show, limit: limit),
    ]);
    // Interleave movie and show rows so neither kind is buried.
    final movies = kinds[0], shows = kinds[1];
    return [
      for (var i = 0; i < movies.length || i < shows.length; i++) ...[
        if (i < movies.length) movies[i],
        if (i < shows.length) shows[i],
      ],
    ];
  }

  @override
  Future<CatalogPage> fetchHub(String id, {int page = 1, int limit = 25}) async {
    if (page > 1) return const CatalogPage(items: []);
    final type = id.split(':').first;
    final kind = type == 'movies' ? MediaKind.movie : MediaKind.show;
    final hubs = await fetchKindHubs(kind, limit: limit);
    return hubs.where((hub) => hub.id == id).firstOrNull?.page ?? const CatalogPage(items: []);
  }

  @override
  Future<CatalogPage> fetchRow(CatalogRowId row, {int page = 1, int limit = 25}) async =>
      const CatalogPage(items: []);

  @override
  Future<List<CatalogItem>> search(String query, {int limit = 30}) async {
    final titles = await client.search(query);
    return [for (final title in titles.take(limit)) toCatalogItem(title)];
  }

  @override
  Future<CatalogDetail> fetchDetail(CatalogItem item, {int castLimit = 20, int relatedLimit = 20}) async =>
      CatalogDetail(item: item);

  static CatalogItem toCatalogItem(HolyArrsTitle title) => CatalogItem(
    source: CatalogSourceId.holyarrs,
    kind: title.kind == 'movie' ? MediaKind.movie : MediaKind.show,
    title: title.name,
    year: title.year,
    overview: title.overview,
    genres: title.genres.isEmpty ? null : title.genres,
    trailerUrl: title.trailerKey == null ? null : 'https://www.youtube.com/watch?v=${title.trailerKey}',
    ids: CatalogItemIds(tmdb: title.tmdbId),
    posterUrl: title.poster,
    backdropUrl: title.backdrop,
    logoUrl: title.logo,
    serverState: serverStateOf(title),
  );

  /// HolyArrs's library and request knowledge as the badges read it.
  static CatalogServerState? serverStateOf(HolyArrsTitle title) {
    final ask = title.askState;
    final state = CatalogServerState(
      availability: title.inLibrary || ask == 'available' ? CatalogAvailability.available : null,
      request: switch (ask) {
        'asked' => CatalogRequestState.pending,
        'approved' => CatalogRequestState.approved,
        'turned_down' => CatalogRequestState.declined,
        _ => null,
      },
    );
    return state.isEmpty ? null : state;
  }

  @override
  Future<void> ensureWatchlistLoaded() async {}

  @override
  bool? isOnWatchlist(MediaKind kind, CatalogItemIds ids) => null;

  @override
  Future<CatalogItemIds?> resolveItemIds(MediaKind kind, ExternalIds external) async =>
      external.tmdb == null ? null : CatalogItemIds(tmdb: int.tryParse('${external.tmdb}'));

  @override
  Future<void> addToWatchlist(MediaKind kind, CatalogItemIds ids) =>
      Future.error(UnsupportedError('HolyArrs has no watchlist'));

  @override
  Future<void> removeFromWatchlist(MediaKind kind, CatalogItemIds ids) =>
      Future.error(UnsupportedError('HolyArrs has no watchlist'));

  @override
  Listenable get watchlistChanges => _watchlistChanges;

  @override
  void dispose() => _watchlistChanges.dispose();
}
