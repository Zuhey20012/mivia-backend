// Golden tests: every component in light, dark, Finnish and large text.
// Create or update the PNGs with: flutter test --update-goldens test/goldens_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import 'helpers.dart';

void main() {
  testWidgets('tokens: colours and type scale', (tester) async {
    await expectGolden(tester, 'tokens', paneHeight: 420, (context) {
      final c = context.mColors;
      Widget swatch(String name, Color bg, Color fg) => Container(
            width: 78,
            height: 40,
            margin: const EdgeInsets.only(right: 4, bottom: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, borderRadius: MRadius.brXs, border: Border.all(color: c.outline)),
            child: Text(name, style: MType.caption.copyWith(color: fg, fontSize: 10)),
          );
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(children: [
          swatch('primary', c.primary, c.onPrimary),
          swatch('primarySoft', c.primarySoft, c.onPrimarySoft),
          swatch('sunshine', c.sunshine, c.onSunshine),
          swatch('success', c.successSoft, c.onSuccessSoft),
          swatch('warning', c.warningSoft, c.onWarningSoft),
          swatch('danger', c.dangerSoft, c.onDangerSoft),
          swatch('surface', c.surface, c.onSurface),
          swatch('variant', c.surfaceVariant, c.onSurfaceVariant),
        ]),
        const SizedBox(height: MSpace.sm),
        for (final e in MType.all.entries) Text(tr(context, 'Birch ${e.key}', 'Koivu ${e.key}'), style: e.value.copyWith(color: c.onSurface)),
      ]);
    });
  });

  testWidgets('MButton', (tester) async {
    await expectGolden(tester, 'button', paneHeight: 420, (context) {
      final label = tr(context, 'Pay', 'Maksa');
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        MButton(label: tr(context, 'Place order', 'Tee tilaus'), icon: Icons.lock_rounded, expand: true, onPressed: () {}),
        const SizedBox(height: MSpace.sm),
        Wrap(spacing: MSpace.sm, runSpacing: MSpace.sm, children: [
          MButton(label: label, onPressed: () {}, variant: MButtonVariant.secondary),
          MButton(label: label, onPressed: () {}, variant: MButtonVariant.outline),
          MButton(label: tr(context, 'Delete', 'Poista'), onPressed: () {}, variant: MButtonVariant.danger),
          MButton(label: tr(context, 'Skip', 'Ohita'), onPressed: () {}, variant: MButtonVariant.text),
          MButton(label: label, onPressed: () {}, size: MButtonSize.sm),
          MButton(label: label, onPressed: () {}, size: MButtonSize.lg, icon: Icons.arrow_forward_rounded, trailingIcon: true),
          MButton(label: label, onPressed: null),
          MButton(label: label, onPressed: () {}, loading: true),
        ]),
      ]);
    });
  });

  testWidgets('MTextField', (tester) async {
    await expectGolden(tester, 'text_field', paneHeight: 330, (context) {
      return Column(children: [
        MTextField(label: tr(context, 'Email', 'Sähköposti'), prefixIcon: Icons.mail_outline_rounded, controller: TextEditingController(text: 'aino@example.fi')),
        const SizedBox(height: MSpace.md),
        MTextField(label: tr(context, 'Password', 'Salasana'), obscure: true, controller: TextEditingController(text: 'secret12'),
            errorText: tr(context, 'Password must be at least 8 characters', 'Salasanassa on oltava vähintään 8 merkkiä.')),
        const SizedBox(height: MSpace.md),
        MTextField(label: tr(context, 'Postal code', 'Postinumero'), enabled: false, helper: tr(context, 'From your address', 'Osoitteestasi')),
      ]);
    });
  });

  testWidgets('MSheet', (tester) async {
    await expectGolden(tester, 'sheet', paneHeight: 330, (context) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: MSheet(
          handle: true,
          title: tr(context, 'Choose a delivery time', 'Valitse toimitusaika'),
          subtitle: tr(context, 'Today or tomorrow', 'Tänään tai huomenna'),
          actions: [MButton(label: tr(context, 'Confirm', 'Vahvista'), expand: true, onPressed: () {})],
          child: Text(tr(context, 'Tonight 17:00–19:00', 'Tänä iltana 17.00–19.00')),
        ),
      );
    });
  });

  testWidgets('MChip and MFilterBar', (tester) async {
    await expectGolden(tester, 'chip_filter_bar', paneHeight: 220, (context) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: MSpace.sm, children: [
          MChip(label: tr(context, 'Open now', 'Auki nyt'), onSelected: (_) {}),
          MChip(label: tr(context, 'Pickup', 'Nouto'), selected: true, onSelected: (_) {}),
          MChip(label: tr(context, 'Sold out', 'Loppu'), icon: Icons.block_rounded),
        ]),
        const SizedBox(height: MSpace.sm),
        MFilterBar(
          padding: EdgeInsets.zero,
          onOpenFilters: () {},
          sortLabel: tr(context, 'Nearest', 'Lähin'),
          onSort: () {},
          active: [const MFilterOption(id: 'm', label: 'M'), MFilterOption(id: 'black', label: tr(context, 'Black', 'Musta'))],
          onRemove: (_) {},
          onClearAll: () {},
        ),
      ]);
    });
  });

  testWidgets('MSkeleton presets', (tester) async {
    await expectGolden(tester, 'skeleton', paneHeight: 300, (context) {
      return const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: SizedBox(height: 260, child: MSkeletonList(count: 2, thumbnail: true, padding: EdgeInsets.zero))),
        SizedBox(width: MSpace.md),
        SizedBox(width: 110, height: 200, child: MSkeletonProductTile()),
      ]);
    });
  });

  testWidgets('MStateMessage', (tester) async {
    await expectGolden(tester, 'state_message', paneHeight: 720, (context) {
      return Column(children: [
        Expanded(
          child: MStateMessage(
            scrollable: false,
            top: 0,
            art: MArtKind.bag,
            title: tr(context, 'Your bag is empty', 'Kassisi on tyhjä'),
            message: tr(context, 'Find something you love nearby.', 'Löydä jotain ihanaa läheltä.'),
            actionLabel: tr(context, 'Browse', 'Selaa'),
            onAction: () {},
          ),
        ),
        Expanded(
          child: MStateMessage.error(
            scrollable: false,
            top: 0,
            message: tr(context, 'Could not load your orders.', 'Tilauksia ei voitu ladata.'),
            onRetry: () {},
          ),
        ),
      ]);
    });
  });

  testWidgets('MSnack', (tester) async {
    await expectGolden(tester, 'snack', paneHeight: 230, (context) {
      return Column(children: [
        for (final k in MSnackKind.values)
          Padding(
            padding: const EdgeInsets.only(bottom: MSpace.sm),
            child: _SnackPreview(MSnack.build(context, switch (k) {
              MSnackKind.success => tr(context, 'Saved', 'Tallennettu'),
              MSnackKind.info => tr(context, 'Added to your bag', 'Lisätty ostoskassiin'),
              MSnackKind.error => tr(context, 'Could not reach Malvoya.', 'Malvoyaan ei saatu yhteyttä.'),
            }, kind: k, actionLabel: k == MSnackKind.info ? tr(context, 'View', 'Näytä') : null)),
          ),
      ]);
    });
  });

  testWidgets('MPrice and MUnitPrice', (tester) async {
    await expectGolden(tester, 'price', paneHeight: 230, (context) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const MPrice(cents: 4990, size: MPriceSize.lg),
        const SizedBox(height: MSpace.sm),
        const MPrice(cents: 3990, previousCents: 4990, discountPct: 20, showReferenceLabel: true),
        const SizedBox(height: MSpace.sm),
        MPrice(cents: 1780, unitPrice: UnitPrice.compute(1780, 100, 'ml')),
        MUnitPrice.forContent(450, 250, 'g'),
      ]);
    });
  });

  testWidgets('MBadge', (tester) async {
    await expectGolden(tester, 'badge', paneHeight: 120, (context) {
      return Wrap(spacing: MSpace.sm, runSpacing: MSpace.sm, children: [
        MBadge(tr(context, 'New', 'Uusi'), tone: MBadgeTone.sunshine, strong: true),
        MBadge(tr(context, 'Paid', 'Maksettu'), tone: MBadgeTone.success, icon: Icons.check_rounded),
        MBadge(tr(context, 'Waiting', 'Odottaa'), tone: MBadgeTone.warning),
        MBadge(tr(context, 'Cancelled', 'Peruttu'), tone: MBadgeTone.danger),
        MBadge(tr(context, 'Video', 'Video'), tone: MBadgeTone.neutral, icon: Icons.play_arrow_rounded),
        const MBadge('Malva'),
        MBadge.count(3),
        MBadge.count(120, tone: MBadgeTone.danger),
      ]);
    });
  });

  testWidgets('MListTile and MSectionHeader', (tester) async {
    await expectGolden(tester, 'list_tile', paneHeight: 300, (context) {
      return Column(children: [
        MSectionHeader(tr(context, 'Account', 'Tili'), actionLabel: tr(context, 'Edit', 'Muokkaa'), onAction: () {}, padding: EdgeInsets.zero),
        MListTile(icon: Icons.receipt_long_outlined, title: tr(context, 'Orders', 'Tilaukset'), subtitle: tr(context, '2 on their way', '2 matkalla'), onTap: () {}),
        MListTile(icon: Icons.language_rounded, title: tr(context, 'Language', 'Kieli'), trailing: Switch(value: true, onChanged: (_) {})),
        MListTile(icon: Icons.delete_outline_rounded, title: tr(context, 'Delete account', 'Poista tili'), destructive: true, onTap: () {}),
      ]);
    });
  });

  testWidgets('MSwipeConfirm', (tester) async {
    await expectGolden(tester, 'swipe_confirm', paneHeight: 200, brand: MPalette.lingon, (context) {
      return Column(children: [
        MSwipeConfirm(label: tr(context, 'Slide to confirm pickup', 'Liu\'uta: nouto tehty'), onConfirmed: () async {}),
        const SizedBox(height: MSpace.md),
        MSwipeConfirm(label: tr(context, 'Delivered', 'Toimitettu'), busy: true, onConfirmed: () async {}),
      ]);
    });
  });

  testWidgets('MSwatchPicker', (tester) async {
    await expectGolden(tester, 'swatch_picker', paneHeight: 170, (context) {
      return MSwatchPicker(
        selectedId: '2',
        onChanged: (_) {},
        options: const [
          MSwatchOption(id: '1', name: 'Porcelain 01', color: Color(0xFFF6E3D3)),
          MSwatchOption(id: '2', name: 'Rose 02', color: Color(0xFFC96F7A)),
          MSwatchOption(id: '3', name: 'Berry 03', color: Color(0xFF7A1F3D), soldOut: true),
          MSwatchOption(id: '4', name: 'Nude 04', color: Color(0xFFD9A48C)),
          MSwatchOption(id: '5', name: 'Cocoa 05', color: Color(0xFF5A3A2E)),
          MSwatchOption(id: '6', name: 'White', color: Color(0xFFFFFFFF)),
        ],
      );
    });
  });

  testWidgets('MSizeSelector', (tester) async {
    await expectGolden(tester, 'size_selector', paneHeight: 240, (context) {
      return MSizeSelector(
        selectedId: 'm',
        onChanged: (_) {},
        onSizeGuide: () {},
        options: const [
          MSizeOption(id: 'xs', label: 'XS', soldOut: true),
          MSizeOption(id: 's', label: 'S'),
          MSizeOption(id: 'm', label: 'M'),
          MSizeOption(id: 'l', label: 'L'),
          MSizeOption(id: 'xl', label: 'XL'),
          MSizeOption(id: '38', label: '38 · Black'),
        ],
      );
    });
  });

  testWidgets('BrandMark and EmptyArt', (tester) async {
    await expectGolden(tester, 'brand_art', paneHeight: 160, (context) {
      return Wrap(spacing: MSpace.sm, runSpacing: MSpace.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
        const BrandTile(size: 56, background: MPalette.malva),
        const BrandTile(size: 56, background: MPalette.moss),
        const BrandTile(size: 56, background: MPalette.lingon),
        for (final k in [MArtKind.orders, MArtKind.search, MArtKind.delivery]) MEmptyArt(k, width: 90),
      ]);
    });
  });
}

/// A SnackBar drawn in place (snackbars normally float over a Scaffold).
class _SnackPreview extends StatelessWidget {
  final SnackBar bar;
  const _SnackPreview(this.bar);

  @override
  Widget build(BuildContext context) => Material(
        color: bar.backgroundColor,
        shape: bar.shape,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.md, MSpace.sm, MSpace.md),
          child: Row(children: [
            Expanded(child: bar.content),
            if (bar.action != null) TextButton(onPressed: () {}, child: Text(bar.action!.label, style: TextStyle(color: bar.action!.textColor))),
          ]),
        ),
      );
}
