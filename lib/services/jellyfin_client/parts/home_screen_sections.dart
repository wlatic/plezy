part of '../../jellyfin_client.dart';

/// Home rows served by the Home Screen Sections server plugin
/// (https://github.com/IAmParadox27/jellyfin-plugin-home-sections).
///
/// The plugin lets each user pick and order their home rows on the server
/// (Latest Movies/Shows by release date, Because You Watched, Discover, ...).
/// When it is installed and enabled for the user, home renders those rows in
/// place of the synthesised Recently Added row; otherwise nothing changes.
mixin _JellyfinHomeScreenSectionsMethods on _JellyfinClientInternals {
  /// Rows Plezy already draws itself (the Continue Watching row) or that make
  /// no sense as a poster row.
  static const _skippedSections = {
    'MyMedia',
    'MyMediaSmall',
    'ContinueWatching',
    'NextUp',
    'ContinueWatchingNextUp',
    'LiveTV',
  };

  /// See [ServerHomeRowsClient.fetchServerHomeRows].
  Future<List<MediaHub>?> fetchServerHomeRows({required int limit}) async {
    final List<Map<String, dynamic>> sections;
    try {
      final response = await _http.get(
        '/HomeScreen/Sections',
        queryParameters: {'UserId': connection.userId},
      );
      if (response.statusCode != 200) return null;
      final data = response.data;
      final items = data is Map<String, dynamic> ? data['Items'] : null;
      if (items is! List) return null;
      sections = items.whereType<Map<String, dynamic>>().toList();
    } catch (e) {
      if (e is MediaServerHttpException && e.isCancellation) rethrow;
      return null;
    }
    final wanted = sections.where((s) {
      final type = s['Section'];
      return type is String && type.isNotEmpty && !_skippedSections.contains(type) && !type.startsWith('Upcoming');
    }).toList();
    if (wanted.isEmpty) return null;

    appLogger.i('Home Screen Sections: ${sections.length} sections, using ${wanted.map((s) => s['Section']).join(', ')}');
    final hubs = await Future.wait([
      for (var i = 0; i < wanted.length; i++) _homeScreenSectionHub(wanted[i], index: i, limit: limit),
    ]);
    return hubs.whereType<MediaHub>().where((hub) => hub.items.isNotEmpty).toList();
  }

  @override
  Future<MediaHub?> _homeScreenSectionHub(
    Map<String, dynamic> section, {
    required int index,
    required int limit,
  }) async {
    final type = section['Section'] as String;
    final additionalData = section['AdditionalData'];
    final List<Map<String, dynamic>> rows;
    try {
      final response = await _http.get(
        '/HomeScreen/Section/${_segment(type)}',
        queryParameters: {
          'UserId': connection.userId,
          if (additionalData is String && additionalData.isNotEmpty) 'AdditionalData': additionalData,
        },
      );
      if (response.statusCode != 200) {
        appLogger.w('Home Screen Sections: $type returned HTTP ${response.statusCode}');
        return null;
      }
      rows = _itemsArray(response.data);
    } catch (e) {
      if (e is MediaServerHttpException && e.isCancellation) rethrow;
      return null;
    }
    final title = section['DisplayText'] as String? ?? type;
    final firstType = rows.isEmpty ? '-' : '${rows.first['Type']}';
    final items = <MediaItem>[
      for (final row in rows.take(limit))
        if (_homeScreenSectionItem(row) case final MediaItem item) item,
    ];
    appLogger.i('Home Screen Sections: $type has ${rows.length} rows, ${items.length} mapped (first type $firstType)');
    return MediaHub(
      id: 'hss.$index.$type',
      identifier: 'hss.$index.$type',
      title: title,
      type: 'mixed',
      items: items,
      size: items.length,
      more: false,
      serverId: serverId,
      serverName: serverName,
    );
  }

  /// Library items map as usual. Discover entries are Seerr titles that are
  /// not on the server, so they become catalog items that open the request
  /// screen.
  MediaItem? _homeScreenSectionItem(Map<String, dynamic> row) {
    final providerIds = row['ProviderIds'];
    final tmdb = providerIds is Map ? int.tryParse('${providerIds['Jellyseerr'] ?? ''}') : null;
    if (tmdb == null) return _mapItem(row);
    final name = row['Name'];
    if (name is! String || name.isEmpty) return null;
    final premiere = DateTime.tryParse('${row['PremiereDate'] ?? ''}');
    final rating = row['CommunityRating'];
    return CatalogItem(
      source: CatalogSourceId.seerr,
      kind: row['SourceType'] == 'tv' ? MediaKind.show : MediaKind.movie,
      title: name,
      year: premiere != null && premiere.year > 1970 ? premiere.year : null,
      rating: rating is num ? rating.toDouble() : null,
      ids: CatalogItemIds(tmdb: tmdb),
      posterUrl: _absolutizeImagePath(providerIds['JellyseerrPoster'] as String?),
    ).toMediaItem();
  }
}
