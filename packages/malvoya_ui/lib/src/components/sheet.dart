import 'package:flutter/material.dart';
import '../tokens/layout.dart';
import '../tokens/tokens.dart';
import '../tokens/type.dart';

/// Shows a bottom sheet with the drag-handle rule built in:
///
/// * a normal sheet uses the theme's surface and shows the theme's drag handle;
/// * a [transparent] sheet draws its own shape (e.g. [MSheet] with `handle: true`), so the theme
///   handle is switched off (`showDragHandle: false`), otherwise two handles would appear or the
///   handle would float over nothing.
///
/// Sheets are scroll-controlled and respect the safe area and the keyboard by default.
Future<T?> showMSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool transparent = false,
  bool isScrollControlled = true,
  bool useSafeArea = true,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useRootNavigator = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    builder: builder,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useRootNavigator: useRootNavigator,
    showDragHandle: !transparent,
    backgroundColor: transparent ? Colors.transparent : null,
    elevation: transparent ? 0 : null,
  );
}

/// The drag handle drawn by a transparent sheet itself: 40 × 4, in the outline colour.
class MSheetHandle extends StatelessWidget {
  /// Creates the handle.
  const MSheetHandle({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(top: MSpace.md, bottom: MSpace.sm),
          decoration: BoxDecoration(color: context.mColors.outline, borderRadius: const BorderRadius.all(Radius.circular(2))),
        ),
      );
}

/// The standard sheet layout: optional title and subtitle, scrollable content and actions pinned at
/// the bottom, padded for the keyboard.
///
/// Inside [showMSheet] leave [handle] false (the theme draws one). With `transparent: true`, set
/// [handle] true: the sheet then draws its own rounded surface and handle.
class MSheet extends StatelessWidget {
  /// Creates the layout.
  const MSheet({
    super.key,
    this.title,
    this.subtitle,
    required this.child,
    this.actions = const [],
    this.handle = false,
    this.padding = const EdgeInsets.fromLTRB(MSpace.xxl, 0, MSpace.xxl, MSpace.xl),
  });

  /// Headline (display face).
  final String? title;

  /// One line under the title.
  final String? subtitle;

  /// The content.
  final Widget child;

  /// Buttons at the bottom (the first is usually an `MButton` with `expand: true`).
  final List<Widget> actions;

  /// Draw an own surface and handle (for transparent sheets).
  final bool handle;

  /// Inner padding.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final body = Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SingleChildScrollView(
        padding: padding.copyWith(top: handle ? MSpace.sm : padding.top),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Semantics(header: true, child: Text(title!, style: MType.displayS.copyWith(color: c.onSurface))),
              const SizedBox(height: MSpace.sm),
            ],
            if (subtitle != null) ...[
              Text(subtitle!, style: MType.bodyM.copyWith(color: c.onSurfaceVariant)),
              const SizedBox(height: MSpace.lg),
            ] else if (title != null)
              const SizedBox(height: MSpace.sm),
            child,
            if (actions.isNotEmpty) ...[
              const SizedBox(height: MSpace.xl),
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(height: MSpace.sm),
                actions[i],
              ],
            ],
          ],
        ),
      ),
    );
    if (!handle) return body;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.surface, borderRadius: MRadius.sheetTop),
      child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [const MSheetHandle(), Flexible(child: body)])),
    );
  }
}
