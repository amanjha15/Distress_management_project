import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audit_api.dart';
import 'auth_provider.dart';

/// M2 Road Safety Audits for a given project. `.family` keyed by projectId
/// since a user can move between projects' audit lists within one session.
final auditsProvider = FutureProvider.autoDispose.family<List<SafetyAudit>, int>((ref, projectId) async {
  final token = ref.watch(authProvider.select((s) => s.token));
  if (token == null) return const [];
  return AuditApi(token).listAudits(projectId);
});

final auditProvider = FutureProvider.autoDispose.family<SafetyAudit?, int>((ref, auditId) async {
  final token = ref.watch(authProvider.select((s) => s.token));
  if (token == null) return null;
  return AuditApi(token).getAudit(auditId);
});

final auditChecklistProvider =
    FutureProvider.autoDispose.family<List<AuditChecklistItem>, int>((ref, auditId) async {
  final token = ref.watch(authProvider.select((s) => s.token));
  if (token == null) return const [];
  return AuditApi(token).listChecklistItems(auditId);
});

final auditAudioClipsProvider =
    FutureProvider.autoDispose.family<List<AuditAudioClip>, int>((ref, auditId) async {
  final token = ref.watch(authProvider.select((s) => s.token));
  if (token == null) return const [];
  return AuditApi(token).listAudioClips(auditId);
});

final auditChainageReportProvider =
    FutureProvider.autoDispose.family<List<ChainageBucket>, int>((ref, auditId) async {
  final token = ref.watch(authProvider.select((s) => s.token));
  if (token == null) return const [];
  return AuditApi(token).chainageReport(auditId);
});
