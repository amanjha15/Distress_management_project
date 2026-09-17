import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'asset_api.dart';
import 'auth_provider.dart';

/// M3 Asset Management documents for a given project. `.family` keyed by
/// projectId since a user can move between projects' document lists.
final projectAssetsProvider =
    FutureProvider.autoDispose.family<List<ProjectAsset>, int>((ref, projectId) async {
  final token = ref.watch(authProvider.select((s) => s.token));
  if (token == null) return const [];
  return AssetApi(token).listAssets(projectId);
});
