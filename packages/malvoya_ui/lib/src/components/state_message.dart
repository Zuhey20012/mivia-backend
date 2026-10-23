import 'package:flutter/material.dart';
import 'package:malvoya_core/malvoya_core.dart';
import '../tokens/layout.dart';
import '../tokens/tokens.dart';
import '../tokens/type.dart';
import 'button.dart';
import 'empty_art.dart';

/// What kind of state a [MStateMessage] shows.
enum MStateKind {
  /// Nothing here yet (no orders, empty bag).
  empty,

  /// Loading failed.
  error,

  /// No connection.
  offline,
}

/// A calm empty, error or offline state: an illustration (or an icon in a soft circle), an optional
/// heading, one sentence and an optional action.
///
/// It is scrollable by default, so it can sit inside a `RefreshIndicator` and still be pulled.
/// The message is a live region, so screen readers announce a failure when it appears.
class MStateMessage extends StatelessWidget {
  /// Creates a state message.
  const MStateMessage({
    super.key,
    this.kind = MStateKind.empty,
    required String this.message,
    this.title,
    this.icon,
    this.art,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.action,
    this.scrollable = true,
    this.top = 96,
    this.centered = false,
  });

  /// "Could not load …" with a "Try again" button.
  const MStateMessage.error({super.key, this.message, required VoidCallback? onRetry, this.title, this.scrollable = true, this.top = 96})
      : kind = MStateKind.error,
        icon = null,
        art = null,
        actionLabel = null,
        actionIcon = null,
        onAction = onRetry,
        action = null,
        centered = false;

  /// "You are offline" with a "Try again" button.
  const MStateMessage.offline({super.key, this.message, required VoidCallback? onRetry, this.title, this.scrollable = true, this.top = 96})
      : kind = MStateKind.offline,
        icon = null,
        art = MArtKind.offline,
        actionLabel = null,
        actionIcon = null,
        onAction = onRetry,
        action = null,
        centered = false;

  /// Empty, error or offline.
  final MStateKind kind;

  /// One or two short sentences. Errors and offline states have a default sentence.
  final String? message;

  /// Optional heading.
  final String? title;

  /// An icon in a soft circle (used when no illustration fits it).
  final IconData? icon;

  /// An illustration; chosen from [icon] when not given (see [MEmptyArt.forIcon]).
  final MArtKind? art;

  /// The action's text. Defaults to "Try again" for errors.
  final String? actionLabel;

  /// The action's icon. Defaults to a refresh arrow for a retry.
  final IconData? actionIcon;

  /// The action. No button without it.
  final VoidCallback? onAction;

  /// A custom action widget instead of the button.
  final Widget? action;

  /// Wrap in an always-scrollable list (for pull to refresh).
  final bool scrollable;

  /// Space above the content.
  final double top;

  /// Centre the content vertically in the available height (instead of [top]).
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    final problem = kind != MStateKind.empty;
    final drawing = art ?? (icon != null ? MEmptyArt.forIcon(icon!) : (kind == MStateKind.empty ? null : MArtKind.offline));
    final retry = problem && actionLabel == null;
    final text = message ??
        (kind == MStateKind.offline
            ? tr(context, 'You are offline. Check your connection and try again.', 'Olet offline-tilassa. Tarkista yhteys ja yritä uudelleen.')
            : tr(context, 'Could not load this. Check your connection and try again.', 'Lataus epäonnistui. Tarkista yhteys ja yritä uudelleen.'));
    final content = Padding(
      padding: EdgeInsets.fromLTRB(MSpace.x4l, centered ? MSpace.x3l : top, MSpace.x4l, MSpace.x4l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (drawing != null)
            MEmptyArt(drawing)
          else
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(color: problem ? c.sunshineSoft : c.primarySoft, shape: BoxShape.circle),
              child: Icon(icon ?? Icons.inbox_outlined, size: 38, color: problem ? c.onSunshineSoft : c.onPrimarySoft),
            ),
          const SizedBox(height: MSpace.lg),
          if (title != null) ...[
            Semantics(header: true, child: Text(title!, textAlign: TextAlign.center, style: MType.displayS.copyWith(fontSize: 20, color: c.onSurface))),
            const SizedBox(height: 6),
          ],
          Semantics(
            liveRegion: problem,
            child: Text(text, textAlign: TextAlign.center, style: MType.bodyL.copyWith(fontSize: 15, color: c.onSurfaceVariant, height: 1.4)),
          ),
          if (action != null) ...[
            const SizedBox(height: 18),
            action!,
          ] else if (onAction != null) ...[
            const SizedBox(height: 18),
            MButton(
              variant: MButtonVariant.secondary,
              size: MButtonSize.sm,
              icon: actionIcon ?? (retry ? Icons.refresh_rounded : Icons.arrow_forward_rounded),
              label: actionLabel ?? tr(context, 'Try again', 'Yritä uudelleen'),
              onPressed: () {
                Haptics.selection();
                onAction!();
              },
            ),
          ],
        ],
      ),
    );
    if (!scrollable) {
      // Inside a list (unbounded height) it simply takes its size; in a fixed box it can scroll
      return LayoutBuilder(
        builder: (context, box) => box.maxHeight.isFinite ? Center(child: SingleChildScrollView(child: content)) : Center(child: content),
      );
    }
    return LayoutBuilder(
      builder: (context, box) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight.isFinite ? box.maxHeight * (centered ? 1 : 0.6) : 0),
            child: Align(alignment: centered ? Alignment.center : Alignment.topCenter, child: content),
          ),
        ],
      ),
    );
  }
}
