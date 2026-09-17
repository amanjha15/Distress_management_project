import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'custom_http_client.dart';
import 'live_detection_api.dart' show kApiBaseUrl, kApiV1;

const List<String> kAssetCategories = ['report', 'drawing', 'photo', 'survey_data', 'other'];

/// Matches backend `ProjectAssetResponse` (app/schemas/asset.py) -- a
/// document/report/drawing attached to a Project for reuse across modules.
class ProjectAsset {
  const ProjectAsset({
    required this.id,
    required this.projectId,
    required this.filename,
    required this.url,
    required this.contentType,
    required this.fileSize,
    required this.category,
    required this.description,
    required this.createdAt,
  });

  final int id;
  final int projectId;
  final String filename;
  final String url;
  final String? contentType;
  final int fileSize;
  final String category;
  final String? description;
  final DateTime createdAt;

  factory ProjectAsset.fromJson(Map<String, dynamic> json) {
    return ProjectAsset(
      id: json['id'] as int,
      projectId: json['project_id'] as int,
      filename: json['filename'] as String,
      url: json['url'] as String,
      contentType: json['content_type'] as String?,
      fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
      category: (json['category'] as String?) ?? 'other',
      description: json['description'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  String get resolvedUrl => url.startsWith('http') ? url : '$kApiBaseUrl$url';
}

class AssetApiException implements Exception {
  const AssetApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Talks to the M3 Asset Management routes (app/api/v1/routes/assets.py):
/// document upload/list/delete tied to a Project.
class AssetApi {
  AssetApi(this.token);

  final String token;
  final http.Client _client = CustomHttpClient();

  Future<List<ProjectAsset>> listAssets(int projectId) async {
    final uri = Uri.parse('$kApiV1/assets/').replace(queryParameters: {'project_id': '$projectId'});
    final response = await _client.get(uri, headers: {'Authorization': 'Bearer $token'});
    if (response.statusCode != 200) {
      throw const AssetApiException('Failed to load documents.');
    }
    final body = jsonDecode(response.body) as List<dynamic>;
    return body.map((e) => ProjectAsset.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<ProjectAsset> uploadAsset(
    int projectId, {
    required Uint8List bytes,
    required String filename,
    required String category,
    String? description,
  }) async {
    final uri = Uri.parse('$kApiV1/assets/').replace(queryParameters: {'project_id': '$projectId'});
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..fields['category'] = category
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    if (description != null && description.isNotEmpty) {
      request.fields['description'] = description;
    }
    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 201) {
      throw const AssetApiException('Failed to upload document.');
    }
    return ProjectAsset.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> deleteAsset(int assetId) async {
    final response = await _client.delete(
      Uri.parse('$kApiV1/assets/$assetId'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 204) {
      throw const AssetApiException('Failed to delete document.');
    }
  }
}
