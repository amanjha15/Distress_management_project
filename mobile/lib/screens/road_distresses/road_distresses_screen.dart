import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/road_distress_api.dart';
import '../../router/app_router.dart';
import '../../theme/app_colors.dart';
import '../../theme/distress_icons.dart';
import 'distress_colors.dart';
import 'widgets/image_lightbox.dart';
import 'widgets/inspection_drawer.dart';

const _kColumnLabels = {
  'tracking_id': 'Tracking ID',
  'detection_id': 'Detection ID',
  'distress_type': 'Type',
  'severity': 'Severity',
  'priority': 'Priority',
  'confidence': 'Confidence',
  'road_health_impact': 'Impact',
  'frame_number': 'Frame',
  'timestamp': 'Timestamp',
  'latitude': 'Lat',
  'longitude': 'Lon',
  'estimated_cost': 'Est. Cost',
  'status': 'Status',
  'video_name': 'Video Name',
  'created_time': 'Created',
};

const _kDefaultColumns = {
  'tracking_id': true,
  'detection_id': true,
  'distress_type': true,
  'severity': true,
  'priority': true,
  'confidence': true,
  'road_health_impact': true,
  'frame_number': false,
  'timestamp': true,
  'latitude': false,
  'longitude': false,
  'estimated_cost': true,
  'status': true,
  'video_name': true,
  'created_time': false,
};

/// Direct port of Road-Distress-Management-System/frontend/src/pages/
/// RoadDistresses/RoadDistresses.tsx: real backend data (GET
/// /api/v1/distress/), search/filter/sort/paginate, configurable column
/// visibility (persisted, like the React source's localStorage, via
/// SharedPreferences here), row selection with bulk actions, an inspection
/// drawer, and an image lightbox (via Flutter's InteractiveViewer -- see
/// widgets/image_lightbox.dart).
///
/// Trimmed vs. the React source: the CSV/Excel/JSON export buttons (pure
/// frontend blob-download conveniences, not backend-driven) and "Export
/// Selected" bulk action are left out to keep scope bounded, documented in
/// mobile/README.md. The "Mark Reviewed"/"Mark Resolved" bulk actions are
/// still included -- they're local-state-only edits in the React source
/// too (no real API call), so nothing is lost by keeping them as-is.
class RoadDistressesScreen extends StatefulWidget {
  const RoadDistressesScreen({super.key});

  @override
  State<RoadDistressesScreen> createState() => _RoadDistressesScreenState();
}

class _RoadDistressesScreenState extends State<RoadDistressesScreen> {
  final _api = RoadDistressApi();

  List<DistressRecord> _records = [];
  bool _isLoading = true;
  String? _error;

  Map<String, bool> _visibleColumns = Map.of(_kDefaultColumns);
  final Set<int> _selectedIds = {};
  DistressRecord? _drawerItem;

  bool _showAdvancedFilters = false;
  bool _showColumnDropdown = false;

  String _sortField = 'id';
  bool _sortAsc = false;

  String _searchQuery = '';
  String _filterSeverity = '';
  String _filterStatus = '';
  String _filterType = '';
  String _filterVideo = '';
  String _filterPriority = '';
  String _filterStartDate = '';
  String _filterEndDate = '';

  int _currentPage = 1;
  int _itemsPerPage = 10;

