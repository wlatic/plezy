part of '../../jellyfin_client.dart';

/// Extra rows for a movie or TV library's Recommended tab, replacing the
/// date-added "Recently Added" row: new releases by release/air date,
/// Because You Watched, unwatched highly rated titles, top rated, started
/// collections and, when the Home Screen Sections plugin is installed, a
/// Seerr Explore row for the first library of each kind.
mixin _JellyfinLibraryRecommendedMethods on _JellyfinClientInternals {
  /// Row settings live in the user's own `DisplayPreferences` row, one
  /// `CustomPrefs` entry per library, so every device shows the same rows.
  static const _rowSettingsPrefsId = 'plezy-library-rows';
  static const _rowSettingsClient = 'plezy';

  Map<String, String> get _rowSettingsQuery => {'userId': connection.userId, 'client': _rowSettingsClient};

  bool supportsLibraryRowSettings(MediaKind? kind) =>
      dialect == MediaBrowserDialect.jellyfin && (kind == MediaKind.movie || kind == MediaKind.show);

  @override
  Future<List<LibraryRowSetting>> fetchLibraryRowSettings(String libraryId, MediaKind kind) async {
    final (response, mainLibrary) = await (
      _http
          .get(MediaBrowserPaths.displayPreferences(_rowSettingsPrefsId), queryParameters: _rowSettingsQuery)
          .then<MediaServerResponse?>((r) => r)
          .catchError((Object e) {
            if (e is MediaServerHttpException && e.isCancellation) throw e;
            return null;
          }),
      _isMainLibrary(libraryId),
    ).wait;
    if (response == null || response.statusCode != 200) return LibraryRows.defaults(kind, exploreTab: mainLibrary);
    final data = response.data;
    final custom = data is Map ? data['CustomPrefs'] : null;
    return LibraryRows.parse(custom is Map ? custom[libraryId] as String? : null, kind, exploreTab: mainLibrary);
  }

  /// The first library of its type (the main Movies or Shows), or an anime
  /// library. Unknown counts as main, so a failed lookup hides nothing.
  Future<bool> _isMainLibrary(String libraryId) async {
    try {
      final response = await _http.get('/Users/${_segment(connection.userId)}/Views');
      if (response.statusCode != 200) return true;
      final views = _itemsArray(response.data);
      final library = views.where((view) => view['Id'] == libraryId).firstOrNull;
      if (library == null) return true;
      if ('${library['Name'] ?? ''}'.toLowerCase().contains('anime')) return true;
      final firstOfType = views.where((view) => view['CollectionType'] == library['CollectionType']).firstOrNull;
      return firstOfType?['Id'] == libraryId;
    } catch (e) {
      if (e is MediaServerHttpException && e.isCancellation) rethrow;
      return true;
    }
  }

  /// Read-modify-write: the `POST` replaces the whole row, so other
  /// libraries' entries travel back with the change.
  Future<void> saveLibraryRowSettings(String libraryId, List<LibraryRowSetting> rows) async {
    final path = MediaBrowserPaths.displayPreferences(_rowSettingsPrefsId);
    final readResponse = await _http.get(path, queryParameters: _rowSettingsQuery);
    throwIfHttpError(readResponse);
    final current = readResponse.data;
    final body = current is Map<String, dynamic>
        ? Map<String, dynamic>.of(current)
        : <String, dynamic>{'Id': _rowSettingsPrefsId, 'Client': _rowSettingsClient};
    final custom = body['CustomPrefs'];
    body['CustomPrefs'] = {if (custom is Map) ...custom, libraryId: LibraryRows.encode(rows)};
    final writeResponse = await _http.post(path, queryParameters: _rowSettingsQuery, body: body);
    throwIfHttpError(writeResponse);
  }

  @override
  Future<Map<String, MediaHub>> _recommendedLibraryRows(
    String libraryId, {
    required String libraryName,
    required MediaKind kind,
    required int limit,
    required Set<String> enabled,
  }) async {
    final isMovies = kind == MediaKind.movie;
    final now = DateTime.now().toUtc();
    Map<String, dynamic> query(Map<String, dynamic> extra) => {
      'userId': connection.userId,
      'ParentId': libraryId,
      'Recursive': 'true',
      'Fields': _hubRowFields,
      'Limit': '$limit',
      ...jellyfinImageQueryParameters,
      ...extra,
    };
    MediaHub row(String suffix, String title, List<Map<String, dynamic>> items) => JellyfinMappers.syntheticHub(
      mapItem: _mapItem,
      identifier: 'library.$libraryId.$suffix',
      title: title,
      type: 'mixed',
      items: items.take(limit).toList(),
      serverId: serverId,
      serverName: serverName,
    );

    final titleType = isMovies ? 'Movie' : 'Series';
    final needsHistory = enabled.any({LibraryRows.because, LibraryRows.gems, LibraryRows.newEpisodes}.contains);
    final recentlyPlayed = !needsHistory
        ? const <Map<String, dynamic>>[]
        : await _safeFetchItemsArray('/Items', {
            ...query({}),
            'IncludeItemTypes': isMovies ? 'Movie' : 'Episode',
            'IsPlayed': 'true',
            'SortBy': 'DatePlayed',
            'SortOrder': 'Descending',
            'Limit': '300',
            'Fields': '$_hubRowFields,SeriesId',
          });
    final startedSeries = {
      for (final played in recentlyPlayed)
        if (played['SeriesId'] case final String id) id,
    };

    Future<MediaHub?>? when(String id, Future<MediaHub?> Function() build) => enabled.contains(id) ? build() : null;
    final pending = <String, Future<MediaHub?>?>{
      // Released / aired: newest first, nothing dated in the future.
      LibraryRows.released: when(
        LibraryRows.released,
        () => _safeFetchItemsArray(
          '/Items',
          query({
            'IncludeItemTypes': titleType,
            'SortBy': 'PremiereDate',
            'SortOrder': 'Descending',
            'MaxPremiereDate': now.toIso8601String(),
          }),
        ).then((items) => row('released', isMovies ? 'New Releases' : 'Latest Shows', items)),
      ),
      // Recently aired episodes of shows the user has been watching, one per show.
      if (!isMovies)
        LibraryRows.newEpisodes: when(
          LibraryRows.newEpisodes,
          () =>
              _safeFetchItemsArray('/Items', {
                ...query({}),
                'IncludeItemTypes': 'Episode',
                'IsPlayed': 'false',
                'SortBy': 'PremiereDate',
                'SortOrder': 'Descending',
                'MinPremiereDate': now.subtract(const Duration(days: 45)).toIso8601String(),
                'MaxPremiereDate': now.toIso8601String(),
                'Limit': '200',
                'Fields': '$_hubRowFields,SeriesId',
              }).then((episodes) {
                final seen = <String>{};
                final fresh = [
                  for (final episode in episodes)
                    if (episode['SeriesId'] case final String id when startedSeries.contains(id) && seen.add(id))
                      episode,
                ];
                return row('newepisodes', 'New Episodes', fresh);
              }),
        ),
      LibraryRows.because: when(
        LibraryRows.because,
        () => _becauseYouWatched(recentlyPlayed, isMovies: isMovies, limit: limit, libraryId: libraryId),
      ),
      // Highly rated and not yet watched (for shows: not yet started).
      LibraryRows.gems: when(
        LibraryRows.gems,
        () =>
            _safeFetchItemsArray(
              '/Items',
              query({
                'IncludeItemTypes': titleType,
                'IsPlayed': 'false',
                'MinCommunityRating': '7.5',
                'SortBy': 'Random',
                'Limit': '${limit * 2}',
              }),
            ).then((items) {
              final unstarted = [
                for (final item in items)
                  if (isMovies || !startedSeries.contains(item['Id'])) item,
              ];
              return row('gems', isMovies ? 'Hidden Gems' : 'Unwatched Picks', unstarted);
            }),
      ),
      LibraryRows.topRated: when(
        LibraryRows.topRated,
        () => _safeFetchItemsArray(
          '/Items',
          query({
            'IncludeItemTypes': titleType,
            'SortBy': isMovies ? 'CriticRating,CommunityRating' : 'CommunityRating',
            'SortOrder': 'Descending',
          }),
        ).then((items) => row('toprated', 'Top Rated', items)),
      ),
      if (isMovies)
        LibraryRows.collections: when(
          LibraryRows.collections,
          () => _startedCollections(limit: limit, libraryId: libraryId),
        ),
      LibraryRows.explore: when(LibraryRows.explore, () => _exploreRow(libraryId, isMovies: isMovies, limit: limit)),
    };
    final built = <String, MediaHub>{};
    for (final MapEntry(:key, :value) in pending.entries) {
      final hub = value == null ? null : await value;
      if (hub != null && hub.items.isNotEmpty) built[key] = hub;
    }
    return built;
  }

  /// Titles similar to the most recently watched one.
  Future<MediaHub?> _becauseYouWatched(
    List<Map<String, dynamic>> recentlyPlayed, {
    required bool isMovies,
    required int limit,
    required String libraryId,
  }) async {
    if (recentlyPlayed.isEmpty) return null;
    final last = recentlyPlayed.first;
    final seedId = isMovies ? last['Id'] : last['SeriesId'];
    final seedName = isMovies ? last['Name'] : last['SeriesName'];
    if (seedId is! String || seedName is! String) return null;
    final similar = await _safeFetchItemsArray('/Items/${_segment(seedId)}/Similar', {
      'userId': connection.userId,
      'Limit': '$limit',
      'Fields': _hubRowFields,
      ...jellyfinImageQueryParameters,
    });
    return JellyfinMappers.syntheticHub(
      mapItem: _mapItem,
      identifier: 'library.$libraryId.because',
      title: 'Because you watched $seedName',
      type: 'mixed',
      items: similar,
      serverId: serverId,
      serverName: serverName,
    );
  }

  /// Collections the user has started but not finished, closest to done first.
  Future<MediaHub?> _startedCollections({required int limit, required String libraryId}) async {
    final sets = await _safeFetchItemsArray('/Items', {
      'userId': connection.userId,
      'IncludeItemTypes': 'BoxSet',
      'Recursive': 'true',
      'Fields': _hubRowFields,
      'Limit': '300',
      ...jellyfinImageQueryParameters,
    });
    double played(Map<String, dynamic> set) {
      final data = set['UserData'];
      return data is Map && data['PlayedPercentage'] is num ? (data['PlayedPercentage'] as num).toDouble() : 0;
    }

    final started = sets.where((set) => played(set) > 0 && played(set) < 100).toList()
      ..sort((a, b) => played(b).compareTo(played(a)));
    return JellyfinMappers.syntheticHub(
      mapItem: _mapItem,
      identifier: 'library.$libraryId.collections',
      title: 'Finish the Collection',
      type: 'mixed',
      items: started.take(limit).toList(),
      serverId: serverId,
      serverName: serverName,
    );
  }

  /// Seerr titles not in the library, served by the Home Screen Sections
  /// plugin. Only the user's first library of each kind gets it, so themed
  /// libraries (a second TV library, say) are not filled with general picks.
  Future<MediaHub?> _exploreRow(String libraryId, {required bool isMovies, required int limit}) async {
    final List<Map<String, dynamic>> views;
    try {
      final response = await _http.get('/Users/${_segment(connection.userId)}/Views');
      if (response.statusCode != 200) return null;
      views = _itemsArray(response.data);
    } catch (e) {
      if (e is MediaServerHttpException && e.isCancellation) rethrow;
      return null;
    }
    final kind = isMovies ? 'movies' : 'tvshows';
    final firstOfKind = views.where((view) => view['CollectionType'] == kind).firstOrNull;
    if (firstOfKind == null || firstOfKind['Id'] != libraryId) return null;
    final hub = await _homeScreenSectionHub(
      {'Section': isMovies ? 'DiscoverMovies' : 'DiscoverTV', 'DisplayText': 'Explore'},
      index: 0,
      limit: limit,
    );
    return hub;
  }

  /// Every movie and show the user can see, as TMDB ids, in one request
  /// without images or user data.
  Future<LibraryTmdbIndex> fetchLibraryTmdbIndex() async {
    final response = await _http.get(
      '/Items',
      queryParameters: {
        'userId': connection.userId,
        'Recursive': 'true',
        'IncludeItemTypes': 'Movie,Series',
        'Fields': 'ProviderIds',
        'EnableImages': 'false',
        'EnableUserData': 'false',
        'EnableTotalRecordCount': 'false',
      },
    );
    throwIfHttpError(response);
    final movies = <int>{}, shows = <int>{};
    for (final item in _itemsArray(response.data)) {
      final ids = item['ProviderIds'];
      final tmdb = ids is Map ? int.tryParse('${ids['Tmdb'] ?? ''}') : null;
      if (tmdb == null) continue;
      (item['Type'] == 'Movie' ? movies : shows).add(tmdb);
    }
    return LibraryTmdbIndex(movies: movies, shows: shows);
  }

  /// Library icons live in their own `DisplayPreferences` row, one
  /// `CustomPrefs` entry per library.
  static const _iconPrefsId = 'plezy-library-icons';

  bool get supportsLibraryIcons => dialect == MediaBrowserDialect.jellyfin;

  Future<Map<String, String>> fetchLibraryIcons() async {
    final response = await _http.get(
      MediaBrowserPaths.displayPreferences(_iconPrefsId),
      queryParameters: _rowSettingsQuery,
    );
    if (response.statusCode != 200) return const {};
    final custom = response.data is Map ? (response.data as Map)['CustomPrefs'] : null;
    if (custom is! Map) return const {};
    return {
      for (final entry in custom.entries)
        if (entry.key is String && entry.value is String && (entry.value as String).isNotEmpty)
          entry.key as String: entry.value as String,
    };
  }

  /// Read-modify-write, as for the row settings.
  Future<void> saveLibraryIcon(String libraryId, String? iconId) async {
    final path = MediaBrowserPaths.displayPreferences(_iconPrefsId);
    final readResponse = await _http.get(path, queryParameters: _rowSettingsQuery);
    throwIfHttpError(readResponse);
    final current = readResponse.data;
    final body = current is Map<String, dynamic>
        ? Map<String, dynamic>.of(current)
        : <String, dynamic>{'Id': _iconPrefsId, 'Client': _rowSettingsClient};
    final custom = body['CustomPrefs'];
    body['CustomPrefs'] = {
      if (custom is Map) ...custom,
      // Jellyfin keeps a key with a null value; an empty string reads as unset.
      libraryId: iconId ?? '',
    };
    final writeResponse = await _http.post(path, queryParameters: _rowSettingsQuery, body: body);
    throwIfHttpError(writeResponse);
  }
}
