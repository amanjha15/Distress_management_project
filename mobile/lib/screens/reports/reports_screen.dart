import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/maintenance_api.dart';
import '../../data/reports_api.dart';
import '../../data/road_distress_api.dart';
import '../../data/video_api.dart';
import '../../theme/app_colors.dart';
import '../../utils/download_helper.dart';
import 'widgets/registry_overview_card.dart';
import 'widgets/report_preview_modal.dart';
import 'widgets/reports_registry_card.dart';

const _kFavoritesPrefsKey = 'road_reports_favorites';

/// Direct port of Road-Distress-Management-System/frontend/src/pages/
/// Reports/ReportsDashboard.tsx: real backend data (GET /api/v1/reports/ +
/// GET /api/v1/videos/ + GET /api/v1/users/, joined client-side into
/// `ReportItem`s exactly as the React source does -- there's no backend
/// endpoint that returns this joined shape directly), real PDF/Excel report
/// generation and deletion, real download links, and favorites persisted
/// the same way the source persists them to `localStorage`. The
/// components/reports/*.tsx files in the React source (ReportGeneratorPanel,
/// ReportsTable) are dead code (never imported by any page or route), so
/// nothing there needed porting.
///
/// Trimmed vs. the ~1,189-line React source: the "Generate Custom Report"
/// button, its 4 decorative State/District/DistressType/Severity filter
/// dropdowns, and the "Schedule Report" button. All three are 100% fake --
/// the custom report is fabricated client-side behind a `setTimeout` with no
/// backend call at all, and "Schedule Report" is just a bare `alert()` --
/// so unlike the PDF/Excel-cover preview renderers (which are decorative
/// but preview *real* generated reports), these have no real functionality
/// to preserve. Trimming them also means every [ReportItem] in this port
/// always has a real `reportId`, which removes the source's dead JSON
/// preview/download branches too (see reports_api.dart for details).
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _reportsApi = ReportsApi();
  final _videoApi = VideoApi();
  final _maintenanceApi = MaintenanceApi();
  final _distressApi = RoadDistressApi();

  List<ReportItem> _reports = [];
  List<UploadedVideo> _videos = [];
  List<DistressRecord> _distresses = [];
  bool _isLoading = true;
  String? _error;

  String _searchQuery = '';
  String _typeFilter = 'All';
  String _severityFilter = 'All';
  String _statusFilter = 'All';
  String _startDate = '';
  String _endDate = '';
  bool _showFavoritesOnly = false;

  int? _selectedVideoId;
  bool _isCompiling = false;
  bool _isCompilingExcel = false;

  ReportItem? _previewReport;
  final Set<String> _favorites = {};
  final Set<String> _selectedReportIds = {};

  int _currentPage = 1;
  static const _itemsPerPage = 8;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    _fetchData();
  }

  @override
  void dispose() {
    _reportsApi.dispose();
    _videoApi.dispose();
    _maintenanceApi.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kFavoritesPrefsKey);
    if (saved == null) return;
    try {
      final decoded = (jsonDecode(saved) as List<dynamic>).cast<String>();
      if (!mounted) return;
      setState(() {
        _favorites
          ..clear()
          ..addAll(decoded);
      });
    } catch (_) {
      // Corrupt/old preference shape; keep empty.
    }
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kFavoritesPrefsKey, jsonEncode(_favorites.toList()));
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _reportsApi.fetchReports(skip: 0, limit: 1000),
        _videoApi.fetchVideos(skip: 0, limit: 200),
        _maintenanceApi.fetchUsers(skip: 0, limit: 200),
        _distressApi.fetchDistresses(skip: 0, limit: 1000),
      ]);
      final records = results[0] as List<ReportRecord>;
      final videos = results[1] as List<UploadedVideo>;
      final users = results[2] as List<AppUser>;
      final distresses = results[3] as List<DistressRecord>;
      if (!mounted) return;
      setState(() {
        _videos = videos;
        _distresses = distresses;
        _reports = records
            .map((r) => ReportItem.fromRecord(r, videos: videos, users: users, distresses: distresses))
            .toList();
        _error = null;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load reports registry. Verify server status.';
        _reports = [];
        _isLoading = false;
      });
    }
  }

  List<ReportItem> get _filteredReports {
    final query = _searchQuery.toLowerCase();
    final startLimit = _startDate.isEmpty ? null : DateTime.tryParse(_startDate);
    final endLimit = _endDate.isEmpty ? null : DateTime.tryParse(_endDate);
    return _reports.where((r) {
      final matchesSearch = r.id.toLowerCase().contains(query) ||
          r.roadId.toLowerCase().contains(query) ||
          r.district.toLowerCase().contains(query);
      final matchesType = _typeFilter == 'All' || r.reportType == _typeFilter;
      final matchesSeverity = _severityFilter == 'All' || r.severity == _severityFilter;
      final matchesStatus = _statusFilter == 'All' || r.status == _statusFilter;
      final matchesFavorite = !_showFavoritesOnly || _favorites.contains(r.id);
      final genTime = DateTime.tryParse(r.generatedDate);
      final matchesDateRange = genTime == null ||
          ((startLimit == null || !genTime.isBefore(startLimit)) &&
              (endLimit == null || !genTime.isAfter(endLimit)));
      return matchesSearch && matchesType && matchesSeverity && matchesStatus && matchesFavorite && matchesDateRange;
    }).toList();
  }

  ({int total, int todayCount, int monthlyCount, String mostDownloaded, String averageGenTime}) get _stats {
    final todayStr = DateTime.now().toIso8601String().split('T').first;
    final thisMonthPrefix = todayStr.substring(0, 7);
    var mostDownloaded = 'None';
    var maxDownloads = -1;
    for (final r in _reports) {
      if (r.downloadCount > maxDownloads) {
        maxDownloads = r.downloadCount;
        mostDownloaded = r.id;
      }
    }
    return (
      total: _reports.length,
      todayCount: _reports.where((r) => r.generatedDate == todayStr).length,
      monthlyCount: _reports.where((r) => r.generatedDate.startsWith(thisMonthPrefix)).length,
      mostDownloaded: mostDownloaded,
      averageGenTime: '2.4 seconds',
    );
  }

  void _toggleFavorite(ReportItem r) {
    setState(() {
      if (!_favorites.remove(r.id)) _favorites.add(r.id);
    });
    _saveFavorites();
  }

  void _toggleSelect(ReportItem r) {
    setState(() {
      if (!_selectedReportIds.remove(r.id)) _selectedReportIds.add(r.id);
    });
  }

  void _selectAllFiltered() {
    final ids = _filteredReports.map((r) => r.id).toSet();
    final allSelected = ids.isNotEmpty && ids.every(_selectedReportIds.contains);
    setState(() {
      if (allSelected) {
        _selectedReportIds.removeAll(ids);
      } else {
        _selectedReportIds.addAll(ids);
      }
    });
  }

  Future<void> _triggerDownload(ReportItem report) async {
    final url = report.reportType == 'EXCEL'
        ? _reportsApi.excelReportDownloadUrl(report.reportId)
        : _reportsApi.reportDownloadUrl(report.reportId);
    final ext = report.reportType == 'EXCEL' ? 'xlsx' : 'pdf';
    await triggerReportDownload(url, '${report.id}.$ext');
  }

  void _handleBulkDownload() {
    final selected = _reports.where((r) => _selectedReportIds.contains(r.id)).toList();
    for (var i = 0; i < selected.length; i++) {
      Future.delayed(Duration(milliseconds: i * 800), () => _triggerDownload(selected[i]));
    }
  }

  Future<void> _handleDeleteReport(ReportItem report) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete report'),
        content: const Text('Are you sure you want to delete this report from the server registry?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _reportsApi.deleteReport(report.reportId);
      if (!mounted) return;
      setState(() {
        _reports = _reports.where((r) => r.reportId != report.reportId).toList();
        if (_previewReport?.id == report.id) _previewReport = null;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete report from database.')),
      );
    }
  }

  Future<void> _generatePdfReport() async {
    final videoId = _selectedVideoId;
    if (videoId == null) return;
    setState(() => _isCompiling = true);
    try {
      final rec = await _reportsApi.generatePdfReport(videoId);
      final newItem = ReportItem.fromGenerated(
        rec,
        videoId: videoId,
        videos: _videos,
        distresses: _distresses,
        reportType: 'PDF',
      );
      if (!mounted) return;
      setState(() {
        _reports = [newItem, ..._reports];
        _selectedVideoId = null;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error compiling PDF report from CCTV processing.')),
      );
    } finally {
      if (mounted) setState(() => _isCompiling = false);
    }
  }

  Future<void> _generateExcelReport() async {
    final videoId = _selectedVideoId;
    if (videoId == null) return;
    setState(() => _isCompilingExcel = true);
    try {
      final rec = await _reportsApi.generateExcelReport(videoId);
      final newItem = ReportItem.fromGenerated(
        rec,
        videoId: videoId,
        videos: _videos,
        distresses: _distresses,
        reportType: 'EXCEL',
      );
      if (!mounted) return;
      setState(() {
        _reports = [newItem, ..._reports];
        _selectedVideoId = null;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error compiling Excel report from CCTV processing.')),
      );
    } finally {
      if (mounted) setState(() => _isCompilingExcel = false);
    }
  }

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
            Text('Synchronizing reports database...', style: TextStyle(color: Colors.white)),
          ],
        ),
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
            const Text('Reports Registry Alert', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 450),
              child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.secondaryTextLight)),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _fetchData, child: const Text('Reinitialize Archive')),
          ],
        ),
      );
    }

    final filtered = _filteredReports;
    final totalPages = (filtered.length / _itemsPerPage).ceil().clamp(1, 1 << 30);
    final paginated = filtered.skip((_currentPage - 1) * _itemsPerPage).take(_itemsPerPage).toList();
    final stats = _stats;

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Reports Center',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryTextLight,
                shadows: [Shadow(color: Color(0x66000000), offset: Offset(0, 2), blurRadius: 4)],
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Compile AI intelligence, run structural distress summary diagnostics, and export audit documents.',
              style: TextStyle(fontSize: 13, color: AppColors.secondaryTextLight),
            ),
            const SizedBox(height: 20),
            _kpiGrid(stats),
            if (_selectedReportIds.isNotEmpty) ...[
              const SizedBox(height: 16),
              _bulkExportBar(),
            ],
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final registry = ReportsRegistryCard(
                  filteredReports: filtered,
                  paginatedReports: paginated,
                  favorites: _favorites,
                  selectedIds: _selectedReportIds,
                  searchQuery: _searchQuery,
                  typeFilter: _typeFilter,
                  severityFilter: _severityFilter,
                  statusFilter: _statusFilter,
                  startDate: _startDate,
                  endDate: _endDate,
                  showFavoritesOnly: _showFavoritesOnly,
                  currentPage: _currentPage,
                  totalPages: totalPages,
                  itemsPerPage: _itemsPerPage,
                  onRefresh: _fetchData,
                  onSearchChanged: (v) => setState(() { _searchQuery = v; _currentPage = 1; }),
                  onTypeChanged: (v) => setState(() { _typeFilter = v; _currentPage = 1; }),
                  onSeverityChanged: (v) => setState(() { _severityFilter = v; _currentPage = 1; }),
                  onStatusChanged: (v) => setState(() { _statusFilter = v; _currentPage = 1; }),
                  onStartDateChanged: (v) => setState(() { _startDate = v; _currentPage = 1; }),
                  onEndDateChanged: (v) => setState(() { _endDate = v; _currentPage = 1; }),
                  onFavoritesOnlyChanged: (v) => setState(() { _showFavoritesOnly = v; _currentPage = 1; }),
                  onSelectAllFiltered: _selectAllFiltered,
                  onToggleSelect: _toggleSelect,
                  onToggleFavorite: _toggleFavorite,
                  onPreview: (r) => setState(() => _previewReport = r),
                  onDownload: _triggerDownload,
                  onDelete: _handleDeleteReport,
                  onPrevPage: () => setState(() => _currentPage = (_currentPage - 1).clamp(1, totalPages)),
                  onNextPage: () => setState(() => _currentPage = (_currentPage + 1).clamp(1, totalPages)),
                );
                final overview = RegistryOverviewCard(allReports: _reports, filteredReports: filtered);

                if (constraints.maxWidth < 1000) {
                  return Column(children: [registry, const SizedBox(height: 20), overview]);
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 11, child: registry),
                    const SizedBox(width: 24),
                    Expanded(flex: 5, child: overview),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            _compilationCard(),
          ],
        ),
        if (_previewReport != null)
          ReportPreviewModal(
            report: _previewReport!,
            onClose: () => setState(() => _previewReport = null),
            onDownload: () => _triggerDownload(_previewReport!),
          ),
      ],
    );
  }

  Widget _kpiGrid(({int total, int todayCount, int monthlyCount, String mostDownloaded, String averageGenTime}) stats) {
    final cards = [
      (LucideIcons.fileText, 'Reports Generated', '${stats.total}', 'Total registry items', AppColors.accentBlue),
      (LucideIcons.calendar, "Today's Reports", '${stats.todayCount}', 'Compiled today', AppColors.success),
      (LucideIcons.clock, 'This Month', '${stats.monthlyCount}', 'Compiled this month', AppColors.accentBlue),
      (LucideIcons.download, 'Most Downloaded', stats.mostDownloaded, 'Top downloaded audit', AppColors.warning),
      (LucideIcons.clock, 'Avg Compile Time', stats.averageGenTime, 'Audit generation SLA', AppColors.accentBlue),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 700 ? 2 : (constraints.maxWidth < 1100 ? 3 : 5);
        const gap = 16.0;
        final tileWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final c in cards)
              SizedBox(
                width: tileWidth,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.cardBg,
                    border: Border.all(color: AppColors.cardBorder),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              c.$2.toUpperCase(),
                              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppColors.secondaryText),
                            ),
                          ),
                          Icon(c.$1, size: 15, color: c.$5),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Tooltip(
                        message: c.$3,
                        child: Text(
                          c.$3,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.$5),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(c.$4, style: const TextStyle(fontSize: 9, color: AppColors.secondaryText)),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _bulkExportBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.accentBlueLight,
        border: Border.all(color: AppColors.cardBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 8,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.fileText, size: 16, color: AppColors.accentBlue),
              const SizedBox(width: 8),
              Text.rich(TextSpan(style: const TextStyle(fontSize: 12, color: AppColors.primaryText), children: [
                const TextSpan(text: 'Selected '),
                TextSpan(text: '${_selectedReportIds.length}', style: const TextStyle(fontWeight: FontWeight.w700)),
                const TextSpan(text: ' reports for batch processing'),
              ])),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton(
                onPressed: _handleBulkDownload,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentBlue, foregroundColor: Colors.white),
                child: Text('Download Selected (${_selectedReportIds.length})', style: const TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'ZIP batch export is disabled since backend compression engine is not available.',
                child: OutlinedButton(
                  onPressed: null,
                  child: const Text('ZIP Batch Export (Disabled)', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _compilationCard() {
    final completedVideos = _videos.where((v) => v.processingStatus == 'completed').toList();

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Configure AI Reports Compilation', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 14),
        if (_videos.isNotEmpty) ...[
          const Text('Select Completed Surveillance Run', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.accentBlue)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 260,
                height: 36,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(color: AppColors.primaryBg, border: Border.all(color: AppColors.cardBorder), borderRadius: BorderRadius.circular(6)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int?>(
                      value: _selectedVideoId,
                      isDense: true,
                      isExpanded: true,
                      hint: const Text('-- Choose Completed Video Run --', style: TextStyle(fontSize: 12)),
                      items: [
                        for (final v in completedVideos)
                          DropdownMenuItem(
                            value: v.id,
                            child: Text(
                              '${v.filename} (ID: ${v.id})',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: AppColors.primaryText),
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _selectedVideoId = v),
                    ),
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: (_selectedVideoId == null || _isCompiling) ? null : _generatePdfReport,
                icon: _isCompiling
                    ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(LucideIcons.fileText, size: 13),
                label: Text(_isCompiling ? 'Compiling...' : 'PDF Report', style: const TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentBlue, foregroundColor: Colors.white),
              ),
              OutlinedButton.icon(
                onPressed: (_selectedVideoId == null || _isCompilingExcel) ? null : _generateExcelReport,
                icon: _isCompilingExcel
                    ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(LucideIcons.table2, size: 13),
                label: Text(_isCompilingExcel ? 'Compiling...' : 'Excel Report', style: const TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.primaryText, side: BorderSide(color: AppColors.cardBorder)),
              ),
            ],
          ),
        ] else
          const Text(
            'No completed surveillance runs available for report compilation yet.',
            style: TextStyle(fontSize: 12, color: AppColors.secondaryText),
          ),
      ],
    );

    final firstReport = _reports.isNotEmpty ? _reports.first : null;
    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Registry Preview Window', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 14),
        if (firstReport != null) ...[
          _previewRow('Target ID:', firstReport.id),
          _previewRow('Format Type:', firstReport.reportType, valueColor: AppColors.accentBlue),
          _previewRow('Created By:', firstReport.generatedBy),
          _previewRow('Downloads count:', '${firstReport.downloadCount} times'),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _previewReport = firstReport),
              icon: const Icon(LucideIcons.externalLink, size: 12),
              label: const Text('Launch Cover Preview Sheet', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.primaryText, side: BorderSide(color: AppColors.cardBorder)),
            ),
          ),
        ] else
          const Text('Generate reports to preview.', style: TextStyle(fontSize: 12, color: AppColors.secondaryText)),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        border: Border.all(color: AppColors.cardBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 800) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [left, const SizedBox(height: 20), right]);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: left),
              const SizedBox(width: 24),
              Container(width: 1, height: 140, color: AppColors.cardBorder),
              const SizedBox(width: 24),
              Expanded(flex: 5, child: right),
            ],
          );
        },
      ),
    );
  }

  Widget _previewRow(String label, String value, {Color? valueColor}) {
    return Container(
      padding: const EdgeInsets.only(bottom: 6),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.cardBorder))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.secondaryText)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}