  @override
  void initState() {
    super.initState();
    _loadColumnPrefs();
    _fetchData();
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  Future<void> _loadColumnPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('distress_columns_visibility');
    if (saved == null) return;
    try {
      final decoded = (jsonDecode(saved) as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, v as bool),
      );
      if (!mounted) return;
      setState(() => _visibleColumns = {..._kDefaultColumns, ...decoded});
    } catch (_) {
      // Corrupt/old preference shape; keep defaults.
    }
  }

  Future<void> _saveColumnPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('distress_columns_visibility', jsonEncode(_visibleColumns));
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final data = await _api.fetchDistresses(limit: 500);
      if (!mounted) return;
      setState(() {
        _records = data;
        _error = null;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to sync distress logs database. Make sure backend service is active.';
        _isLoading = false;
      });
    }
  }

  Future<void> _handleGeneratePdf(int id) async {
    // Matches the React source: the catch branch shows the same success
    // message as the happy path, so the user always sees success here too.
    try {
      await _api.generatePdfReport(id);
    } catch (_) {
      // Intentionally ignored -- see doc comment above.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('PDF report generated successfully for Distress #$id! Check Reports section.')),
    );
  }

  String _dateOnly(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  List<DistressRecord> get _filtered {
    final query = _searchQuery.toLowerCase().trim();
    return _records.where((item) {
      if (query.isNotEmpty) {
        final matchesTracking = item.trackingId?.toString().contains(query) ?? false;
        final matchesDetection = item.id.toString().contains(query);
        final matchesType = item.distressType.toLowerCase().contains(query);
        final matchesStatus = item.status.toLowerCase().contains(query);
        final matchesVideo = item.videoId != null && 'video ${item.videoId}'.contains(query);
        final matchesLat = item.latitude.toString().contains(query);
        final matchesLon = item.longitude.toString().contains(query);
        if (!matchesTracking &&
            !matchesDetection &&
            !matchesType &&
            !matchesStatus &&
            !matchesVideo &&
            !matchesLat &&
            !matchesLon) {
          return false;
        }
      }
      if (_filterSeverity.isNotEmpty && item.severity != _filterSeverity) return false;
      if (_filterStatus.isNotEmpty && item.status.toLowerCase() != _filterStatus) return false;
      if (_filterType.isNotEmpty && item.distressType.toLowerCase() != _filterType) return false;
      if (_filterVideo.isNotEmpty && item.videoId?.toString() != _filterVideo) return false;
      if (_filterStartDate.isNotEmpty && _dateOnly(item.detectedAt).compareTo(_filterStartDate) < 0) return false;
      if (_filterEndDate.isNotEmpty && _dateOnly(item.detectedAt).compareTo(_filterEndDate) > 0) return false;
      if (_filterPriority.isNotEmpty) {
        final p = priorityScore(item.severity);
        if (_filterPriority == 'high' && p < 80) return false;
        if (_filterPriority == 'medium' && (p < 50 || p >= 80)) return false;
        if (_filterPriority == 'low' && p >= 50) return false;
      }
      return true;
    }).toList();
  }

  num _sortValue(DistressRecord item, String field) {
    switch (field) {
      case 'tracking_id':
        return item.trackingId ?? 0;
      case 'id':
      case 'detection_id':
        return item.id;
      case 'priority':
      case 'road_health_impact':
        return priorityScore(item.severity);
      case 'confidence_score':
        return item.confidenceScore;
      case 'frame_number':
        return item.frameNumber ?? 0;
      case 'video_timestamp':
        return item.videoTimestamp ?? 0;
      case 'latitude':
        return item.latitude;
      case 'longitude':
        return item.longitude;
      case 'estimated_cost':
        return switch (item.severity) {
          'critical' => 95000,
          'high' => 65000,
          'medium' => 45000,
          _ => 25000,
        };
      case 'video_name':
        return item.videoId ?? 0;
      default:
        return 0;
    }
  }

  List<DistressRecord> get _sorted {
    final list = _filtered;
    const stringFields = {'distress_type', 'severity', 'status'};
    list.sort((a, b) {
      if (stringFields.contains(_sortField)) {
        final valA = switch (_sortField) {
          'distress_type' => a.distressType,
          'severity' => a.severity,
          _ => a.status,
        };
        final valB = switch (_sortField) {
          'distress_type' => b.distressType,
          'severity' => b.severity,
          _ => b.status,
        };
        return _sortAsc ? valA.compareTo(valB) : valB.compareTo(valA);
      }
      final valA = _sortValue(a, _sortField);
      final valB = _sortValue(b, _sortField);
      final cmp = valA.compareTo(valB);
      return _sortAsc ? cmp : -cmp;
    });
    return list;
  }

  void _handleSort(String field) {
    setState(() {
      if (_sortField == field) {
        _sortAsc = !_sortAsc;
      } else {
        _sortField = field;
        _sortAsc = true;
      }
      _currentPage = 1;
    });
  }

  void _handleResetFilters() {
    setState(() {
      _searchQuery = '';
      _filterSeverity = '';
      _filterStatus = '';
      _filterType = '';
      _filterVideo = '';
      _filterPriority = '';
      _filterStartDate = '';
      _filterEndDate = '';
      _currentPage = 1;
    });
  }

  void _toggleSelectRow(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _toggleSelectAll(List<DistressRecord> visibleRows) {
    final allSelected = visibleRows.every((r) => _selectedIds.contains(r.id));
    setState(() {
      if (allSelected) {
        for (final r in visibleRows) {
          _selectedIds.remove(r.id);
        }
      } else {
        for (final r in visibleRows) {
          _selectedIds.add(r.id);
        }
      }
    });
  }

  void _handleBulkStatusChange(String status) {
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please select at least one row.')));
      return;
    }
    final count = _selectedIds.length;
    // Matches the React source: this only updates local state, no API call.
    setState(() {
      _records = [
        for (final r in _records)
          if (_selectedIds.contains(r.id))
            DistressRecord(
              id: r.id,
              distressType: r.distressType,
              severity: r.severity,
              confidenceScore: r.confidenceScore,
              latitude: r.latitude,
              longitude: r.longitude,
              detectedAt: r.detectedAt,
              status: status,
              imageUrl: r.imageUrl,
              videoId: r.videoId,
              frameNumber: r.frameNumber,
              videoTimestamp: r.videoTimestamp,
              trackingId: r.trackingId,
              boxWidth: r.boxWidth,
              boxHeight: r.boxHeight,
              affectedArea: r.affectedArea,
            )
          else
            r,
      ];
      _selectedIds.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Successfully updated status of $count detections to '${status.replaceAll('_', ' ')}'!")),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _sorted;
    final totalPages = (sorted.length / _itemsPerPage).ceil().clamp(1, 1 << 30);
    final startIndex = (_currentPage - 1) * _itemsPerPage;
    final paginated = sorted.skip(startIndex).take(_itemsPerPage).toList();

    final totalCount = _records.length;
    final criticalCount = _records.where((d) => d.severity == 'critical').length;
    final highCount = _records.where((d) => d.severity == 'high').length;
    final mediumCount = _records.where((d) => d.severity == 'medium').length;
    final lowCount = _records.where((d) => d.severity == 'low').length;
    final resolvedCount = _records.where((d) => d.status.toLowerCase() == 'completed').length;
    final pendingCount =
        _records.where((d) => ['detected', 'pending'].contains(d.status.toLowerCase())).length;
    final healthPenalty = _records.fold<double>(0, (sum, d) {
      final w = switch (d.severity) {
        'critical' => 5.0,
        'high' => 3.0,
        'medium' => 1.5,
        _ => 0.5,
      };
      return sum + w;
    });
    final healthScore = (100 - healthPenalty).clamp(0, 100).round();

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'AI Detection Management',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryTextLight,
                shadows: [Shadow(color: Color(0x66000000), offset: Offset(0, 2), blurRadius: 4)],
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Review, filter, inspect, and export detected distresses.',
              style: TextStyle(fontSize: 13, color: AppColors.secondaryTextLight),
            ),
            const SizedBox(height: 20),
            _KpiStrip(
              totalCount: totalCount,
              criticalCount: criticalCount,
              highCount: highCount,
              mediumCount: mediumCount,
              lowCount: lowCount,
              resolvedCount: resolvedCount,
              pendingCount: pendingCount,
              healthScore: healthScore,
            ),
            const SizedBox(height: 20),
            _Toolbar(
              searchQuery: _searchQuery,
              onSearchChanged: (v) => setState(() {
                _searchQuery = v;
                _currentPage = 1;
              }),
              showAdvancedFilters: _showAdvancedFilters,
              onToggleFilters: () => setState(() => _showAdvancedFilters = !_showAdvancedFilters),
              showColumnDropdown: _showColumnDropdown,
              onToggleColumns: () => setState(() => _showColumnDropdown = !_showColumnDropdown),
              visibleColumns: _visibleColumns,
              onColumnToggle: (key) {
                setState(() => _visibleColumns[key] = !(_visibleColumns[key] ?? true));
                _saveColumnPrefs();
              },
              filterSeverity: _filterSeverity,
              filterStatus: _filterStatus,
              filterType: _filterType,
              filterVideo: _filterVideo,
              filterPriority: _filterPriority,
              filterStartDate: _filterStartDate,
              filterEndDate: _filterEndDate,
              onFilterSeverity: (v) => setState(() { _filterSeverity = v; _currentPage = 1; }),
              onFilterStatus: (v) => setState(() { _filterStatus = v; _currentPage = 1; }),
              onFilterType: (v) => setState(() { _filterType = v; _currentPage = 1; }),
              onFilterVideo: (v) => setState(() { _filterVideo = v; _currentPage = 1; }),
              onFilterPriority: (v) => setState(() { _filterPriority = v; _currentPage = 1; }),
              onFilterStartDate: (v) => setState(() { _filterStartDate = v; _currentPage = 1; }),
              onFilterEndDate: (v) => setState(() { _filterEndDate = v; _currentPage = 1; }),
              onResetFilters: _handleResetFilters,
            ),
            if (_selectedIds.isNotEmpty) ...[
              const SizedBox(height: 12),
              _BulkActionsBar(
                count: _selectedIds.length,
                onMarkReviewed: () => _handleBulkStatusChange('in_progress'),
                onMarkResolved: () => _handleBulkStatusChange('completed'),
                onClear: () => setState(_selectedIds.clear),
              ),
            ],
            const SizedBox(height: 20),
            _TableCard(
              isLoading: _isLoading,
              error: _error,
              items: paginated,
              visibleColumns: _visibleColumns,
              selectedIds: _selectedIds,
              sortField: _sortField,
              sortAsc: _sortAsc,
              onSort: _handleSort,
              onToggleSelectRow: _toggleSelectRow,
              onToggleSelectAll: () => _toggleSelectAll(paginated),
              onRowTap: (item) => setState(() => _drawerItem = item),
              onThumbnailTap: (item) => showDialog<void>(
                context: context,
                builder: (context) => ImageLightbox(record: item),
              ),
              onGenerateReport: _handleGeneratePdf,
              onLocateGis: () => context.go(AppRoutes.gisMap),
            ),
            if (!_isLoading && sorted.isNotEmpty) ...[
              const SizedBox(height: 16),
              _PaginationFooter(
                currentPage: _currentPage,
                totalPages: totalPages,
                itemsPerPage: _itemsPerPage,
                totalItems: sorted.length,
                onPrev: () => setState(() => _currentPage = (_currentPage - 1).clamp(1, totalPages)),
                onNext: () => setState(() => _currentPage = (_currentPage + 1).clamp(1, totalPages)),
                onItemsPerPageChanged: (v) => setState(() {
                  _itemsPerPage = v;
                  _currentPage = 1;
                }),
              ),
            ],
          ],
        ),
        if (_drawerItem != null)
          // Pins the drawer to the Stack's own top/bottom edge so it gets a
          // *finite* height constraint. Left unconstrained deliberately: the
          // drawer sizes its own width (see InspectionDrawer's Container).
          // Without this, the Stack sits inside DashboardShell's
          // SingleChildScrollView, which hands its child an unbounded
          // height -- that unbounded height used to reach the drawer's
          // Container(height: double.infinity) and break the Expanded
          // scroll region inside it (shrunken image, overflowing text).
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            child: InspectionDrawer(
              record: _drawerItem!,
              onClose: () => setState(() => _drawerItem = null),
              onDownloadPdf: () => _handleGeneratePdf(_drawerItem!.id),
              onLocateGis: () => context.go(AppRoutes.gisMap),
            ),
          ),
      ],
    );
  }
}

