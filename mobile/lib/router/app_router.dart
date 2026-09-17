import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/auth_provider.dart';
import '../screens/asset/asset_list_screen.dart';
import '../screens/audit/audit_detail_screen.dart';
import '../screens/audit/audit_list_screen.dart';
import '../screens/dashboard/dashboard_shell.dart';
import '../screens/dashboard/overview_screen.dart';
import '../screens/dashboard_grid/dashboard_grid_screen.dart';
import '../screens/gis_map/gis_map_screen.dart';
import '../screens/live_detection/live_detection_screen.dart';
import '../screens/live_processing/live_processing_screen.dart';
import '../screens/login/login_screen.dart';
import '../screens/analytics/analytics_screen.dart';
import '../screens/history/history_screen.dart';
import '../screens/maintenance/maintenance_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/projects/module_chooser_screen.dart';
import '../screens/projects/project_list_screen.dart';
import '../screens/reports/reports_screen.dart';
import '../screens/road_distresses/road_distresses_screen.dart';
import '../screens/survey/survey_screen.dart';
import '../screens/upload_video/upload_video_screen.dart';
import '../screens/video_review/video_review_screen.dart';

/// Route paths mirror Road-Distress-Management-System/frontend/src/routes/AppRoutes.tsx
/// 1:1, so links and navigation logic stay recognizable across both apps.
/// `/projects` and `/projects/:id/modules` are new: the project-picker and
/// module-chooser homepage that now sits between login and the M1 survey flow.
class AppRoutes {
  AppRoutes._();

  static const login = '/login';
  static const projects = '/projects';
  static const survey = '/survey';
  static const dashboard = '/dashboard';
  static const overview = '/overview';
  static const liveMonitoring = '/live-monitoring';
  static const gisMap = '/gis-map';
  static const uploadVideo = '/upload-video';
  static const liveProcessing = '/live-processing';
  static const roadDistresses = '/road-distresses';
  static const maintenance = '/maintenance';
  static const reports = '/reports';
  static const analytics = '/analytics';
  static const history = '/history';
  static const notifications = '/notifications';
  static const videoReview = '/video-review';

  static String projectModules(int projectId) => '/projects/$projectId/modules';
  static String auditList(int projectId) => '/projects/$projectId/audits';
  static String auditDetail(int projectId, int auditId) => '/projects/$projectId/audits/$auditId';
  static String assetList(int projectId) => '/projects/$projectId/assets';
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.login,
    refreshListenable: _AuthListenable(ref),
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      if (authState.isRestoring) return null;

      final isAuthenticated = authState.isAuthenticated;
      final onLoginPage = state.matchedLocation == AppRoutes.login;

      if (!isAuthenticated && !onLoginPage) return AppRoutes.login;
      if (isAuthenticated && onLoginPage) return AppRoutes.projects;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.projects,
        builder: (context, state) => const ProjectListScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.projects}/:id/modules',
        builder: (context, state) => ModuleChooserScreen(
          projectId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '${AppRoutes.projects}/:id/audits',
        builder: (context, state) => AuditListScreen(
          projectId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '${AppRoutes.projects}/:id/audits/:auditId',
        builder: (context, state) => AuditDetailScreen(
          auditId: int.tryParse(state.pathParameters['auditId'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '${AppRoutes.projects}/:id/assets',
        builder: (context, state) => AssetListScreen(
          projectId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: AppRoutes.survey,
        builder: (context, state) => const SurveyScreen(),
      ),
      GoRoute(
        path: AppRoutes.dashboard,
        builder: (context, state) => const DashboardShell(child: DashboardGridScreen()),
      ),
      GoRoute(
        path: AppRoutes.overview,
        builder: (context, state) =>
            const DashboardShell(child: OverviewScreen()),
      ),
      GoRoute(
        path: AppRoutes.liveMonitoring,
        builder: (context, state) =>
            const DashboardShell(child: LiveDetectionScreen()),
      ),
      GoRoute(
        path: AppRoutes.gisMap,
        builder: (context, state) => const DashboardShell(child: GisMapScreen()),
      ),
      GoRoute(
        path: AppRoutes.uploadVideo,
        builder: (context, state) => const DashboardShell(child: UploadVideoScreen()),
      ),
      GoRoute(
        path: AppRoutes.liveProcessing,
        builder: (context, state) => const DashboardShell(child: LiveProcessingScreen()),
      ),
      GoRoute(
        path: AppRoutes.roadDistresses,
        builder: (context, state) => const DashboardShell(child: RoadDistressesScreen()),
      ),
      GoRoute(
        path: AppRoutes.maintenance,
        builder: (context, state) => const DashboardShell(child: MaintenanceScreen()),
      ),
      GoRoute(
        path: AppRoutes.reports,
        builder: (context, state) => const DashboardShell(child: ReportsScreen()),
      ),
      GoRoute(
        path: AppRoutes.analytics,
        builder: (context, state) => const DashboardShell(child: AnalyticsScreen()),
      ),
      GoRoute(
        path: AppRoutes.history,
        builder: (context, state) => const DashboardShell(child: HistoryScreen()),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        builder: (context, state) => const DashboardShell(child: NotificationsScreen()),
      ),
      GoRoute(
        path: AppRoutes.videoReview,
        builder: (context, state) => const DashboardShell(child: VideoReviewScreen()),
      ),
      GoRoute(
        path: '${AppRoutes.videoReview}/:id',
        builder: (context, state) => DashboardShell(
          child: VideoReviewScreen(videoId: int.tryParse(state.pathParameters['id'] ?? '')),
        ),
      ),
    ],
  );
});

/// Bridges Riverpod's authProvider to go_router's Listenable-based redirect
/// refresh, so navigating after login/logout re-evaluates `redirect` above.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(this.ref) {
    ref.listen(authProvider, (previous, next) {
      if (previous?.isAuthenticated != next.isAuthenticated ||
          previous?.isRestoring != next.isRestoring) {
        notifyListeners();
      }
    });
  }

  final Ref ref;
}
