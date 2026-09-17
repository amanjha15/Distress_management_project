import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/project_provider.dart';
import '../../router/app_router.dart';
import '../../theme/app_colors.dart';

/// The "choose what they want" screen from the workflow sketches: once a
/// Project is selected, the user picks one of the four modules.
/// M1 (Crack Detection) and M4 (Predictive Analysis) wire into the existing
/// survey/analytics flows; M2 (Road Safety Audit) and M3 (Asset Management)
/// are new modules built from scratch on top of the Project container.
class ModuleChooserScreen extends ConsumerWidget {
  const ModuleChooserScreen({super.key, required this.projectId});

  final int projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(selectedProjectProvider);

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
                            onPressed: () => context.go(AppRoutes.projects),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  project?.name ?? 'Project #$projectId',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                                if (project?.highwayName != null)
                                  Text(
                                    '${project!.highwayName} · ${project.startingChainage ?? '--'} → ${project.endingChainage ?? '--'}',
                                    style: const TextStyle(fontSize: 12.5, color: Color(0xFFCBD5E1)),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      const Text(
                        'Choose a module',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: GridView.count(
                          crossAxisCount: MediaQuery.of(context).size.width < 900 ? 1 : 2,
                          crossAxisSpacing: 18,
                          mainAxisSpacing: 18,
                          childAspectRatio: 2.6,
                          children: [
                            _ModuleTile(
                              icon: LucideIcons.scanSearch,
                              code: 'M1',
                              title: 'Crack Detection',
                              subtitle: 'Road Survey — video/live AI distress detection',
                              available: true,
                              onTap: () => context.go(AppRoutes.survey),
                            ),
                            _ModuleTile(
                              icon: LucideIcons.shieldAlert,
                              code: 'M2',
                              title: 'Road Safety Audit',
                              subtitle: 'Project Management — chainage-wise + audio report',
                              available: true,
                              onTap: () => context.go(AppRoutes.auditList(projectId)),
                            ),
                            _ModuleTile(
                              icon: LucideIcons.archive,
                              code: 'M3',
                              title: 'Asset Management',
                              subtitle: 'Project Management — document upload & attachments',
                              available: true,
                              onTap: () => context.go(AppRoutes.assetList(projectId)),
                            ),
                            _ModuleTile(
                              icon: LucideIcons.lineChart,
                              code: 'M4',
                              title: 'Predictive Analysis',
                              subtitle: 'Analytics — trends, severity distribution & forecasts',
                              available: true,
                              onTap: () => context.go(AppRoutes.analytics),
                            ),
                          ],
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
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({
    required this.icon,
    required this.code,
    required this.title,
    required this.subtitle,
    required this.available,
    required this.onTap,
  });

  final IconData icon;
  final String code;
  final String title;
  final String subtitle;
  final bool available;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.glassCardFill,
          border: Border.all(color: AppColors.glassCardBorder),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.accentBlueHover.withValues(alpha: 0.3),
                border: Border.all(color: AppColors.accentBlueHover.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 22, color: AppColors.warning),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        code,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.warning, letterSpacing: 1),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ),
                      if (!available)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'SOON',
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8), letterSpacing: 0.5),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1), height: 1.3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
