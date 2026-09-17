import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/analytics_api.dart';
import '../../data/maintenance_api.dart';
import '../../data/reports_api.dart';
import '../../data/road_distress_api.dart';
import '../../data/video_api.dart';
import '../../router/app_router.dart';
import '../../theme/app_colors.dart';
import 'widgets/analytics_map_card.dart';
import 'widgets/distress_donut_card.dart';
import 'widgets/inspections_table.dart';
import 'widgets/kpi_grid.dart';
import 'widgets/priority_cost_row.dart';
import 'widgets/road_health_gauge.dart';
import 'widgets/severity_stacked_card.dart';
import 'widgets/summary_section.dart';
import 'widgets/timeline_scatter_row.dart';

const _kShortMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _shortDate(DateTime d) => '${_kShortMonths[d.month - 1]} ${d.day}';
String _monthYear(DateTime d) => '${_kShortMonths[d.month - 1]} ${(d.year % 100).toString().padLeft(2, '0')}';
// .toLocal() matters here: these DateTimes may be UTC-aware (parsed from a
// backend timestamp with a +00:00 suffix) -- without converting first,
// _isoDay buckets events by their UTC calendar day instead of the viewer's,
// which visibly mis-files anything near a local midnight.
String _dateIN(DateTime d) {
  final local = d.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
}
String _isoDay(DateTime d) => d.toLocal().toIso8601String().split('T').first;
String _capitalizeFirst(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
String _titleCaseWords(String s) =>
    s.split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');

double _severityPenalty(String severity) => switch (severity) {
      'critical' => 5.0,
      'high' => 3.0,
      'medium' => 1.5,
      _ => 0.5,
    };

/// Direct port of Road-Distress-Management-System/frontend/src/pages/
/// Analytics/AnalyticsDashboard.tsx: real data from GET
/// /api/v1/detection/summary, GET /api/v1/distress/, GET /api/v1/videos/,
/// GET /api/v1/reports/, and GET /api/v1/maintenance/recommendations,
/// combined client-side into 11 charts, a real interactive GIS map (via
/// flutter_map, the closest equivalent to the source's react-leaflet map),
/// a road-health gauge, an inspections registry table, and executive
/// summary cards -- all computed exactly as the source's `useMemo` blocks
/// do. `components/dashboard/MaintenanceAnalytics.tsx` in the React source
/// is dead code (never imported by any page or route), so nothing there
/// needed porting.
///
/// Three computations in the source are themselves dead code -- discovered
/// while porting, not a scope decision: `processingPerformanceData`,
/// `availablePerformanceMetrics`, and `confidenceHistogramData` are all
/// computed and fed into `fullscreenChartId === 'performance'`/`'histogram'`
/// branches of the fullscreen modal, but no button anywhere in the source
/// ever calls `setFullscreenChartId('performance')` or `'histogram')` --
/// there's no card for either chart in the main layout. Since those charts
/// are unreachable from any real interaction, none of it was ported.
///
/// Trimmed vs. the ~1,486-line React source: the PNG-export button on every
/// chart card (client-side SVG-to-canvas-to-PNG, no backend tie) and the
/// "expand to fullscreen" modal for each chart (a pure view convenience --
/// every chart's data is already fully visible at its normal card size).
/// Both reasons match the CSV/export-button trims made on earlier screens:
/// no backend tie, peripheral to the screen's informational purpose.
///
/// The "Analyze" button in the inspections table navigates to `/dashboard`
/// rather than the source's `/inspection/:videoId` -- see
/// `lib/screens/analytics/widgets/inspections_table.dart`'s doc comment for
/// why (the existing DashboardGridScreen doesn't support deep-linking to a
/// specific run, and extending it is out of scope for this port).
///
/// The "AI Model Performance Indicators" card hardcodes 5 of its 6 fields
/// (model name/version/size, inference device/speed) because the backend's
/// `get_detection_analytics` never actually returns those keys -- see
/// `widgets/summary_section.dart`'s `AiModelPerformanceCard` doc comment.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final _analyticsApi = AnalyticsApi();
  final _distressApi = RoadDistressApi();
  final _videoApi = VideoApi();
  final _reportsApi = ReportsApi();
  final _maintenanceApi = MaintenanceApi();

  List<DistressRecord> _distresses = [];
  List<UploadedVideo> _videos = [];
  List<ReportRecord> _reports = [];
  List<MaintenanceRecommendation> _maintenanceTasks = [];
  bool _isLoading = true;
  String? _error;

  String _timelinePeriod = 'weekly';
  final Set<String> _hiddenSeverities = {};
  int _animatedHealthScore = 0;
  Timer? _healthTimer;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    _healthTimer?.cancel();
    _analyticsApi.dispose();
    _distressApi.dispose();
    _videoApi.dispose();
    _reportsApi.dispose();
    _maintenanceApi.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _analyticsApi.pingDetectionSummary(),
        _distressApi.fetchDistresses(limit: 1000),
        _videoApi.fetchVideos(limit: 200),
        _reportsApi.fetchReports(skip: 0, limit: 200),
        _maintenanceApi.fetchRecommendations(),
      ]);
      final distresses = results[1] as List<DistressRecord>;
      final videos = results[2] as List<UploadedVideo>;
      final reports = results[3] as List<ReportRecord>;
      final tasks = results[4] as List<MaintenanceRecommendation>;
      if (!mounted) return;
      setState(() {
        _distresses = distresses;
        _videos = videos;
        _reports = reports;
        _maintenanceTasks = tasks;
        _isLoading = false;
      });
      _startHealthAnimation(_targetHealthScore);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to synchronize executive analytics databases. Verification logs ready.';
        _isLoading = false;
      });
    }
  }

  void _startHealthAnimation(int target) {
    _healthTimer?.cancel();
    if (target <= 0) {
      setState(() => _animatedHealthScore = 0);
      return;
    }
    var start = 0;
    final stepMs = (800 / target).floor().clamp(5, 800);
    _healthTimer = Timer.periodic(Duration(milliseconds: stepMs), (timer) {
      start += 1;
      if (start >= target) {
        setState(() => _animatedHealthScore = target);
        timer.cancel();
      } else {
        setState(() => _animatedHealthScore = start);
      }
    });
  }

  int get _targetHealthScore {
    final completed = _videos.where((v) => v.processingStatus == 'completed').toList();
    if (completed.isEmpty) return 100;
    final scores = completed.map((vid) {
      final vidDists = _distresses.where((d) => d.videoId == vid.id);
      final penalty = vidDists.fold<double>(0, (sum, d) => sum + _severityPenalty(d.severity));
      return (100 - penalty).clamp(0, 100);
    }).toList();
    final avg = scores.reduce((a, b) => a + b) / scores.length;
    return avg.round();
  }

  ({Color color, String label}) get _healthCondition {
    final score = _animatedHealthScore;
    if (score >= 95) return (color: const Color(0xFF10B981), label: 'Excellent');
    if (score >= 80) return (color: const Color(0xFF8FA06A), label: 'Good');
    if (score >= 60) return (color: const Color(0xFFF97316), label: 'Fair');
    return (color: const Color(0xFFEF4444), label: 'Critical');
  }

  Future<void> _onRefresh() => _fetchData();

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        heightFactor: 6,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('Synchronizing executive analytics infrastructure...', style: TextStyle(color: Colors.white)),
          ],
        ),
      );
    }

    if (_videos.isEmpty && _error == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          const SizedBox(height: 40),
          Center(
            heightFactor: 4,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('📂', style: TextStyle(fontSize: 40)),
                const SizedBox(height: 8),
                const Text('No inspections available.', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.primaryTextLight)),
                const SizedBox(height: 4),
                const Text('Please upload videos to run AI analytics and compile logs.', style: TextStyle(fontSize: 12, color: AppColors.secondaryTextLight)),
                const SizedBox(height: 12),
                ElevatedButton(onPressed: () => context.go(AppRoutes.uploadVideo), child: const Text('Upload Video Feed')),
              ],
            ),
          ),
        ],
      );
    }

    if (_error != null) {
      return Center(
        heightFactor: 6,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('⚠️', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            const Text('Executive Database Error', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.secondaryTextLight)),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _onRefresh, child: const Text('Retry Initialization')),
          ],
        ),
      );
    }

    final health = _healthCondition;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        const SizedBox(height: 20),
        AnalyticsKpiGrid(kpis: _kpiList()),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final gauge = RoadHealthGauge(score: _animatedHealthScore, color: health.color, label: health.label);
            final map = AnalyticsMapCard(
              clusters: _clusteredMarkers,
              center: _mapCenter,
              videos: _videos,
              allDistresses: _distresses,
            );
            if (constraints.maxWidth < 1000) {
              return Column(children: [gauge, const SizedBox(height: 20), map]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: gauge),
                const SizedBox(width: 24),
                Expanded(flex: 6, child: map),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final donut = DistressDonutCard(data: _donutChartData);
            final severity = SeverityStackedCard(
              data: _severityChartData,
              hiddenSeverities: _hiddenSeverities,
              onToggleSeverity: (s) => setState(() {
                if (!_hiddenSeverities.remove(s)) _hiddenSeverities.add(s);
              }),
            );
            if (constraints.maxWidth < 1000) {
              return Column(children: [donut, const SizedBox(height: 20), severity]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: donut),
                const SizedBox(width: 24),
                Expanded(flex: 6, child: severity),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        PriorityCostRow(priorities: _priorityChartData, costs: _costAnalysisData),
        const SizedBox(height: 20),
        TimelineScatterRow(
          timeline: _timelineChartData,
          period: _timelinePeriod,
          onPeriodChanged: (p) => setState(() => _timelinePeriod = p),
          scatter: _scatterPlotData,
        ),
        const SizedBox(height: 20),
        InspectionsTable(
          rows: _tableRows,
          showDuration: _videos.any((v) => v.processingDuration != null),
          onAnalyze: () => context.go(AppRoutes.dashboard),
        ),
        const SizedBox(height: 20),
        MaintenanceReportsSummaryRow(
          pending: _maintenanceTasks.where((t) => t.status == 'pending' || t.status == 'detected').length,
          assigned: _maintenanceTasks.where((t) => t.status == 'assigned' || t.status == 'scheduled').length,
          inProgress: _maintenanceTasks.where((t) => t.status == 'in_progress').length,
          completed: _maintenanceTasks.where((t) => t.status == 'completed' || t.status == 'resolved').length,
          pdfCount: _reportsSummary.pdf,
          excelCount: _reportsSummary.excel,
          jsonCount: _reportsSummary.json,
          latestReportDate: _reportsSummary.latest,
        ),
        const SizedBox(height: 20),
        ExecutiveInsightsCard(insights: _executiveInsights),
        const SizedBox(height: 20),
        AiModelPerformanceCard(averageConfidence: _kpis.avgConfidence),
      ],
    );
  }

  Widget _header() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Executive Analytics Center',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryTextLight,
            shadows: [Shadow(color: Color(0x66000000), offset: Offset(0, 2), blurRadius: 4)],
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'AI-powered road distress telemetry, structural indices, and rehabilitation forecasts.',
          style: TextStyle(fontSize: 13, color: AppColors.secondaryTextLight),
        ),
      ],
    );
  }

  List<AnalyticsKpi> _kpiList() {
    final kpis = _kpis;
    final trends = _trends;
    return [
      AnalyticsKpi(
        icon: LucideIcons.activity,
        label: 'Videos Processed',
        value: '${kpis.totalVideos}',
        borderColor: const Color(0xFF3B82F6),
        trendLabel: trends.videosToday > 0 ? '↑ +${trends.videosToday} Today' : null,
        trendBadgeColor: AppColors.success,
      ),
      AnalyticsKpi(
        icon: LucideIcons.layers,
        label: 'Total Distresses',
        value: '${kpis.totalDistresses}',
        borderColor: const Color(0xFFF97316),
        trendLabel: trends.distressToday > 0 ? '↑ +${trends.distressToday} Today' : null,
        trendBadgeColor: AppColors.success,
      ),
      AnalyticsKpi(
        icon: LucideIcons.gauge,
        label: 'Overall Road Health',
        value: '$_animatedHealthScore%',
        borderColor: const Color(0xFF10B981),
        valueColor: _healthCondition.color,
        trendLabel: '${_healthCondition.label.toUpperCase()} CONDITION',
        trendBadgeColor: _healthCondition.color,
      ),
      AnalyticsKpi(
        icon: LucideIcons.wrench,
        label: 'Estimated Rehab Cost',
        value: kpis.estCostFormatted,
        borderColor: const Color(0xFFEAB308),
      ),
      AnalyticsKpi(
        icon: LucideIcons.clock,
        label: 'Avg Processing Speed',
        value: kpis.avgProcTime,
        borderColor: const Color(0xFF8B5CF6),
      ),
      AnalyticsKpi(
        icon: LucideIcons.brain,
        label: 'Average Confidence',
        value: kpis.avgConfidence,
        borderColor: const Color(0xFF06B6D4),
      ),
      AnalyticsKpi(
        icon: LucideIcons.alertTriangle,
        label: 'Active Task Tickets',
        value: '${kpis.activeTasks}',
        borderColor: const Color(0xFFEF4444),
        valueColor: AppColors.danger,
      ),
      AnalyticsKpi(
        icon: LucideIcons.fileText,
        label: 'Reports Generated',
        value: '${kpis.totalReports}',
        borderColor: const Color(0xFF64748B),
        trendLabel: trends.reportsToday > 0 ? '↑ +${trends.reportsToday} Today' : null,
        trendBadgeColor: AppColors.success,
      ),
    ];
  }

  ({int totalVideos, int totalDistresses, String estCostFormatted, String avgProcTime, String avgConfidence, int activeTasks, int totalReports}) get _kpis {
    final totalVideos = _videos.length;
    final totalDistresses = _distresses.length;

    final totalCost = _maintenanceTasks.fold<double>(0, (sum, t) => sum + (t.estimatedCost ?? 0));
    final estCostFormatted = totalCost > 0 ? '₹${(totalCost / 100000).toStringAsFixed(2)}L' : '₹0.00';

    final completed = _videos.where((v) => v.processingStatus == 'completed').toList();
    final withDuration = completed.where((v) => v.processingDuration != null).toList();
    final avgProcTime = withDuration.isNotEmpty
        ? '${(withDuration.fold<double>(0, (s, v) => s + v.processingDuration!) / withDuration.length).toStringAsFixed(1)}s'
        : 'Not Available';

    final totalConf = _distresses.fold<double>(0, (s, d) => s + (d.confidenceScore > 0 ? d.confidenceScore : 0.85));
    final avgConfidence = totalDistresses > 0 ? '${((totalConf / totalDistresses) * 100).round()}%' : '87.4%';

    final activeTasks = _maintenanceTasks.where((t) => (t.status ?? '') != 'completed').length;

    return (
      totalVideos: totalVideos,
      totalDistresses: totalDistresses,
      estCostFormatted: estCostFormatted,
      avgProcTime: avgProcTime,
      avgConfidence: avgConfidence,
      activeTasks: activeTasks,
      totalReports: _reports.length,
    );
  }

  ({int videosToday, int distressToday, int reportsToday}) get _trends {
    final todayStr = _isoDay(DateTime.now());
    return (
      videosToday: _videos.where((v) => _isoDay(v.uploadTimestamp) == todayStr).length,
      distressToday: _distresses.where((d) => _isoDay(d.detectedAt) == todayStr).length,
      reportsToday: _reports.where((r) => (r.generatedAt ?? r.createdAt).split('T').first == todayStr).length,
    );
  }

  Map<String, int> get _donutChartData {
    final counts = <String, int>{};
    for (final d in _distresses) {
      final type = d.distressType.replaceAll('_', ' ').toLowerCase();
      counts[type] = (counts[type] ?? 0) + 1;
    }
    return counts.map((k, v) => MapEntry(_capitalizeFirst(k), v));
  }

  List<SeverityRunData> get _severityChartData {
    final videoMap = <String, Map<String, int>>{};
    for (final d in _distresses) {
      final vidName = d.videoId != null ? 'Run #${d.videoId}' : 'Manual';
      final counts = videoMap.putIfAbsent(vidName, () => {'critical': 0, 'high': 0, 'medium': 0, 'low': 0});
      if (counts.containsKey(d.severity)) counts[d.severity] = counts[d.severity]! + 1;
    }
    return videoMap.entries.take(6).map((e) => SeverityRunData(name: e.key, counts: e.value)).toList();
  }

  List<PriorityCount> get _priorityChartData {
    final priorities = {'P1': 0, 'P2': 0, 'P3': 0, 'P4': 0};
    for (final t in _maintenanceTasks) {
      final p = (t.priority ?? '').toUpperCase();
      if (p == 'CRITICAL' || p == 'HIGH') {
        priorities['P1'] = priorities['P1']! + 1;
      } else if (p == 'MEDIUM') {
        priorities['P2'] = priorities['P2']! + 1;
      } else if (p == 'LOW') {
        priorities['P3'] = priorities['P3']! + 1;
      } else {
        priorities['P4'] = priorities['P4']! + 1;
      }
    }
    if (_maintenanceTasks.isEmpty) {
      for (final d in _distresses) {
        switch (d.severity) {
          case 'critical':
            priorities['P1'] = priorities['P1']! + 1;
          case 'high':
            priorities['P2'] = priorities['P2']! + 1;
          case 'medium':
            priorities['P3'] = priorities['P3']! + 1;
          default:
            priorities['P4'] = priorities['P4']! + 1;
        }
      }
    }
    return priorities.entries.map((e) => PriorityCount(e.key, e.value)).toList();
  }

  List<CostRow> get _costAnalysisData {
    final classStats = <String, (double total, int count, double max)>{};
    for (final t in _maintenanceTasks) {
      DistressRecord? distress;
      for (final d in _distresses) {
        if (d.id == t.distressId) {
          distress = d;
          break;
        }
      }
      final type = distress?.distressType.toLowerCase() ?? 'other';
      final cost = t.estimatedCost ?? 0;
      final existing = classStats[type];
      if (existing == null) {
        classStats[type] = (cost, 1, cost);
      } else {
        classStats[type] = (existing.$1 + cost, existing.$2 + 1, existing.$3 > cost ? existing.$3 : cost);
      }
    }
    return classStats.entries.map((e) {
      final label = _capitalizeFirst(e.key.replaceAll('_', ' '));
      final (total, count, max) = e.value;
      return CostRow(
        name: label,
        estimated: (total / 1000).round(),
        average: (total / (count == 0 ? 1 : count) / 1000).round(),
        highest: (max / 1000).round(),
      );
    }).toList();
  }

  List<TimelinePoint> get _timelineChartData {
    final dailyCounts = <String, int>{};
    for (final d in _distresses) {
      final date = _isoDay(d.detectedAt);
      dailyCounts[date] = (dailyCounts[date] ?? 0) + 1;
    }
    final sortedDates = dailyCounts.keys.toList()..sort();

    if (_timelinePeriod == 'daily') {
      final recent = sortedDates.length > 10 ? sortedDates.sublist(sortedDates.length - 10) : sortedDates;
      return [for (final date in recent) TimelinePoint(_shortDate(DateTime.parse(date)), dailyCounts[date]!)];
    }

    if (_timelinePeriod == 'weekly') {
      final weeks = <String, int>{};
      for (final date in sortedDates) {
        final d = DateTime.parse(date);
        final startOfWeek = d.subtract(Duration(days: d.weekday % 7));
        final key = _isoDay(startOfWeek);
        weeks[key] = (weeks[key] ?? 0) + dailyCounts[date]!;
      }
      final sortedWeeks = weeks.keys.toList()..sort();
      return [for (final w in sortedWeeks) TimelinePoint('Wk ${_shortDate(DateTime.parse(w))}', weeks[w]!)];
    }

    final months = <String, int>{};
    for (final date in sortedDates) {
      final mLabel = _monthYear(DateTime.parse(date));
      months[mLabel] = (months[mLabel] ?? 0) + dailyCounts[date]!;
    }
    return [for (final entry in months.entries) TimelinePoint(entry.key, entry.value)];
  }

  List<ScatterPoint> get _scatterPlotData {
    return _distresses.take(40).map((d) {
      final area = double.parse((d.affectedArea ?? 0.15).toStringAsFixed(3));
      return ScatterPoint(area: area, impact: _severityPenalty(d.severity), severity: d.severity);
    }).toList();
  }

  bool get _mapCoordinatesExist => _distresses.any((d) => d.latitude != 0 || d.longitude != 0);

  LatLng get _mapCenter {
    final valid = _distresses.where((d) => d.latitude != 0 || d.longitude != 0).toList();
    if (valid.isEmpty) return const LatLng(18.75, 73.40);
    final avgLat = valid.fold<double>(0, (s, d) => s + d.latitude) / valid.length;
    final avgLng = valid.fold<double>(0, (s, d) => s + d.longitude) / valid.length;
    return LatLng(avgLat, avgLng);
  }

  List<DistressCluster> get _clusteredMarkers {
    if (!_mapCoordinatesExist) return [];
    final groups = <String, List<DistressRecord>>{};
    for (final d in _distresses) {
      if (d.latitude == 0 && d.longitude == 0) continue;
      final key = '${d.latitude.toStringAsFixed(3)},${d.longitude.toStringAsFixed(3)}';
      groups.putIfAbsent(key, () => []).add(d);
    }
    return groups.entries.map((e) {
      final parts = e.key.split(',');
      return DistressCluster(lat: double.parse(parts[0]), lng: double.parse(parts[1]), items: e.value);
    }).toList();
  }

  ({int pdf, int excel, int json, String latest}) get _reportsSummary {
    final hasReports = _reports.isNotEmpty;
    final pdf = hasReports ? _reports.where((r) => r.reportType.toLowerCase() == 'pdf').length : 14;
    final excel = hasReports ? _reports.where((r) => r.reportType.toLowerCase() == 'excel').length : 8;
    final json = hasReports ? _reports.where((r) => r.reportType.toLowerCase() == 'json').length : 5;
    final latest = _reports.isNotEmpty
        ? _dateIN(DateTime.parse(_reports.first.generatedAt ?? _reports.first.createdAt))
        : '02/07/2026';
    return (pdf: pdf, excel: excel, json: json, latest: latest);
  }

  List<String> get _executiveInsights {
    final insights = <String>[];
    if (_distresses.isNotEmpty) {
      final counts = <String, int>{};
      for (final d in _distresses) {
        counts[d.distressType] = (counts[d.distressType] ?? 0) + 1;
      }
      final topType = counts.entries.reduce((a, b) => a.value > b.value ? a : b).key;
      insights.add('Most detected distress is ${_titleCaseWords(topType.replaceAll('_', ' '))}.');
      final criticalCount = _distresses.where((d) => d.severity == 'critical').length;
      final ratio = (criticalCount / _distresses.length * 100).round();
      insights.add('Critical defects account for $ratio% of detections.');
    } else {
      insights.add('Most detected distress is Longitudinal Crack.');
      insights.add('Critical defects account for 8% of all detections.');
    }
    insights.add('Road Health Index is rated at $_animatedHealthScore% based on completed inspections.');
    final rehabNeeded = _maintenanceTasks.where((t) => (t.status ?? '') != 'completed').length;
    insights.add(rehabNeeded > 0
        ? '$rehabNeeded active maintenance tasks are queued in the pipeline.'
        : 'No active maintenance tasks pending.');
    insights.add('Damage area index parameters show maximum density in low-light environments.');
    return insights;
  }

  List<InspectionRow> get _tableRows {
    final rows = _videos.map((v) {
      final vidDists = _distresses.where((d) => d.videoId == v.id);
      final penalty = vidDists.fold<double>(0, (sum, d) => sum + _severityPenalty(d.severity));
      final healthScore = (100 - penalty).clamp(0, 100).round();
      return InspectionRow(video: v, distressCount: vidDists.length, healthScore: healthScore);
    }).toList();
    rows.sort((a, b) => b.video.uploadTimestamp.compareTo(a.video.uploadTimestamp));
    return rows;
  }
}
