import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';

void main() {
  registerMalvoyaFontLicenses();
  runApp(const GalleryApp());
}

/// The Birch Market gallery: every component, switchable between light/dark, English/Finnish,
/// normal/large text and the three app brands.
class GalleryApp extends StatefulWidget {
  const GalleryApp({super.key});

  @override
  State<GalleryApp> createState() => _GalleryAppState();
}

class _GalleryAppState extends State<GalleryApp> {
  Color _brand = MPalette.malva;
  bool _dark = false;
  bool _finnish = false;
  bool _largeText = false;

  @override
  Widget build(BuildContext context) {
    final style = _brand == MPalette.malva ? MalvoyaThemeStyle.shop : MalvoyaThemeStyle.tool;
    return MaterialApp(
      title: 'Birch Market',
      debugShowCheckedModeBanner: false,
      theme: buildMalvoyaTheme(brand: _brand, brightness: Brightness.light, style: style),
      darkTheme: buildMalvoyaTheme(brand: _brand, brightness: Brightness.dark, style: style),
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      locale: Locale(_finnish ? 'fi' : 'en'),
      supportedLocales: const [Locale('en'), Locale('fi')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(_largeText ? 1.3 : 1)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Birch Market')),
          body: ListView(
            padding: const EdgeInsets.only(bottom: MSpace.x4l),
            children: [
              _Controls(
                brand: _brand,
                dark: _dark,
                finnish: _finnish,
                largeText: _largeText,
                onBrand: (b) => setState(() => _brand = b),
                onDark: (v) => setState(() => _dark = v),
                onFinnish: (v) => setState(() {
                  _finnish = v;
                  AppLanguage.code = v ? 'fi' : 'en';
                }),
                onLargeText: (v) => setState(() => _largeText = v),
              ),
              const _Tokens(),
              const _Buttons(),
              const _Fields(),
              const _Chips(),
              const _Commerce(),
              const _Feedback(),
              const _Lists(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  final Color brand;
  final bool dark, finnish, largeText;
  final ValueChanged<Color> onBrand;
  final ValueChanged<bool> onDark, onFinnish, onLargeText;
  const _Controls({
    required this.brand,
    required this.dark,
    required this.finnish,
    required this.largeText,
    required this.onBrand,
    required this.onDark,
    required this.onFinnish,
    required this.onLargeText,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: MSpace.lg),
        child: Wrap(spacing: MSpace.sm, runSpacing: MSpace.sm, children: [
          for (final (name, color) in const [('Malva', MPalette.malva), ('Moss', MPalette.moss), ('Lingon', MPalette.lingon)])
            MChip(label: name, selected: brand == color, onSelected: (_) => onBrand(color)),
          MChip(label: 'Dark', selected: dark, onSelected: onDark),
          MChip(label: 'Suomi', selected: finnish, onSelected: onFinnish),
          MChip(label: 'Text 1.3', selected: largeText, onSelected: onLargeText),
        ]),
      );
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section(this.title, this.children);

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MSectionHeader(title),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: MSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        ),
      ]);
}

class _Tokens extends StatelessWidget {
  const _Tokens();

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    final roles = <(String, Color, Color)>[
      ('primary', c.primary, c.onPrimary),
      ('primarySoft', c.primarySoft, c.onPrimarySoft),
      ('sunshine', c.sunshine, c.onSunshine),
      ('sunshineSoft', c.sunshineSoft, c.onSunshineSoft),
      ('success', c.success, c.onSuccess),
      ('successSoft', c.successSoft, c.onSuccessSoft),
      ('warningSoft', c.warningSoft, c.onWarningSoft),
      ('danger', c.danger, c.onDanger),
      ('dangerSoft', c.dangerSoft, c.onDangerSoft),
      ('surface', c.surface, c.onSurface),
      ('surfaceVariant', c.surfaceVariant, c.onSurfaceVariant),
      ('inverse', c.inverseSurface, c.onInverseSurface),
    ];
    final p = context.mPastels;
    return _Section(tr(context, 'Tokens', 'Tokenit'), [
      Wrap(spacing: MSpace.xs, runSpacing: MSpace.xs, children: [
        for (final (name, bg, fg) in roles)
          Container(
            width: 104,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, borderRadius: MRadius.brSm, border: Border.all(color: c.outline)),
            child: Text(name, style: MType.caption.copyWith(color: fg)),
          ),
      ]),
      const SizedBox(height: MSpace.md),
      Row(children: [
        for (final tile in p.all)
          Expanded(child: Container(height: 40, margin: const EdgeInsets.only(right: MSpace.xs), decoration: BoxDecoration(color: tile, borderRadius: MRadius.brSm))),
      ]),
      const SizedBox(height: MSpace.md),
      for (final e in MType.all.entries) Text('${e.key} · Koivumarkkinat', style: e.value),
      const SizedBox(height: MSpace.md),
      Row(children: [
        for (final level in MElevation.values)
          Expanded(
            child: Container(
              height: 56,
              margin: const EdgeInsets.only(right: MSpace.md),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: c.surface, borderRadius: MRadius.brMd, boxShadow: context.mTokens.shadow(level)),
              child: Text(level.name, style: MType.label),
            ),
          ),
      ]),
    ]);
  }
}

