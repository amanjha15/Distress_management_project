import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../data/reports_api.dart';
import '../../../theme/app_colors.dart';
import '../../history/widgets/activity_timeline.dart' show formatDateTimeIN;

/// Direct port of ReportsDashboard.tsx's "Generated Reports Registry" card:
/// the sync-refresh header, the search/format/severity/status/date-range/
/// favorites filter toolbar, the data table, and the pagination footer.
class ReportsRegistryCard extends StatelessWidget {
  const ReportsRegistryCard({
    super.key,
    required this.filteredReports,
    required this.paginatedReports,
    required this.favorites,
    required this.selectedIds,
    required this.searchQuery,
    required this.typeFilter,
    required this.severityFilter,
    required this.statusFilter,
    required this.startDate,
    required this.endDate,
    required this.showFavoritesOnly,
    required this.currentPage,
    required this.totalPages,
    required this.itemsPerPage,
    required this.onRefresh,
    required this.onSearchChanged,
    required this.onTypeChanged,
    required this.onSeverityChanged,
    required this.onStatusChanged,
    required this.onStartDateChanged,
    required this.onEndDateChanged,
    required this.onFavoritesOnlyChanged,
    required this.onSelectAllFiltered,
    required this.onToggleSelect,
    required this.onToggleFavorite,
    required this.onPreview,
    required this.onDownload,
    required this.onDelete,
    required this.onPrevPage,
    required this.onNextPage,
  });

  final List<ReportItem> filteredReports;
  final List<ReportItem> paginatedReports;
  final Set<String> favorites;
  final Set<String> selectedIds;
  final String searchQuery;
  final String typeFilter;
  final String severityFilter;
  final String statusFilter;
  final String startDate;
  final String endDate;
  final bool showFavoritesOnly;
  final int currentPage;
  final int totalPages;
  final int itemsPerPage;

