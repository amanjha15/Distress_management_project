import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../router/app_router.dart';
import '../../theme/app_colors.dart';
import '../../widgets/server_config_dialog.dart';
import 'widgets/mobile_bottom_nav.dart';
import 'widgets/mobile_drawer.dart';
import 'widgets/sidebar.dart';
import 'widgets/top_navbar.dart';

void _showServerConfigDialog(BuildContext context) {
  showServerConfigDialog(
    context,
    onSaved: () => GoRouter.of(context).go(AppRoutes.videoReview),
  );
}

/// Direct port of Road-Distress-Management-System/frontend/src/layouts/
/// DashboardLayout.tsx with adaptive mobile-first navigation.
class DashboardShell extends StatelessWidget {
  const DashboardShell({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 700;

        return Scaffold(
          drawer: isMobile ? const MobileDrawer() : null,
          appBar: isMobile
              ? AppBar(
                  elevation: 0,
                  backgroundColor: const Color(0xFF191D17),
                  leading: Builder(
                    builder: (ctx) => IconButton(
                      icon: const Icon(LucideIcons.menu, color: Colors.white, size: 22),
                      onPressed: () => Scaffold.of(ctx).openDrawer(),
                    ),
                  ),
                  title: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'THAPAR - AKCM',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'ROAD INSPECTION MOBILE',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF949E8C),
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    IconButton(
                      icon: const Icon(LucideIcons.globe, color: Colors.white, size: 20),
                      tooltip: 'Server Connection Settings',
                      onPressed: () => _showServerConfigDialog(context),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.bell, color: Colors.white70, size: 20),
                      onPressed: () {},
                    ),
                  ],
                )
              : null,
          bottomNavigationBar: isMobile ? const MobileBottomNav() : null,
          body: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  'assets/images/highway_background.png',
                  fit: BoxFit.cover,
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.dashboardOverlayStart,
                        AppColors.dashboardOverlayEnd,
                      ],
                    ),
                  ),
                ),
              ),
              if (isMobile)
                SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1600),
                        child: child ?? const _DashboardContentPlaceholder(),
                      ),
                    ),
                  ),
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const DashboardSidebar(),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const DashboardTopNavbar(),
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(32),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 1600),
                                  child: child ?? const _DashboardContentPlaceholder(),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DashboardContentPlaceholder extends StatelessWidget {
  const _DashboardContentPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'Dashboard content — next phase of the Flutter port',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.secondaryText,
          ),
        ),
      ),
    );
  }
}

