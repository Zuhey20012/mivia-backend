import 'package:flutter/material.dart';
import '../../../../config/theme.dart';

typedef WidgetBuilderFunc = Widget Function(
  BuildContext context,
  Map<String, dynamic> props,
  Map<String, dynamic>? action,
);

class SDUIActionHandler {
  static void execute(BuildContext context, Map<String, dynamic>? action) {
    if (action == null) return;
    if (action['type'] == 'NAVIGATE') {
      final route = action['payload']?['route'] as String?;
      if (route != null) {
        Navigator.of(context).pushNamed(route);
      }
    }
  }
}

class SDUIWidgetRegistry {
  static final Map<String, WidgetBuilderFunc> _registry = {
    'HERO_BANNER': (ctx, props, act) => GestureDetector(
          onTap: () => SDUIActionHandler.execute(ctx, act),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            height: 160,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.primary, AppTheme.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  props['title'] ?? '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  props['subtitle'] ?? '',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
    'SECTION_TABS': (ctx, props, act) {
      final items = (props['tabs'] as List?) ?? [];
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: items.map((tab) {
            return Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
              ),
              child: Text(
                tab.toString(),
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          }).toList(),
        ),
      );
    },
  };

  static Widget render(BuildContext ctx, Map<String, dynamic> data) {
    final builder = _registry[data['type']];
    return builder != null
        ? builder(ctx, data['properties'] ?? {}, data['action'])
        : const SizedBox.shrink();
  }
}
