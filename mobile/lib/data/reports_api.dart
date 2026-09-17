import 'dart:convert';

import 'package:http/http.dart' as http;

import 'custom_http_client.dart';
import 'live_detection_api.dart' show kApiV1;
import 'maintenance_api.dart' show AppUser;
import 'road_distress_api.dart' show DistressRecord;
import 'video_api.dart' show UploadedVideo;

/// Direct Dart port of `ReportResponse` in apiService.ts.
class ReportRecord {
  const ReportRecord({
    required this.id,
    required this.reportName,
    required this.reportType,
    required this.createdAt,
    this.filepath,
    this.generatedBy,
    this.generatedAt,
  });

  final int id;
  final String reportName;
  final String reportType;
  final String? filepath;
  final int? generatedBy;
  final String? generatedAt;
  final String createdAt;

  factory ReportRecord.fromJson(Map<String, dynamic> json) {
    return ReportRecord(
      id: json['id'] as int,
      reportName: json['report_name'] as String,
      reportType: json['report_type'] as String? ?? '',
      filepath: json['filepath'] as String?,
      generatedBy: (json['generated_by'] as num?)?.toInt(),
      generatedAt: json['generated_at'] as String?,
      createdAt: json['created_at'] as String,
    );
  }
}

const _kDistricts = ['Mumbai', 'Pune', 'Nagpur', 'Thane', 'Satara'];

/// Direct port of ReportsDashboard.tsx's `SEVERITY_COLORS`.
const kReportSeverityColors = {
  'Critical': 0xFFEF4444,
  'High': 0xFFF97316,
  'Medium': 0xFFFACC15,
  'Low': 0xFF3B82F6,
};

const _kSeverityRank = {'critical': 4, 'high': 3, 'medium': 2, 'low': 1};

String _prettifyDistressType(String raw) {
  final words = raw.replaceAll('_', ' ').trim().split(RegExp(r'\s+'));
  return words.map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase()).join(' ');
}

String _prettifySeverity(String raw) => raw.isEmpty ? raw : raw[0].toUpperCase() + raw.substring(1).toLowerCase();

/// Picks the most severe real distress record for [videoId] (as opposed to
/// the old videoId-modulo fake placeholder every ReportItem used to show
/// regardless of what was actually detected) so the "Distress class"
/// column reflects the report's actual content. Falls back to a neutral
/// placeholder only if the video genuinely has no distress records.
({String distressType, String severity}) _principalDistressFor(
  int videoId,
  List<DistressRecord> distresses,
) {
  final forVideo = distresses.where((d) => d.videoId == videoId).toList()
    ..sort((a, b) =>
        (_kSeverityRank[b.severity.toLowerCase()] ?? 0).compareTo(_kSeverityRank[a.severity.toLowerCase()] ?? 0));
  if (forVideo.isEmpty) {
    return (distressType: 'No distress data', severity: 'Low');
  }
  final principal = forVideo.first;
  return (
    distressType: _prettifyDistressType(principal.distressType),
    severity: _prettifySeverity(principal.severity),
  );
}

/// Direct Dart port of ReportsDashboard.tsx's `ReportItem`, joined
/// client-side from a [ReportRecord] plus the uploaded-videos, users, and
/// distresses lists exactly as `loadDashboardData` does -- there's no
/// backend endpoint that returns this joined shape directly. `roadId` and
/// `district` are still faithfully-preserved fake-but-deterministic values
/// derived from `videoId % <lookup array>.length` (matching the React
/// source's own placeholder logic; there's no real district/geo data on
/// the backend to join against). `distressType`/`severity`, however, are
/// real -- computed from that video's actual RoadDistress records via
/// [_principalDistressFor], not the source's placeholder logic, since
/// showing a fake class/severity for a real generated report was actively
/// misleading (every report for the same video always showed the same
/// value regardless of what was actually detected).
///
/// The source's `reportId` is optional because its fake "Generate Custom
/// Report" feature fabricates a `ReportItem` with no backing DB row. That
/// feature has no backend tie at all (client-side `setTimeout` only) and is
/// trimmed from this port, so every [ReportItem] here always wraps a real
/// [ReportRecord] and `reportId` is never null -- which also means the
/// source's `triggerDownload`/`handleDeleteReport` fallback branches for a
/// missing `reportId` (direct-filepath download, "unavailable" alert, and
/// local-only delete) are unreachable and were dropped from the port.
class ReportItem {
  const ReportItem({
    required this.id,
    required this.roadId,
    required this.district,
    required this.distressType,
    required this.severity,
    required this.generatedDate,
    required this.generatedAt,
    required this.status,
    required this.reportType,
    required this.size,
    required this.generatedBy,
    required this.downloadCount,
    required this.reportId,
    this.filepath,
  });

  final String id;
  final String roadId;
  final String district;
  final String distressType;
  final String severity;
  final String generatedDate;

  /// Full timestamp (not just the date) for display -- see
  /// reports_registry_card.dart's "Generated Date" column, which uses
  /// formatDateTimeIN (.toLocal()-aware) on this instead of [generatedDate].
  final DateTime generatedAt;
  final String status;
  final String? filepath;
  final int reportId;
  final String reportType;
  final String size;
  final String generatedBy;
  final int downloadCount;

