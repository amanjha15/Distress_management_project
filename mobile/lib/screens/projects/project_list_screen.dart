import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/auth_provider.dart';
import '../../data/project_api.dart';
import '../../data/project_provider.dart';
import '../../router/app_router.dart';
import '../../theme/app_colors.dart';

/// The "Project-wise Survey" homepage from the workflow sketches: every
/// module (M1 Crack Detection, M2 Road Safety Audit, M3 Asset Management,
/// M4 Predictive Analysis) operates within a Project the user picks here.
/// Admins see every project (GET /projects/ scoping is server-side);
/// employees only see projects they've been added to.
class ProjectListScreen extends ConsumerWidget {
  const ProjectListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final projectsAsync = ref.watch(projectsProvider);
    final isAdmin = auth.user?.isAdmin ?? false;

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
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Header(email: auth.user?.email, role: auth.user?.role ?? '—'),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          const Text(
                            'Projects',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const Spacer(),
                          if (isAdmin)
                            ElevatedButton.icon(
                              onPressed: () => _showCreateProjectDialog(context, ref),
                              icon: const Icon(LucideIcons.plus, size: 16),
                              label: const Text('New Project'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.accentBlue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: projectsAsync.when(
                          loading: () => const Center(
                            child: CircularProgressIndicator(color: AppColors.warning),
                          ),
                          error: (err, _) => Center(
                            child: Text(
                              '$err',
                              style: const TextStyle(color: Color(0xFFFCA5A5)),
                            ),
                          ),
                          data: (projects) {
                            if (projects.isEmpty) {
                              return const Center(
                                child: Text(
                                  'No projects yet. Ask an administrator to add you to one.',
                                  style: TextStyle(color: Color(0xFFCBD5E1)),
                                ),
                              );
                            }
                            return GridView.builder(
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 380,
                                mainAxisExtent: 184,
                                crossAxisSpacing: 18,
                                mainAxisSpacing: 18,
                              ),
                              itemCount: projects.length,
                              itemBuilder: (context, i) => _ProjectCard(project: projects[i]),
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

  Future<void> _showCreateProjectDialog(BuildContext context, WidgetRef ref) async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final highwayNameCtrl = TextEditingController();
    final highwayNumberCtrl = TextEditingController();
    final startCtrl = TextEditingController();
    final endCtrl = TextEditingController();
    final stateCtrl = TextEditingController();
    final membersCtrl = TextEditingController();

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('New Project', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _DialogField(controller: nameCtrl, label: 'Project Name *', validateRequired: true),
                  _DialogField(controller: highwayNameCtrl, label: 'Highway Name'),
                  _DialogField(controller: highwayNumberCtrl, label: 'Highway Number'),
                  Row(
                    children: [
                      Expanded(child: _DialogField(controller: startCtrl, label: 'Start Chainage')),
                      const SizedBox(width: 12),
                      Expanded(child: _DialogField(controller: endCtrl, label: 'End Chainage')),
                    ],
                  ),
                  _DialogField(controller: stateCtrl, label: 'State'),
                  _DialogField(
                    controller: membersCtrl,
                    label: 'Employee emails (comma separated)',
                  ),
                ],
              ),
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
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(context, true);
              }
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
      await ProjectApi(token).createProject(
        name: nameCtrl.text.trim(),
        highwayName: highwayNameCtrl.text.trim().isEmpty ? null : highwayNameCtrl.text.trim(),
        highwayNumber: highwayNumberCtrl.text.trim().isEmpty ? null : highwayNumberCtrl.text.trim(),
        startingChainage: startCtrl.text.trim().isEmpty ? null : startCtrl.text.trim(),
        endingChainage: endCtrl.text.trim().isEmpty ? null : endCtrl.text.trim(),
        state: stateCtrl.text.trim().isEmpty ? null : stateCtrl.text.trim(),
        memberEmails: membersCtrl.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
      );
      ref.invalidate(projectsProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }
}

class _DialogField extends StatelessWidget {
  const _DialogField({required this.controller, required this.label, this.validateRequired = false});

  final TextEditingController controller;
  final String label;
  final bool validateRequired;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        style: const TextStyle(color: Colors.white, fontSize: 13.5),
        validator: validateRequired
            ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
            : null,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
          filled: true,
          fillColor: Colors.black26,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.email, required this.role});

  final String? email;
  final String role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Text(
            'NHAI · ROAD INSPECTION CONTROL CENTER',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ),
        const Spacer(),
        if (email != null) ...[
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(email!, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
              Text(role.toUpperCase(), style: const TextStyle(color: AppColors.warning, fontSize: 10.5, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(width: 12),
        ],
        IconButton(
          icon: const Icon(LucideIcons.logOut, color: Colors.white70, size: 20),
          tooltip: 'Sign out',
          onPressed: () async {
            await ref.read(authProvider.notifier).logout();
            if (context.mounted) context.go(AppRoutes.login);
          },
        ),
      ],
    );
  }
}

class _ProjectCard extends ConsumerWidget {
  const _ProjectCard({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        ref.read(selectedProjectProvider.notifier).state = project;
        context.go(AppRoutes.projectModules(project.id));
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.glassCardFill,
          border: Border.all(color: AppColors.glassCardBorder),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.accentBlueHover.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(LucideIcons.folderOpen, size: 18, color: AppColors.warning),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    project.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (project.highwayName != null)
              _InfoLine(icon: LucideIcons.navigation, text: project.highwayName!),
            if (project.startingChainage != null && project.endingChainage != null)
              _InfoLine(
                icon: LucideIcons.ruler,
                text: '${project.startingChainage} → ${project.endingChainage}',
              ),
            if (project.state != null) _InfoLine(icon: LucideIcons.mapPin, text: project.state!),
            const Spacer(),
            Text(
              '${project.memberEmails.length} member${project.memberEmails.length == 1 ? '' : 's'}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 12, color: const Color(0xFF94A3B8)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
            ),
          ),
        ],
      ),
    );
  }
}
