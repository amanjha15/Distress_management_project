import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/live_detection_api.dart' show kApiBaseUrl, setCustomServerUrl;
import '../theme/app_colors.dart';

/// Shared "Backend Connection URL" dialog, used both from the post-login
/// dashboard shell and from the login screen itself. Native builds (unlike
/// web) have no way to auto-detect their backend's address, so this is the
/// only way to point the app at a real server -- and since login itself
/// needs that address to work at all, this must be reachable *before*
/// logging in too, not just from inside the dashboard shell.
void showServerConfigDialog(BuildContext context, {VoidCallback? onSaved}) {
  final controller = TextEditingController(text: kApiBaseUrl);
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1E231C),
      title: const Row(
        children: [
          Icon(LucideIcons.globe, color: AppColors.accentBlue, size: 20),
          SizedBox(width: 8),
          Text('Backend Connection URL', style: TextStyle(color: Colors.white, fontSize: 16)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter your backend\'s address (e.g. your Railway deployment URL, or your '
            'computer\'s Wi-Fi IP on port 8000 for local dev) to connect:',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.black26,
              hintText: 'e.g. https://your-backend.up.railway.app',
              hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentBlue),
          onPressed: () {
            if (controller.text.trim().isNotEmpty) {
              setCustomServerUrl(controller.text);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Connecting to: ${controller.text.trim()}'),
                  backgroundColor: AppColors.accentBlue,
                ),
              );
              onSaved?.call();
            }
          },
          child: const Text('Save & Connect', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}