class _KpiStrip extends StatelessWidget {
  const _KpiStrip({
    required this.totalCount,
    required this.criticalCount,
    required this.highCount,
    required this.mediumCount,
    required this.lowCount,
    required this.resolvedCount,
    required this.pendingCount,
    required this.healthScore,
  });

  final int totalCount;
  final int criticalCount;
  final int highCount;
  final int mediumCount;
  final int lowCount;
  final int resolvedCount;
  final int pendingCount;
  final int healthScore;

  @override
  Widget build(BuildContext context) {
    final cards = [
      ('Total Detections', '$totalCount', AppColors.primaryText),
      ('Critical Cases', '$criticalCount', AppColors.danger),
      ('High Severity', '$highCount', const Color(0xFFF97316)),
      ('Medium Severity', '$mediumCount', AppColors.warning),
      ('Low Severity', '$lowCount', AppColors.success),
      ('Resolved', '$resolvedCount', AppColors.success),
      ('Pending', '$pendingCount', AppColors.warning),
      ('Road Health Score', '$healthScore%', AppColors.accentBlue),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 600 ? 2 : (constraints.maxWidth < 1000 ? 4 : 8);
        const gap = 12.0;
        final tileWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final c in cards)
              SizedBox(
                width: tileWidth,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.cardBg,
                    border: Border.all(color: AppColors.cardBorder),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        c.$1.toUpperCase(),
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppColors.secondaryText),
                      ),
                      const SizedBox(height: 4),
                      Text(c.$2, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.$3)),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.searchQuery,
    required this.onSearchChanged,
    required this.showAdvancedFilters,
    required this.onToggleFilters,
    required this.showColumnDropdown,
    required this.onToggleColumns,
    required this.visibleColumns,
    required this.onColumnToggle,
    required this.filterSeverity,
    required this.filterStatus,
    required this.filterType,
    required this.filterVideo,
    required this.filterPriority,
    required this.filterStartDate,
    required this.filterEndDate,
    required this.onFilterSeverity,
    required this.onFilterStatus,
    required this.onFilterType,
    required this.onFilterVideo,
    required this.onFilterPriority,
    required this.onFilterStartDate,
    required this.onFilterEndDate,
    required this.onResetFilters,
  });

  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final bool showAdvancedFilters;
  final VoidCallback onToggleFilters;
  final bool showColumnDropdown;
  final VoidCallback onToggleColumns;
  final Map<String, bool> visibleColumns;
  final ValueChanged<String> onColumnToggle;
  final String filterSeverity;
  final String filterStatus;
  final String filterType;
  final String filterVideo;
  final String filterPriority;
  final String filterStartDate;
  final String filterEndDate;
  final ValueChanged<String> onFilterSeverity;
  final ValueChanged<String> onFilterStatus;
  final ValueChanged<String> onFilterType;
  final ValueChanged<String> onFilterVideo;
  final ValueChanged<String> onFilterPriority;
  final ValueChanged<String> onFilterStartDate;
  final ValueChanged<String> onFilterEndDate;
  final VoidCallback onResetFilters;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        border: Border.all(color: AppColors.cardBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: onSearchChanged,
                  controller: TextEditingController(text: searchQuery)
                    ..selection = TextSelection.collapsed(offset: searchQuery.length),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(LucideIcons.search, size: 16),
                    hintText: 'Search by ID, distress type, status, video or coordinates...',
                    hintStyle: const TextStyle(fontSize: 12),
                    filled: true,
                    fillColor: AppColors.primaryBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppColors.cardBorder),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: onToggleFilters,
                icon: const Icon(LucideIcons.slidersHorizontal, size: 14),
                label: const Text('Filters', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryText,
                  side: BorderSide(color: AppColors.cardBorder),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: 'Columns',
                itemBuilder: (context) => [
                  for (final entry in _kColumnLabels.entries)
                    PopupMenuItem<String>(
                      value: entry.key,
                      onTap: () => onColumnToggle(entry.key),
                      child: Row(
                        children: [
                          Icon(
                            (visibleColumns[entry.key] ?? true) ? LucideIcons.checkSquare : LucideIcons.square,
                            size: 15,
                          ),
                          const SizedBox(width: 8),
                          Text(entry.value, style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                ],
                child: OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(LucideIcons.columns, size: 14),
                  label: const Text('Columns', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryText,
                    side: BorderSide(color: AppColors.cardBorder),
                    disabledForegroundColor: AppColors.primaryText,
                  ),
                ),
              ),
            ],
          ),
          if (showAdvancedFilters) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MiniSelect(
                  label: 'Severity',
                  value: filterSeverity,
                  options: const {'': 'All', 'critical': 'Critical', 'high': 'High', 'medium': 'Medium', 'low': 'Low'},
                  onChanged: onFilterSeverity,
                ),
                _MiniSelect(
                  label: 'Status',
                  value: filterStatus,
                  options: const {
                    '': 'All',
                    'detected': 'Detected',
                    'scheduled': 'Scheduled',
                    'in_progress': 'In Progress',
                    'completed': 'Completed',
                  },
                  onChanged: onFilterStatus,
                ),
                _MiniSelect(
                  label: 'Type',
                  value: filterType,
                  options: const {
                    '': 'All',
                    'pothole': 'Pothole',
                    'crack': 'Crack',
                    'rutting': 'Rutting',
                    'edge_break': 'Edge Break',
                  },
                  onChanged: onFilterType,
                ),
                _MiniTextField(label: 'Video ID', value: filterVideo, onChanged: onFilterVideo),
                _MiniSelect(
                  label: 'Priority Group',
                  value: filterPriority,
                  options: const {'': 'All', 'high': 'High (>=80)', 'medium': 'Medium (50-80)', 'low': 'Low (<50)'},
                  onChanged: onFilterPriority,
                ),
                _MiniDateField(label: 'Start Date', value: filterStartDate, onChanged: onFilterStartDate),
                _MiniDateField(label: 'End Date', value: filterEndDate, onChanged: onFilterEndDate),
                SizedBox(
                  height: 52,
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: OutlinedButton(
                      onPressed: onResetFilters,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryText,
                        side: BorderSide(color: AppColors.cardBorder),
                      ),
                      child: const Text('Reset Filters', style: TextStyle(fontSize: 11)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniSelect extends StatelessWidget {
  const _MiniSelect({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.secondaryText)),
          const SizedBox(height: 4),
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.cardBorder),
              borderRadius: BorderRadius.circular(4),
              color: AppColors.primaryBg,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isDense: true,
                isExpanded: true,
                items: [
                  for (final e in options.entries)
                    DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value, style: const TextStyle(fontSize: 11, color: AppColors.primaryText)),
                    ),
                ],
                onChanged: (v) => onChanged(v ?? ''),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniTextField extends StatelessWidget {
  const _MiniTextField({required this.label, required this.value, required this.onChanged});

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 130,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.secondaryText)),
          const SizedBox(height: 4),
          SizedBox(
            height: 32,
            child: TextField(
              controller: TextEditingController(text: value)
                ..selection = TextSelection.collapsed(offset: value.length),
              onChanged: onChanged,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 11),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                filled: true,
                fillColor: AppColors.primaryBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: AppColors.cardBorder),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniDateField extends StatelessWidget {
  const _MiniDateField({required this.label, required this.value, required this.onChanged});

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.secondaryText)),
          const SizedBox(height: 4),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime.tryParse(value) ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                onChanged(
                  '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}',
                );
              }
            },
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.cardBorder),
                borderRadius: BorderRadius.circular(4),
                color: AppColors.primaryBg,
              ),
              child: Text(value.isEmpty ? '—' : value, style: const TextStyle(fontSize: 11)),
            ),
          ),
        ],
      ),
    );
  }
}

