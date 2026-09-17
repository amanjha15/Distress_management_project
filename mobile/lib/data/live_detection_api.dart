import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'custom_http_client.dart';

/// Global override for dynamic server URL changes inside the app
String? gCustomServerUrl;

const _kServerUrlPrefsKey = 'custom_server_url';

/// Restores a previously saved backend URL (set via [setCustomServerUrl]) so
/// the user doesn't have to re-enter it on every app launch.
Future<void> loadSavedServerUrl() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString(_kServerUrlPrefsKey);
  if (saved != null && saved.isNotEmpty) {
    gCustomServerUrl = saved;
  }
}

void setCustomServerUrl(String newUrl) {
  var clean = newUrl.trim();
  if (clean.endsWith('/')) {
    clean = clean.substring(0, clean.length - 1);
  }
  if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
    // Bare host/IP entries are almost always a LAN backend serving plain
    // HTTP, not HTTPS — default accordingly.
    clean = 'http://$clean';
  }
  gCustomServerUrl = clean;
  SharedPreferences.getInstance().then((prefs) {
    prefs.setString(_kServerUrlPrefsKey, clean);
  });
}

/// Dynamic API Base URL calculation:
/// Supports local dev, IP-based network access, in-app custom URLs, and public tunnels
String get kApiBaseUrl {
  if (gCustomServerUrl != null && gCustomServerUrl!.isNotEmpty) {
    return gCustomServerUrl!;
  }
  const customUrl = String.fromEnvironment('API_BASE_URL');
  if (customUrl.isNotEmpty) {
    return customUrl;
  }
  if (kIsWeb) {
    final host = Uri.base.host;
    if (host == 'localhost' || host == '127.0.0.1') {
      return 'http://127.0.0.1:8000';
    }
    if (RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(host)) {
      return 'http://$host:8000';
    }
    final origin = Uri.base.origin;
    if (origin.isNotEmpty && !origin.startsWith('file:')) {
      return origin;
    }
  }
  // No saved/env URL and not running on web: fall back to localhost. Real
  // devices must set the backend URL once via the in-app connection dialog
  // (persisted afterwards by setCustomServerUrl/loadSavedServerUrl).
  return 'http://localhost:8000';
}

String get kApiV1 => '$kApiBaseUrl/api/v1';

/// Mirrors the backend's `GET /api/v1/live/status` (and the `status` field
/// pushed over the `/live/ws` WebSocket).
class LiveStatus {
  const LiveStatus({
    required this.running,
    required this.error,
    required this.frames,
    required this.inferences,
    required this.detectionsTotal,
    required this.detectionsRoad,
    required this.detectionsSign,
    required this.criticalAlerts,
    required this.persisted,
    required this.avgConfidence,
    required this.fps,
    required this.inferenceFps,
    this.videoId,
  });

  final bool running;
  final String? error;
  final int frames;
  final int inferences;
  final int detectionsTotal;
  final int detectionsRoad;
  final int detectionsSign;
  final int criticalAlerts;
  final int persisted;
  final double avgConfidence;
  final double fps;
  final double? inferenceFps;

  /// The synthetic UploadedVideo record id created for this live session
  /// (see LiveCameraManager._start_session_video_record on the backend) --
  /// pass this to RoadDistressApi.generatePdfReport once the session
  /// stops, to get a report of exactly this session's detections.
  final int? videoId;

  factory LiveStatus.fromJson(Map<String, dynamic> json) {
    return LiveStatus(
      running: json['running'] as bool? ?? false,
      error: json['error'] as String?,
      frames: (json['frames'] as num?)?.toInt() ?? 0,
      inferences: (json['inferences'] as num?)?.toInt() ?? 0,
      detectionsTotal: (json['detections_total'] as num?)?.toInt() ?? 0,
      detectionsRoad: (json['detections_road'] as num?)?.toInt() ?? 0,
      detectionsSign: (json['detections_sign'] as num?)?.toInt() ?? 0,
      criticalAlerts: (json['critical_alerts'] as num?)?.toInt() ?? 0,
      persisted: (json['persisted'] as num?)?.toInt() ?? 0,
      avgConfidence: (json['avg_confidence'] as num?)?.toDouble() ?? 0,
      fps: (json['fps'] as num?)?.toDouble() ?? 0,
      inferenceFps: (json['inference_fps'] as num?)?.toDouble(),
      videoId: (json['video_id'] as num?)?.toInt(),
    );
  }
}

/// Mirrors one entry of the `events` array pushed over the WebSocket.
class LiveEvent {
  const LiveEvent({
    required this.seq,
    required this.time,
    required this.className,
    required this.confidence,
    required this.severity,
    required this.modelSource,
    required this.frame,
    required this.latitude,
    required this.longitude,
    this.box,
    this.frameWidth,
    this.frameHeight,
  });

