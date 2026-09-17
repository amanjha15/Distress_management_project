import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/asset_api.dart';
import '../../data/asset_provider.dart';
import '../../data/auth_provider.dart';
import '../../data/project_provider.dart';
import '../../router/app_router.dart';
import '../../theme/app_colors.dart';

String _categoryLabel(String category) => category
    .split('_')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

IconData _iconForFilename(String filename) {
  final ext = filename.contains('.') ? filename.split('.').last.toLowerCase() : '';
  switch (ext) {
    case 'xls':
    case 'xlsx':
    case 'csv':
      return LucideIcons.fileSpreadsheet;
    case 'png':
    case 'jpg':
    case 'jpeg':
      return LucideIcons.image;
    default:
      return LucideIcons.fileText;
  }
}

String _formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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

/// M3 Asset Management: documents, drawings, photos and reports attached to
/// a Project so they can be managed and reused across modules, rather than
/// living only inside whichever module produced them.
class AssetListScreen extends ConsumerStatefulWidget {
  const AssetListScreen({super.key, required this.projectId});

  final int projectId;

  @override
  ConsumerState<AssetListScreen> createState() => _AssetListScreenState();
}

class _AssetListScreenState extends ConsumerState<AssetListScreen> {
  String? _categoryFilter;
  bool _isUploading = false;

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'csv', 'png', 'jpg', 'jpeg', 'txt'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    if (picked.bytes == null) return;
    if (!mounted) return;
    await _showUploadDialog(picked.bytes!, picked.name);
  }

  Future<void> _showUploadDialog(Uint8List bytes, String filename) async {
    String category = kAssetCategories.first;
    final descriptionCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          title: const Text('Upload Document', style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(filename, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5)),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  dropdownColor: const Color(0xFF0F172A),
                  style: const TextStyle(color: Colors.white, fontSize: 13.5),
                  decoration: _dialogFieldDecoration('Category'),
                  items: [
                    for (final c in kAssetCategories) DropdownMenuItem(value: c, child: Text(_categoryLabel(c))),
                  ],
                  onChanged: (v) => setDialogState(() => category = v ?? category),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionCtrl,
                  maxLines: 2,
                  style: const TextStyle(color: Colors.white, fontSize: 13.5),
                  decoration: _dialogFieldDecoration('Description (optional)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentBlue),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Upload', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    final token = ref.read(authProvider).token;
    if (token == null) return;

    setState(() => _isUploading = true);
    try {
      await AssetApi(token).uploadAsset(
        widget.projectId,
        bytes: bytes,
        filename: filename,
        category: category,
        description: descriptionCtrl.text.trim(),
      );
      ref.invalidate(projectAssetsProvider(widget.projectId));
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

  Future<void> _deleteAsset(ProjectAsset asset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('Delete Document?', style: TextStyle(color: Colors.white)),
        content: Text(
          'This permanently removes "${asset.filename}". This cannot be undone.',
          style: const TextStyle(color: Color(0xFFCBD5E1)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final token = ref.read(authProvider).token;
    if (token == null) return;
    try {
      await AssetApi(token).deleteAsset(asset.id);
      ref.invalidate(projectAssetsProvider(widget.projectId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Future<void> _openAsset(ProjectAsset asset) async {
    await launchUrl(Uri.parse(asset.resolvedUrl), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(selectedProjectProvider);
    final assetsAsync = ref.watch(projectAssetsProvider(widget.projectId));

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
                            onPressed: () => context.go(AppRoutes.projectModules(widget.projectId)),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'M3 · Asset Management',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.warning, letterSpacing: 1),
                                ),
                                Text(
                                  project?.name ?? 'Project #${widget.projectId}',
                                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                          _isUploading
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 20),
                                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.warning)),
                                )
                              : ElevatedButton.icon(
                                  onPressed: _pickAndUpload,
                                  icon: const Icon(LucideIcons.upload, size: 16),
                                  label: const Text('Upload Document'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.accentBlue,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  ),
                                ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      assetsAsync.when(
                        loading: () => const SizedBox(),
                        error: (_, __) => const SizedBox(),
                        data: (assets) {
                          final categories = assets.map((a) => a.category).toSet().toList()..sort();
                          if (categories.isEmpty) return const SizedBox();
                          return SizedBox(
                            height: 36,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                _FilterChip(
                                  label: 'All',
                                  selected: _categoryFilter == null,
                                  onTap: () => setState(() => _categoryFilter = null),
                                ),
                                for (final c in categories)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: _FilterChip(
                                      label: _categoryLabel(c),
                                      selected: _categoryFilter == c,
                                      onTap: () => setState(() => _categoryFilter = c),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: assetsAsync.when(
                          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.warning)),
                          error: (err, _) => Center(
                            child: Text('$err', style: const TextStyle(color: Color(0xFFFCA5A5))),
                          ),
                          data: (assets) {
                            final filtered = _categoryFilter == null
                                ? assets
                                : assets.where((a) => a.category == _categoryFilter).toList();
                            if (filtered.isEmpty) {
                              return const Center(
                                child: Text(
                                  'No documents yet. Upload reports, drawings, or photos with "Upload Document".',
                                  style: TextStyle(color: Color(0xFFCBD5E1)),
                                ),
                              );
                            }
                            return ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (context, i) => _AssetCard(
                                asset: filtered[i],
                                onOpen: () => _openAsset(filtered[i]),
                                onDelete: () => _deleteAsset(filtered[i]),
                              ),
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
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentBlue.withValues(alpha: 0.3) : AppColors.glassCardFill,
          border: Border.all(color: selected ? AppColors.accentBlue : AppColors.glassCardBorder),
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : const Color(0xFFCBD5E1),
          ),
        ),
      ),
    );
  }
}

class _AssetCard extends StatelessWidget {
  const _AssetCard({required this.asset, required this.onOpen, required this.onDelete});

  final ProjectAsset asset;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.all(16),
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
              child: Icon(_iconForFilename(asset.filename), size: 20, color: AppColors.warning),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    asset.filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _categoryLabel(asset.category).toUpperCase(),
                          style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.warning),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(_formatFileSize(asset.fileSize), style: const TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8))),
                    ],
                  ),
                  if (asset.description != null && asset.description!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      asset.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: const Icon(LucideIcons.externalLink, size: 18, color: Color(0xFF94A3B8)),
              tooltip: 'Open',
              onPressed: onOpen,
            ),
            IconButton(
              icon: const Icon(LucideIcons.trash2, size: 18, color: Color(0xFFFCA5A5)),
              tooltip: 'Delete',
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
