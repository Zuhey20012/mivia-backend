import 'package:flutter_test/flutter_test.dart';
import 'package:malvoya_core/malvoya_core.dart';

/// NumberFormat uses no-break spaces in Finnish ("1 249,90 €").
String plain(String s) => s.replaceAll(' ', ' ').replaceAll(' ', ' ');

void main() {
  group('formatEuro', () {
    test('Finnish: comma decimals, space groups, symbol after', () {
      expect(plain(formatEuro(4990, languageCode: 'fi')), '49,90 €');
      expect(plain(formatEuro(124990, languageCode: 'fi')), '1 249,90 €');
      expect(plain(formatEuro(0, languageCode: 'fi')), '0,00 €');
    });

    test('English: symbol first, point decimals', () {
      expect(formatEuro(4990, languageCode: 'en'), '€49.90');
      expect(formatEuro(124990, languageCode: 'en'), '€1,249.90');
    });

    test('null counts as zero and whole euros can drop the cents', () {
      expect(formatEuro(null, languageCode: 'en'), '€0.00');
      expect(formatEuro(1500, languageCode: 'en', showCents: false), '€15');
    });

    test('follows AppLanguage when no language is given', () {
      AppLanguage.code = 'en';
      expect(formatEuro(199), '€1.99');
      AppLanguage.code = 'fi';
      expect(plain(formatEuro(199)), '1,99 €');
    });
  });

  group('UnitPrice', () {
    test('per litre and per kilogram, like the API', () {
      // 17,80 € for 100 ml → 178,00 €/l
      expect(UnitPrice.compute(1780, 100, 'ml'), const UnitPrice(17800, 'l'));
      // 4,50 € for 250 g → 18,00 €/kg
      expect(UnitPrice.compute(450, 250, 'g'), const UnitPrice(1800, 'kg'));
      // Rounded to the cent: 9,99 € / 75 ml = 133,2 €/l
      expect(UnitPrice.compute(999, 75, 'ml')!.cents, 13320);
    });

    test('none for pieces, missing content or under 50 ml / 50 g', () {
      expect(UnitPrice.compute(1000, 3, 'pcs'), isNull);
      expect(UnitPrice.compute(1000, null, 'ml'), isNull);
      expect(UnitPrice.compute(1000, 0, 'ml'), isNull);
      expect(UnitPrice.compute(1000, 49, 'g'), isNull);
      expect(UnitPrice.compute(null, 100, 'ml'), isNull);
      expect(UnitPrice.compute(1000, 50, 'g'), isNotNull);
    });

    test('a reduced price gives a reduced unit price', () {
      final full = UnitPrice.compute(2000, 200, 'ml')!;
      final sale = UnitPrice.compute(1500, 200, 'ml')!;
      expect(sale.cents, lessThan(full.cents));
    });

    test('text in both languages', () {
      const u = UnitPrice(17800, 'l');
      expect(plain(u.format(languageCode: 'fi')), '178,00 €/l');
      expect(u.format(languageCode: 'en'), '€178.00/l');
    });

    test('reads the API object and rejects anything else', () {
      expect(UnitPrice.fromJson({'cents': 1800, 'per': 'kg'}), const UnitPrice(1800, 'kg'));
      expect(UnitPrice.fromJson({'cents': '1800', 'per': 'l'}), const UnitPrice(1800, 'l'));
      expect(UnitPrice.fromJson({'cents': 1800, 'per': '100g'}), isNull);
      expect(UnitPrice.fromJson(null), isNull);
    });
  });

  group('dates', () {
    test('formatDate', () {
      final d = DateTime(2026, 11, 3, 14, 5);
      expect(formatDate(d, languageCode: 'fi'), '3.11.2026');
      expect(formatDate(d, languageCode: 'en'), '3 November 2026');
      expect(formatDate(d, languageCode: 'en', short: true), '3 Nov 2026');
      expect(formatClock(d, languageCode: 'fi'), '14.05');
      expect(formatClock(d, languageCode: 'en'), '14:05');
    });

    test('scheduled window names today, tonight and tomorrow', () {
      final now = DateTime(2026, 10, 22, 12);
      final tonight = DateTime(2026, 10, 22, 17).toIso8601String();
      final tonightEnd = DateTime(2026, 10, 22, 19).toIso8601String();
      expect(scheduledWindowText(tonight, tonightEnd, languageCode: 'en', now: now), 'Tonight 17:00–19:00');
      expect(scheduledWindowText(tonight, tonightEnd, languageCode: 'fi', now: now), 'Tänä iltana 17.00–19.00');
      final tomorrow = DateTime(2026, 10, 23, 17).toIso8601String();
      final tomorrowEnd = DateTime(2026, 10, 23, 19).toIso8601String();
      expect(scheduledWindowText(tomorrow, tomorrowEnd, languageCode: 'fi', now: now), 'Huomenna 17.00–19.00');
      expect(scheduledWindowText(null, tomorrowEnd, now: now), isNull);
    });

    test('etaWindow', () {
      expect(etaWindow({'etaMinutes': 25, 'etaMaxMinutes': 35}), '25–35 min');
      expect(etaWindow({'etaMinutes': 25.4}), '25 min');
      expect(etaWindow({}), isNull);
    });
  });

  test('asInt and localizedFor', () {
    expect(asInt(3), 3);
    expect(asInt(3.7), 3);
    expect(asInt('12'), 12);
    expect(asInt('x'), isNull);
    expect(localizedFor('fi', {'en': 'Hello', 'fi': 'Hei'}), 'Hei');
    expect(localizedFor('en', {'fi': 'Hei'}), 'Hei');
    expect(localizedFor('en', ''), isNull);
  });
}
