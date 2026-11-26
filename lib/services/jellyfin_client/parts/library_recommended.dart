part of '../../jellyfin_client.dart';

/// Extra rows for a movie or TV library's Recommended tab, replacing the
/// date-added "Recently Added" row: new releases by release/air date,
/// Because You Watched, unwatched highly rated titles, top rated, started
/// collections and, when the Home Screen Sections plugin is installed, a
/// Seerr Explore row for the first library of each kind.
mixin _JellyfinLibraryRecommendedMethods on _JellyfinClientInternals {
  @override
  Future<List<MediaHub>> _recommendedLibraryRows(
    String libraryId, {
    required String libraryName,
    required MediaKind kind,
    required int limit,
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
    final recentlyPlayed = await _safeFetchItemsArray('/Items', {
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

    final rows = await Future.wait<MediaHub?>([
      // Released / aired: newest first, nothing dated in the future.
      _safeFetchItemsArray('/Items', query({
        'IncludeItemTypes': titleType,
        'SortBy': 'PremiereDate',
        'SortOrder': 'Descending',
        'MaxPremiereDate': now.toIso8601String(),
      })).then((items) => row('released', isMovies ? 'New Releases' : 'Latest Shows', items)),
      if (!isMovies)
        // Recently aired episodes of shows the user has been watching, one per show.
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
              if (episode['SeriesId'] case final String id when startedSeries.contains(id) && seen.add(id)) episode,
          ];
          return row('newepisodes', 'New Episodes', fresh);
        }),
      _becauseYouWatched(recentlyPlayed, isMovies: isMovies, limit: limit, libraryId: libraryId),
      // Highly rated and not yet watched (for shows: not yet started).
      _safeFetchItemsArray('/Items', query({
        'IncludeItemTypes': titleType,
        'IsPlayed': 'false',
        'MinCommunityRating': '7.5',
        'SortBy': 'Random',
        'Limit': '${limit * 2}',
      })).then((items) {
        final unstarted = [
          for (final item in items)
            if (isMovies || !startedSeries.contains(item['Id'])) item,
        ];
        return row('gems', isMovies ? 'Hidden Gems' : 'Unwatched Picks', unstarted);
      }),
      _safeFetchItemsArray('/Items', query({
        'IncludeItemTypes': titleType,
        'SortBy': isMovies ? 'CriticRating,CommunityRating' : 'CommunityRating',
        'SortOrder': 'Descending',
      })).then((items) => row('toprated', 'Top Rated', items)),
      if (isMovies) _startedCollections(limit: limit, libraryId: libraryId),
      _exploreRow(libraryId, isMovies: isMovies, limit: limit),
    ]);
    return rows.whereType<MediaHub>().where((hub) => hub.items.isNotEmpty).toList();
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
}