class _Buttons extends StatefulWidget {
  const _Buttons();

  @override
  State<_Buttons> createState() => _ButtonsState();
}

class _ButtonsState extends State<_Buttons> {
  bool _loading = false;

  Future<void> _pay() async {
    setState(() => _loading = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) => _Section(tr(context, 'Buttons', 'Painikkeet'), [
        MButton(label: tr(context, 'Pay 49,90 €', 'Maksa 49,90 €'), icon: Icons.lock_rounded, expand: true, loading: _loading, onPressed: _pay),
        const SizedBox(height: MSpace.sm),
        Wrap(spacing: MSpace.sm, runSpacing: MSpace.sm, children: [
          for (final v in MButtonVariant.values) MButton(label: v.name, variant: v, onPressed: () {}),
          for (final s in MButtonSize.values) MButton(label: s.name, size: s, onPressed: () {}),
          MButton(label: tr(context, 'Disabled', 'Ei käytössä'), onPressed: null),
        ]),
        const SizedBox(height: MSpace.md),
        MSwipeConfirm(
          label: tr(context, 'Slide to confirm pickup', 'Liu\'uta: nouto tehty'),
          onConfirmed: () async => MSnack.success(context, tr(context, 'Picked up', 'Noudettu')),
        ),
      ]);
}

class _Fields extends StatelessWidget {
  const _Fields();

  @override
  Widget build(BuildContext context) => _Section(tr(context, 'Text fields', 'Tekstikentät'), [
        MTextField(label: tr(context, 'Email', 'Sähköposti'), prefixIcon: Icons.mail_outline_rounded, keyboardType: TextInputType.emailAddress),
        const SizedBox(height: MSpace.md),
        MTextField(label: tr(context, 'Password', 'Salasana'), obscure: true),
        const SizedBox(height: MSpace.md),
        MTextField(label: tr(context, 'Postal code', 'Postinumero'), errorText: tr(context, 'A Finnish postal code has 5 digits', 'Suomalaisessa postinumerossa on 5 numeroa.')),
      ]);
}

class _Chips extends StatefulWidget {
  const _Chips();

  @override
  State<_Chips> createState() => _ChipsState();
}

class _ChipsState extends State<_Chips> {
  bool _open = true;
  final _active = <String, String>{'m': 'M', 'black': 'Black'};

  @override
  Widget build(BuildContext context) => _Section(tr(context, 'Chips and filters', 'Sirut ja suodattimet'), [
        MFilterBar(
          padding: EdgeInsets.zero,
          onOpenFilters: () {},
          sortLabel: tr(context, 'Nearest', 'Lähin'),
          onSort: () {},
          quick: [MFilterOption(id: 'open', label: tr(context, 'Open now', 'Auki nyt'), selected: _open)],
          onQuickChanged: (_, v) => setState(() => _open = v),
          active: [for (final e in _active.entries) MFilterOption(id: e.key, label: e.value)],
          onRemove: (id) => setState(() => _active.remove(id)),
          onClearAll: () => setState(_active.clear),
        ),
      ]);
}

class _Commerce extends StatefulWidget {
  const _Commerce();

  @override
  State<_Commerce> createState() => _CommerceState();
}

class _CommerceState extends State<_Commerce> {
  String? _shade = '2';
  String? _size;

