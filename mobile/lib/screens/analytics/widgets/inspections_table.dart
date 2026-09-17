import 'package:flutter/material.dart';

import '../../../data/video_api.dart';
import '../../../theme/app_colors.dart';

class InspectionRow {
  const InspectionRow({required this.video, required this.distressCount, required this.healthScore});
  final UploadedVideo video;
  final int distressCount;
  final int healthScore;
}

Color statusPillColor(String status) {
  switch (status.toLowerCase()) {
    case 'processing':
      return const Color(0xFF3B82F6);
    case 'completed':
      return const Color(0xFF10B981);
    case 'failed':
      return const Color(0xFFEF4444);
    default:
      return const Color(0xFF616161);
  }
}

/// Direct port of AnalyticsDashboard.tsx's "Surveillance Run Inspections
/// Registry" table: one row per uploaded video with its computed
/// distress-count and road-health score, an optional Duration column (only
/// shown when at least one video has a real `processing_duration`), and an
/// "Analyze" button.
///
/// The source navigates to `/inspection/:videoId` (the same `Dashboard`
/// component as `/dashboard`, just deep-linked to one run). This port's
/// `/dashboard` screen (`DashboardGridScreen`) doesn't support selecting a
/// specific run by ID -- adding that would mean modifying an already-shipped
/// screen, which is out of scope here -- so "Analyze" just navigates to the
/// Dashboard inspection view without preselecting this row's run.
class InspectionsTable extends StatelessWidget {
  const InspectionsTable({super.key, required this.rows, required this.showDuration, required this.onAnalyze});

  final List<InspectionRow> rows;
  final bool showDuration;
  final VoidCallback onAnalyze;

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
          const Text('Surveillance Run Inspections Registry', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 38,
              dataRowMinHeight: 44,
              dataRowMaxHeight: 52,
              columnSpacing: 24,
              columns: [
                const DataColumn(label: Text('Video Run')),
                const DataColumn(label: Text('Status')),
                const DataColumn(label: Text('Road Health')),
                const DataColumn(label: Text('Distresses')),
                const DataColumn(label: Text('Upload Date')),
                if (showDuration) const DataColumn(label: Text('Duration')),
                const DataColumn(label: Text('Actions')),
              ],
              rows: [
                for (final row in rows)
                  DataRow(cells: [
                    DataCell(Text(row.video.filename, style: const TextStyle(fontWeight: FontWeight.w600))),
                    DataCell(Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusPillColor(row.video.processingStatus).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(9999),
                      ),
                      child: Text(
                        row.video.processingStatus,
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: statusPillColor(row.video.processingStatus)),
                      ),
                    )),
                    DataCell(Text(
                      '${row.healthScore}%',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                        color: row.healthScore >= 75 ? AppColors.success : AppColors.danger,
                      ),
                    )),
                    DataCell(Text('${row.distressCount}', style: const TextStyle(fontFamily: 'monospace'))),
                    DataCell(Text(_formatDate(row.video.uploadTimestamp))),
                    if (showDuration)
                      DataCell(Text(row.video.processingDuration != null ? '${row.video.processingDuration}s' : 'N/A')),
                    DataCell(OutlinedButton(
                      onPressed: onAnalyze,
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 28), padding: const EdgeInsets.symmetric(horizontal: 10), side: BorderSide(color: AppColors.cardBorder)),
                      child: const Text('Analyze', style: TextStyle(fontSize: 11)),
                    )),
                  ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    final local = d.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  }
}
