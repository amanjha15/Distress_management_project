import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../theme/app_colors.dart';
import '../timeline_event.dart';

Color categoryColor(String category) {
  switch (category) {
    case 'Inference':
      return const Color(0xFF3B82F6);
    case 'Reports':
      return const Color(0xFF8B5CF6);
    case 'Uploads':
      return const Color(0xFF10B981);
    default:
      return AppColors.secondaryText;
  }
}

/// `type` only ever equals 'Report Exported', 'Video Uploaded', 'AI
/// Inference Completed', or 'AI Inference Failed' in this port (see
/// timeline_event.dart) -- the source's icon switch also has cases for
/// 'AI Inference Running' and 6 fake-system-event types, but `type` (as
/// opposed to `title`) never actually takes those values even in the
/// source, so those branches were dead code there too and aren't ported.
IconData timelineIcon(String type) {
  switch (type) {
    case 'Report Exported':
      return LucideIcons.fileSpreadsheet;
    case 'Video Uploaded':
      return LucideIcons.fileUp;
    case 'AI Inference Completed':
      return LucideIcons.brain;
    case 'AI Inference Failed':
      return LucideIcons.alertCircle;
    default:
      return LucideIcons.clock;
  }
}

Color statusColor(String status) {
  switch (status) {
    case 'Success':
      return AppColors.success;
    case 'Warning':
      return AppColors.warning;
    case 'Info':
      return AppColors.accentBlue;
    case 'Failed':
      return AppColors.danger;
    default:
      return AppColors.secondaryText;
  }
}

IconData statusIcon(String status) {
  switch (status) {
    case 'Success':
      return LucideIcons.checkCircle2;
    case 'Warning':
      return LucideIcons.alertTriangle;
    case 'Info':
      return LucideIcons.clock;
    case 'Failed':
      return LucideIcons.xCircle;
    default:
      return LucideIcons.clock;
  }
}

Widget statusPill(String status) {
  final color = statusColor(status);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9999), border: Border.all(color: color.withValues(alpha: 0.3))),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(statusIcon(status), size: 11, color: color),
        const SizedBox(width: 4),
        Text(status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
      ],
    ),
  );
}

String formatDateTimeIN(DateTime d) {
  // .toLocal() is a no-op if d is already local; required when d came from
  // parsing a UTC-aware backend timestamp (e.g. "...+00:00"), otherwise this
  // prints the UTC wall-clock time as if it were the viewer's local time.
  final local = d.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final ampm = local.hour >= 12 ? 'PM' : 'AM';
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}, '
      '${hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} $ampm';
}

/// Direct port of History.tsx's "Activity Timeline" (left, 70% column):
/// a connected-dot timeline of report-exported and video-upload/inference
/// events, each with inline download/view/delete or retry/delete actions.
class ActivityTimeline extends StatelessWidget {
  const ActivityTimeline({
    super.key,
    required this.events,
    required this.isLoading,
    required this.onDownloadReport,
    required this.onViewReport,
    required this.onDeleteReport,
    required this.onRetryVideo,
    required this.onDeleteVideo,
  });

  final List<TimelineEvent> events;
  final bool isLoading;
  final ValueChanged<TimelineEvent> onDownloadReport;
  final ValueChanged<TimelineEvent> onViewReport;
  final ValueChanged<TimelineEvent> onDeleteReport;
  final ValueChanged<TimelineEvent> onRetryVideo;
  final ValueChanged<TimelineEvent> onDeleteVideo;

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
              const Icon(LucideIcons.activity, size: 18, color: AppColors.accentBlue),
              const SizedBox(width: 8),
              const Expanded(child: Text('Activity Timeline', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
              Text('${events.length} events matching filters', style: const TextStyle(fontSize: 11, color: AppColors.secondaryText)),
            ],
          ),
          const SizedBox(height: 16),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: Text('Fetching activity history database...', style: TextStyle(color: AppColors.secondaryText))),
            )
          else if (events.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text('No audit records found matching the active search and filter presets.',
                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.secondaryText)),
              ),
            )
          else
            for (final act in events) _eventNode(act),
        ],
      ),
    );
  }

  Widget _eventNode(TimelineEvent act) {
    final color = categoryColor(act.category);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
              ),
              child: Icon(timelineIcon(act.type), size: 16, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.primaryBg, border: Border.all(color: AppColors.cardBorder), borderRadius: BorderRadius.circular(10)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(act.category, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
                              Text(act.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                        Wrap(
                          spacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            statusPill(act.status),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: AppColors.cardBg, border: Border.all(color: AppColors.cardBorder), borderRadius: BorderRadius.circular(9999)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(LucideIcons.user, size: 10, color: AppColors.secondaryText),
                                  const SizedBox(width: 4),
                                  Text(act.user, style: const TextStyle(fontSize: 10, color: AppColors.secondaryText)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(act.description, style: const TextStyle(fontSize: 12, color: AppColors.primaryText)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(LucideIcons.clock, size: 11, color: AppColors.secondaryText),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(formatDateTimeIN(act.timestamp), style: const TextStyle(fontSize: 10, color: AppColors.secondaryText)),
                        ),
                        if (act.category == 'Reports' && act.reportId != null) ...[
                          _actionBtn(LucideIcons.download, 'Download', () => onDownloadReport(act)),
                          _actionBtn(LucideIcons.arrowUpRight, 'View', () => onViewReport(act)),
                          _actionIconBtn(LucideIcons.trash2, AppColors.danger, () => onDeleteReport(act)),
                        ],
                        if (act.category == 'Inference' && act.videoId != null) ...[
                          _actionBtn(LucideIcons.refreshCw, 'Retry', () => onRetryVideo(act)),
                          _actionIconBtn(LucideIcons.trash2, AppColors.danger, () => onDeleteVideo(act)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(border: Border.all(color: AppColors.cardBorder), borderRadius: BorderRadius.circular(6), color: AppColors.cardBg),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: AppColors.primaryText),
              const SizedBox(width: 3),
              Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionIconBtn(IconData icon, Color color, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(border: Border.all(color: AppColors.cardBorder), borderRadius: BorderRadius.circular(6), color: AppColors.cardBg),
          child: Icon(icon, size: 11, color: color),
        ),
      ),
    );
  }
}
