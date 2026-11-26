// Runs against a real HolyArrs only when HOLYARRS_URL and HOLYARRS_KEY_FILE
// are set; otherwise every test is skipped.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/services/catalog/holyarrs_catalog_source.dart';
import 'package:plezy/services/holyarrs/holyarrs_client.dart';

void main() {
  final url = Platform.environment['HOLYARRS_URL'];
  final keyFile = Platform.environment['HOLYARRS_KEY_FILE'];
  final skip = url == null || keyFile == null ? 'no live HolyArrs configured' : null;
  HolyArrsClient client() =>
      HolyArrsClient(HolyArrsCredentials(baseUrl: url!, apiKey: File(keyFile!).readAsStringSync().trim()));

  test('live: who am I, rows, search, limit, request', () async {
    final c = client();
    final name = await c.whoAmI();
    print('signed in as: $name');
    final source = HolyArrsCatalogSource(c);
    for (final kind in [MediaKind.movie, MediaKind.show]) {
      final hubs = await source.fetchKindHubs(kind);
      final items = hubs.expand((h) => h.page.items).toList();
      print('${kind.name}: ${hubs.length} rows, ${items.length} items; first rows: ${hubs.take(4).map((h) => '${h.title} (${h.page.items.length})').join(' | ')}');
      final badged = items.where((i) => i.serverState != null).length;
      print('  items with a badge state: $badged; all have tmdb ids: ${items.every((i) => i.ids.tmdb != null)}; posters: ${items.where((i) => i.posterUrl != null).length}');
      expect(hubs, isNotEmpty);
    }
    final results = await source.search('succession');
    print('search "succession": ${results.take(3).map((r) => '${r.title} ${r.year} ${r.kind.name} state=${r.serverState?.availability?.name ?? '-'}').join(' | ')}');
    final limit = await c.askLimit();
    print('weekly limit movies=${limit?.moviesLeft ?? 'none'} shows=${limit?.showsLeft ?? 'none'}');
    final movies = await c.exploreRows('movies');
    final candidate = movies.expand((r) => r.items).firstWhere((t) => !t.inLibrary && t.askState == null);
    print('requesting: ${candidate.name} (tmdb ${candidate.tmdbId})');
    await c.ask(tmdbId: candidate.tmdbId, isShow: false);
    File('/home/claude/tmp/holyarrs-test-asked.txt').writeAsStringSync('${candidate.tmdbId}');
    final after = await c.exploreRows('movies');
    final seen = after.expand((r) => r.items).where((t) => t.tmdbId == candidate.tmdbId);
    print('after request, ask state on that title: ${seen.map((t) => '${t.askState}/${t.askLabel}').toSet()}');
  }, skip: skip);
}
