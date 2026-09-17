import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/audit_api.dart';
import '../../data/audit_provider.dart';
import '../../data/auth_provider.dart';
import '../../data/project_provider.dart';
import '../../router/app_router.dart';
import '../../theme/app_colors.dart';

/// M2 Road Safety Audit — list of audit drives run within a Project, each
/// producing a chainage-wise findings report + an audio commentary report.
/// Distinct from M1: no AI crack/pothole detection here, this is a manual
/// checklist-driven audit (signage, markings, guardrails, lighting, ...).
class AuditListScreen extends ConsumerWidget {
  const AuditListScreen({super.key, required this.projectId});

  final int projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(selectedProjectProvider);
    final auditsAsync = ref.watch(auditsProvider(projectId));

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/images/highway_background.png', fit: BoxFit.cover),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.dashboardOverlayStart, AppColors.dashboardOverlayEnd],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
                            onPressed: () => context.go(AppRoutes.projectModules(projectId)),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'M2 · Road Safety Audit',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.warning, letterSpacing: 1),
                                ),
                                Text(
                                  project?.name ?? 'Project #$projectId',
                                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: () => _showCreateAuditDialog(context, ref),
                            icon: const Icon(LucideIcons.plus, size: 16),
                            label: const Text('New Audit'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accentBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Expanded(
                        child: auditsAsync.when(
                          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.warning)),
                          error: (err, _) => Center(
                            child: Text('$err', style: const TextStyle(color: Color(0xFFFCA5A5))),
                          ),
                          data: (audits) {
                            if (audits.isEmpty) {
                              return const Center(
                                child: Text(
                                  'No safety audits yet for this project. Start one with "New Audit".',
                                  style: TextStyle(color: Color(0xFFCBD5E1)),
                                ),
                              );
                            }
                            return ListView.separated(
                              itemCount: audits.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (context, i) => _AuditCard(audit: audits[i]),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateAuditDialog(BuildContext context, WidgetRef ref) async {
    final titleCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('New Safety Audit', style: TextStyle(color: Colors.white)),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: titleCtrl,
            autofocus: true,
            style: const TextStyle(color: Colors.white, fontSize: 13.5),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            decoration: InputDecoration(
              labelText: 'Audit Title',
              hintText: 'e.g. NH-48 Safety Audit - Sept 2026',
              labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
              hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12.5),
              filled: true,
              fillColor: Colors.black26,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentBlue),
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) Navigator.pop(context, true);
            },
            child: const Text('Create', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (created != true) return;
    final token = ref.read(authProvider).token;
    if (token == null) return;

    try {
      final audit = await AuditApi(token).createAudit(projectId, titleCtrl.text.trim());
      ref.invalidate(auditsProvider(projectId));
      if (context.mounted) {
        context.go(AppRoutes.auditDetail(projectId, audit.id));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }
}

class _AuditCard extends StatelessWidget {
  const _AuditCard({required this.audit});

  final SafetyAudit audit;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => context.go(AppRoutes.auditDetail(audit.projectId, audit.id)),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.glassCardFill,
          border: Border.all(color: AppColors.glassCardBorder),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.accentBlueHover.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(LucideIcons.shieldAlert, size: 20, color: AppColors.warning),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(audit.title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(
                    '${audit.checklistItemCount} finding${audit.checklistItemCount == 1 ? '' : 's'} · ${audit.audioClipCount} audio clip${audit.audioClipCount == 1 ? '' : 's'}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: (audit.status == 'completed' ? AppColors.success : AppColors.warning).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                audit.status == 'completed' ? 'COMPLETED' : 'IN PROGRESS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: audit.status == 'completed' ? AppColors.success : AppColors.warning,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(LucideIcons.chevronRight, size: 18, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }
}
