import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:record/record.dart';

import '../../data/audit_api.dart';
import '../../data/audit_provider.dart';
import '../../data/auth_provider.dart';
import '../../router/app_router.dart';
import '../../theme/app_colors.dart';
import '../../utils/audio_bytes_reader.dart';
import 'widgets/audio_clip_player.dart';

Color severityColor(String severity) {
  switch (severity) {
    case 'critical':
      return AppColors.danger;
    case 'high':
      return const Color(0xFFF97316);
    case 'medium':
      return AppColors.warning;
    default:
      return AppColors.success;
  }
}

String categoryLabel(String category) => category
    .split('_')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

/// M2 Road Safety Audit detail: checklist findings, audio commentary
/// (record-in-app or upload), and the two report views this module exists
/// to produce -- the chainage-wise report and the audio report.
class AuditDetailScreen extends ConsumerStatefulWidget {
  const AuditDetailScreen({super.key, required this.auditId});

  final int auditId;

  @override
  ConsumerState<AuditDetailScreen> createState() => _AuditDetailScreenState();
}

class _AuditDetailScreenState extends ConsumerState<AuditDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auditAsync = ref.watch(auditProvider(widget.auditId));

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
                  padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
                            onPressed: () {
                              final projectId = auditAsync.value?.projectId;
                              if (projectId != null) {
                                context.go(AppRoutes.auditList(projectId));
                              } else {
                                context.go(AppRoutes.projects);
                              }
                            },
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
                                  auditAsync.value?.title ?? 'Audit #${widget.auditId}',
                                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.glassCardFill,
                          border: Border.all(color: AppColors.glassCardBorder),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TabBar(
                          controller: _tabController,
                          indicatorColor: AppColors.warning,
                          labelColor: Colors.white,
                          unselectedLabelColor: const Color(0xFF94A3B8),
                          tabs: const [
                            Tab(text: 'Checklist'),
                            Tab(text: 'Audio Commentary'),
                            Tab(text: 'Chainage Report'),
                          ],
                        ),
                      ),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _ChecklistTab(auditId: widget.auditId),
                            _AudioTab(auditId: widget.auditId),
                            _ChainageReportTab(auditId: widget.auditId),
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

// ---------------------------------------------------------------------------
// Checklist tab
// ---------------------------------------------------------------------------

class _ChecklistTab extends ConsumerWidget {
  const _ChecklistTab({required this.auditId});