  static final _videoIdPattern = RegExp(r'Video_(\d+)', caseSensitive: false);

  factory ReportItem.fromRecord(
    ReportRecord rec, {
    required List<UploadedVideo> videos,
    required List<AppUser> users,
    required List<DistressRecord> distresses,
  }) {
    final match = _videoIdPattern.firstMatch(rec.reportName);
    var roadId = 'NH-48';
    var district = 'Mumbai';
    var distressType = 'Potholes & Cracks';
    var severity = 'High';
    var downloadCount = 10;

    if (match != null) {
      final vidId = int.parse(match.group(1)!);
      UploadedVideo? associated;
      for (final v in videos) {
        if (v.id == vidId) {
          associated = v;
          break;
        }
      }
      if (associated != null) {
        roadId = 'Road-${associated.id}';
        district = _kDistricts[vidId % _kDistricts.length];
        final principal = _principalDistressFor(vidId, distresses);
        distressType = principal.distressType;
        severity = principal.severity;
      }
      downloadCount = vidId * 3 + 4;
    }

    String engineer = 'System Auditor';
    for (final u in users) {
      if (u.id == rec.generatedBy) {
        engineer = u.fullName ?? engineer;
        break;
      }
    }

    final generatedAtStr = rec.generatedAt ?? rec.createdAt;
    return ReportItem(
      id: rec.reportName,
      roadId: roadId,
      district: district,
      distressType: distressType,
      severity: severity,
      generatedDate: generatedAtStr.split('T').first,
      generatedAt: DateTime.tryParse(generatedAtStr) ?? DateTime.now(),
      status: rec.filepath != null ? 'Exported' : 'Approved',
      filepath: rec.filepath,
      reportId: rec.id,
      reportType: rec.reportType.isNotEmpty ? rec.reportType : 'PDF',
      size: rec.reportType == 'EXCEL' ? '240 KB' : '1.8 MB',
      generatedBy: engineer,
      downloadCount: downloadCount,
    );
  }

  /// Mirrors `handleGeneratePdfReport`/`handleGenerateExcelReport`'s
  /// newly-generated-item construction, which uses a slightly different
  /// derivation than [fromRecord]: no 'NH-48'/'Mumbai' fallback (falls back
  /// to `Road-$videoId` and unconditional district/type/severity lookups
  /// instead), and always attributes `generatedBy` to 'System Auditor'
  /// rather than looking up the uploader.
  factory ReportItem.fromGenerated(
    ReportRecord rec, {
    required int videoId,
    required List<UploadedVideo> videos,
    required List<DistressRecord> distresses,
    required String reportType,
  }) {
    UploadedVideo? associated;
    for (final v in videos) {
      if (v.id == videoId) {
        associated = v;
        break;
      }
    }
    final roadId = associated != null ? 'Road-${associated.id}' : 'Road-$videoId';
    final principal = _principalDistressFor(videoId, distresses);
    final generatedAtStr = rec.generatedAt ?? rec.createdAt;
    return ReportItem(
      id: rec.reportName,
      roadId: roadId,
      district: _kDistricts[videoId % _kDistricts.length],
      distressType: principal.distressType,
      severity: principal.severity,
      generatedDate: generatedAtStr.split('T').first,
      generatedAt: DateTime.tryParse(generatedAtStr) ?? DateTime.now(),
      status: rec.filepath != null ? 'Exported' : 'Approved',
      filepath: rec.filepath,
      reportId: rec.id,
      reportType: reportType,
      size: reportType == 'EXCEL' ? '240 KB' : '1.8 MB',
      generatedBy: 'System Auditor',
      downloadCount: 0,
    );
  }
}

class ReportsApiException implements Exception {
  const ReportsApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Direct port of the `/reports`-related calls in apiService.ts as used by
/// ReportsDashboard.tsx.
class ReportsApi {
  ReportsApi();

  final http.Client _client = CustomHttpClient();

  Future<List<ReportRecord>> fetchReports({int skip = 0, int limit = 1000}) async {
    final uri = Uri.parse(
      '$kApiV1/reports/',
    ).replace(queryParameters: {'skip': '$skip', 'limit': '$limit'});
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw const ReportsApiException('Failed to load reports registry. Verify server status.');
    }
    final body = jsonDecode(response.body) as List<dynamic>;
    return body.map((e) => ReportRecord.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<ReportRecord> generatePdfReport(int videoId) async {
    final response = await _client.post(Uri.parse('$kApiV1/reports/generate/$videoId'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const ReportsApiException('Error compiling PDF report from CCTV processing.');
    }
    return ReportRecord.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<ReportRecord> generateExcelReport(int videoId) async {
    final response = await _client.post(Uri.parse('$kApiV1/reports/excel/$videoId'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const ReportsApiException('Error compiling Excel report from CCTV processing.');
    }
    return ReportRecord.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> deleteReport(int id) async {
    final response = await _client.delete(Uri.parse('$kApiV1/reports/$id'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const ReportsApiException('Failed to delete report from database.');
    }
  }

  String reportDownloadUrl(int reportId) => '$kApiV1/reports/download/$reportId';

  String excelReportDownloadUrl(int reportId) => '$kApiV1/reports/excel/download/$reportId';

  String reportPreviewUrl(int reportId) => '$kApiV1/reports/preview/$reportId';

  void dispose() => _client.close();
}
