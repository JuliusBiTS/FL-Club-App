import 'dart:io';

import 'package:flutter/foundation.dart' show consolidateHttpClientResponseBytes;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The member photo is only ever served as a 15-minute signed URL (never
/// a stable one, per §13.6 — no public URLs for membership photos), which
/// is useless for "renders entirely offline" (§9.6) on its own. This
/// downloads the image once per successful get-member-card call and
/// caches the bytes locally, so the card can still show a photo with no
/// network at all — same reasoning as TicketSecretsStore/
/// EventScanKeyStore caching secrets rather than re-deriving them live.
class MemberPhotoCache {
  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'member_photo.jpg'));
  }

  Future<void> downloadAndSave(String signedUrl) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(signedUrl));
      final response = await request.close();
      if (response.statusCode != 200) return;
      final bytes = await consolidateHttpClientResponseBytes(response);
      final file = await _file();
      await file.writeAsBytes(bytes, flush: true);
    } finally {
      client.close();
    }
  }

  Future<File?> cached() async {
    final file = await _file();
    return file.existsSync() ? file : null;
  }

  Future<void> clear() async {
    final file = await _file();
    if (file.existsSync()) await file.delete();
  }
}