class _BulkActionsBar extends StatelessWidget {
  const _BulkActionsBar({
    required this.count,
    required this.onMarkReviewed,
    required this.onMarkResolved,
    required this.onClear,
  });

  final int count;
  final VoidCallback onMarkReviewed;
  final VoidCallback onMarkResolved;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.accentBlueLight,
        border: Border.all(color: AppColors.accentBlue.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Selected: $count rows',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.accentBlue),
            ),
          ),
          OutlinedButton(
            onPressed: onMarkReviewed,
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.primaryText, side: BorderSide(color: AppColors.cardBorder)),
            child: const Text('Mark Reviewed', style: TextStyle(fontSize: 11)),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: onMarkResolved,
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6C7354), foregroundColor: Colors.white),
            child: const Text('Mark Resolved', style: TextStyle(fontSize: 11)),
          ),
          IconButton(onPressed: onClear, icon: const Icon(LucideIcons.x, size: 16)),
        ],
      ),
    );
  }
}

class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.isLoading,
    required this.error,
    required this.items,
    required this.visibleColumns,
    required this.selectedIds,
    required this.sortField,
    required this.sortAsc,
    required this.onSort,
    required this.onToggleSelectRow,
    required this.onToggleSelectAll,
    required this.onRowTap,
    required this.onThumbnailTap,
    required this.onGenerateReport,
    required this.onLocateGis,
  });

  final bool isLoading;
  final String? error;
  final List<DistressRecord> items;
  final Map<String, bool> visibleColumns;
  final Set<int> selectedIds;
  final String sortField;
  final bool sortAsc;
  final ValueChanged<String> onSort;
  final ValueChanged<int> onToggleSelectRow;
  final VoidCallback onToggleSelectAll;
  final ValueChanged<DistressRecord> onRowTap;
  final ValueChanged<DistressRecord> onThumbnailTap;
  final ValueChanged<int> onGenerateReport;
  final VoidCallback onLocateGis;

  static const _sortKeys = {
    'tracking_id': 'tracking_id',
    'detection_id': 'id',
    'distress_type': 'distress_type',
    'severity': 'severity',
    'priority': 'priority',
    'confidence': 'confidence_score',
    'road_health_impact': 'road_health_impact',
    'frame_number': 'frame_number',
    'timestamp': 'video_timestamp',
    'latitude': 'latitude',
    'longitude': 'longitude',
    'estimated_cost': 'estimated_cost',
    'status': 'status',
    'video_name': 'video_name',
    'created_time': 'detected_at',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        border: Border.all(color: AppColors.cardBorder),
        borderRadius: BorderRadius.circular(20),
      ),
      child: _content(context),
    );
  }

  Widget _content(BuildContext context) {
    if (isLoading) {
      return const SizedBox(
        height: 220,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(strokeWidth: 2),
              SizedBox(height: 10),
              Text('Loading surveillance detections registry...', style: TextStyle(fontSize: 13, color: AppColors.secondaryText)),
            ],
          ),
        ),
      );
    }
    if (error != null) {
      return SizedBox(
        height: 220,
        child: Center(child: Text(error!, style: const TextStyle(color: AppColors.danger))),
      );
    }
    if (items.isEmpty) {
      return const SizedBox(
        height: 220,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.shieldAlert, size: 36, color: AppColors.secondaryText),
              SizedBox(height: 12),
              Text('No distress records match active parameters.', style: TextStyle(fontSize: 13, color: AppColors.secondaryText)),
            ],
          ),
        ),
      );
    }

    final allSelected = items.every((r) => selectedIds.contains(r.id));

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(AppColors.primaryBg),
        columns: [
          DataColumn(
            label: InkWell(
              onTap: onToggleSelectAll,
              child: Icon(allSelected ? LucideIcons.checkSquare : LucideIcons.square, size: 16),
            ),
          ),
          const DataColumn(label: Text('THUMB', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.secondaryText))),
          for (final key in _kColumnLabels.keys)
            if (visibleColumns[key] ?? true) DataColumn(label: _sortableHeader(key)),
          const DataColumn(label: Text('ACTIONS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.secondaryText))),
        ],
        rows: [for (final item in items) _row(context, item)],
      ),
    );
  }

  Widget _sortableHeader(String key) {
    final field = _sortKeys[key] ?? key;
    final isActive = field == sortField;
    return InkWell(
      onTap: () => onSort(field),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _kColumnLabels[key]!.toUpperCase(),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.secondaryText),
          ),
          const SizedBox(width: 4),
          Icon(
            isActive
                ? (sortAsc ? LucideIcons.arrowUp : LucideIcons.arrowDown)
                : LucideIcons.arrowUpDown,
            size: 12,
            color: isActive ? AppColors.accentBlue : AppColors.secondaryText,
          ),
        ],
      ),
    );
  }

  DataRow _row(BuildContext context, DistressRecord item) {
    final checked = selectedIds.contains(item.id);
    return DataRow(
      onSelectChanged: (_) => onRowTap(item),
      cells: [
        DataCell(
          InkWell(
            onTap: () => onToggleSelectRow(item.id),
            child: Icon(checked ? LucideIcons.checkSquare : LucideIcons.square, size: 16),
          ),
        ),
        DataCell(
          InkWell(
            onTap: () => onThumbnailTap(item),
            child: Container(
              width: 52,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.cardBorder),
              ),
              clipBehavior: Clip.antiAlias,
              child: item.resolvedImageUrl != null
                  ? Image.network(
                      item.resolvedImageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) =>
                          const Icon(LucideIcons.image, size: 16, color: AppColors.secondaryText),
                    )
                  : const Icon(LucideIcons.image, size: 16, color: AppColors.secondaryText),
            ),
          ),
        ),
        if (visibleColumns['tracking_id'] ?? true)
          DataCell(Text(item.trackingId?.toString() ?? 'TRK-MOCK-${item.id}', style: const TextStyle(fontSize: 11))),
        if (visibleColumns['detection_id'] ?? true)
          DataCell(Text('RD-${item.id}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
        if (visibleColumns['distress_type'] ?? true)
          DataCell(Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(distressTypeIcon(item.distressType), size: 14, color: distressTypeIconColor(item.distressType)),
              const SizedBox(width: 6),
              Text(formatDistressType(item.distressType), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          )),
        if (visibleColumns['severity'] ?? true)
          DataCell(
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: severityColor(item.severity).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9999),
              ),
              child: Text(
                item.severity.toUpperCase(),
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: severityColor(item.severity)),
              ),
            ),
          ),
        if (visibleColumns['priority'] ?? true)
          DataCell(Text('${priorityScore(item.severity)}', style: const TextStyle(fontWeight: FontWeight.w700))),
        if (visibleColumns['confidence'] ?? true)
          DataCell(Text('${(item.confidenceScore * 100).round().clamp(0, 100) == 0 ? 85 : (item.confidenceScore * 100).round()}%')),
        if (visibleColumns['road_health_impact'] ?? true)
          DataCell(Text(healthImpactScore(item.severity), style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700))),
        if (visibleColumns['frame_number'] ?? true) DataCell(Text('${item.frameNumber ?? 0}')),
        if (visibleColumns['timestamp'] ?? true)
          DataCell(Text('${(item.videoTimestamp ?? 0).toStringAsFixed(2)}s')),
        if (visibleColumns['latitude'] ?? true) DataCell(Text(item.latitude.toStringAsFixed(5), style: const TextStyle(fontSize: 11))),
        if (visibleColumns['longitude'] ?? true) DataCell(Text(item.longitude.toStringAsFixed(5), style: const TextStyle(fontSize: 11))),
        if (visibleColumns['estimated_cost'] ?? true)
          DataCell(Text(estimatedCost(item.severity), style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700))),
        if (visibleColumns['status'] ?? true)
          DataCell(
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor(item.status).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9999),
              ),
              child: Text(
                item.status.replaceAll('_', ' '),
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor(item.status)),
              ),
            ),
          ),
        if (visibleColumns['video_name'] ?? true)
          DataCell(Text(item.videoId != null ? 'video_${item.videoId}.mp4' : 'manual_upload', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
        if (visibleColumns['created_time'] ?? true) DataCell(Text(item.detectedAt.toLocal().toString())),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () => onGenerateReport(item.id),
                child: const Text('Report', style: TextStyle(fontSize: 11)),
              ),
              TextButton(
                onPressed: onLocateGis,
                child: const Text('GIS', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PaginationFooter extends StatelessWidget {
  const _PaginationFooter({
    required this.currentPage,
    required this.totalPages,
    required this.itemsPerPage,
    required this.totalItems,
    required this.onPrev,
    required this.onNext,
    required this.onItemsPerPageChanged,
  });

  final int currentPage;
  final int totalPages;
  final int itemsPerPage;
  final int totalItems;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<int> onItemsPerPageChanged;

  @override
  Widget build(BuildContext context) {
    final start = totalItems == 0 ? 0 : (currentPage - 1) * itemsPerPage + 1;
    final end = (currentPage * itemsPerPage).clamp(0, totalItems);
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        Text(
          'Showing $start to $end of $totalItems items',
          style: const TextStyle(fontSize: 12, color: AppColors.secondaryText),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Rows per page:', style: TextStyle(fontSize: 12, color: AppColors.secondaryText)),
            const SizedBox(width: 6),
            DropdownButton<int>(
              value: itemsPerPage,
              isDense: true,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 10, child: Text('10')),
                DropdownMenuItem(value: 20, child: Text('20')),
                DropdownMenuItem(value: 50, child: Text('50')),
              ],
              onChanged: (v) => onItemsPerPageChanged(v ?? 10),
            ),
            const SizedBox(width: 16),
            IconButton(
              onPressed: currentPage == 1 ? null : onPrev,
              icon: const Icon(LucideIcons.chevronLeft, size: 16),
            ),
            Text('Page $currentPage of $totalPages', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            IconButton(
              onPressed: currentPage == totalPages ? null : onNext,
              icon: const Icon(LucideIcons.chevronRight, size: 16),
            ),
          ],
        ),
      ],
    );
  }
}
