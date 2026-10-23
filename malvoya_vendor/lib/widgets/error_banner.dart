import 'package:flutter/material.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';

/// A slim error strip above content that is still shown (e.g. older data after a failed refresh).
class ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ErrorBanner({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    return Container(
      margin: const EdgeInsets.only(bottom: MSpace.md),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(color: c.dangerSoft, borderRadius: MRadius.brMd),
      child: Row(children: [
        Icon(Icons.cloud_off_rounded, size: 18, color: c.onDangerSoft),
        const SizedBox(width: MSpace.sm),
        Expanded(child: Semantics(liveRegion: true, child: Text(message, style: MType.label.copyWith(color: c.onDangerSoft, fontWeight: FontWeight.w600)))),
        TextButton(onPressed: onRetry, child: Text(tr(context, 'Try again', 'Yritä uudelleen'))),
      ]),
    );
  }
}