  final int seq;
  final String time;
  final String className;
  final double confidence;
  final String severity;
  final String modelSource;
  final int frame;
  final double latitude;
  final double longitude;

  /// [x1, y1, x2, y2] in pixel coords of the frame that produced this
  /// detection -- relative to [frameWidth]/[frameHeight], NOT the on-screen
  /// widget size. A consumer drawing this on a preview must scale by
  /// (widgetSize / frameSize). Null for older backends that predate box
  /// reporting, or if the backend ever fails to include it.
  final List<double>? box;
  final int? frameWidth;
  final int? frameHeight;

  factory LiveEvent.fromJson(Map<String, dynamic> json) {
    final boxJson = json['box'] as List<dynamic>?;
    return LiveEvent(
      seq: (json['seq'] as num).toInt(),
      time: json['time'] as String,
      className: json['class_name'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      severity: json['severity'] as String,
      modelSource: json['model_source'] as String,
      frame: (json['frame'] as num).toInt(),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      box: boxJson?.map((v) => (v as num).toDouble()).toList(),
      frameWidth: (json['frame_width'] as num?)?.toInt(),
      frameHeight: (json['frame_height'] as num?)?.toInt(),
    );
  }
}

/// Thrown when `/live/start` responds with a non-2xx status; carries the
/// backend's `detail` message (e.g. "YOLOX models not found").
class LiveDetectionException implements Exception {
  const LiveDetectionException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Direct port of the fetch/WebSocket calls in LiveMonitoringDashboard.tsx.
/// Deliberately bypasses the app's Riverpod/dio setup, same as the React
/// source bypasses `apiService.ts` for this one feature.
class LiveDetectionApi {
  LiveDetectionApi();

  final http.Client _client = CustomHttpClient();

  Future<void> start({required int cameraIndex}) async {
    final response = await _client.post(
      Uri.parse('$kApiV1/live/start'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'camera_index': cameraIndex}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var detail = 'Failed to start';
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        detail = body['detail']?.toString() ?? detail;
      } catch (_) {
        // Non-JSON error body; fall back to the generic message.
      }
      throw LiveDetectionException(detail);
    }
  }

  /// Returns the stopped session's video_id (for generating a report of
  /// just this session -- see LiveStatus.videoId), or null if the request
  /// failed or the backend didn't return one.
  Future<int?> stop() async {
    try {
      final response = await _client.post(Uri.parse('$kApiV1/live/stop'));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return (body['video_id'] as num?)?.toInt();
      }
    } catch (_) {
      // Matches the React source's fire-and-forget `catch { /* noop */ }`.
    }
    return null;
  }

  /// Returns null on any failure (offline backend, network error, etc.) —
  /// matches the React source's silent `catch (e) { /* ignore offline */ }`.
  Future<LiveStatus?> fetchStatus() async {
    try {
      final response = await _client.get(Uri.parse('$kApiV1/live/status'));
      if (response.statusCode == 200) {
        return LiveStatus.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      }
    } catch (_) {
      // Offline/unreachable backend.
    }
    return null;
  }

  String streamUrlFor(int streamKey) => '$kApiV1/live/stream?k=$streamKey';

  /// Builds a ws:// or wss:// URI for [path], preserving the base URL's port
  /// -- explicit if it has one, or the correct implicit default (443/80) if
  /// it doesn't (e.g. a tunnel URL like https://foo.loca.lt with no :port).
  /// A plain text scheme swap (http -> ws) loses that implicit default: Dart's
  /// Uri only knows built-in default ports for http/https, not ws/wss, so a
  /// port-less https:// base would silently resolve to port 0 on the wss://
  /// side -- which is exactly what broke phone-camera streaming over the
  /// public tunnel (LAN URLs always have an explicit :8000, so this only
  /// surfaced over cellular/tunnel access, never on Wi-Fi).
  Uri _wsUri(String path) {
    final base = Uri.parse(kApiBaseUrl);
    final secure = base.scheme == 'https';
    final port = base.hasPort ? base.port : (secure ? 443 : 80);
    return Uri(scheme: secure ? 'wss' : 'ws', host: base.host, port: port, path: path);
  }

  WebSocketChannel connectWs() => WebSocketChannel.connect(_wsUri('/api/v1/live/ws'));

  /// Connects to the remote-stream session: send one binary message per
  /// frame (raw JPEG bytes) on the returned channel's sink to feed the
  /// backend's detection loop from this device's own camera instead of a
  /// USB camera attached to the server. Detection results still arrive the
  /// normal way, via [connectWs] -- this channel is send-only from the
  /// client's side. Closing it stops the session server-side.
  WebSocketChannel connectPhoneStreamWs() =>
      WebSocketChannel.connect(_wsUri('/api/v1/live/phone-stream'));

  void dispose() => _client.close();
}
