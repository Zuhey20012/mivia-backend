import 'package:flutter/material.dart';
import 'package:malvoya_core/malvoya_core.dart';
import 'package:malvoya_ui/malvoya_ui.dart';
import 'support_hub_screen.dart';

/// "Size & shade help": how to measure yourself, how the shops' size charts and the shade swatches
/// work. Plain guidance only; no medical or skin-health claims.
class SizeShadeHelpScreen extends StatelessWidget {
  const SizeShadeHelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.mColors;
    Widget heading(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(MSpace.lg, MSpace.xxl, MSpace.lg, MSpace.sm),
          child: Semantics(header: true, child: Text(text, style: MType.displayS.copyWith(color: c.onSurface))),
        );
    Widget para(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(MSpace.lg, 0, MSpace.lg, MSpace.md),
          child: Text(text, style: MType.bodyL.copyWith(color: c.onSurface)),
        );
    Widget step(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.fromLTRB(MSpace.lg, 0, MSpace.lg, MSpace.md),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: c.primarySoft, shape: BoxShape.circle),
              child: Icon(icon, size: 20, color: c.onPrimarySoft),
            ),
            const SizedBox(width: MSpace.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: MType.bodyL.copyWith(fontWeight: FontWeight.w700, color: c.onSurface)),
                const SizedBox(height: 2),
                Text(body, style: MType.bodyM.copyWith(color: c.onSurfaceVariant)),
              ]),
            ),
          ]),
        );

    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'Size & shade help', 'Koko- ja sävyapu'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: MSpace.x4l),
        children: [
          heading(tr(context, 'How to measure yourself', 'Näin mittaat itsesi')),
          para(tr(context, 'Use a soft tape measure and measure over thin clothes or underwear. Keep the tape level and snug, but not tight. Measurements are in centimetres.',
              'Käytä pehmeää mittanauhaa ja mittaa ohuiden vaatteiden tai alusvaatteiden päältä. Pidä nauha suorassa ja tiiviisti, mutta ei kireällä. Mitat ovat senttimetreinä.')),
          step(Icons.straighten_rounded, tr(context, 'Chest or bust', 'Rinnanympärys'),
              tr(context, 'Around the fullest part of the chest, under the arms.', 'Rinnan leveimmästä kohdasta, kainaloiden alta.')),
          step(Icons.straighten_rounded, tr(context, 'Waist', 'Vyötärö'),
              tr(context, 'Around the narrowest part of your waist, usually just above the belly button.', 'Vyötärön kapeimmasta kohdasta, yleensä vähän navan yläpuolelta.')),
          step(Icons.straighten_rounded, tr(context, 'Hips', 'Lantio'),
              tr(context, 'Around the widest part of the hips and seat, feet together.', 'Lantion ja pakaroiden leveimmästä kohdasta, jalat yhdessä.')),
          step(Icons.straighten_rounded, tr(context, 'Inside leg', 'Sisäsauma'),
              tr(context, 'From the crotch down to the floor, standing straight without shoes.', 'Haarasta lattiaan, suorana seisten ilman kenkiä.')),
          step(Icons.height_rounded, tr(context, 'Height (children)', 'Pituus (lapset)'),
              tr(context, 'Kids’ sizes are given as height in cm (for example 110 or 128). Measure without shoes, back against a wall.',
                  'Lasten koot ovat pituus senttimetreinä (esimerkiksi 110 tai 128). Mittaa ilman kenkiä selkä seinää vasten.')),
          step(Icons.snowshoeing_rounded, tr(context, 'Foot length', 'Jalan pituus'),
              tr(context, 'Stand on a sheet of paper, mark the heel and the longest toe, and measure the distance. Measure both feet and use the longer one.',
                  'Seiso paperin päällä, merkitse kantapää ja pisin varvas ja mittaa väli. Mittaa molemmat jalat ja käytä pidempää.')),
          heading(tr(context, 'How size charts work', 'Näin kokotaulukot toimivat')),
          para(tr(context, 'When a shop has added its own size chart, you find it under “Size guide” on the product page. Sizes differ between brands, so always compare your measurements with that product’s chart rather than the size you usually wear.',
              'Kun kauppa on lisännyt oman kokotaulukkonsa, löydät sen tuotesivulta kohdasta ”Kokotaulukko”. Koot vaihtelevat merkeittäin, joten vertaa mittojasi aina kyseisen tuotteen taulukkoon äläkä vain tavalliseen kokoosi.')),
          para(tr(context, 'A chart shows either body measurements (the body the size is made for) or garment measurements (the item itself, measured flat). The chart says which. For second-hand items the seller often gives the measured garment, because old size labels vary.',
              'Taulukossa on joko vartalon mitat (vartalo, jolle koko on tehty) tai vaatteen mitat (itse tuote tasolta mitattuna). Taulukossa kerrotaan, kumpi on kyseessä. Käytetyissä tuotteissa myyjä antaa usein vaatteen omat mitat, koska vanhat kokomerkinnät vaihtelevat.')),
          para(tr(context, 'Between two sizes? Check the fit: for a relaxed fit the smaller size is often fine, for a slim fit choose the larger one. If there is no chart, ask the shop before you buy.',
              'Oletko kahden koon välissä? Katso istuvuus: väljässä mallissa pienempi koko sopii usein, kapeassa mallissa valitse isompi. Jos taulukkoa ei ole, kysy kaupalta ennen ostoa.')),
          heading(tr(context, 'How shade swatches work', 'Näin sävynäytteet toimivat')),
          para(tr(context, 'Each round swatch shows the shade the shop picked from its swatch photo. The shade’s name is always written next to it, so you never have to rely on colour alone. A crossed-out swatch is sold out.',
              'Jokainen pyöreä sävynäyte näyttää sävyn, jonka kauppa on poiminut sävykuvastaan. Sävyn nimi kerrotaan aina näytteen vieressä, joten sinun ei tarvitse luottaa pelkkään väriin. Yliviivattu näyte on loppunut.')),
          para(tr(context, 'Colours vary by screen and by light. Compare the shade name and number with what you already use, and check the shade on the pack when it arrives.',
              'Värit vaihtelevat näytön ja valon mukaan. Vertaa sävyn nimeä ja numeroa siihen, mitä jo käytät, ja tarkista sävy pakkauksesta, kun tuote saapuu.')),
          para(tr(context, 'A product marked “Hygiene-sealed” on its page can be returned within 14 days only while the seal is unbroken, so check the shade before you open the pack.',
              'Tuotesivulla hygieniasinetöidyksi merkityn tuotteen voi palauttaa 14 päivän kuluessa vain, jos sinetti on ehjä, joten tarkista sävy ennen kuin avaat pakkauksen.')),
          heading(tr(context, 'Still unsure?', 'Vieläkö epävarma?')),
          para(tr(context, 'Ask the shop about fit or shade before you buy, or contact Malvoya’s help.', 'Kysy kaupalta istuvuudesta tai sävystä ennen ostoa tai ota yhteyttä Malvoyan tukeen.')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: MSpace.lg),
            child: MButton(
              label: tr(context, 'Help & contact', 'Apua ja yhteystiedot'),
              variant: MButtonVariant.outline,
              icon: Icons.support_agent_rounded,
              expand: true,
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportHubScreen())),
            ),
          ),
        ],
      ),
    );
  }
}
