import 'package:flutter/foundation.dart';

import '../../utils/external_ids.dart';
import '../../media/library_tmdb_index.dart';
import '../../media/media_kind.dart';
import '../../models/catalog/catalog_cast_member.dart';
import '../../models/catalog/catalog_item.dart';
import '../../models/catalog/catalog_metadata.dart';
import '../holyarrs/holyarrs_client.dart';
import 'catalog_source.dart';

/// HolyArrs as an Explore source: its own personalised Explore rows (Top
/// picks, Because you have …, New seasons, …) for movies and shows, search,
/// and per-title library/request state for the availability badges.
/// Requests go through [client]; HolyArrs has no watchlist to mirror.
///
/// HolyArrs only knows the titles it manages, so while Radarr and Sonarr
/// still fill the library its "in library" flag misses most of it. When
/// [libraryIndex] is given, a title the media server already has is marked
/// available too.
class HolyArrsCatalogSource implements CatalogSource, CatalogHubSource {
  HolyArrsCatalogSource(this.client, {this.libraryIndex});

  final HolyArrsClient client;
  final CachedLibraryTmdbIndex? libraryIndex;
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
    final (rows, owned) = await (client.exploreRows(type), _ownedIndex()).wait;
    return [
      for (final row in rows)
        if (row.items.isNotEmpty)
          CatalogHub(
            id: '$type:${row.id}',
            title: row.title,
            page: CatalogPage(items: [for (final title in row.items.take(limit)) toCatalogItem(title, owned: owned)]),
          ),
    ];
  }

  Future<LibraryTmdbIndex?> _ownedIndex() async {
    try {
      return await libraryIndex?.get();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<CatalogHub>> fetchHubs({int limit = 25}) async {
    final kinds = await Future.wait([
      fetchKindHubs(MediaKind.movie, limit: limit),
      fetchKindHubs(MediaKind.show, limit: limit),
    ]);
    // Interleave movie and show rows so neither kind is buried. Both kinds
    // have rows with the same name ("Top picks for you"), so on this mixed
    // page each title says which kind it holds.
    final movies = kinds[0], shows = kinds[1];
    CatalogHub labelled(CatalogHub hub, String suffix) =>
        CatalogHub(id: hub.id, title: withKindLabel(hub.title, suffix), page: hub.page);
    return [
      for (var i = 0; i < movies.length || i < shows.length; i++) ...[
        if (i < movies.length) labelled(movies[i], 'Movies'),
        if (i < shows.length) labelled(shows[i], 'Shows'),
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
  Future<CatalogPage> fetchRow(CatalogRowId row, {int page = 1, int limit = 25}) async => const CatalogPage(items: []);

  @override
  Future<List<CatalogItem>> search(String query, {int limit = 30}) async {
    final (titles, owned) = await (client.search(query), _ownedIndex()).wait;
    return [for (final title in titles.take(limit)) toCatalogItem(title, owned: owned)];
  }

  /// HolyArrs's title page: runtime, score, cast and similar titles. Any
  /// failure leaves the card's own fields.
  @override
  Future<CatalogDetail> fetchDetail(CatalogItem item, {int castLimit = 20, int relatedLimit = 20}) async {
    final tmdbId = item.ids.tmdb;
    if (tmdbId == null || !canRequest(item.kind)) return CatalogDetail(item: item);
    try {
      final (detail, owned) = await (
        client.titleDetail(tmdbId: tmdbId, isShow: item.kind == MediaKind.show),
        _ownedIndex(),
      ).wait;
      if (detail == null) return CatalogDetail(item: item);
      final title = detail.title;
      final full = _catalogItem(
        title,
        item.kind,
        inServerLibrary: owned?.has(item.kind, title.tmdbId) ?? false,
        runtimeMinutes: detail.runtimeMinutes,
        certification: detail.certification,
        rating: detail.score,
        votes: detail.votes,
      );
      return CatalogDetail(
        item: item.enrichedWith(full),
        cast: [
          for (final person in detail.people.take(castLimit))
            CatalogCastMember(name: person.name, secondary: person.character, imageUrl: person.photo),
        ],
        related: [for (final similar in detail.similar.take(relatedLimit)) toCatalogItem(similar, owned: owned)],
      );
    } catch (_) {
      return CatalogDetail(item: item);
    }
  }

  /// "Top picks for you" → "Top picks for you · Movies", unless the title
  /// already names the kind ("Trending movies this week").
  static String withKindLabel(String title, String kind) {
    final lower = title.toLowerCase();
    final singular = kind.toLowerCase().substring(0, kind.length - 1);
    return lower.contains(singular) ? title : '$title · $kind';
  }

  static CatalogItem toCatalogItem(HolyArrsTitle title, {LibraryTmdbIndex? owned}) {
    final kind = title.kind == 'movie' ? MediaKind.movie : MediaKind.show;
    return _catalogItem(title, kind, inServerLibrary: owned?.has(kind, title.tmdbId) ?? false);
  }

  static CatalogItem _catalogItem(
    HolyArrsTitle title,
    MediaKind kind, {
    required bool inServerLibrary,
    int? runtimeMinutes,
    String? certification,
    double? rating,
    int? votes,
  }) => CatalogItem(
    source: CatalogSourceId.holyarrs,
    kind: kind,
    runtimeMinutes: runtimeMinutes,
    certification: certification,
    rating: rating,
    votes: votes,
    title: title.name,
    year: title.year,
    overview: title.overview,
    genres: title.genres.isEmpty ? null : title.genres,
    trailerUrl: title.trailerKey == null ? null : 'https://www.youtube.com/watch?v=${title.trailerKey}',
    ids: CatalogItemIds(tmdb: title.tmdbId),
    posterUrl: title.poster,
    backdropUrl: title.backdrop,
    logoUrl: title.logo,
    serverState: serverStateOf(title, inServerLibrary: inServerLibrary),
  );

  /// HolyArrs's library and request knowledge as the badges read it, plus
  /// the media server's own library when [inServerLibrary].
  static CatalogServerState? serverStateOf(HolyArrsTitle title, {bool inServerLibrary = false}) {
    final ask = title.askState;
    final state = CatalogServerState(
      availability: inServerLibrary || title.inLibrary || ask == 'available' ? CatalogAvailability.available : null,
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
