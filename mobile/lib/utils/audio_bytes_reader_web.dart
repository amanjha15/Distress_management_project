import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// `record`'s web implementation returns a `blob:` URL from `stop()`.
/// `http.get` under Flutter web resolves it via `fetch`, entirely
/// client-side -- no network round trip -- same technique as
/// download_helper_web.dart's reverse direction (bytes -> blob URL).
Future<Uint8List> readRecordedAudioBytes(String path) async {
  final response = await http.get(Uri.parse(path));
  return response.bodyBytes;
}
