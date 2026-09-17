import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../data/audit_api.dart';
import '../../../theme/app_colors.dart';

/// One audio commentary clip: play/pause + its transcript (or a status
/// badge while app/services/transcription_service.py is still working on
/// it). Used by both the Audio Commentary tab and the audio report view.
class AudioClipCard extends StatefulWidget {
  const AudioClipCard({super.key, required this.clip, this.onDelete});

  final AuditAudioClip clip;

  /// Called after the user confirms deletion in this card's own dialog.
  final VoidCallback? onDelete;

  @override
  State<AudioClipCard> createState() => _AudioClipCardState();
}

class _AudioClipCardState extends State<AudioClipCard> {
  final _player = AudioPlayer();
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _isPlaying = state == PlayerState.playing);
    });
    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() => _isPlaying = false);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play(UrlSource(widget.clip.resolvedUrl));
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('Delete Audio Commentary?', style: TextStyle(color: Colors.white)),
        content: Text(
          'This permanently removes "${widget.clip.filename}"${widget.clip.transcript != null ? ' and its transcript' : ''}.',
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
    if (confirmed == true) {
      if (_isPlaying) await _player.stop();
      widget.onDelete?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final clip = widget.clip;
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
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: _togglePlay,
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.accentBlueHover.withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
              child: Icon(_isPlaying ? LucideIcons.pause : LucideIcons.play, size: 16, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (clip.chainageKm != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${clip.chainageKm!.toStringAsFixed(2)} km',
                          style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.warning),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        clip.filename,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                    ),
                    _TranscriptStatusBadge(status: clip.transcriptStatus),
                    if (widget.onDelete != null) ...[
                      const SizedBox(width: 4),
                      InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: _confirmDelete,
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(LucideIcons.trash2, size: 15, color: Color(0xFF94A3B8)),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                if (clip.transcript != null)
                  Text(
                    '"${clip.transcript}"',
                    style: const TextStyle(fontSize: 12.5, color: Color(0xFFCBD5E1), fontStyle: FontStyle.italic, height: 1.4),
                  )
                else if (clip.transcriptStatus == 'pending')
                  const Text('Transcribing...', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)))
                else if (clip.transcriptStatus == 'failed')
                  const Text('Transcription failed — audio is still saved above.', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)))
                else if (clip.transcriptStatus == 'unavailable')
                  const Text('Transcription unavailable — audio is still saved above.', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TranscriptStatusBadge extends StatelessWidget {
  const _TranscriptStatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    if (status == 'done') return const SizedBox.shrink();
    Color color;
    switch (status) {
      case 'pending':
        color = AppColors.warning;
      case 'failed':
      case 'unavailable':
        color = const Color(0xFF94A3B8);
      default:
        color = AppColors.success;
    }
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
      child: Text(status.toUpperCase(), style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700, color: color)),
    );
  }
}