  final int auditId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(auditChecklistProvider(auditId));

    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: () => _showAddFindingDialog(context, ref),
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text('Add Finding'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentBlue,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: itemsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.warning)),
              error: (err, _) => Center(child: Text('$err', style: const TextStyle(color: Color(0xFFFCA5A5)))),
              data: (items) {
                if (items.isEmpty) {
                  return const Center(
                    child: Text('No findings logged yet.', style: TextStyle(color: Color(0xFFCBD5E1))),
                  );
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _FindingCard(item: items[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddFindingDialog(BuildContext context, WidgetRef ref) async {
    final formKey = GlobalKey<FormState>();
    final chainageCtrl = TextEditingController();
    final descriptionCtrl = TextEditingController();
    String category = kAuditCategories.first;
    String severity = 'medium';

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          title: const Text('Add Finding', style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: chainageCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Colors.white, fontSize: 13.5),
                      validator: (v) => double.tryParse(v?.trim() ?? '') == null ? 'Enter a chainage in km, e.g. 119.4' : null,
                      decoration: _dialogFieldDecoration('Chainage (km) *'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: category,
                      dropdownColor: const Color(0xFF0F172A),
                      style: const TextStyle(color: Colors.white, fontSize: 13.5),
                      decoration: _dialogFieldDecoration('Category'),
                      items: [
                        for (final c in kAuditCategories) DropdownMenuItem(value: c, child: Text(categoryLabel(c))),
                      ],
                      onChanged: (v) => setDialogState(() => category = v ?? category),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: severity,
                      dropdownColor: const Color(0xFF0F172A),
                      style: const TextStyle(color: Colors.white, fontSize: 13.5),
                      decoration: _dialogFieldDecoration('Severity'),
                      items: [
                        for (final s in kAuditSeverities) DropdownMenuItem(value: s, child: Text(s.toUpperCase())),
                      ],
                      onChanged: (v) => setDialogState(() => severity = v ?? severity),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: descriptionCtrl,
                      maxLines: 3,
                      style: const TextStyle(color: Colors.white, fontSize: 13.5),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      decoration: _dialogFieldDecoration('Description *'),
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
                if (formKey.currentState?.validate() ?? false) Navigator.pop(context, true);
              },
              child: const Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;
    final token = ref.read(authProvider).token;
    if (token == null) return;

    try {
      await AuditApi(token).createChecklistItem(
        auditId,
        chainageKm: double.parse(chainageCtrl.text.trim()),
        category: category,
        severity: severity,
        description: descriptionCtrl.text.trim(),
      );
      ref.invalidate(auditChecklistProvider(auditId));
      ref.invalidate(auditProvider(auditId));
      ref.invalidate(auditChainageReportProvider(auditId));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }
}

InputDecoration _dialogFieldDecoration(String label) {
  return InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
    filled: true,
    fillColor: Colors.black26,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  );
}

class _FindingCard extends StatelessWidget {
  const _FindingCard({required this.item});

  final AuditChecklistItem item;

  @override
  Widget build(BuildContext context) {
    final color = severityColor(item.severity);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.glassCardFill,
        border: Border.all(color: AppColors.glassCardBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
            child: Text(
              '${item.chainageKm.toStringAsFixed(2)} km',
              style: TextStyle(fontFamily: 'JetBrains Mono', fontSize: 12, fontWeight: FontWeight.w700, color: color),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(categoryLabel(item.category), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                      child: Text(item.severity.toUpperCase(), style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: color)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(item.description, style: const TextStyle(fontSize: 12.5, color: Color(0xFFCBD5E1), height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Audio tab
// ---------------------------------------------------------------------------

class _AudioTab extends ConsumerStatefulWidget {
  const _AudioTab({required this.auditId});

  final int auditId;

  @override
  ConsumerState<_AudioTab> createState() => _AudioTabState();
}

class _AudioTabState extends ConsumerState<_AudioTab> {
  final _recorder = AudioRecorder();
  final _chainageCtrl = TextEditingController();
  bool _isRecording = false;
  bool _isUploading = false;

  @override
  void dispose() {
    _recorder.dispose();
    _chainageCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final path = await _recorder.stop();
      setState(() => _isRecording = false);
      if (path == null) return;
      final bytes = await readRecordedAudioBytes(path);
      await _upload(bytes, 'commentary_${DateTime.now().millisecondsSinceEpoch}.webm');
      return;
    }

    if (!await _recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required to record commentary.')),
        );
      }
      return;
    }
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.opus),
      path: 'commentary.webm',
    );
    setState(() => _isRecording = true);
  }

  Future<void> _upload(Uint8List bytes, String filename) async {
    final token = ref.read(authProvider).token;
    if (token == null) return;
    setState(() => _isUploading = true);
    try {
      final chainage = double.tryParse(_chainageCtrl.text.trim());
      await AuditApi(token).uploadAudioClip(
        widget.auditId,
        bytes: bytes,
        filename: filename,
        chainageKm: chainage,
      );
      ref.invalidate(auditAudioClipsProvider(widget.auditId));
      ref.invalidate(auditProvider(widget.auditId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _pickAndUploadFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'webm'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    if (picked.bytes == null) return;
    await _upload(picked.bytes!, picked.name);
  }

  Future<void> _deleteClip(int clipId) async {
    final token = ref.read(authProvider).token;
    if (token == null) return;
    try {
      await AuditApi(token).deleteAudioClip(widget.auditId, clipId);
      ref.invalidate(auditAudioClipsProvider(widget.auditId));
      ref.invalidate(auditProvider(widget.auditId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final clipsAsync = ref.watch(auditAudioClipsProvider(widget.auditId));

    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.glassCardFill,
              border: Border.all(color: AppColors.glassCardBorder),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: _chainageCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: _dialogFieldDecoration('Chainage (km)'),
                  ),
                ),
                const SizedBox(width: 16),
                _isUploading
                    ? const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.warning)),
                      )
                    : ElevatedButton.icon(
                        onPressed: _toggleRecording,
                        icon: Icon(_isRecording ? LucideIcons.square : LucideIcons.mic, size: 16),
                        label: Text(_isRecording ? 'Stop & Upload' : 'Record Commentary'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isRecording ? AppColors.danger : AppColors.accentBlue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                const SizedBox(width: 10),
                if (!_isUploading && !_isRecording)
                  OutlinedButton.icon(
                    onPressed: _pickAndUploadFile,
                    icon: const Icon(LucideIcons.upload, size: 15, color: Colors.white),
                    label: const Text('Upload File', style: TextStyle(color: Colors.white)),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white24)),
                  ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Records in-browser via your microphone, or upload a pre-recorded clip.',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: clipsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.warning)),
              error: (err, _) => Center(child: Text('$err', style: const TextStyle(color: Color(0xFFFCA5A5)))),
              data: (clips) {
                if (clips.isEmpty) {
                  return const Center(
                    child: Text('No audio commentary recorded yet.', style: TextStyle(color: Color(0xFFCBD5E1))),
                  );
                }
                return ListView.separated(
                  itemCount: clips.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => AudioClipCard(
                    clip: clips[i],
                    onDelete: () => _deleteClip(clips[i].id),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chainage report tab
// ---------------------------------------------------------------------------

class _ChainageReportTab extends ConsumerWidget {
  const _ChainageReportTab({required this.auditId});

  final int auditId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(auditChainageReportProvider(auditId));

    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 16),
      child: reportAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.warning)),
        error: (err, _) => Center(child: Text('$err', style: const TextStyle(color: Color(0xFFFCA5A5)))),
        data: (buckets) {
          final nonEmpty = buckets.where((b) => b.items.isNotEmpty).toList();
          if (nonEmpty.isEmpty) {
            return const Center(
              child: Text(
                'No findings logged yet — the chainage report fills in as you add checklist items.',
                style: TextStyle(color: Color(0xFFCBD5E1)),
              ),
            );
          }
          return ListView.separated(
            itemCount: nonEmpty.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _BucketCard(bucket: nonEmpty[i]),
          );
        },
      ),
    );
  }
}

class _BucketCard extends StatelessWidget {
  const _BucketCard({required this.bucket});

  final ChainageBucket bucket;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.glassCardFill,
        border: Border.all(color: AppColors.glassCardBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${bucket.startKm.toStringAsFixed(2)} — ${bucket.endKm.toStringAsFixed(2)} km',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white, fontFamily: 'JetBrains Mono'),
              ),
              const Spacer(),
              for (final s in kAuditSeverities)
                if ((bucket.severityCounts[s] ?? 0) > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: severityColor(s).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${bucket.severityCounts[s]} $s',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: severityColor(s)),
                      ),
                    ),
                  ),
            ],
          ),
          const SizedBox(height: 10),
          for (final item in bucket.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(top: 5, right: 8),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: severityColor(item.severity)),
                  ),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${categoryLabel(item.category)}: ',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                          TextSpan(
                            text: item.description,
                            style: const TextStyle(fontSize: 12.5, color: Color(0xFFCBD5E1)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
