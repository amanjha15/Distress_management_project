import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'auth_provider.dart';
import 'project_api.dart';

/// Role-scoped project list for the "Project-wise Survey" homepage --
/// admins see every project, employees only the ones they're assigned to
/// (enforced server-side by GET /projects/, not here).
final projectsProvider = FutureProvider.autoDispose<List<Project>>((ref) async {
  final token = ref.watch(authProvider.select((s) => s.token));
  if (token == null) return const [];
  return ProjectApi(token).listProjects();
});

/// Currently selected Project, set when the user opens it from the project
/// list and read by the module chooser + M1/M2/M3/M4 screens.
final selectedProjectProvider = StateProvider<Project?>((ref) => null);