  final VoidCallback onRefresh;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<String> onSeverityChanged;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onStartDateChanged;
  final ValueChanged<String> onEndDateChanged;
  final ValueChanged<bool> onFavoritesOnlyChanged;
  final VoidCallback onSelectAllFiltered;
  final ValueChanged<ReportItem> onToggleSelect;
  final ValueChanged<ReportItem> onToggleFavorite;
  final ValueChanged<ReportItem> onPreview;
  final ValueChanged<ReportItem> onDownload;
  final ValueChanged<ReportItem> onDelete;
  final VoidCallback onPrevPage;
  final VoidCallback onNextPage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
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
              const Expanded(
                child: Text('Generated Reports Registry', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              OutlinedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(LucideIcons.refreshCw, size: 13),
                label: const Text('Sync Database', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.primaryText, side: BorderSide(color: AppColors.cardBorder)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _filterToolbar(),
          const SizedBox(height: 16),
          _table(),
          if (filteredReports.isNotEmpty) ...[
            const SizedBox(height: 16),
            _pagination(),
          ],
        ],
      ),
    );
  }

  Widget _filterToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primaryBg,
        border: Border.all(color: AppColors.cardBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 220,
            child: TextField(
              onChanged: onSearchChanged,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(LucideIcons.search, size: 14),
                hintText: 'Search report IDs, roads, cities...',
                hintStyle: const TextStyle(fontSize: 11),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppColors.cardBorder)),
              ),
            ),
          ),
          _dropdown('All Formats', typeFilter, ['All', 'PDF', 'EXCEL', 'JSON'], onTypeChanged),
          _dropdown('All Severities', severityFilter, ['All', 'Critical', 'High', 'Medium', 'Low'], onSeverityChanged),
          _dropdown('All Statuses', statusFilter, ['All', 'Approved', 'Exported', 'Under Review', 'Draft'], onStatusChanged),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('From:', style: TextStyle(fontSize: 11, color: AppColors.secondaryText)),
              const SizedBox(width: 4),
              _dateField(startDate, onStartDateChanged),
              const SizedBox(width: 8),
              const Text('To:', style: TextStyle(fontSize: 11, color: AppColors.secondaryText)),
              const SizedBox(width: 4),
              _dateField(endDate, onEndDateChanged),
            ],
          ),
          _favoritesToggle(),
        ],
      ),
    );
  }

  Widget _dateField(String value, ValueChanged<String> onChanged) {
    return Builder(
      builder: (context) => InkWell(
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
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.cardBorder), borderRadius: BorderRadius.circular(6)),
          alignment: Alignment.center,
          child: Text(value.isEmpty ? '--' : value, style: const TextStyle(fontSize: 11)),
        ),
      ),
    );
  }

  Widget _favoritesToggle() {
    return Builder(
      builder: (context) => InkWell(
        onTap: () => onFavoritesOnlyChanged(!showFavoritesOnly),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(value: showFavoritesOnly, onChanged: (v) => onFavoritesOnlyChanged(v ?? false), visualDensity: VisualDensity.compact),
            const Text('★ Favorites Only', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _dropdown(String allLabel, String value, List<String> options, ValueChanged<String> onChanged) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.cardBorder), borderRadius: BorderRadius.circular(6)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          items: [
            for (final o in options)
              DropdownMenuItem(
                value: o,
                child: Text(o == 'All' ? allLabel : o, style: const TextStyle(fontSize: 12, color: AppColors.primaryText)),
              ),
          ],
          onChanged: (v) => onChanged(v ?? value),
        ),
      ),
    );
  }

  Widget _table() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        showCheckboxColumn: false,
        headingRowHeight: 38,
        dataRowMinHeight: 44,
        dataRowMaxHeight: 52,
        columnSpacing: 20,
        columns: [
          DataColumn(
            label: Checkbox(value: allFilteredSelectedFor(), onChanged: (_) => onSelectAllFiltered()),
          ),
          const DataColumn(label: Text('★')),
          const DataColumn(label: Text('Report Name')),
          const DataColumn(label: Text('Road segment')),
          const DataColumn(label: Text('District')),
          const DataColumn(label: Text('Distress class')),
          const DataColumn(label: Text('Severity')),
          const DataColumn(label: Text('Generated Date')),
          const DataColumn(label: Text('Format')),
          const DataColumn(label: Text('Size')),
          const DataColumn(label: Text('Actions')),
        ],
        rows: paginatedReports.isEmpty
            ? [
                const DataRow(cells: [
                  DataCell(Text('')),
                  DataCell(Text('')),
                  DataCell(Text('No reports match your filters.', style: TextStyle(color: AppColors.secondaryText))),
                  DataCell(Text('')),
                  DataCell(Text('')),
                  DataCell(Text('')),
                  DataCell(Text('')),
                  DataCell(Text('')),
                  DataCell(Text('')),
                  DataCell(Text('')),
                  DataCell(Text('')),
                ]),
              ]
            : [for (final r in paginatedReports) _row(r)],
      ),
    );
  }

  bool allFilteredSelectedFor() =>
      filteredReports.isNotEmpty && filteredReports.every((r) => selectedIds.contains(r.id));

  DataRow _row(ReportItem r) {
    final isFav = favorites.contains(r.id);
    final isChecked = selectedIds.contains(r.id);
    final severityColor = Color(kReportSeverityColors[r.severity] ?? 0xFF999999);

    return DataRow(
      color: isChecked ? WidgetStateProperty.all(const Color(0x081565C0)) : null,
      onSelectChanged: (_) => onPreview(r),
      cells: [
        DataCell(Checkbox(value: isChecked, onChanged: (_) => onToggleSelect(r))),
        DataCell(IconButton(
          icon: Icon(LucideIcons.star, size: 14, color: isFav ? const Color(0xFFEAB308) : AppColors.secondaryText),
          onPressed: () => onToggleFavorite(r),
          tooltip: 'Favorite this report',
        )),
        DataCell(Text(r.id, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, fontFamily: 'monospace'))),
        DataCell(Text(r.roadId, style: const TextStyle(fontWeight: FontWeight.w700))),
        DataCell(Text(r.district)),
        DataCell(Text(r.distressType, style: const TextStyle(fontWeight: FontWeight.w600))),
        DataCell(Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: severityColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(9999)),
          child: Text(r.severity, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: severityColor)),
        )),
        DataCell(Text(formatDateTimeIN(r.generatedAt), style: const TextStyle(fontSize: 12, color: AppColors.secondaryText))),
        DataCell(Text(r.reportType, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.accentBlue, fontFamily: 'monospace'))),
        DataCell(Text(r.size, style: const TextStyle(fontSize: 11, color: AppColors.secondaryText, fontFamily: 'monospace'))),
        DataCell(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton(
              onPressed: () => onPreview(r),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 28), padding: const EdgeInsets.symmetric(horizontal: 8), side: BorderSide(color: AppColors.cardBorder)),
              child: const Text('Preview', style: TextStyle(fontSize: 11)),
            ),
            const SizedBox(width: 6),
            ElevatedButton(
              onPressed: () => onDownload(r),
              style: ElevatedButton.styleFrom(minimumSize: const Size(0, 28), padding: const EdgeInsets.symmetric(horizontal: 8), backgroundColor: AppColors.accentBlue, foregroundColor: Colors.white),
              child: const Text('Download', style: TextStyle(fontSize: 11)),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(LucideIcons.trash2, size: 13, color: AppColors.danger),
              onPressed: () => onDelete(r),
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
            ),
          ],
        )),
      ],
    );
  }

  Widget _pagination() {
    return Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 12, color: AppColors.secondaryText),
              children: [
                const TextSpan(text: 'Showing '),
                TextSpan(text: '${((currentPage - 1) * itemsPerPage) + 1}', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primaryText)),
                const TextSpan(text: ' to '),
                TextSpan(
                  text: '${(currentPage * itemsPerPage).clamp(0, filteredReports.length)}',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primaryText),
                ),
                const TextSpan(text: ' of '),
                TextSpan(text: '${filteredReports.length}', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primaryText)),
                const TextSpan(text: ' reports'),
              ],
            ),
          ),
        ),
        IconButton(onPressed: currentPage == 1 ? null : onPrevPage, icon: const Icon(LucideIcons.chevronLeft, size: 16)),
        Text('Page $currentPage of $totalPages', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'monospace')),
        IconButton(onPressed: currentPage == totalPages ? null : onNextPage, icon: const Icon(LucideIcons.chevronRight, size: 16)),
      ],
    );
  }
}
