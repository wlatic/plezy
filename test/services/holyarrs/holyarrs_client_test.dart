import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/media/library_tmdb_index.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/models/catalog/catalog_metadata.dart';
import 'package:plezy/services/catalog/holyarrs_catalog_source.dart';
import 'package:plezy/services/holyarrs/holyarrs_client.dart';

const _creds = HolyArrsCredentials(baseUrl: 'http://holy:6262', apiKey: 'k1');

Map<String, Object?> _title({String id = '76331', String kind = 'show', bool inLibrary = false, Object? ask}) => {
  'tmdb_id': id,
  'kind': kind,
  'name': 'Succession',
  'year': 2018,
  'poster': 'https://image.tmdb.org/p.jpg',
  'genres': ['Drama'],
  'in_library': inLibrary,
  'ask': ask,
  'trailer_key': 'abc',
};

void main() {
  test('Explore rows parse, sending the key and the kind', () async {
    late http.Request seen;
    final client = HolyArrsClient(
      _creds,
      httpClient: MockClient((request) async {
        seen = request;
        return http.Response(
          jsonEncode({
            'head': [
              {
                'id': 'top_picks',
                'title': 'Top picks for you',
                'items': [
                  _title(),
                  {'kind': 'show'},
                ],
              },
            ],
          }),
          200,
        );
      }),
    );
    final rows = await client.exploreRows('shows');
    expect(seen.url.toString(), 'http://holy:6262/api/v1/explore/head?type=shows');
    expect(seen.headers['X-Api-Key'], 'k1');
    expect(rows.single.title, 'Top picks for you');
    expect(rows.single.items.single.tmdbId, 76331); // the malformed item is skipped
  });

  test('a request sends tmdb id, kind and new-seasons-only', () async {
    late Map<String, Object?> body;
    final client = HolyArrsClient(
      _creds,
      httpClient: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response('{"id":1}', 201);
      }),
    );
    await client.ask(tmdbId: 76331, isShow: true, futureOnly: true);
    expect(body, {'id': 'tmdb:76331', 'kind': 'show', 'future_only': true});
  });

  test('a turned-off part surfaces HolyArrs wording', () async {
    final client = HolyArrsClient(
      _creds,
      httpClient: MockClient(
        (_) async => http.Response(jsonEncode({'error': 'this part is off', 'text': 'Requests is off.'}), 409),
      ),
    );
    expect(
      () => client.ask(tmdbId: 1, isShow: false),
      throwsA(
        isA<HolyArrsException>()
            .having((e) => e.message, 'message', 'Requests is off.')
            .having((e) => e.isPartOff, 'part off', true),
      ),
    );
  });

  test('weekly limits read per kind, with no limit as null', () async {
    final client = HolyArrsClient(
      _creds,
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'movies': {'per_week': 5, 'left': 3},
            'shows': {'per_week': 0, 'left': 0},
          }),
          200,
        ),
      ),
    );
    final limit = await client.askLimit();
    expect(limit!.leftFor(isShow: false), 3);
    expect(limit.leftFor(isShow: true), isNull);
  });

  test('badges: in library is available, asked is pending, approved is approved', () {
    expect(
      HolyArrsCatalogSource.serverStateOf(HolyArrsTitle.fromJson(_title(inLibrary: true))!)!.availability,
      CatalogAvailability.available,
    );
    expect(
      HolyArrsCatalogSource.serverStateOf(HolyArrsTitle.fromJson(_title(ask: {'state': 'asked'}))!)!.request,
      CatalogRequestState.pending,
    );
    expect(
      HolyArrsCatalogSource.serverStateOf(HolyArrsTitle.fromJson(_title(ask: {'state': 'approved'}))!)!.request,
      CatalogRequestState.approved,
    );
    expect(HolyArrsCatalogSource.serverStateOf(HolyArrsTitle.fromJson(_title())!), isNull);
  });

  group('server library overlay', () {
    HolyArrsClient exploreClient() => HolyArrsClient(
      _creds,
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'head': [
              {
                'id': 'top_picks',
                'title': 'Top picks for you',
                'items': [_title(kind: 'movie')],
              },
            ],
          }),
          200,
        ),
      ),
    );

    test('a title the media server has is available even when HolyArrs says not', () async {
      final source = HolyArrsCatalogSource(
        exploreClient(),
        libraryIndex: CachedLibraryTmdbIndex(() async => const LibraryTmdbIndex(movies: {76331})),
      );
      final hubs = await source.fetchKindHubs(MediaKind.movie);
      expect(hubs.single.page.items.single.serverState?.availability, CatalogAvailability.available);
    });

    test('the same TMDB id as a show does not count for a movie', () async {
      final source = HolyArrsCatalogSource(
        exploreClient(),
        libraryIndex: CachedLibraryTmdbIndex(() async => const LibraryTmdbIndex(shows: {76331})),
      );
      final hubs = await source.fetchKindHubs(MediaKind.movie);
      expect(hubs.single.page.items.single.serverState, isNull);
    });

    test('a failing index leaves the HolyArrs state', () async {
      final source = HolyArrsCatalogSource(
        exploreClient(),
        libraryIndex: CachedLibraryTmdbIndex(() async => throw Exception('server down')),
      );
      final hubs = await source.fetchKindHubs(MediaKind.movie);
      expect(hubs.single.page.items.single.serverState, isNull);
    });
  });

  test('mixed-page row titles say their kind unless they already do', () {
    expect(HolyArrsCatalogSource.withKindLabel('Top picks for you', 'Movies'), 'Top picks for you · Movies');
    expect(HolyArrsCatalogSource.withKindLabel('Trending movies this week', 'Movies'), 'Trending movies this week');
    expect(HolyArrsCatalogSource.withKindLabel('New seasons', 'Shows'), 'New seasons · Shows');
  });

  test('the cached index is reused within its lifetime and reloaded after', () async {
    var loads = 0;
    var now = DateTime(2026, 11, 26);
    final cache = CachedLibraryTmdbIndex(() async {
      loads++;
      return const LibraryTmdbIndex();
    }, now: () => now);
    await cache.get();
    await cache.get();
    expect(loads, 1);
    now = now.add(const Duration(minutes: 11));
    await cache.get();
    expect(loads, 2);
  });

  test('genre pages become rows, a mood row shared by two genres shows once', () async {
    final seen = <String>[];
    final client = HolyArrsClient(
      _creds,
      httpClient: MockClient((request) async {
        seen.add(request.url.query);
        final genre = request.url.queryParameters['genre'];
        return http.Response(
          jsonEncode({
            'rows': [
              {
                'id': 'genre_trending',
                'title': 'Trending $genre',
                'items': [_title()],
              },
              {
                'id': 'genre_mood_nature',
                'title': 'Nature',
                'items': [_title()],
              },
            ],
          }),
          200,
        );
      }),
    );
    final hubs = await HolyArrsCatalogSource(client).fetchGenreHubs(MediaKind.show, [99, 10764]);
    expect(hubs.map((h) => h.title), ['Trending 99', 'Nature', 'Trending 10764']);
    expect(seen, containsAll(['type=shows&genre=99', 'type=shows&genre=10764']));
  });
}
