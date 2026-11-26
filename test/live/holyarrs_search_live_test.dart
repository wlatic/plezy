import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/catalog/holyarrs_catalog_source.dart';
import 'package:plezy/services/holyarrs/holyarrs_client.dart';

void main() {
  final url = Platform.environment['HOLYARRS_URL'];
  final keyFile = Platform.environment['HOLYARRS_KEY_FILE'];
  test('live: search by name and by description', () async {
    final source = HolyArrsCatalogSource(
      HolyArrsClient(HolyArrsCredentials(baseUrl: url!, apiKey: File(keyFile!).readAsStringSync().trim())),
    );
    for (final q in ['succession', 'severance', 'space movie with a robot']) {
      final r = await source.search(q);
      print('"$q": ${r.length} results: ${r.take(4).map((i) => '${i.title} (${i.year ?? '?'}, ${i.kind.name}, ${i.serverState?.availability?.name ?? 'not in library'})').join(' | ')}');
    }
  }, skip: url == null || keyFile == null ? 'no live HolyArrs configured' : null);
}
