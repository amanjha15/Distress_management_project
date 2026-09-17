import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../utils/local_time.dart';

/// Mirrors RealTimeDetectionFeed.tsx's `FeedDetection` shape.
class FeedDetection {
  const FeedDetection({
    required this.id,
    required this.time,
    required this.roadId,
    required this.distressType,
    required this.severity,
    required this.confidence,
    required this.coordinates,
  });

  final String id;
  final String time;
  final String roadId;
  final String distressType;
  final String severity; // 'Critical' | 'High' | 'Medium' | 'Low'
  final int confidence;
  final String coordinates;
}

/// Direct port of components/monitoring/RealTimeDetectionFeed.tsx and its
/// CSS: a self-contained dark widget (unlike the rest of this light-themed
/// page), always fed real detections here rather than replicating the
/// React source's standalone/simulated-data fallback mode.
class RealTimeDetectionFeed extends StatefulWidget {
  const RealTimeDetectionFeed({super.key, required this.detections});

  final List<FeedDetection> detections;

  @override
  State<RealTimeDetectionFeed> createState() => _RealTimeDetectionFeedState();
}

class _RealTimeDetectionFeedState extends State<RealTimeDetectionFeed> {
  final _scrollController = ScrollController();
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void didUpdateWidget(covariant RealTimeDetectionFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.detections.length != widget.detections.length && _autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      });
    }
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final atBottom = pos.maxScrollExtent - pos.pixels < 30;
    if (atBottom != _autoScroll) setState(() => _autoScroll = atBottom);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  static const _severityColors = {
    'critical': Color(0xFFEF4444),
    'high': Color(0xFFF97316),
    'medium': Color(0xFFEAB308),
    'low': Color(0xFF3B82F6),
  };

  static const _badgeColors = {
    'critical': (bg: Color(0x1AEF4444), fg: Color(0xFFEF4444), border: Color(0x26EF4444)),
    'high': (bg: Color(0x1AF97316), fg: Color(0xFFF97316), border: Color(0x26F97316)),
    'medium': (bg: Color(0x1AEAB308), fg: Color(0xFFEAB308), border: Color(0x26EAB308)),
    'low': (bg: Color(0x1A3B82F6), fg: Color(0xFF3B82F6), border: Color(0x263B82F6)),
  };

  IconData _iconFor(String type) {
    switch (type.toLowerCase()) {
      case 'pothole':
        return LucideIcons.alertTriangle;
      case 'alligator cracks':
      case 'longitudinal cracks':
      case 'cracks':
        return LucideIcons.alertCircle;
      case 'rutting':
        return LucideIcons.activity;
      case 'edge break':
        return LucideIcons.cornerRightDown;
      case 'patch':
        return LucideIcons.layers;
      default:
        return LucideIcons.helpCircle;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 480),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.1),
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Real-Time Detection Feed',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFCBD5E1),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_autoScroll) ...[
                      _ResumeScrollButton(onTap: () {
                        setState(() => _autoScroll = true);
                        if (_scrollController.hasClients) {
                          _scrollController.animateTo(
                            _scrollController.position.maxScrollExtent,
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                          );
                        }
                      }),
                      const SizedBox(width: 10),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0x14C084FC),
                        border: Border.all(color: const Color(0x26C084FC)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Telemetry Stream Active',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFFC084FC),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Flexible(
            child: widget.detections.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Waiting for camera detections...',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  )
                : ListView.separated(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(20),
                    itemCount: widget.detections.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final det = widget.detections[index];
                      final sevKey = det.severity.toLowerCase();
                      return _DetectionCard(
                        det: det,
                        borderColor: _severityColors[sevKey] ?? const Color(0xFF3B82F6),
                        badgeColors: _badgeColors[sevKey] ?? _badgeColors['low']!,
                        icon: _iconFor(det.distressType),
                        iconColor: _severityColors[sevKey] ?? const Color(0xFF3B82F6),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ResumeScrollButton extends StatelessWidget {
  const _ResumeScrollButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x1A3B82F6),
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0x403B82F6)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.arrowDown, size: 10, color: Color(0xFF60A5FA)),
              SizedBox(width: 5),
              Text(
                'Resume Auto-Scroll',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF60A5FA),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetectionCard extends StatelessWidget {
  const _DetectionCard({
    required this.det,
    required this.borderColor,
    required this.badgeColors,
    required this.icon,
    required this.iconColor,
  });

  final FeedDetection det;
  final Color borderColor;
  final ({Color bg, Color fg, Color border}) badgeColors;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          right: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          left: BorderSide(color: borderColor, width: 3),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: iconColor),
                  const SizedBox(width: 8),
                  Text(
                    det.id,
                    style: const TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFF8FAFC),
                    ),
                  ),
                ],
              ),
              Text(
                '[${formatLocalTime(det.time)}]',
                style: const TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 11.5,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.04)),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _FeedRow(label: 'Road ID', value: det.roadId, bold: true),
                    const SizedBox(height: 10),
                    _FeedBadgeRow(label: 'Severity', badgeText: det.severity, colors: badgeColors),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _FeedRow(label: 'Distress Type', value: det.distressType),
                    const SizedBox(height: 10),
                    _FeedRow(
                      label: 'Confidence',
                      value: '${det.confidence}%',
                      mono: true,
                      color: const Color(0xFF4ADE80),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.04)),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.compass, size: 11, color: Color(0xFF60A5FA)),
              const SizedBox(width: 6),
              Text(
                det.coordinates,
                style: const TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 11.5,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeedRow extends StatelessWidget {
  const _FeedRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.mono = false,
    this.color,
  });

  final String label;
  final String value;
  final bool bold;
  final bool mono;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 12.5,
            fontFamily: mono ? 'JetBrains Mono' : null,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            color: color ?? const Color(0xFFCBD5E1),
          ),
        ),
      ],
    );
  }
}

class _FeedBadgeRow extends StatelessWidget {
  const _FeedBadgeRow({
    required this.label,
    required this.badgeText,
    required this.colors,
  });

  final String label;
  final String badgeText;
  final ({Color bg, Color fg, Color border}) colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: colors.bg,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            badgeText.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: colors.fg,
            ),
          ),
        ),
      ],
    );
  }
}
