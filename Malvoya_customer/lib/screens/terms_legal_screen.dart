import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../l10n.dart';
import '../locale_provider.dart';

class TermsLegalScreen extends StatelessWidget {
  const TermsLegalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<LocaleProvider>(
      builder: (context, localeProvider, _) {
        final l10n = AppLocalizations.of(context);
        final isFi = localeProvider.locale.languageCode == 'fi';
        final cardBg = AppTheme.cardBackground(context);
        final textPrimary = AppTheme.primaryText(context);
        final textSecondary = AppTheme.secondaryText(context);
        final borderColor = AppTheme.cardBorder(context);

        return DefaultTabController(
          length: 4,
          child: Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            appBar: AppBar(
              title: Text(
                l10n.translate('legalTermsTitle'),
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: textPrimary),
              ),
              backgroundColor: cardBg,
              elevation: 0,
              leading: IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: textPrimary),
                tooltip: l10n.translate('settings'),
                onPressed: () => Navigator.pop(context),
              ),
              bottom: TabBar(
                isScrollable: true,
                labelColor: AppTheme.primary,
                unselectedLabelColor: textSecondary,
                indicatorColor: AppTheme.primary,
                indicatorWeight: 3,
                labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                tabs: [
                  Tab(text: l10n.translate('tabConsumerTerms')),
                  Tab(text: l10n.translate('tabReturnsAlv')),
                  Tab(text: l10n.translate('tabPrivacyCookies')),
                  Tab(text: l10n.translate('tabImpressumAudit')),
                ],
              ),
            ),
            body: TabBarView(
              physics: const BouncingScrollPhysics(),
              children: [
                // TAB 1: CONSUMER TERMS
                _buildTabContent(
                  context: context,
                  cardBg: cardBg,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                  borderColor: borderColor,
                  sections: isFi
                      ? const [
                          _LegalSection(
                            title: '1. Palvelun rooli ja identiteetti',
                            content: '''Malvoya on Helsingistä käsin toimiva digitaalinen huippumuodin ja artesaanipukineiden tilaus- ja pikatoimitusalusta.

Malvoya yhdistää itsenäiset muotisuunnittelijat, ateljeet ja vahvistetut paikalliset putiikit kuluttajiin Suomessa ja Euroopan talousalueella (ETA). Kaikki kauppiaat ja itsenäiset myyjät todennetaan tiukkojen laatu- ja turvallisuuskriteerien mukaisesti.''',
                          ),
                          _LegalSection(
                            title: '2. Sopimuksen syntyminen ja alaikäisten suoja',
                            content: '''Sitova kuluttajasopimus syntyy, kun vahvistat tilauksen valitsemalla maksutavan (maksukortti tai SEPA-pankkisiirto) ja suoritat 3D Secure- tai biometrisen vahvistuksen.

Alaikäiset saavat selata valikoimaa ja luoda toivelistoja huoltajan suostumuksella. Kaikki maksutapahtumat edellyttävät kuitenkin vahvaa tunnistautumista (3D Secure tai biometrinen vahvistus). Huoltajan maksukortin luvaton käyttö on ehdottomasti kielletty pankkisääntelyn nojalla.''',
                          ),
                          _LegalSection(
                            title: '3. Läpinäkyvät hinnat ja Suomen ALV 25,5 %',
                            content: '''Kaikki Malvoyan hinnat sisältävät Suomen arvonlisäveron (ALV 25,5 %, Verohallinnon 1.9.2024 voimaan tulleen verokannan mukaisesti).

Ei piilokuluja: Kuriiritoimitusmaksu lasketaan suoraan asiakkaan ja putiikin välisen etäisyyden perusteella ja eritellään selkeästi ennen maksua. Virallinen sähköinen ALV-kuitti toimitetaan välittömästi tilauksen yhteydessä.''',
                          ),
                          _LegalSection(
                            title: '4. Saatavuus ja toimitusvarmuus',
                            content: '''Tilaukset riippuvat ateljeiden varastotilanteesta ja kuriirien saatavuudesta. Jos artesaanituote on loppuunmyyty, katevaraus vapautetaan välittömästi pankkitilillesi ilman kuluja.''',
                          ),
                        ]
                      : const [
                          _LegalSection(
                            title: '1. Platform Role & Identity',
                            content: '''Malvoya is an on-demand digital boutique discovery and delivery marketplace operated from Helsinki, Finland.

Malvoya connects independent fashion designers, studios, and verified merchants with consumers across Finland and the European Economic Area (EEA). All merchant studios and independent sellers are onboarded through authenticated verification.''',
                          ),
                          _LegalSection(
                            title: '2. Contract Formation & Youth Usage',
                            content: '''A binding consumer agreement is concluded when you authorize payment (Credit/Debit Card or SEPA Bank Transfer) and complete 3D Secure / Biometric authorization.

Minors may discover collections and curate wishlists with parental awareness. However, all payment authorizations are strictly scrutinized: 3D Secure verification and authentication are mandatory. Using a parent or guardian's payment card without authorization is strictly prohibited under banking regulations.''',
                          ),
                          _LegalSection(
                            title: '3. Transparent Pricing & ALV (Finnish VAT 25.5%)',
                            content: '''All prices displayed on Malvoya are inclusive of Finnish Value Added Tax (ALV 25.5%, Arvonlisävero) in full compliance with Finnish Tax Administration (Verohallinto) standards.

Zero Hidden Fees: Delivery fees are dynamically computed from customer GPS coordinates to store location and itemized prior to checkout. An electronic tax invoice with full ALV breakdown is issued immediately.''',
                          ),
                          _LegalSection(
                            title: '4. Merchant Availability & Fulfillment',
                            content: '''Orders are subject to boutique stock availability and courier fleet assignment. If an artisan item is sold out or unavailable, your pre-authorization is voided and funds are released immediately.''',
                          ),
                        ],
                ),

                // TAB 2: 14-DAY STATUTORY RETURNS & ALV
                _buildTabContent(
                  context: context,
                  cardBg: cardBg,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                  borderColor: borderColor,
                  sections: isFi
                      ? const [
                          _LegalSection(
                            title: '1. 14 päivän lakisääteinen peruuttamisoikeus (Kuluttajansuojalaki)',
                            content: '''Kuluttajansuojalain (38/1978) 6 luvun ja EU:n kuluttajaoikeusdirektiivin 2011/83/EU mukaisesti sinulla on oikeus peruuttaa tavanomainen muotituoteostos 14 kalenteripäivän kuluessa tuotteen vastaanottamisesta ilman perusteluja.''',
                          ),
                          _LegalSection(
                            title: '2. Palautusprosessi ja Postin automaatit',
                            content: '''Palautus tai koon vaihto voidaan aloittaa suoraan Malvoya-sovelluksen kohdasta Profiili > Pyyhkäise vaihtaaksesi / Lakisääteiset palautukset.

Voit valita maksuttoman Postin tai Matkahuollon pakettiautomaatin (digitaalisella koodilla) tai tilata kuriirin noutamaan paketin suoraan kotioveltasi.''',
                          ),
                          _LegalSection(
                            title: '3. Hygieniatuotteiden lakisääteiset poikkeukset',
                            content: '''Kuluttajansuojalain 6 luvun 16 §:n mukaisesti peruuttamisoikeus ei koske sinetöityjä tavaroita, joiden sinetti on avattu ja joita ei terveydellisistä tai hygieniasyistä voida palauttaa (kuten avatut kosmetiikkapullot, ihovoiteet tai alusvaatteet, joiden hygieniasuoja on rikottu).''',
                          ),
                          _LegalSection(
                            title: '4. Rahojen palautus ja SEPA-maksut',
                            content: '''Palautus maksetaan 14 päivän kuluessa siitä, kun palautettu tuote on vastaanotettu ja tarkistettu ateljeessa. Hyvitys suoritetaan suoraan alkuperäiselle maksutavalle (Visa/Mastercard tai SEPA-pankkitilille).''',
                          ),
                        ]
                      : const [
                          _LegalSection(
                            title: '1. 14-Day Right of Withdrawal (Kuluttajansuojalaki)',
                            content: '''In accordance with Chapter 6 of the Finnish Consumer Protection Act (Kuluttajansuojalaki 38/1978) and EU Directive 2011/83/EU on Consumer Rights, you possess the statutory right to cancel and return standard retail fashion purchases within 14 calendar days of physical delivery without providing a reason.''',
                          ),
                          _LegalSection(
                            title: '2. Return Procedure & Automated Posti Lockers',
                            content: '''Returns can be initiated instantly within the Malvoya Customer App under Profile > Swipe to Swap / Statutory Returns.

You can choose automated Posti / Matkahuolto parcel locker drop-off (with an automated digital PIN barcode) or request an on-demand courier to collect the parcel directly from your delivery entrance.''',
                          ),
                          _LegalSection(
                            title: '3. Statutory Hygiene Exceptions',
                            content: '''In accordance with Section 16(e) of Chapter 6 of Kuluttajansuojalaki, the right of withdrawal does not apply to sealed goods that cannot be returned for health or hygiene reasons once unsealed by the consumer (e.g. opened cosmetic jars, face serums, or intimate garments with broken hygiene seals).''',
                          ),
                          _LegalSection(
                            title: '4. Refund Timeline & SEPA Banking',
                            content: '''Refunds are processed within 14 days of return parcel receipt and verification by the partner studio, credited directly to the original payment method (Visa/Mastercard or direct SEPA bank account).''',
                          ),
                        ],
                ),

                // TAB 3: PRIVACY & COOKIES
                _buildTabContent(
                  context: context,
                  cardBg: cardBg,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                  borderColor: borderColor,
                  sections: isFi
                      ? const [
                          _LegalSection(
                            title: '1. Rekisterinpitäjä ja käsittelyn perusteet',
                            content: '''Malvoya toimii EU:n yleisen tietosuoja-asetuksen (GDPR 2016/679) ja Suomen tietosuojalain (1050/2018) mukaisena rekisterinpitäjänä.

• Sopimuksen täytäntöönpano (art. 6(1)(b)): Toimitusosoitteen, nimen ja maksutietojen käsittely tilausten toimittamiseksi.
• Suostumus (art. 6(1)(a)): Vapaaehtoiset luvat markkinointiviesteihin ja kuriirin live-tutkaan.
• Lakisääteinen velvoite (art. 6(1)(c)): Kirjanpitoaineiston säilytys kirjanpitolain (1336/1997) mukaisesti.''',
                          ),
                          _LegalSection(
                            title: '2. Evästeet ja paikallinen tallennus',
                            content: '''Sähköisen viestinnän tietosuojadirektiivin (2002/58/EY) mukaisesti:

• Välttämättömät tiedot: Kirjautumistunnisteet, aktiivinen ostoskori ja turva-PIN-koodi.
• Toiminnalliset tiedot: Teemavalinnat (Vaalea/OLED/Lämmin) ja valittu kieli.
• Toimitus ja reititys: Reaaliaikainen etäisyyden ja kuriirireitin laskenta.

Malvoya ei käytä mainosverkostojen seurantapikseleitä eikä myy käyttäjätietoja ulkopuolisille.''',
                          ),
                          _LegalSection(
                            title: '3. Rekisteröidyn oikeudet ja omien tietojen poisto',
                            content: '''Sinulla on täydet GDPR:n artiklojen 15–22 mukaiset oikeudet:

• Artikla 15 (Pääsy tietoihin): Lataa koko tietoprofiilisi selkeänä JSON-tiedostona yhdellä napautuksella.
• Artikla 16 (Tietojen oikaiseminen): Muokkaa toimitusosoitteitasi ja profiiliasi välittömästi sovelluksessa.
• Artikla 17 (Oikeus tulla unohdetuksi): Poista tilisi ja kaikki henkilötietosi pysyvästi Tietosuoja & GDPR -valikosta.''',
                          ),
                        ]
                      : const [
                          _LegalSection(
                            title: '1. Data Controller & Legal Bases',
                            content: '''Malvoya acts as Data Controller under Regulation (EU) 2016/679 (GDPR) and the Finnish Data Protection Act (Tietosuojalaki 1050/2018).

• Contractual Necessity (Art 6(1)(b)): Processing delivery addresses, names, and transaction tokens to fulfill orders.
• Explicit Consent (Art 6(1)(a)): Granular opt-ins for marketing notifications and location radar.
• Legal Obligation (Art 6(1)(c)): Retaining invoice data pursuant to the Finnish Accounting Act (Kirjanpitolaki 1336/1997).''',
                          ),
                          _LegalSection(
                            title: '2. Cookie & Local Storage Disclosures',
                            content: '''In compliance with Directive 2002/58/EC (ePrivacy Directive):

• Strictly Necessary: Authentication tokens, active basket state, and security PIN verification.
• Functional: Theme preferences (Light/OLED/Amber) and selected language.
• Performance & Dispatch: Real-time road routing and courier distance calculations.

Zero covert ad-trackers or data brokers are embedded in Malvoya.''',
                          ),
                          _LegalSection(
                            title: '3. Data Subject Rights & Self-Service Erasure',
                            content: '''You hold full rights under GDPR Articles 15–22:

• Article 15 (Access): Export your entire personal data profile as structured JSON in one tap.
• Article 16 (Rectification): Edit your saved delivery details and profile instantly.
• Article 17 (Erasure / Right to be Forgotten): Permanently delete your account and personal identifiers under Privacy & GDPR Hub.''',
                          ),
                        ],
                ),

                // TAB 4: IMPRESSUM & SDK AUDIT
                _buildTabContent(
                  context: context,
                  cardBg: cardBg,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                  borderColor: borderColor,
                  sections: isFi
                      ? const [
                          _LegalSection(
                            title: '1. Julkaisutiedot ja yhteystiedot (Impressum)',
                            content: '''Malvoya Platform
Toimivalta: Helsinki, Suomi
Virallinen asiakastuki: support@malvoya.com
Tietosuoja ja juridiset asiat: legal@malvoya.com

Valvontaviranomainen: Tietosuojavaltuutetun toimisto, Lintulahdenkuja 4, 00530 Helsinki.
Kaupparekisteri: Patentti- ja rekisterihallitus (PRH). Y-tunnus päivitetään virallisen rekisteröinnin valmistuttua.''',
                          ),
                          _LegalSection(
                            title: '2. Kolmansien osapuolien ohjelmistokirjastot (SDK)',
                            content: '''Malvoya hyödyntää vain tarkasti auditoituja komponentteja:

• Stripe SDK: PCI-DSS Level 1 -tason maksuturvallisuus. Maksukorttitiedot eivät koskaan tallennu Malvoyan palvelimille.
• OpenStreetMap / Leaflet: Avoimen lähdekoodin karttapohja toimitusreiteille.
• Google Sign-In: Suojattu OAuth 2.0 -tunnistautuminen.

Ei mainosverkostoja, ei kolmansien osapuolien seurantakoodeja eikä luvatonta telemetriaa.''',
                          ),
                          _LegalSection(
                            title: '3. Typografia ja avoimen lähdekoodin lisenssit',
                            content: '''• Typografia: Inter ja Plus Jakarta Sans (SIL Open Font License OFL).
• Kuvakkeet: Google Material Symbols (Apache License 2.0).
• Visuaalinen sisältö: Lisensoitu toimituksellinen valokuvaus avoimilla kaupallisilla käyttöoikeuksilla.''',
                          ),
                        ]
                      : const [
                          _LegalSection(
                            title: '1. Corporate Impressum & Contact',
                            content: '''Malvoya Platform
Jurisdiction: Helsinki, Finland
Official Customer Support: support@malvoya.com
Legal & Data Protection: legal@malvoya.com

Supervisory Authority: Office of the Data Protection Ombudsman (Tietosuojavaltuutetun toimisto), Lintulahdenkuja 4, 00530 Helsinki.
Commercial Registration: Finnish Patent and Registration Office (PRH - Patentti- ja rekisterihallitus). Official business identifier (Y-tunnus) will be updated upon formal registry publication.''',
                          ),
                          _LegalSection(
                            title: '2. Third-Party SDK & Library Audit',
                            content: '''Malvoya maintains a strictly audited, minimalist SDK footprint:

• Stripe SDK: PCI-DSS Level 1 payment encryption. Card numbers never touch Malvoya servers.
• OpenStreetMap / Leaflet: Open mapping tiles for Helsinki route rendering.
• Google Sign-In: Secure OAuth 2.0 authentication.

No social tracking pixels, no advertising networks, and no unauthorized telemetry.''',
                          ),
                          _LegalSection(
                            title: '3. Typography & Open-Source Licenses',
                            content: '''• Typography: Inter & Plus Jakarta Sans licensed under the SIL Open Font License (OFL).
• Icons: Google Material Symbols licensed under Apache License 2.0.
• Editorial Visuals: Licensed royalty-free photography under open commercial licenses.''',
                          ),
                        ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTabContent({
    required BuildContext context,
    required Color cardBg,
    required Color textPrimary,
    required Color textSecondary,
    required Color borderColor,
    required List<_LegalSection> sections,
  }) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: sections.map((sec) => _buildCard(
        title: sec.title,
        content: sec.content,
        cardBg: cardBg,
        textPrimary: textPrimary,
        textSecondary: textSecondary,
        borderColor: borderColor,
      )).toList(),
    );
  }

  Widget _buildCard({
    required String title,
    required String content,
    required Color cardBg,
    required Color textPrimary,
    required Color textSecondary,
    required Color borderColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: textPrimary,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            content,
            style: TextStyle(
              fontSize: 13,
              height: 1.55,
              color: textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalSection {
  final String title;
  final String content;
  const _LegalSection({required this.title, required this.content});
}
