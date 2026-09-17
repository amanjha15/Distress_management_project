import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'custom_http_client.dart';
import 'live_detection_api.dart' show kApiBaseUrl, kApiV1;

const List<String> kAuditCategories = [
  'signage',
  'road_markings',
  'guardrail',
  'lighting',
  'sight_distance',
  'junction',
  'pedestrian',
  'other',
];

const List<String> kAuditSeverities = ['low', 'medium', 'high', 'critical'];

class SafetyAudit {
  const SafetyAudit({
    required this.id,
    required this.projectId,
    required this.title,
    required this.status,
    required this.checklistItemCount,
    required this.audioClipCount,
  });

  final int id;
  final int projectId;
  final String title;
  final String status;
  final int checklistItemCount;
  final int audioClipCount;

  factory SafetyAudit.fromJson(Map<String, dynamic> json) {
    return SafetyAudit(
      id: json['id'] as int,
      projectId: json['project_id'] as int,
      title: json['title'] as String,
      status: json['status'] as String,
      checklistItemCount: (json['checklist_item_count'] as num?)?.toInt() ?? 0,
      audioClipCount: (json['audio_clip_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class AuditChecklistItem {
  const AuditChecklistItem({
    required this.id,
    required this.chainageKm,
    required this.category,
    required this.severity,
    required this.description,
  });

  final int id;
  final double chainageKm;
  final String category;
  final String severity;
  final String description;

  factory AuditChecklistItem.fromJson(Map<String, dynamic> json) {
    return AuditChecklistItem(
      id: json['id'] as int,
      chainageKm: (json['chainage_km'] as num).toDouble(),
      category: json['category'] as String,
      severity: json['severity'] as String,
      description: json['description'] as String,
    );
  }
}

class AuditAudioClip {
  const AuditAudioClip({
    required this.id,
    required this.chainageKm,
    required this.filename,
    required this.url,
    required this.transcript,
    required this.transcriptStatus,
  });

  final int id;
  final double? chainageKm;
  final String filename;
  final String url;
  final String? transcript;
  final String transcriptStatus;

  factory AuditAudioClip.fromJson(Map<String, dynamic> json) {
    return AuditAudioClip(
      id: json['id'] as int,
      chainageKm: (json['chainage_km'] as num?)?.toDouble(),
      filename: json['filename'] as String,
      url: json['url'] as String,
      transcript: json['transcript'] as String?,
      transcriptStatus: json['transcript_status'] as String,
    );
  }

  String get resolvedUrl => url.startsWith('http') ? url : '$kApiBaseUrl$url';
}

class ChainageBucket {
  const ChainageBucket({
    required this.startKm,
    required this.endKm,
    required this.severityCounts,
    required this.items,
  });

  final double startKm;
  final double endKm;
  final Map<String, int> severityCounts;
  final List<AuditChecklistItem> items;

  factory ChainageBucket.fromJson(Map<String, dynamic> json) {
    return ChainageBucket(
      startKm: (json['start_km'] as num).toDouble(),
      endKm: (json['end_km'] as num).toDouble(),
      severityCounts: (json['severity_counts'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, (v as num).toInt()),
      ),
      items: (json['items'] as List<dynamic>)
          .map((e) => AuditChecklistItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class AuditApiException implements Exception {
  const AuditApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Talks to the M2 Road Safety Audit routes (app/api/v1/routes/audits.py):
/// checklist findings + audio commentary tied to a Project, plus the
/// chainage-wise and audio report views.
class AuditApi {
  AuditApi(this.token);

  final String token;
  final http.Client _client = CustomHttpClient();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  Future<List<SafetyAudit>> listAudits(int projectId) async {
    final uri = Uri.parse('$kApiV1/audits/').replace(queryParameters: {'project_id': '$projectId'});
    final response = await _client.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw const AuditApiException('Failed to load safety audits.');
    }
    final body = jsonDecode(response.body) as List<dynamic>;
    return body.map((e) => SafetyAudit.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<SafetyAudit> createAudit(int projectId, String title) async {
    final uri = Uri.parse('$kApiV1/audits/').replace(queryParameters: {'project_id': '$projectId'});
    final response = await _client.post(uri, headers: _headers, body: jsonEncode({'title': title}));
    if (response.statusCode != 201) {
      throw const AuditApiException('Failed to create safety audit.');
    }
    return SafetyAudit.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<SafetyAudit> getAudit(int auditId) async {
    final response = await _client.get(Uri.parse('$kApiV1/audits/$auditId'), headers: _headers);
    if (response.statusCode != 200) {
      throw const AuditApiException('Failed to load audit.');
    }
    return SafetyAudit.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<AuditChecklistItem>> listChecklistItems(int auditId) async {
    final response = await _client.get(Uri.parse('$kApiV1/audits/$auditId/checklist-items'), headers: _headers);
    if (response.statusCode != 200) {
      throw const AuditApiException('Failed to load checklist items.');
    }
    final body = jsonDecode(response.body) as List<dynamic>;
    return body.map((e) => AuditChecklistItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<AuditChecklistItem> createChecklistItem(
    int auditId, {
    required double chainageKm,
    required String category,
    required String severity,
    required String description,
  }) async {
    final response = await _client.post(
      Uri.parse('$kApiV1/audits/$auditId/checklist-items'),
      headers: _headers,
      body: jsonEncode({
        'chainage_km': chainageKm,
        'category': category,
        'severity': severity,
        'description': description,
      }),
    );
    if (response.statusCode != 201) {
      throw const AuditApiException('Failed to add checklist item.');
    }
    return AuditChecklistItem.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<AuditAudioClip>> listAudioClips(int auditId) async {
    final response = await _client.get(Uri.parse('$kApiV1/audits/$auditId/audio'), headers: _headers);
    if (response.statusCode != 200) {
      throw const AuditApiException('Failed to load audio clips.');
    }
    final body = jsonDecode(response.body) as List<dynamic>;
    return body.map((e) => AuditAudioClip.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<AuditAudioClip> uploadAudioClip(
    int auditId, {
    required Uint8List bytes,
    required String filename,
    double? chainageKm,
  }) async {
    final uri = Uri.parse('$kApiV1/audits/$auditId/audio');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    if (chainageKm != null) {
      request.fields['chainage_km'] = '$chainageKm';
    }
    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 201) {
      throw const AuditApiException('Failed to upload audio clip.');
    }
    return AuditAudioClip.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> deleteAudioClip(int auditId, int clipId) async {
    final response = await _client.delete(
      Uri.parse('$kApiV1/audits/$auditId/audio/$clipId'),
      headers: _headers,
    );
    if (response.statusCode != 204) {
      throw const AuditApiException('Failed to delete audio clip.');
    }
  }

  Future<List<ChainageBucket>> chainageReport(int auditId, {double intervalKm = 0.5}) async {
    final uri = Uri.parse('$kApiV1/audits/$auditId/report/chainage')
        .replace(queryParameters: {'interval_km': '$intervalKm'});
    final response = await _client.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw const AuditApiException('Failed to load chainage report.');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['buckets'] as List<dynamic>)
        .map((e) => ChainageBucket.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
