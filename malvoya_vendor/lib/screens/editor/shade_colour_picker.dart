import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';

/// "#RRGGBB" for a colour.
String hexOf(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Typical make-up and nail shades to start from (skin tones light to deep, lips, nails).
const _presets = [
  '#F6DCC8', '#EFC9AE', '#E4B591', '#D4A07A', '#C18A63', '#A86F4C', '#8B5638', '#6B3F27', '#4A2A1A',
  '#E8A3A0', '#D9777A', '#C2414B', '#A3243B', '#7E1F3A', '#5C1A33', '#C96F5A', '#E07B5F', '#B5651D',
  '#F2C6D3', '#E58FB0', '#9E4F7F', '#6A3D7A', '#2E3A87', '#2E6B4F', '#111111', '#FFFFFF', '#D4AF37',
];

/// A swatch-colour picker for one shade: a preview, hue / saturation / brightness sliders, a hex
/// field and starting presets. Colour is never the only cue: the sheet always shows the hex too.
Future<String?> pickShadeColour(BuildContext context, {String? initial, String? shadeName}) {
  return showMSheet<String>(context, builder: (ctx) => _ShadeColourSheet(initial: initial, shadeName: shadeName));
}

class _ShadeColourSheet extends StatefulWidget {
  final String? initial;
  final String? shadeName;
  const _ShadeColourSheet({this.initial, this.shadeName});

  @override
  State<_ShadeColourSheet> createState() => _ShadeColourSheetState();
}

class _ShadeColourSheetState extends State<_ShadeColourSheet> {
  late HSVColor _hsv = HSVColor.fromColor(colorFromHex(widget.initial) ?? colorFromHex('#D4A07A')!);
  late final _hex = TextEditingController(text: hexOf(_hsv.toColor()));
  String? _hexError;

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _set(HSVColor v) => setState(() {
        _hsv = v;
        _hex.text = hexOf(v.toColor());
        _hexError = null;
      });

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    final colour = _hsv.toColor();
    Widget slider(String label, double value, double max, ValueChanged<double> onChanged, String valueText) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$label · $valueText', style: MType.label),
            Slider(value: value, max: max, onChanged: onChanged, label: valueText, semanticFormatterCallback: (_) => valueText),
          ],
        );
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(MSpace.xxl, 0, MSpace.xxl, MediaQuery.viewInsetsOf(context).bottom + MSpace.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(
            widget.shadeName?.trim().isNotEmpty == true
                ? tr(context, 'Swatch colour: ${widget.shadeName}', 'Sävynäyte: ${widget.shadeName}')
                : tr(context, 'Swatch colour', 'Sävynäyte'),
            style: MType.displayS,
          ),
          const SizedBox(height: MSpace.xs),
          Text(
            tr(context, 'Match the colour to a daylight photo of the swatch. Shoppers see a note that colours vary by screen.',
                'Sovita väri päivänvalossa otettuun kuvaan sävynäytteestä. Asiakkaat näkevät huomautuksen, että värit voivat näyttää erilaisilta eri näytöillä.'),
            style: MType.caption.copyWith(color: c.onSurfaceVariant),
          ),
          const SizedBox(height: MSpace.md),
          Row(children: [
            MSwatch(color: colour, name: hexOf(colour), size: 64, selected: true),
            const SizedBox(width: MSpace.lg),
            Expanded(
              child: MTextField(
                controller: _hex,
                label: tr(context, 'Hex code', 'Hex-koodi'),
                errorText: _hexError,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')), LengthLimitingTextInputFormatter(7)],
                onChanged: (v) {
                  final parsed = colorFromHex(v.startsWith('#') ? v : '#$v');
                  setState(() {
                    if (parsed != null) _hsv = HSVColor.fromColor(parsed);
                    _hexError = parsed == null && v.replaceAll('#', '').length == 6 ? tr(context, 'Use six characters, e.g. #C2414B', 'Käytä kuutta merkkiä, esim. #C2414B') : null;
                  });
                },
              ),
            ),
          ]),
          const SizedBox(height: MSpace.md),
          slider(tr(context, 'Hue', 'Sävy'), _hsv.hue, 360, (v) => _set(_hsv.withHue(v)), '${_hsv.hue.round()}°'),
          slider(tr(context, 'Saturation', 'Kylläisyys'), _hsv.saturation, 1, (v) => _set(_hsv.withSaturation(v)), '${(_hsv.saturation * 100).round()} %'),
          slider(tr(context, 'Brightness', 'Kirkkaus'), _hsv.value, 1, (v) => _set(_hsv.withValue(v)), '${(_hsv.value * 100).round()} %'),
          const SizedBox(height: MSpace.sm),
          Text(tr(context, 'Start from', 'Aloita sävystä'), style: MType.label),
          const SizedBox(height: MSpace.xs),
          Wrap(spacing: 0, runSpacing: 0, children: [
            for (final p in _presets)
              MSwatch(color: colorFromHex(p)!, name: p, size: 32, selected: hexOf(colour) == p, onTap: () => _set(HSVColor.fromColor(colorFromHex(p)!))),
          ]),
          const SizedBox(height: MSpace.lg),
          MButton(
            label: tr(context, 'Use this colour', 'Käytä tätä väriä'),
            expand: true,
            onPressed: () => Navigator.pop(context, hexOf(_hsv.toColor())),
          ),
        ]),
      ),
    );
  }
}
