import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The bundled fonts are under the SIL Open Font License; this adds their licence texts to the
/// app's "Open-source licences" page.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final family in const ['HankenGrotesk', 'BricolageGrotesque']) {
      final text = await rootBundle.loadString('assets/licenses/OFL-$family.txt');
      yield LicenseEntryWithLineBreaks([family], text);
    }
  });
}