  @override
  Widget build(BuildContext context) => _Section(tr(context, 'Shopping', 'Ostaminen'), [
        const MPrice(cents: 3990, previousCents: 4990, discountPct: 20, size: MPriceSize.lg, showReferenceLabel: true),
        const SizedBox(height: MSpace.sm),
        MPrice(cents: 2490, unitPrice: UnitPrice.compute(2490, 150, 'ml')),
        const SizedBox(height: MSpace.lg),
        MSwatchPicker(
          selectedId: _shade,
          onChanged: (id) => setState(() => _shade = id),
          options: const [
            MSwatchOption(id: '1', name: 'Porcelain 01', color: Color(0xFFF6E3D3)),
            MSwatchOption(id: '2', name: 'Rose 02', color: Color(0xFFC96F7A)),
            MSwatchOption(id: '3', name: 'Berry 03', color: Color(0xFF7A1F3D), soldOut: true),
            MSwatchOption(id: '4', name: 'Cocoa 05', color: Color(0xFF5A3A2E)),
          ],
        ),
        const SizedBox(height: MSpace.lg),
        MSizeSelector(
          selectedId: _size,
          onChanged: (id) => setState(() => _size = id),
          onSizeGuide: () => showMSheet<void>(
            context,
            builder: (_) => MSheet(title: tr(context, 'Size guide (EU)', 'Kokotaulukko (EU)'), child: const Text('XS 32–34 · S 36–38 · M 40–42 · L 44–46')),
          ),
          options: const [
            MSizeOption(id: 'xs', label: 'XS', soldOut: true),
            MSizeOption(id: 's', label: 'S'),
            MSizeOption(id: 'm', label: 'M'),
            MSizeOption(id: 'l', label: 'L'),
          ],
        ),
        const SizedBox(height: MSpace.lg),
        Wrap(spacing: MSpace.sm, runSpacing: MSpace.sm, children: [
          for (final t in MBadgeTone.values) MBadge(t.name, tone: t),
          MBadge.count(3),
        ]),
      ]);
}

class _Feedback extends StatelessWidget {
  const _Feedback();

  @override
  Widget build(BuildContext context) => _Section(tr(context, 'Feedback', 'Palaute'), [
        Wrap(spacing: MSpace.sm, runSpacing: MSpace.sm, children: [
          for (final k in MSnackKind.values) MButton(label: k.name, variant: MButtonVariant.outline, size: MButtonSize.sm, onPressed: () => MSnack.show(context, k.name, kind: k)),
          MButton(
            label: tr(context, 'Sheet', 'Arkki'),
            variant: MButtonVariant.outline,
            size: MButtonSize.sm,
            onPressed: () => showMSheet<void>(
              context,
              transparent: true,
              builder: (ctx) => MSheet(
                handle: true,
                title: tr(context, 'Start a new bag?', 'Aloitetaanko uusi ostoskassi?'),
                actions: [MButton(label: tr(context, 'New bag', 'Uusi kassi'), expand: true, onPressed: () => Navigator.pop(ctx))],
                child: Text(tr(context, 'One order comes from one store.', 'Yksi tilaus tulee yhdestä kaupasta.')),
              ),
            ),
          ),
        ]),
        const SizedBox(height: MSpace.md),
        const SizedBox(height: 220, child: MSkeletonList(count: 2, thumbnail: true, padding: EdgeInsets.zero)),
        SizedBox(
          height: 360,
          child: MStateMessage(
            top: MSpace.lg,
            art: MArtKind.orders,
            title: tr(context, 'No orders yet', 'Ei vielä tilauksia'),
            message: tr(context, 'Your orders appear here.', 'Tilauksesi näkyvät tässä.'),
          ),
        ),
      ]);
}

class _Lists extends StatelessWidget {
  const _Lists();

  @override
  Widget build(BuildContext context) => _Section(tr(context, 'Lists', 'Listat'), [
        MListTile(icon: Icons.receipt_long_outlined, title: tr(context, 'Orders', 'Tilaukset'), subtitle: tr(context, '2 on their way', '2 matkalla'), onTap: () {}),
        MListTile(icon: Icons.delete_outline_rounded, title: tr(context, 'Delete account', 'Poista tili'), destructive: true, onTap: () {}),
        const SizedBox(height: MSpace.md),
        const Row(children: [BrandTile(size: 56, background: MPalette.malva), SizedBox(width: 8), BrandTile(size: 56, background: MPalette.moss), SizedBox(width: 8), BrandTile(size: 56, background: MPalette.lingon)]),
      ]);
}
