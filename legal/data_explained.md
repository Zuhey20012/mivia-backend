# Tietosi selkokielellä / Your data, explained

**Päivitetty / Last updated:** [DATE OF PUBLICATION]

> Tämä sivu kertoo arkikielellä, mitä tietoja Malvoya käsittelee ja miksi. Sitova teksti on [tietosuojaseloste](https://malvoya-api-eu.onrender.com/legal/privacy). Palvelua ylläpitää [COMPANY LEGAL NAME] (Y-tunnus [Y-TUNNUS]). English version below: **Your data, explained**.

- **Suomeksi:** Lyhyesti · Mitä emme koskaan kerää tai tee · Ostajat · Kaupat ja myyjät · Lähetit · Kaikki käyttäjät · Sijainti · Maksut · Turvatoimet · Oikeutesi · Kuka käsittelee tietojasi
- **In English:** In short · What we never collect or do · Shoppers · Shops and sellers · Couriers · Everyone · Location · Payments · Security · Your rights · Who handles your data

## Suomeksi

### Lyhyesti

- Keräämme vain sen, mitä tarvitaan ostamiseen, myymiseen ja toimittamiseen.
- Tietosi ovat palvelimellamme Frankfurtissa, Saksassa (EU). Kaikki liikenne on salattua (HTTPS).
- Emme myy tietojasi emmekä näytä mainoksia.
- Voit ladata tietosi, korjata ne ja poistaa tilisi itse sovelluksessa.
- Joitakin tietoja laki velvoittaa säilyttämään (esimerkiksi tilaukset kirjanpitoa varten). Ne säilytetään ilman nimeäsi, kun poistat tilisi.

Jokaisesta tiedosta kerromme: mitä keräämme, **miksi tarvitsemme sen**, mitä tapahtuu jos et anna sitä, kuka sen näkee, missä se on, miten se on suojattu, kuinka kauan säilytämme sen ja miten voit itse vaikuttaa siihen. "Palvelimemme" tarkoittaa Malvoyan tietokantaa Render-palvelussa Frankfurtissa (EU).

### Mitä emme koskaan kerää tai tee

- **Emme myy tietojasi** emmekä anna niitä mainostajille.
- **Ei mainoksia eikä mainosseurantaa.** Sovelluksissa ei ole mainos-SDK:ita eikä mainostunnistetta.
- **Ei istuntojen tallennusta** (session replay): emme nauhoita, mitä teet sovelluksessa tai verkkosivulla.
- **Ei kolmannen osapuolen analytiikkaa.** Jos joskus otamme sellaisen käyttöön, kysymme ensin luvan, eikä mitään ole valittu valmiiksi. Verkkosivumme ei käytä evästeitä.
- **Emme profiloi alaikäisiä.** Palvelu on täysi-ikäisille. Jos tiedämme tai epäilemme käyttäjän olevan alle 18, hänelle ei koskaan näytetä profilointiin perustuvia suosituksia. Tällaisia suosituksia ei tällä hetkellä ole kenellekään.
- **Ei korttinumeroita palvelimillamme.** Kortin tiedot menevät suoraan Stripelle; Malvoya ei näe koko korttinumeroa koskaan.
- **Emme seuraa ostajan sijaintia.** Puhelimen sijainti luetaan vain kerran, kun itse painat "Käytä sijaintiani".
- **Emme tallenna lähetin reittihistoriaa.** Vain viimeisin sijainti, ja se poistetaan kun lähetti poistuu linjoilta tai kun sijainti ei ole päivittynyt 15 minuuttiin.
- **Live-lähetyksiä ei tallenneta.**
- **Emme tee automaattisia päätöksiä**, joilla on oikeudellisia tai vastaavia vaikutuksia sinuun. Kauppojen ja lähettien hyväksynnästä päättää aina ihminen.

### Ostajat (Malvoya-sovellus)

#### Tili: nimi, sähköposti, puhelin ja kirjautuminen

- **Mitä keräämme:** nimesi, sähköpostiosoitteesi, halutessasi puhelinnumerosi, salasanasi (vain tiivisteenä), Google- tai Apple-tunnuksesi numeron jos kirjaudut niillä, kielivalintasi (suomi tai englanti) ja ajan, jolloin vahvistit olevasi vähintään 18-vuotias.
- **Miksi tarvitsemme sen:** jotta voit kirjautua, tilauksesi kuuluvat sinulle ja voimme lähettää kuitit, koodit ja ilmoitukset omalla kielelläsi. Ikävahvistus tarvitaan, koska palvelu on täysi-ikäisille.
- **Jos et anna sitä:** voit selata ilman tiliä, mutta et voi tilata. Puhelinnumero ei ole pakollinen, ellet kirjaudu puhelinnumerolla.
- **Kuka näkee:** sinä ja Malvoyan ylläpito. Lähettisi näkee nimesi toimituksen ajan. Arvosteluissa ja kommenteissa näkyy vain etunimesi. Kauppa ei näe nimeäsi, sähköpostiasi eikä puhelinnumeroasi.
- **Missä se on:** palvelimellamme. Jos kirjaudut puhelinnumerolla tai Applella, kirjautumistieto on myös Google Firebasessa. Google-kirjautumisessa Google tietää, että käytät Malvoyaa.
- **Miten se on suojattu:** salasana tallennetaan bcrypt-tiivisteenä, istunto toimii 15 minuutin tunnuksilla ja kertakäyttöisillä päivitystunnuksilla (tallennettu tiivisteinä), kirjautumiskoodit ovat tiivisteitä ja vanhenevat 10 minuutissa, ja yrityskertoja on rajoitettu.
- **Kuinka kauan:** kunnes poistat tilisi.
- **Miten hallitset:** vaihda nimesi profiilin asetuksissa; sähköpostin tai puhelinnumeron korjaus tuen kautta; lataa tietosi; poista tili (Profiili → Tietosuoja → Tietosi). Google-linkityksen voit poistaa tilin asetuksista, jos tililläsi on salasana.

#### Toimitusosoite, karttanasta ja "Käytä sijaintiani"

- **Mitä keräämme:** toimitusosoitteen, sen kohdalle asetetun karttanastan (koordinaatit) ja tilauksen lisätiedot (esimerkiksi ovikoodin). Jos painat "Käytä sijaintiani", puhelin lukee sijaintisi kerran nastan asettamiseksi.
- **Miksi tarvitsemme sen:** näytämme lähellä olevat kaupat, oikean toimitusmaksun ja -ajan, ja lähetti löytää perille.
- **Jos et anna sitä:** et voi tilata kotiinkuljetusta. Nouto kaupasta ei tarvitse osoitetta. Sijaintilupaa ei tarvita: voit vetää karttaa tai hakea katuosoitteella.
- **Kuka näkee:** tilauksen kauppa (osoite, nasta ja lisätiedot, ei nimeäsi) ja lähetti vasta hyväksyttyään keikan; ennen sitä lähetit näkevät vain noin kilometrin tarkkuisen alueen. Malvoyan ylläpito.
- **Missä se on:** tilauksen mukana palvelimellamme. Tallennetut osoitteesi ovat vain puhelimessasi. Nasta kulkee palvelimelle kauppojen ja hintojen hakemiseksi, mutta se tallennetaan vain tilauksen tai "Kerro kun Malvoya avautuu lähelläni" -ilmoituksen mukana.
- **Miten se on suojattu:** salattu yhteys; lokeihin tallentuu vain osoitepolku ilman sijaintia.
- **Kuinka kauan:** karttanasta poistetaan tilauksesta 30 päivää sen jälkeen, kun tilaus toimitettiin tai peruttiin; kirjoitettu osoite säilyy tilauksen mukana 6 vuotta (kirjanpitolaki). Kun poistat tilisi, osoite, nasta ja lisätiedot poistetaan tilauksista heti.
- **Miten hallitset:** muokkaa tai poista tallennettuja osoitteita profiilissa; peru sijaintilupa puhelimen asetuksista; poista tili.

#### Tilaukset, palautukset ja peruminen

- **Mitä keräämme:** mitä ostit, hinnat, maksun tila, hyvitykset, palautukset (syy, oma huomautuksesi, onko hygieniasinetti ehjä), peruutustoiminnolla tehdyt perumiset ja milloin vahvistus lähetettiin, juomaraha, käytetty kampanja- tai kutsukoodi ja valitsemasi toimitusaika.
- **Miksi tarvitsemme sen:** kauppa, toimitus ja palautukset toimivat, 14 päivän peruuttamisoikeus toteutuu ja kirjanpito on lain mukainen.
- **Jos et anna sitä:** et voi ostaa.
- **Kuka näkee:** sinä, tilauksen kauppa (tuotteet ja summat), lähetti keikan ajan ja Malvoyan ylläpito. Noutokoodin näet vain sinä.
- **Missä se on:** palvelimellamme; maksutapahtuma myös Stripellä.
- **Miten se on suojattu:** tilauksen näkevät vain sen osapuolet (sinä, kauppa, lähetti ja ylläpito); yksi tarkistus päättää jokaisesta pyynnöstä.
- **Kuinka kauan:** 6 vuotta tilikauden päättymisestä (kirjanpitolaki 2:10). Jos poistat tilisi aiemmin, tilaus säilyy ilman nimeäsi ja yhteystietojasi.
- **Miten hallitset:** lataa tietosi; peru tilaus tai palauta tuote tilauksen sivulla ("Peru sopimus tästä" yrityksen myymissä tilauksissa).

#### Toimituskuva ja luovutuspaikka

- **Mitä keräämme:** kun lähetti jättää tilauksen ovellesi, hän ottaa kuvan paikasta. Jokaisessa toimituksessa tallennetaan lähetin sijainti luovutushetkellä.
- **Miksi tarvitsemme sen:** todisteeksi toimituksesta, jos paketti ei löydy.
- **Jos et anna sitä:** et anna sitä itse. Jos otat tilauksen vastaan henkilökohtaisesti, kuvaa ei oteta.
- **Kuka näkee:** sinä, lähetti ja Malvoyan ylläpito. Kauppa ei näe kuvaa.
- **Missä se on:** kuva yksityisenä Cloudinaryssa, sijainti palvelimellamme.
- **Miten se on suojattu:** kuva avautuu vain lyhytaikaisella, allekirjoitetulla linkillä.
- **Kuinka kauan:** 30 päivää toimituksesta, sitten ne poistetaan automaattisesti; luovutuspaikka myös silloin, kun tilaus annettiin käteen. Jos poistat tilisi, tilaustesi luovutuspaikat poistetaan heti.
- **Miten hallitset:** kysy tuelta, jos haluat kuvan pois aiemmin.

#### Chat lähetin kanssa

- **Mitä keräämme:** viestit, niiden ajan ja lähettäjän.
- **Miksi tarvitsemme sen:** voit sopia luovutuksesta lähettisi kanssa, myös jos yhteys välillä katkeaa.
- **Jos et anna sitä:** chat on vapaaehtoinen.
- **Kuka näkee:** sinä, lähettisi ja tarvittaessa Malvoyan ylläpito. Kauppa ei näe chattia.
- **Missä se on:** palvelimellamme.
- **Miten se on suojattu:** vain chatin jäsenet pääsevät siihen; viestien määrää on rajoitettu.
- **Kuinka kauan:** 30 päivää siitä, kun tilaus toimitettiin tai peruttiin. Omat viestisi poistetaan heti, kun poistat tilisi.
- **Miten hallitset:** omat viestisi ovat ladattavissa tiedoissasi; poista tili.

#### Arvostelut

- **Mitä keräämme:** tähdet kaupalle ja lähetille sekä kirjoittamasi tekstin.
- **Miksi tarvitsemme sen:** arvostelut ovat varmennettuja: vain toimitetusta tilauksesta, kerran, 30 päivän sisällä.
- **Jos et anna sitä:** arvostelu on vapaaehtoinen.
- **Kuka näkee:** kaupan tähdet ja tekstin kuka tahansa etunimelläsi. Lähetin tähdet eivät näy julkisesti; lähetti näkee vain keskiarvonsa.
- **Missä se on:** palvelimellamme.
- **Miten se on suojattu:** ilmoitetut arvostelut tarkistaa ihminen; voit estää käyttäjiä.
- **Kuinka kauan:** teksti kunnes poistat tilisi; tähdet jäävät ilman nimeäsi, koska ne ovat osa kaupan arvosanaa.
- **Miten hallitset:** poista tili; ilmoita asiaton arvostelu; estä käyttäjä.

#### Dropit: tykkäykset, tallennukset, katselut, kommentit ja seuratut kaupat

- **Mitä keräämme:** tykkäämäsi ja tallentamasi dropit, "Ei kiinnosta" -merkinnät, katselut (kerran päivässä per droppi), kommenttisi, seuraamasi kaupat ja suosikkituotteet.
- **Miksi tarvitsemme sen:** näytämme valintasi, piilotamme mitä et halua nähdä, laskemme suosion ja tuomme seuraamiesi kauppojen uudet dropit. Syöte järjestetään uutuuden, reaktioiden, etäisyyden ja arvosanan mukaan ilman henkilökohtaista profiilia; voit valita myös aikajärjestyksen.
- **Jos et anna sitä:** kaikki on vapaaehtoista.
- **Kuka näkee:** kommentit kuka tahansa etunimelläsi. Tykkäykset, katselut, tallennukset ja seuraajat näkyvät muille vain lukuina.
- **Missä se on:** palvelimellamme.
- **Miten se on suojattu:** kirjautumattomasta katselusta tallennetaan vain IP-osoitteesta tehty, päivittäin vaihtuva tiiviste; puhelimeesi ei tallenneta mitään tätä varten. Jos vanha sovellusversio lähettää asennustunnisteen, sitä ei käytetä eikä tallenneta.
- **Kuinka kauan:** kunnes poistat merkinnän tai tilisi. Katselumerkintä säilyy vain kaksi päivää (sillä lasketaan yksi katselu päivässä); sen jälkeen jäljellä on vain dropin katselumäärä lukuna, jota ei voi yhdistää sinuun. Katselusi poistetaan tilisi mukana, ja ne ovat tietojesi latauksessa.
- **Miten hallitset:** poista tykkäys, tallennus tai seuranta, kumoa "Ei kiinnosta", poista oma kommenttisi, estä käyttäjä.

#### Live-ostokset

- **Mitä keräämme:** kirjoittamasi viestit kaupan live-lähetyksessä, sydämet ja tiedon, jos kauppa hiljensi sinut. Videon välittämiseksi LiveKit-palvelu saa tilinumerosi, etunimesi ja IP-osoitteesi. Kirjautumaton katsoja saa satunnaisen vierasnimen.
- **Miksi tarvitsemme sen:** lähetys ja sen chat toimivat, ja kauppa ja ylläpito voivat valvoa keskustelua.
- **Jos et anna sitä:** voit katsoa kirjoittamatta.
- **Kuka näkee:** viestit kaikki lähetyksen katsojat etunimelläsi; kauppa ja ylläpito.
- **Missä se on:** viestit palvelimellamme; video kulkee LiveKitin kautta eikä sitä tallenneta.
- **Miten se on suojattu:** pääsy vain lyhytaikaisella tunnuksella; viestien määrää on rajoitettu.
- **Kuinka kauan:** 30 päivää lähetyksen päättymisestä; omat viestisi poistetaan heti, kun poistat tilisi.
- **Miten hallitset:** ilmoita lähetys; poista tili.

#### Ilmoitukset, sähköpostit ja "Kerro kun Malvoya avautuu lähelläni"

- **Mitä keräämme:** puhelimesi push-tunnuksen, tiedon oletko kieltäytynyt valinnaisista sähköposteista, ja jos pyydät avausilmoitusta, valitsemasi karttapisteen ja alueen nimen.
- **Miksi tarvitsemme sen:** kerromme tilauksistasi ja toimituksesta. Avausilmoitus lähetetään kerran, kun ensimmäinen kauppa avautuu 10 km:n sisällä.
- **Jos et anna sitä:** et saa ilmoituksia puhelimeesi; palvelu toimii silti.
- **Kuka näkee:** Malvoya. Ylläpito näkee avausilmoitusten alueet yhteenvetona.
- **Missä se on:** palvelimellamme; ilmoitukset kulkevat Google Firebase Cloud Messagingin, sähköpostit [EMAIL PROVIDER]:n ja tekstiviestit Twilion kautta.
- **Miten se on suojattu:** valinnaisissa sähköposteissa on allekirjoitettu peruutuslinkki.
- **Kuinka kauan:** push-tunnus kunnes kirjaudut ulos (enintään 10 puhelinta per tili); avausilmoitus kunnes perut sen tai poistat tilin.
- **Miten hallitset:** puhelimen ilmoitusasetukset; Profiili → Tietosuoja → Tietosi → Sähköpostiasetukset (kytkee valinnaiset sähköpostit pois ja peruu avausilmoituksen); peruutuslinkki sähköpostissa. Palveluviestit (kuitit, koodit, takaisinvedot) tulevat aina.

#### Kutsukoodit

- **Mitä keräämme:** oman kutsukoodisi, kuka liittyi sillä ja saamasi palkintokoodit.
- **Miksi tarvitsemme sen:** annamme kutsualennuksen ja palkinnon oikealle henkilölle.
- **Jos et anna sitä:** et saa kutsuetua.
- **Kuka näkee:** sinä ja Malvoya. Kauppa ja lähetti eivät koskaan näe, kuka kutsui kenet.
- **Missä se on:** palvelimellamme.
- **Miten se on suojattu:** kutsujan tietoa ei palauteta yhteenkään tilausnäkymään.
- **Kuinka kauan:** tilausten mukana; koodi lakkaa toimimasta, kun poistat tilisi.
- **Miten hallitset:** poista tili.

#### Ilmoitukset sisällöstä, estot ja tekijänoikeusilmoitukset

- **Mitä keräämme:** ilmoittamasi tuotteen, dropin, kommentin, arvostelun tai lähetyksen, syyn ja kirjoittamasi tekstin. Tekijänoikeus- tai tavaramerkki-ilmoituksessa myös nimesi, sähköpostisi, teos, sijainti ja vilpittömän mielen vakuutus. Estämäsi käyttäjät.
- **Miksi tarvitsemme sen:** käsittelemme ilmoitukset (digipalvelusäädös) ja piilotamme estettyjen sisällön sinulta.
- **Jos et anna sitä:** ilmoittaminen on vapaaehtoista; tekijänoikeusilmoitus vaatii lain edellyttämät tiedot.
- **Kuka näkee:** Malvoyan ylläpito. Myyjä saa tietää, mitä ilmoitettiin ja miksi, mutta ei nimeäsi eikä sähköpostiasi, ellet suostu tai laki vaadi.
- **Missä se on:** palvelimellamme.
- **Miten se on suojattu:** pääsy vain ylläpidolla.
- **Kuinka kauan:** ilmoitus säilyy päätöksen kirjauksena; nimesi, sähköpostisi ja tilisi poistetaan siitä, kun poistat tilisi. Estot kunnes poistat ne.
- **Miten hallitset:** poista esto; poista tili.

#### Tuki ja yhteydenottolomake

- **Mitä keräämme:** sähköpostiosoitteesi, sovelluksen, aiheen, viestisi ja halutessasi tilausnumeron.
- **Miksi tarvitsemme sen:** vastaamme sinulle ja muistamme, mitä sovittiin.
- **Jos et anna sitä:** emme voi vastata.
- **Kuka näkee:** Malvoyan tiimi; viesti voidaan lähettää myös tiimin postilaatikkoon ([MAILBOX PROVIDER]).
- **Missä se on:** palvelimellamme ja tiimin postilaatikossa.
- **Miten se on suojattu:** lomakkeen käyttöä on rajoitettu; lomakkeella ei ole skriptejä.
- **Kuinka kauan:** sovelluksesta lähetetyt viestit kunnes poistat tilisi; lomakkeella tai ilman tiliä lähetetyt 24 kuukautta viimeisestä käsittelystä, sitten ne poistetaan automaattisesti. Tiimin postilaatikkoon välitetyt kopiot poistetaan samassa ajassa käsin.
- **Miten hallitset:** pyydä poistoa tuelta; poista tili.

#### Tuotteiden takaisinvedot ja hyväksymäsi ehdot

- **Mitä keräämme:** jos ostamasi tuote vedetään takaisin turvallisuussyistä, milloin ja miten kerroimme siitä. Jokaisesta hyväksymästäsi ehtoversiosta: mikä versio, milloin, miten, lyhennetty verkko-osoite (IPv4:stä kolme ensimmäistä numeroa), selaimen tai puhelimen tunnisteteksti ja sovelluksen versio.
- **Miksi tarvitsemme sen:** laki velvoittaa kertomaan takaisinvedosta suoraan ostajalle. Hyväksyntä on todisteemme siitä, mikä sopimus sinua koskee.
- **Jos et anna sitä:** takaisinvetoilmoitus lähetetään aina, myös jos olet kieltänyt valinnaiset viestit. Ehtoja ei voi ohittaa, jos haluat tilata; tietosuojaselosteen lukeminen ei koskaan estä mitään.
- **Kuka näkee:** sinä ja Malvoya.
- **Missä se on:** palvelimellamme.
- **Miten se on suojattu:** verkko-osoite on lyhennetty, jotta se ei yksilöi yhteyttä.
- **Kuinka kauan:** takaisinvetoilmoitukset takaisinvetorekisterin ajan; hyväksynnät tilin elinajan ja 10 vuotta sen poistamisen jälkeen, sitten ne poistetaan automaattisesti.
- **Miten hallitset:** Profiili → Sopimukset näyttää hyväksyntäsi ja kopiot.

### Kaupat ja myyjät (Malvoya Store)

#### Kaupan tili ja julkinen profiili

- **Mitä keräämme:** tilin tiedot kuten ostajilla, sekä kaupan nimen, kuvauksen, logon ja kuvat, osoitteen ja karttapisteen, onko kauppa kotona toimiva, myyjätyypin (yritys tai yksityinen), Y-tunnuksen, aukioloajat, kaupan puhelinnumeron ja sähköpostin. Jos painat "Käytä nykyistä sijaintiani", puhelin lukee sijainnin kerran kartan pistettä varten.
- **Miksi tarvitsemme sen:** ostajat löytävät kaupan ja näkevät, keneltä he ostavat; laki edellyttää elinkeinonharjoittajan tietojen näyttämistä (digipalvelusäädös 30 art., kuluttajansuojalaki).
- **Jos et anna sitä:** et voi myydä.
- **Kuka näkee:** profiili, osoite, karttapiste ja Y-tunnus ovat julkisia. **Kotona toimivan kaupan osoite voi olla kotiosoite, ja se näkyy kaikille.** Puhelinnumero näkyy tilauksen asiakkaalle ja lähetille.
- **Missä se on:** palvelimellamme; kuvat Cloudinaryssa.
- **Miten se on suojattu:** kuvat ladataan vain kaupan omaan kansioon allekirjoitetulla latauksella.
- **Kuinka kauan:** kunnes poistat tilin. Sen jälkeen kaupan nimi, osoite ja Y-tunnus jäävät kaupan tietoihin, koska kauppa on myyjä aiemmissa tilauksissa; puhelin ja sähköposti poistetaan, tuotteet piilotetaan ja kuvat, videot ja dropit poistetaan.
- **Miten hallitset:** muokkaa profiilia sovelluksessa (myyjätyyppi ja Y-tunnus lukitaan hyväksynnän jälkeen); poista tili.

#### Y-tunnuksen tarkistus

- **Mitä keräämme:** yritysmyyjän Y-tunnuksella haetaan Patentti- ja rekisterihallituksen avoimesta YTJ-rekisteristä: löytyikö yritys, rekisteröity nimi, rekisteröintipäivä ja onko yritys toiminnassa.
- **Miksi tarvitsemme sen:** digipalvelusäädös pyytää markkinapaikkoja tarkistamaan myyjien tiedot. Tulos vain auttaa tiimiä; hyväksynnästä päättää aina ihminen.
- **Jos et anna sitä:** yritysmyyjä ei voi tulla hyväksytyksi ilman Y-tunnusta.
- **Kuka näkee:** Malvoyan ylläpito. PRH saa vain Y-tunnuksen, ei tietoa kuka kysyi.
- **Missä se on:** palvelimellamme.
- **Miten se on suojattu:** pääsy vain ylläpidolla.
- **Kuinka kauan:** kaupan tietojen mukana; korvataan, kun tarkistus tehdään uudelleen.
- **Miten hallitset:** korjaa Y-tunnus ennen hyväksyntää; kysy tuelta.

#### Verotiedot (DAC7)

- **Mitä keräämme:** yritykseltä virallinen nimi, Y-tunnus, ALV-numero jos on ja rekisteröity osoite. Yksityiseltä myyjältä virallinen nimi, syntymäaika, verotunniste (suomalaisilla henkilötunnus) ja osoite. Lisäksi myyntien määrä ja tilitykset vuosineljänneksittäin.
- **Miksi tarvitsemme sen:** EU:n DAC7-direktiivi velvoittaa ilmoittamaan myyjät Verohallinnolle kerran vuodessa. Keräämme vain sen, mitä ilmoitus tarvitsee.
- **Jos et anna sitä:** muistutamme enintään kaksi kertaa vuodessa; tilityksiä ei pidätetä.
- **Kuka näkee:** sinä (verotunniste peitettynä, esim. •••••-308T) ja vain Malvoyan ylläpito vuosiraportissa. Verohallinto saa ilmoituksen ja voi jakaa sen asuinmaasi veroviranomaisen kanssa. Alle rajan (alle 30 myyntiä ja enintään 2 000 €) myyjiä ei ilmoiteta.
- **Missä se on:** palvelimellamme.
- **Miten se on suojattu:** verotunniste salataan (AES-256-GCM) ja avataan vain vuosiraporttia varten.
- **Kuinka kauan:** 10 vuotta sen vuoden päättymisestä, jota tieto koskee, myös tilin poiston jälkeen.
- **Miten hallitset:** korjaa tiedot sovelluksessa (Verotiedot); kysy tuelta.

#### Tilitykset ja kuukausiraportit

- **Mitä keräämme:** Stripe Connect -tilisi tunnisteen, tilitysten summat ja tilan, provisio (tällä hetkellä 0 %) ja kuukausiraportit. Pankki- ja henkilöllisyystiedot annat Stripen omilla sivuilla, ei Malvoyalle.
- **Miksi tarvitsemme sen:** maksamme sinulle ja annamme selvityksen myynnistäsi.
- **Jos et anna sitä:** et saa tilityksiä.
- **Kuka näkee:** sinä, Malvoyan ylläpito ja Stripe. Stripe saa tilin luonnissa sähköpostisi, maan ja tiedon onko kyse yksityishenkilöstä vai yrityksestä.
- **Missä se on:** palvelimellamme; pankkitiedot Stripellä.
- **Miten se on suojattu:** raporttilinkit ovat allekirjoitettuja ja vanhenevat 10 minuutissa; siirroilla on yksilöllinen tunniste, ettei mitään makseta kahdesti.
- **Kuinka kauan:** 6 vuotta tilikauden päättymisestä (kirjanpitolaki); Stripe säilyttää omat tietonsa rahanpesulain mukaan.
- **Miten hallitset:** Stripen sivuilla; lataa raportit sovelluksesta.

#### Tuotteet, kuvat, videot, dropit, äänet ja live-lähetykset

- **Mitä keräämme:** tuotetiedot, kuvat ja videot, dropit (kuvat, videot, äänet ja oma äänityksesi), kommenttivastaukset ja live-lähetysten otsikot ja tuotteet. Live-lähetyksessä puhelimesi kameran ja mikrofonin kuva ja ääni kulkevat LiveKitin kautta katsojille, mutta niitä ei tallenneta.
- **Miksi tarvitsemme sen:** näytämme tuotteesi ja sisältösi ostajille.
- **Jos et anna sitä:** tuotetta ei voi julkaista ilman pakollisia tietoja.
- **Kuka näkee:** julkaistut sisällöt kuka tahansa. Jos kuvissa tai videoissa näkyy ihmisiä, sinä vastaat siitä, että sinulla on heidän lupansa.
- **Missä se on:** palvelimellamme ja Cloudinaryssa; live-video LiveKitin kautta.
- **Miten se on suojattu:** lataus vain allekirjoitettuna kaupan omaan kansioon; salaisuus ei koskaan lähde palvelimelta.
- **Kuinka kauan:** kunnes poistat ne tai tilisi; tilin poistossa kuvat, videot ja dropit poistetaan Cloudinarysta.
- **Miten hallitset:** muokkaa ja poista sovelluksessa.

#### Tuoteturvallisuuden yhteystiedot, sertifikaatit ja tuonti

- **Mitä keräämme:** valmistajan ja EU-vastuuhenkilön nimen, osoitteen, sähköpostin, puhelimen ja verkkosivun; sertifikaattien haltijan ja numeron; turvallisuussitoumuksen ajan. Luettelotuonnissa WooCommerce-avaimia käytetään vain muistissa tuonnin ajan eikä niitä tallenneta.
- **Miksi tarvitsemme sen:** tuoteturvallisuusasetus (GPSR) ja kosmetiikka-asetus vaativat nämä tiedot tuotesivulle.
- **Jos et anna sitä:** tuotetta ei voi julkaista.
- **Kuka näkee:** tuotesivulla kuka tahansa; sertifikaatit tarkistaa ylläpito ennen näyttämistä.
- **Missä se on:** palvelimellamme.
- **Miten se on suojattu:** tuonnissa on suojaus väärien osoitteiden varalta (vain julkiset https-osoitteet).
- **Kuinka kauan:** kunnes poistat ne tai kaupan.
- **Miten hallitset:** muokkaa sovelluksessa.

#### Mitä näet asiakkaista

- **Mitä saat:** tilatut tuotteet, toimitusosoitteen karttapisteineen ja asiakkaan lisätiedot. Et saa asiakkaan nimeä, sähköpostia etkä puhelinnumeroa. Noutotilauksessa asiakas näyttää noutokoodin.
- **Miksi:** jotta voit valmistella tilauksen.
- **Sinun vastuusi:** olet näiden tietojen osalta itsenäinen rekisterinpitäjä. Käytä niitä vain tilauksen hoitamiseen äläkä kopioi niitä muualle.

### Lähetit (Malvoya Courier)

#### Tili, puhelin, kulkuneuvo ja sijaintiselosteen kuittaus

- **Mitä keräämme:** tilin tiedot kuten ostajilla, kulkuneuvon (pyörä, sähköpyörä, mopo, skootteri, auto tai kävellen) ja ajan, jolloin kuittasit lukeneesi, miten sijaintiasi käytetään.
- **Miksi tarvitsemme sen:** perehdytys ja sopivien keikkojen tarjoaminen.
- **Jos et anna sitä:** et voi aloittaa keikkoja.
- **Kuka näkee:** sinä ja Malvoyan ylläpito; asiakas ja kauppa näkevät nimesi ja kulkuneuvosi (esimerkiksi pyörä) toimituksen aikana.
- **Missä se on:** palvelimellamme.
- **Miten se on suojattu:** kuten ostajien tilit.
- **Kuinka kauan:** kunnes poistat tilin.
- **Miten hallitset:** muokkaa sovelluksessa; poista tili (myös hyväksyntää odottaessa).

#### Sijainti

Katso kohta **Sijainti tarkemmin** alempana.

#### Keikat, palkkio ja arviot

- **Mitä keräämme:** tekemäsi keikat, jokaisen palkkion erittelyn (perusosa, matka, ajo kauppaan, odotus, juomaraha), asiakkaiden antamat tähdet ja ongelmailmoitukset (esim. asiakas ei tavoitettavissa).
- **Miksi tarvitsemme sen:** maksamme sinulle oikein ja näytämme, miten palkkio laskettiin (alustatyödirektiivi).
- **Jos et anna sitä:** ei koske; tiedot syntyvät työstä.
- **Kuka näkee:** sinä ja Malvoyan ylläpito. Tähtiäsi ei näytetä julkisesti.
- **Missä se on:** palvelimellamme.
- **Miten se on suojattu:** vain sinä näet oman palkkioerittelysi.
- **Kuinka kauan:** 6 vuotta tilikauden päättymisestä (kirjanpitolaki).
- **Miten hallitset:** lataa tietosi Courier-sovelluksesta (Tili → Lataa tietoni; versiosta 1.9.1 alkaen, vanhemmissa versioissa pyydä kopio tuelta): tiedostossa ovat keikkasi palkkioerittelyineen, saamasi tähdet ja tilityksesi; pyydä ihmistä selittämään tai tarkistamaan mikä tahansa päätös.

#### Tilitykset

- **Mitä keräämme:** Stripe Connect -tilisi tunnisteen ja tilitykset. Pankki- ja henkilöllisyystiedot annat Stripen sivuilla.
- **Miksi tarvitsemme sen:** maksamme ansiosi.
- **Jos et anna sitä:** et saa tilityksiä.
- **Kuka näkee:** sinä, ylläpito ja Stripe.
- **Missä se on:** palvelimellamme ja Stripellä.
- **Miten se on suojattu:** jokaisella siirrolla on yksilöllinen tunniste.
- **Kuinka kauan:** 6 vuotta (kirjanpitolaki).
- **Miten hallitset:** Stripen sivuilla.

#### Mitä näet asiakkaista

- **Mitä saat:** ennen hyväksyntää vain noin kilometrin tarkkuisen alueen. Hyväksyttyäsi keikan asiakkaan nimen, osoitteen, karttapisteen ja lisätiedot sekä chatin.
- **Sinun vastuusi:** käytä tietoja vain toimitukseen. Ota toimituskuva vain paikasta, älä ihmisistä.

### Kaikki käyttäjät

#### Kaatumisraportit (Firebase Crashlytics)

- **Mitä keräämme:** kun sovellus kaatuu tai palvelimemme vastaa virheellä, sovellus lähettää raportin: virheen, kohdan koodissa, sovellusversion, roolin, laitetiedot (malli, käyttöjärjestelmä, vapaa muisti), satunnaisen asennustunnisteen ja kirjautuneena tilisi numeron. Ei nimeä, sähköpostia, puhelinta, osoitetta, viestejä eikä kirjoittamaasi.
- **Miksi tarvitsemme sen:** löydämme ja korjaamme vikoja.
- **Jos et anna sitä:** sovelluksessa ei vielä ole kytkintä; voit vastustaa käsittelyä tuen kautta.
- **Kuka näkee:** Malvoyan kehittäjät ja Google palvelun tarjoajana.
- **Missä se on:** Google Firebase.
- **Miten se on suojattu:** virhetekstit siivotaan henkilötiedoista ennen lähetystä; kehitysversiot eivät lähetä mitään.
- **Kuinka kauan:** 90 päivää.
- **Miten hallitset:** vastusta tuen tai lomakkeen kautta.

#### Tekniset lokit, pyyntötunnukset ja virheseuranta

- **Mitä keräämme:** jokaisesta pyynnöstä rivin: satunnainen pyyntötunnus, aika, metodi, polku ilman kyselyosaa ja tulos. Ei IP-osoitetta, ei sisältöä, ei salasanoja eikä tunnuksia. IP-osoitetta käytetään vain pyyntömäärien rajoittamiseen enintään tunnin ajan. Jos virheseuranta (Sentry) on käytössä, raportissa on vain tilinumerosi.
- **Miksi tarvitsemme sen:** turvallisuus, väärinkäytösten esto ja vikojen korjaus.
- **Jos et anna sitä:** ei koske; tämä on palvelun toiminnan edellytys.
- **Kuka näkee:** Malvoyan kehittäjät; Render ja Sentry palveluntarjoajina.
- **Missä se on:** Render (Frankfurt); Sentry jos käytössä.
- **Miten se on suojattu:** tunnisteet ja otsakkeet peitetään; Sentry-raporteista poistetaan sähköpostit, puhelinnumerot, koodit ja IP-osoitteet.
- **Kuinka kauan:** [LOG RETENTION OF THE HOSTING PLAN] päivää.
- **Miten hallitset:** vastusta tuen kautta.

#### Kartat ja osoitehaku (OpenStreetMap)

- **Mitä tapahtuu:** sovellusten karttakuvat ja osoitehaku haetaan suoraan puhelimesta OpenStreetMapin palvelimilta, jotka näkevät IP-osoitteesi, katsomasi kartta-alueen ja hakemasi osoitteet.
- **Miksi:** voit valita toimitusosoitteen kartalta ja seurata toimitusta.
- **Kuka:** OpenStreetMap Foundation (Iso-Britannia) itsenäisenä vastaanottajana, ei Malvoyan alihankkijana.
- **Miten hallitset:** voit kirjoittaa osoitteen hakematta karttaa.

#### Varmuuskopiot

- Palveluntarjoajamme ottaa tietokannasta jatkuvat varmuuskopiot, joita säilytetään [7] päivää. Poistettu tieto katoaa varmuuskopioista sen ajan kuluessa.

### Sijainti tarkemmin

#### Ostajat

- Puhelimen sijainti luetaan vain, kun painat "Käytä sijaintiani" osoitetta valitessa. Se luetaan kerran, ja sitä käytetään vain nastan asettamiseen. Mitään ei lähetetä ennen kuin vahvistat osoitteen.
- Sovellus ei seuraa sinua taustalla eikä lue sijaintia muulloin.
- Nasta tallennetaan vain tilauksen ja avausilmoituksen mukana.

#### Lähetit

- **Ensin selitys:** ennen kuin sovellus pyytää Androidin sijaintilupaa, se näyttää selityksen siitä, mitä kerätään ja miksi. Kuittaus tallennetaan.
- **Milloin:** vain kun olet linjoilla tai sinulla on toimitus kesken, myös taustalla. Koko ajan näkyy ilmoitus "Sijaintisi jaetaan, kun olet linjoilla".
- **Mihin:** lähellä olevien keikkojen tarjoamiseen (7,5 km, lähin ensin), sen tarkistamiseen että olet kaupalla (300 m), kauppaan ajon palkkion laskemiseen ja asiakkaalle näyttämiseen toimituksen aikana. Asiakas saa yhden ilmoituksen "Lähetti on pian perillä", kun olet noin 300 metrin päässä.
- **Kuka näkee:** vain toimittamasi tilauksen asiakas ja kauppa, siitä kun hyväksyt keikan siihen asti, kun tilaus on toimitettu tai palautettu kauppaan, sekä ylläpito. Valmiissa, perutuissa tai muissa tilauksissa sijaintiasi ei näytetä kenellekään.
- **Mitä tallennetaan:** vain viimeisin sijainti (enintään 15 sekunnin välein). Ei reittihistoriaa. Keikan mukana tallennetaan kauppaan ajon matka (palkkiota varten) ja luovutuspaikka (30 päivää).
- **Reitti asiakkaan kartalla:** asiakkaan sovellus näyttää katureitin sijainnistasi kauppaan ja kaupasta asiakkaalle. Reitti lasketaan pyydettäessä eikä sitä tallenneta: palvelin pitää sitä muistissa enintään 10 minuuttia (sijainnistasi alkavaa reittiä minuutin), ja vain tilauksen asiakas ja kauppa saavat sinusta alkavan reitin, kun keikka on kesken. Jos reittipalvelu on käytössä, OpenRouteService (HeiGIT gGmbH, Saksa) saa reitin alku- ja loppupisteen, ei nimiä eikä tilaustietoja.
- **Milloin se loppuu:** kun poistut linjoilta, sijainnin jakaminen loppuu ja tallennettu sijainti poistetaan. Uloskirjautuminen ja tilin poisto lopettavat jakamisen myös. Yli 2 minuuttia vanha sijainti katsotaan tuntemattomaksi. Jos uutta sijaintia ei tule 15 minuuttiin (esimerkiksi sovellus suljettiin), tallennettu sijainti poistetaan automaattisesti ja sinut merkitään poissa linjoilta; jos sinulla on toimitus kesken, se jatkuu normaalisti ja sijaintisi näkyy taas seuraavasta päivityksestä.
- **Ei mainontaan.** Sijaintiasi ei käytetä mainontaan eikä myydä.

### Maksut

- Maksat Stripen maksuikkunassa (myös Google Pay). Kortin tiedot menevät suoraan Stripelle; **Malvoya ei koskaan näe koko korttinumeroa**, eikä sovelluksissa ole korttikenttiä.
- Malvoya näkee vain maksun tilan, summan ja Stripen viitteen. Stripe saa maksun mukana tilausnumeron, tilinumerosi ja kaupan nimen.
- Stripen maksuikkuna kerää laitetietoja petosten estämiseksi. Vahvan tunnistautumisen (PSD2) hoitaa Stripe.
- Kauppojen ja lähettien pankki- ja henkilöllisyystiedot annetaan Stripen omilla sivuilla.
- Stripen oma tietosuojaseloste: [stripe.com/privacy](https://stripe.com/privacy).

### Turvatoimet, jotka ovat oikeasti käytössä

- **Salattu yhteys (TLS/HTTPS)** kaikessa liikenteessä: palvelin, reaaliaikayhteydet, Stripe, Cloudinary, Firebase ja kartat.
- **Salasanat** tallennetaan vain bcrypt-tiivisteinä.
- **Vaihtuvat tunnukset:** istunnot toimivat 15 minuutin tunnuksilla ja kertakäyttöisillä 7 päivän päivitystunnuksilla, jotka tallennetaan vain tiivisteinä. Salasanan vaihto, tilin sulkeminen tai poisto katkaisee kaikki istunnot.
- **Salatut verotunnisteet:** myyjien verotunnisteet ja ylläpitäjien kaksivaiheisen kirjautumisen salaisuudet salataan AES-256-GCM:llä.
- **Allekirjoitetut linkit:** toimituskuvat, kuukausiraportit, sopimusten kopiot ja peruutuslinkit toimivat vain allekirjoitettuina; useimmat vanhenevat 10 minuutissa.
- **Pyyntörajat** kirjautumisessa, salasanan palautuksessa, koodeissa, tuessa, chatissa ja ilmoituksissa.
- **Kaksivaiheinen kirjautuminen** on pakollinen ylläpitäjille.
- **Vähimmät oikeudet:** jokainen tilaus näkyy vain asiakkaalleen, kaupalleen, lähetilleen ja ylläpidolle; kauppa ei näe asiakkaan yhteystietoja; ylläpitäjäksi ei voi rekisteröityä itse. Ylläpitäjärooleja ei vielä ole jaettu pienempiin osiin.
- **Kirjausloki:** ylläpitäjien tekemät muutokset provisioihin, ehtoihin, takaisinvetoihin, live-lähetyksiin ja kaksivaiheiseen kirjautumiseen kirjataan, samoin kauppojen ja lähettien hyväksynnät, lähettien keskeytykset, käyttäjien estot sekä jokainen DAC7-raportin avaus ja lataus (silloin verotunnisteet avataan).
- **Varmuuskopiot:** tietokannasta on palautettavat varmuuskopiot.
- **Tiedot EU:ssa:** palvelin ja tietokanta ovat Frankfurtissa.

### Oikeutesi ja miten käytät niitä

| Oikeus | Mitä se tarkoittaa | Miten käytät sitä |
|---|---|---|
| Pääsy tietoihin (15 art.) | Saat tietää ja saada kopion tiedoistasi | Malvoya: Profiili → Tietosuoja → Tietosi → Lataa tietosi. Store: Kauppa-välilehti → Lataa tietoni. Courier: Tili → Lataa tietoni (versiosta 1.9.1; vanhemmissa tuen kautta) |
| Oikaisu (16 art.) | Korjaamme väärät tiedot | Nimi profiilin asetuksissa, osoitteet profiilissa, muu tuen kautta |
| Poistaminen (17 art.) | Poistamme tilisi ja tietosi; laki voi velvoittaa säilyttämään osan ilman nimeäsi | Malvoya: Profiili → Tietosuoja → Tietosi → Poista tilini. Store ja Courier: tilivalikko → Poista tili |
| Käsittelyn rajoittaminen (18 art.) | Tietoja säilytetään mutta ei käytetä | Tuen tai lomakkeen kautta |
| Siirrettävyys (20 art.) | Saat tiedot koneluettavassa muodossa | Sama kuin lataus (JSON-tiedosto) |
| Vastustaminen (21 art.) | Voit vastustaa oikeutettuun etuun perustuvaa käsittelyä, esim. kaatumisraportteja | Tuen tai lomakkeen kautta |
| Automaattiset päätökset (22 art.) | Sinusta ei tehdä pelkästään automaattisia päätöksiä, joilla on oikeusvaikutuksia | Voit aina pyytää ihmistä selittämään tai tarkistamaan päätöksen |
| Suostumuksen peruminen | Avausilmoitus ja valinnaiset sähköpostit | Profiili → Tietosuoja → Tietosi → Sähköpostiasetukset, tai peruutuslinkki sähköpostissa |

Lomake: [malvoya-api-eu.onrender.com/contact](https://malvoya-api-eu.onrender.com/contact?lang=fi), aihe "Tietosuojapyyntö (GDPR)". Vastaamme kuukauden kuluessa. Tilin poistaminen: [ohje](https://malvoya-api-eu.onrender.com/legal/delete-account).

**Valitus:** voit tehdä valituksen tietosuojavaltuutetulle: [tietosuoja.fi](https://tietosuoja.fi), PL 800, 00531 Helsinki.

### Kuka käsittelee tietojasi

| Palvelu | Mihin | Missä | Siirron suoja |
|---|---|---|---|
| Render | Palvelin ja tietokanta | Frankfurt, Saksa (EU) | Data EU:ssa; tukipääsy Yhdysvalloista vakiolausekkein |
| Stripe | Maksut ja tilitykset | Irlanti (EU) ja Yhdysvallat | EU–US Data Privacy Framework tai vakiolausekkeet |
| Cloudinary | Kuvat, videot ja äänet | [CLOUDINARY REGION] | Data Privacy Framework tai vakiolausekkeet |
| Google Firebase | Kirjautuminen, push-ilmoitukset, kaatumisraportit | EU ja Yhdysvallat | Data Privacy Framework ja vakiolausekkeet |
| Twilio | Tekstiviestikoodit | Yhdysvallat | Data Privacy Framework tai vakiolausekkeet |
| LiveKit | Live-lähetysten video (vain kun käytössä) | [LIVEKIT REGION] | Vakiolausekkeet |
| Sentry | Virheraportit (vain kun käytössä) | [SENTRY REGION] | Data Privacy Framework tai vakiolausekkeet |
| OpenRouteService (HeiGIT) | Katureitit toimituskartalle: vain alku- ja loppupiste (vain kun käytössä) | Saksa (EU) | Data EU:ssa |
| [EMAIL PROVIDER] | Sähköpostit | [REGION] | [SAFEGUARD] |
| PRH (avoindata.prh.fi) | Y-tunnuksen tarkistus | Suomi | Viranomainen, saa vain Y-tunnuksen |
| OpenStreetMap Foundation | Kartat ja osoitehaku puhelimesta | Iso-Britannia | Komission tietosuojan riittävyyspäätös; itsenäinen vastaanottaja |
| Verohallinto | DAC7-ilmoitus | Suomi | Lakisääteinen |

### Muutokset

Kun tämä sivu tai tietosuojaseloste muuttuu, julkaisemme uuden version päivämäärineen. Tietosuojaselosteen muutoksista kerromme etukäteen push-ilmoituksella ja sähköpostilla.

## In English

### In short

- We collect only what is needed to buy, sell and deliver.
- Your data is on our server in Frankfurt, Germany (EU). All traffic is encrypted (HTTPS).
- We do not sell your data and we show no ads.
- You can download your data, correct it and delete your account yourself in the app.
- Some data must be kept by law (for example orders, for bookkeeping). It is kept without your name once you delete your account.

For each piece of data we say: what we collect, **why we need it**, what happens if you don't give it, who can see it, where it is stored, how it is protected, how long we keep it and how you control it. "Our server" means Malvoya's database at Render in Frankfurt (EU).

### What we never collect or do

- **We never sell your data** and never give it to advertisers.
- **No ads and no ad tracking.** The apps contain no ads SDK and no advertising ID.
- **No session recording** (session replay): we do not record what you do in the app or on the website.
- **No third-party analytics.** If we ever add any, we will ask for your consent first, with nothing ticked in advance. Our website uses no cookies.
- **No profiling of minors.** The service is for adults. If we know or think a user is under 18, they are never shown recommendations based on profiling. Today there are no such recommendations for anyone.
- **No card numbers on our servers.** Card details go straight to Stripe; Malvoya never sees the full card number.
- **We do not track shoppers' location.** Your phone's position is read only once, when you tap "Use my location" yourself.
- **We keep no route history for couriers.** Only the latest position, deleted when the courier goes offline or when it has not been updated for 15 minutes.
- **Live streams are never recorded.**
- **No automated decisions** with legal or similarly significant effects on you. A person always decides whether a store or courier is approved.

### Shoppers (Malvoya app)

#### Account: name, email, phone and sign-in

- **What we collect:** your name, email address, phone number if you give it, your password (only as a hash), your Google or Apple account number if you sign in with them, your language (Finnish or English) and when you confirmed you are 18 or older.
- **Why we need it:** so you can sign in, your orders belong to you, and we can send receipts, codes and notifications in your language. The age confirmation is needed because the service is for adults.
- **If you don't give it:** you can browse without an account, but you cannot order. A phone number is optional unless you sign in with it.
- **Who can see it:** you and Malvoya's admins. Your courier sees your name during the delivery. Reviews and comments show only your first name. The store does not see your name, email address or phone number.
- **Where it is stored:** on our server. If you sign in with a phone number or Apple, the sign-in record is also at Google Firebase. With Google sign-in, Google knows you use Malvoya.
- **How it is protected:** the password is stored as a bcrypt hash, sessions use 15-minute tokens and single-use refresh tokens (stored as hashes), sign-in codes are hashed and expire in 10 minutes, and attempts are limited.
- **How long we keep it:** until you delete your account.
- **How you control it:** change your name in the profile settings; correct your email or phone number through Help; download your data; delete your account (Profile → Privacy → Your data). You can unlink Google in the account settings if your account has a password.

#### Delivery address, map pin and "Use my location"

- **What we collect:** the delivery address, the map pin you set for it (coordinates) and your order notes (such as a door code). If you tap "Use my location", the phone reads your position once to place the pin.
- **Why we need it:** to show stores near you, the right delivery fee and time, and so the courier finds you.
- **If you don't give it:** you cannot order delivery. Pickup from the store needs no address. No location permission is needed: you can drag the map or search for your street.
- **Who can see it:** the store of the order (address, pin and notes, not your name), the courier only after accepting the job (before that couriers see only an area of about 1 km), and Malvoya's admins.
- **Where it is stored:** with the order on our server. Your saved addresses stay only on your phone. The pin is sent to our server to find stores and prices, but it is stored only with an order or a "tell me when Malvoya opens near me" alert.
- **How it is protected:** encrypted connection; logs record only the path, never the position.
- **How long we keep it:** the map pin is removed from the order 30 days after it was delivered or cancelled; the written address stays with the order for 6 years (Accounting Act). When you delete your account, the address, pin and notes are removed from your orders at once.
- **How you control it:** edit or delete saved addresses in your profile; withdraw the location permission in the phone's settings; delete your account.

#### Orders, returns and withdrawals

- **What we collect:** what you bought, prices, payment status, refunds, returns (reason, your note, whether a hygiene seal is intact), withdrawals made with the withdrawal function and when we sent the acknowledgement, tips, any promo or invite code and your chosen delivery time.
- **Why we need it:** so the sale, delivery and returns work, the 14-day right of withdrawal works, and our bookkeeping follows the law.
- **If you don't give it:** you cannot buy.
- **Who can see it:** you, the store of the order (items and amounts), the courier during the job and Malvoya's admins. Only you see your pickup code.
- **Where it is stored:** on our server; the payment also at Stripe.
- **How it is protected:** only the parties of an order (you, the store, the courier and admins) can see it; one check decides every request.
- **How long we keep it:** 6 years from the end of the financial year (Accounting Act 2:10). If you delete your account sooner, the order stays without your name and contact details.
- **How you control it:** download your data; cancel or return on the order's page ("Withdraw from contract here" on orders from business sellers).

#### Delivery photo and handover position

- **What we collect:** when a courier leaves an order at your door, they take a photo of the spot. For every delivery, the courier's position at handover is stored.
- **Why we need it:** proof of delivery if a parcel goes missing.
- **If you don't give it:** you don't give it yourself. If you take the order in person, no photo is taken.
- **Who can see it:** you, the courier and Malvoya's admins. The store does not see the photo.
- **Where it is stored:** the photo privately at Cloudinary, the position on our server.
- **How it is protected:** the photo opens only through a short-lived signed link.
- **How long we keep it:** 30 days after delivery, then they are deleted automatically; the handover position also when the order was handed over in person. If you delete your account, the handover positions of your orders are removed at once.
- **How you control it:** ask Help if you want the photo removed sooner.

#### Chat with the courier

- **What we collect:** the messages, when they were sent and by whom.
- **Why we need it:** so you and your courier can agree on the handover, also if the connection drops.
- **If you don't give it:** the chat is optional.
- **Who can see it:** you, your courier and, if needed, Malvoya's admins. The store cannot see the chat.
- **Where it is stored:** on our server.
- **How it is protected:** only the chat's members can join it; the number of messages is limited.
- **How long we keep it:** 30 days after the order was delivered or cancelled. Your own messages are deleted at once when you delete your account.
- **How you control it:** your own messages are in your data download; delete your account.

#### Reviews

- **What we collect:** stars for the store and the courier, and the text you write.
- **Why we need it:** reviews are verified: only for a delivered order, once, within 30 days.
- **If you don't give it:** reviewing is optional.
- **Who can see it:** anyone sees the store's stars and your text, with your first name. The courier's stars are never shown publicly; the courier sees only their average.
- **Where it is stored:** on our server.
- **How it is protected:** a person checks reported reviews; you can block users.
- **How long we keep it:** the text until you delete your account; the stars stay without your name, because they are part of the store's rating.
- **How you control it:** delete your account; report a review; block a user.

#### Drops: likes, saves, views, comments and followed stores

- **What we collect:** drops you like and save, "Not interested" marks, views (once a day per drop), your comments, the stores you follow and your favourite products.
- **Why we need it:** to show your choices, hide what you don't want to see, count popularity and bring you new drops from stores you follow. The feed is ranked by freshness, reactions, distance and rating without a personal profile; you can choose chronological order instead.
- **If you don't give it:** all of this is optional.
- **Who can see it:** anyone sees your comments with your first name. Likes, views, saves and followers are shown to others only as numbers.
- **Where it is stored:** on our server.
- **How it is protected:** for signed-out viewing we store only a scrambled value made from the IP address, which changes every day; nothing is stored on your phone for this. If an old app version sends an installation number, it is ignored and not stored.
- **How long we keep it:** until you remove it or delete your account. A view record is kept for only two days (it is used to count one view a day); after that only the drop's view count remains, as a number that cannot be linked to you. Your views are deleted with your account and are in your data download.
- **How you control it:** remove a like, save or follow, undo "Not interested", delete your own comment, block a user.

#### Live shopping

- **What we collect:** the messages you write in a store's live stream, your hearts, and whether the store muted you. To deliver the video, the LiveKit service receives your account number, first name and IP address. Signed-out viewers get a random guest name.
- **Why we need it:** to run the stream and its chat, and let the store and our admins moderate it.
- **If you don't give it:** you can watch without writing.
- **Who can see it:** all viewers of the stream see your messages with your first name; the store and admins.
- **Where it is stored:** messages on our server; the video passes through LiveKit and is never recorded.
- **How it is protected:** access only with a short-lived token; the number of messages is limited.
- **How long we keep it:** 30 days after the stream ended; your own messages are deleted at once when you delete your account.
- **How you control it:** report a stream; delete your account.

#### Notifications, emails and "Tell me when Malvoya opens near me"

- **What we collect:** your phone's push token, whether you said no to optional emails, and if you ask for the launch alert, the map position you pinned and the area name.
- **Why we need it:** to tell you about your orders and delivery. The launch alert is sent once, when the first store opens within 10 km.
- **If you don't give it:** you get no notifications on your phone; the service still works.
- **Who can see it:** Malvoya. Admins see launch-alert areas as a summary.
- **Where it is stored:** on our server; notifications go through Google Firebase Cloud Messaging, emails through [EMAIL PROVIDER] and text messages through Twilio.
- **How it is protected:** optional emails carry a signed unsubscribe link.
- **How long we keep it:** the push token until you sign out (at most 10 phones per account); the launch alert until you cancel it or delete your account.
- **How you control it:** your phone's notification settings; Profile → Privacy → Your data → Email preferences (switches optional emails off and cancels the launch alert); the unsubscribe link in the email. Service messages (receipts, codes, recalls) are always sent.

#### Invite codes

- **What we collect:** your own invite code, who joined with it and the reward codes you received.
- **Why we need it:** to give the invite discount and the reward to the right person.
- **If you don't give it:** you don't get the invite benefit.
- **Who can see it:** you and Malvoya. The store and the courier never see who invited whom.
- **Where it is stored:** on our server.
- **How it is protected:** the inviter is left out of every order view.
- **How long we keep it:** with the orders; your code stops working when you delete your account.
- **How you control it:** delete your account.

#### Reports, blocks and copyright notices

- **What we collect:** the product, drop, comment, review or stream you report, the reason and what you wrote. For a copyright or trademark notice also your name, email, the work, where it is used and your good-faith statement. The users you block.
- **Why we need it:** to handle notices (Digital Services Act) and hide blocked users' content from you.
- **If you don't give it:** reporting is optional; a copyright notice needs the details the law requires.
- **Who can see it:** Malvoya's admins. The seller learns what was reported and why, but not your name or email, unless you agree or the law requires it.
- **Where it is stored:** on our server.
- **How it is protected:** only admins can see it.
- **How long we keep it:** the notice stays as a record of the decision; your name, email and account are removed from it when you delete your account. Blocks until you remove them.
- **How you control it:** remove a block; delete your account.

#### Help and the contact form

- **What we collect:** your email address, the app, the topic, your message and the order number if you give it.
- **Why we need it:** to answer you and remember what was agreed.
- **If you don't give it:** we cannot answer.
- **Who can see it:** Malvoya's team; the message may also be forwarded to the team mailbox ([MAILBOX PROVIDER]).
- **Where it is stored:** on our server and in the team mailbox.
- **How it is protected:** the form is rate-limited and runs no scripts.
- **How long we keep it:** messages from the app until you delete your account; messages sent through the form or without an account 24 months after we last handled them, then they are deleted automatically. Copies forwarded to the team mailbox are deleted by hand within the same time.
- **How you control it:** ask Help to delete it; delete your account.

#### Product recalls and the terms you accepted

- **What we collect:** if a product you bought is recalled for safety reasons, when and how we told you. For every version of our terms you accept: which version, when, how, a shortened network address (for IPv4 the first three numbers), your browser's or phone's user-agent text and the app version.
- **Why we need it:** the law requires us to tell buyers about recalls directly. The acceptance is our proof of which contract applies to you.
- **If you don't give it:** recall notices are always sent, even if you said no to optional messages. You cannot skip the terms if you want to order; reading the privacy policy never blocks anything.
- **Who can see it:** you and Malvoya.
- **Where it is stored:** on our server.
- **How it is protected:** the network address is shortened so it does not identify one connection.
- **How long we keep it:** recall notices as long as the recall record; acceptances for the life of your account and 10 years after it is deleted, then they are deleted automatically.
- **How you control it:** Profile → Agreements shows your acceptances and copies.

### Shops and sellers (Malvoya Store)

#### Store account and public profile

- **What we collect:** account details as for shoppers, plus the store's name, description, logo and pictures, address and map position, whether it is home-based, seller type (business or private), business ID (Y-tunnus), opening hours, and the store's phone number and email. If you tap "Use my current location", the phone reads its position once for the map pin.
- **Why we need it:** so shoppers can find the store and see who they buy from; the law requires marketplaces to show trader information (Digital Services Act Art. 30, Consumer Protection Act).
- **If you don't give it:** you cannot sell.
- **Who can see it:** the profile, address, map position and business ID are public. **A home-based store's address may be a home address, and everyone can see it.** The phone number is shown to the customer and courier of an order.
- **Where it is stored:** on our server; pictures at Cloudinary.
- **How it is protected:** pictures are uploaded only to the store's own folder with a signed upload.
- **How long we keep it:** until you delete the account. After that the store's name, address and business ID stay on the store record, because the store is the seller on past orders; the phone and email are removed, products hidden and photos, videos and drops deleted.
- **How you control it:** edit the profile in the app (seller type and business ID are locked after approval); delete your account.

#### Business ID check

- **What we collect:** for business sellers, we look up the business ID in the Finnish Patent and Registration Office's open company register (YTJ): whether it was found, the registered name, the registration date and whether the company is active.
- **Why we need it:** the Digital Services Act asks marketplaces to check sellers' details. The result only helps our team; a person always decides on approval.
- **If you don't give it:** a business seller cannot be approved without a business ID.
- **Who can see it:** Malvoya's admins. PRH receives only the business ID, not who asked.
- **Where it is stored:** on our server.
- **How it is protected:** only admins can see it.
- **How long we keep it:** with the store record; replaced when the check is run again.
- **How you control it:** correct the business ID before approval; ask Help.

#### Tax details (DAC7)

- **What we collect:** for businesses the legal name, business ID, VAT number if any and registered address. For private sellers the legal name, date of birth, tax identification number (for Finns the personal identity code, henkilötunnus) and address. Also the number of sales and the payouts per quarter.
- **Why we need it:** the EU DAC7 directive requires us to report sellers to the Finnish Tax Administration once a year. We collect only what the report needs.
- **If you don't give it:** we remind you at most twice a year; payouts are never withheld.
- **Who can see it:** you (the tax number masked, e.g. •••••-308T) and only Malvoya's admins in the yearly report. The Tax Administration receives the report and may share it with the tax authority of your country of residence. Sellers under the threshold (fewer than 30 sales and at most 2 000 €) are not reported.
- **Where it is stored:** on our server.
- **How it is protected:** the tax number is encrypted (AES-256-GCM) and decrypted only for the yearly report.
- **How long we keep it:** 10 years from the end of the year it concerns, also after the account is deleted.
- **How you control it:** correct it in the app (Tax details); ask Help.

#### Payouts and monthly statements

- **What we collect:** the id of your Stripe Connect account, payout amounts and status, commission (currently 0 %) and monthly statements. You give your bank and identity details on Stripe's own pages, not to Malvoya.
- **Why we need it:** to pay you and give you a statement of your sales.
- **If you don't give it:** you get no payouts.
- **Who can see it:** you, Malvoya's admins and Stripe. When the account is created, Stripe receives your email, country and whether you are an individual or a company.
- **Where it is stored:** on our server; bank details at Stripe.
- **How it is protected:** statement links are signed and expire in 10 minutes; each transfer has a unique key so nothing is paid twice.
- **How long we keep it:** 6 years from the end of the financial year (Accounting Act); Stripe keeps its own records under anti-money-laundering law.
- **How you control it:** on Stripe's pages; download statements in the app.

#### Products, photos, videos, drops, sounds and live streams

- **What we collect:** product details, photos and videos, drops (photos, videos, sounds and your own voice-over), replies to comments, and the titles and products of your live streams. During a live stream your phone's camera and microphone are sent to viewers through LiveKit, but nothing is recorded.
- **Why we need it:** to show your products and content to shoppers.
- **If you don't give it:** a product cannot be published without its required details.
- **Who can see it:** anyone can see published content. If people appear in your photos or videos, you are responsible for having their permission.
- **Where it is stored:** on our server and at Cloudinary; live video through LiveKit.
- **How it is protected:** uploads are signed and go only to the store's own folder; the secret never leaves the server.
- **How long we keep it:** until you delete it or your account; on account deletion the photos, videos and drops are deleted from Cloudinary.
- **How you control it:** edit and delete in the app.

#### Product-safety contacts, certificates and imports

- **What we collect:** the manufacturer's and EU responsible person's name, address, email, phone and website; certificate holders and numbers; when you gave the safety pledge. For catalogue imports, WooCommerce keys are held in memory during the import only and never stored.
- **Why we need it:** the General Product Safety Regulation (GPSR) and the Cosmetics Regulation require these details on the product page.
- **If you don't give it:** the product cannot be published.
- **Who can see it:** anyone, on the product page; admins check certificates before they are shown.
- **Where it is stored:** on our server.
- **How it is protected:** imports are protected against unsafe addresses (only public https addresses).
- **How long we keep it:** until you delete it or the store.
- **How you control it:** edit in the app.

#### What you see about customers

- **What you get:** the items ordered, the delivery address with its map pin and the customer's order notes. You do not get the customer's name, email address or phone number. For a pickup order the customer shows a pickup code.
- **Why:** so you can prepare the order.
- **Your duty:** you are an independent controller of this data. Use it only to fulfil the order and do not copy it elsewhere.

### Couriers (Malvoya Courier)

#### Account, phone, vehicle and location disclosure

- **What we collect:** account details as for shoppers, your vehicle (bicycle, e-bike, moped, scooter, car or on foot) and when you confirmed you read how your location is used.
- **Why we need it:** onboarding and offering suitable jobs.
- **If you don't give it:** you cannot start taking jobs.
- **Who can see it:** you and Malvoya's admins; the customer and store see your name and your vehicle (for example a bike) during a delivery.
- **Where it is stored:** on our server.
- **How it is protected:** as for shopper accounts.
- **How long we keep it:** until you delete your account.
- **How you control it:** edit in the app; delete your account (also while waiting for approval).

#### Location

See **Location in detail** below.

#### Jobs, pay and ratings

- **What we collect:** the jobs you did, the breakdown of each job's pay (base, distance, ride to the store, waiting, tip), the stars customers give you and problem reports (such as "customer not available").
- **Why we need it:** to pay you correctly and show how your pay was calculated (Platform Work Directive).
- **If you don't give it:** not applicable; this data comes from the work.
- **Who can see it:** you and Malvoya's admins. Your stars are never shown publicly.
- **Where it is stored:** on our server.
- **How it is protected:** only you see your own pay breakdown.
- **How long we keep it:** 6 years from the end of the financial year (Accounting Act).
- **How you control it:** download your data in the Courier app (Account → Download my data; from version 1.9.1, on older versions ask Help for a copy): the file contains your jobs with their pay breakdown, the stars you got and your payouts; ask a person to explain or review any decision.

#### Payouts

- **What we collect:** the id of your Stripe Connect account and your payouts. You give your bank and identity details on Stripe's pages.
- **Why we need it:** to pay your earnings.
- **If you don't give it:** you get no payouts.
- **Who can see it:** you, admins and Stripe.
- **Where it is stored:** on our server and at Stripe.
- **How it is protected:** each transfer has a unique key.
- **How long we keep it:** 6 years (Accounting Act).
- **How you control it:** on Stripe's pages.

#### What you see about customers

- **What you get:** before accepting, only an area of about 1 km. After accepting, the customer's name, address, map pin and notes, and the chat.
- **Your duty:** use the data only for the delivery. Photograph only the spot where you leave the order, not people.

### Everyone

#### Crash reports (Firebase Crashlytics)

- **What we collect:** when an app crashes or our server answers with an error, the app sends a report: the error, where in the code, the app version, the role, device details (model, operating system, free memory), a random installation id and, when signed in, your account number. No name, email, phone, address, messages or what you typed.
- **Why we need it:** to find and fix faults.
- **If you don't give it:** the apps have no switch yet; you can object through Help.
- **Who can see it:** Malvoya's developers, and Google as the service provider.
- **Where it is stored:** Google Firebase.
- **How it is protected:** error texts are cleaned of personal data before sending; development builds send nothing.
- **How long we keep it:** 90 days.
- **How you control it:** object through Help or the contact form.

#### Technical logs, request ids and error tracking

- **What we collect:** one line per request: a random request id, the time, the method, the path without its query part and the result. No IP address, no content, no passwords or tokens. Your IP address is used only to limit the number of requests, for at most one hour. If error tracking (Sentry) is switched on, its reports carry only your account number.
- **Why we need it:** security, abuse prevention and fixing faults.
- **If you don't give it:** not applicable; the service cannot run without it.
- **Who can see it:** Malvoya's developers; Render and Sentry as service providers.
- **Where it is stored:** Render (Frankfurt); Sentry if switched on.
- **How it is protected:** tokens and headers are masked; Sentry reports are cleaned of emails, phone numbers, codes and IP addresses.
- **How long we keep it:** [LOG RETENTION OF THE HOSTING PLAN] days.
- **How you control it:** object through Help.

#### Maps and address search (OpenStreetMap)

- **What happens:** the apps' map pictures and address search come straight from OpenStreetMap's servers, which see your IP address, the map area you look at and the addresses you search for.
- **Why:** so you can pick the delivery address on a map and follow the delivery.
- **Who:** the OpenStreetMap Foundation (United Kingdom), as an independent recipient, not Malvoya's processor.
- **How you control it:** you can type the address without opening the map search.

#### Backups

- Our hosting provider keeps continuous database backups for [7] days. Deleted data disappears from the backups within that time.

### Location in detail

#### Shoppers

- Your phone's position is read only when you tap "Use my location" while choosing an address. It is read once and used only to place the pin. Nothing is sent until you confirm the address.
- The app does not track you in the background and does not read your location at any other time.
- The pin is stored only with an order and with the launch alert.

#### Couriers

- **The explanation comes first:** before the app asks Android for location permission, it shows what is collected and why. Your confirmation is recorded.
- **When:** only while you are online or have a delivery in progress, also in the background. A notification shows the whole time: "Your location is shared while you are online".
- **What for:** offering nearby jobs (7.5 km, nearest first), checking you are at the store (300 m), calculating pay for the ride to the store, and showing the customer your position during the delivery. The customer gets one "Your courier is arriving" notice when you are about 300 m away.
- **Who sees it:** only the customer and store of the order you are delivering, from when you accept the job until the order is delivered or taken back to the shop, and admins. On finished, cancelled or other orders your position is shown to nobody.
- **What is stored:** only your latest position (written at most every 15 seconds). No route history. With the job we store the distance of the ride to the store (for your pay) and the handover position (30 days).
- **The route on the customer's map:** the customer's app shows the street route from your position to the store, and from the store to the customer. It is worked out when asked for and never stored: the server keeps it in memory for at most 10 minutes (a route starting at your position for one minute), and only the order's customer and store get a route that starts at you, while the job is in progress. When the routing service is switched on, OpenRouteService (HeiGIT gGmbH, Germany) receives the start and end point of the route, no names or order details.
- **When it stops:** when you go offline, sharing stops and the stored position is deleted. Signing out and deleting your account stop it too. A position older than 2 minutes counts as unknown. If no new position arrives for 15 minutes (for example because the app was closed), the stored position is deleted automatically and you are set offline; if you have a delivery in progress, it carries on as normal and your position shows again with your next update.
- **Never for ads.** Your location is not used for advertising or sold.

### Payments

- You pay in Stripe's payment sheet (also Google Pay). Card details go straight to Stripe; **Malvoya never sees the full card number**, and the apps have no card fields.
- Malvoya sees only the payment status, the amount and Stripe's reference. With the payment Stripe receives the order number, your account number and the store's name.
- Stripe's payment sheet collects device information to prevent fraud. Strong customer authentication (PSD2) is handled by Stripe.
- Stores and couriers give their bank and identity details on Stripe's own pages.
- Stripe's own privacy policy: [stripe.com/privacy](https://stripe.com/privacy).

### Security measures that really exist

- **Encrypted connections (TLS/HTTPS)** for all traffic: our server, live connections, Stripe, Cloudinary, Firebase and maps.
- **Passwords** are stored only as bcrypt hashes.
- **Rotating tokens:** sessions use 15-minute tokens and single-use 7-day refresh tokens, stored only as hashes. Changing your password, or a ban or deletion, ends every session.
- **Encrypted tax IDs:** sellers' tax identification numbers and admins' two-step secrets are encrypted with AES-256-GCM.
- **Signed links:** delivery photos, monthly statements, agreement copies and unsubscribe links work only when signed; most expire in 10 minutes.
- **Rate limits** on sign-in, password reset, codes, support, chat and reports.
- **Two-step sign-in** is required for admins.
- **Least privilege:** each order is visible only to its customer, store, courier and admins; stores do not see customers' contact details; nobody can register as an admin. Admin access is not yet split into smaller roles.
- **Audit log:** admins' changes to commissions, legal texts, recalls, live streams and two-step settings are recorded, and so are approvals of stores and couriers, courier suspensions, bans, and every time the DAC7 report is opened or downloaded (that is when tax identification numbers are decrypted).
- **Backups:** the database has restorable backups.
- **Data in the EU:** server and database are in Frankfurt.

### Your rights and how to use them

| Right | What it means | How to use it |
|---|---|---|
| Access (Art. 15) | Know and get a copy of your data | Malvoya: Profile → Privacy → Your data → Download your data. Store: Store tab → Download my data. Courier: Account → Download my data (from version 1.9.1; older versions through Help) |
| Rectification (Art. 16) | We correct wrong data | Name in the profile settings, addresses in your profile, anything else through Help |
| Erasure (Art. 17) | We delete your account and data; the law may require us to keep some of it without your name | Malvoya: Profile → Privacy → Your data → Delete my account. Store and Courier: account menu → Delete account |
| Restriction (Art. 18) | Data is kept but not used | Through Help or the contact form |
| Portability (Art. 20) | Get your data in a machine-readable format | Same as the download (a JSON file) |
| Objection (Art. 21) | Object to processing based on legitimate interest, such as crash reports | Through Help or the contact form |
| Automated decisions (Art. 22) | No decisions with legal effects are made about you by automated means alone | You can always ask a person to explain or review a decision |
| Withdrawing consent | The launch alert and optional emails | Profile → Privacy → Your data → Email preferences, or the unsubscribe link in the email |

Contact form: [malvoya-api-eu.onrender.com/contact](https://malvoya-api-eu.onrender.com/contact), topic "Privacy (GDPR) request". We reply within one month. Deleting your account: [how](https://malvoya-api-eu.onrender.com/legal/delete-account).

**Complaints:** you can complain to the Data Protection Ombudsman: [tietosuoja.fi](https://tietosuoja.fi/en), PL 800, 00531 Helsinki, Finland.

### Who handles your data

| Service | What for | Where | Transfer safeguard |
|---|---|---|---|
| Render | Server and database | Frankfurt, Germany (EU) | Data in the EU; support access from the US under Standard Contractual Clauses |
| Stripe | Payments and payouts | Ireland (EU) and the US | EU–US Data Privacy Framework or Standard Contractual Clauses |
| Cloudinary | Photos, videos and sound | [CLOUDINARY REGION] | Data Privacy Framework or Standard Contractual Clauses |
| Google Firebase | Sign-in, push notifications, crash reports | EU and the US | Data Privacy Framework and Standard Contractual Clauses |
| Twilio | Text-message codes | US | Data Privacy Framework or Standard Contractual Clauses |
| LiveKit | Live-stream video (only while switched on) | [LIVEKIT REGION] | Standard Contractual Clauses |
| Sentry | Error reports (only while switched on) | [SENTRY REGION] | Data Privacy Framework or Standard Contractual Clauses |
| OpenRouteService (HeiGIT) | Street routes for the delivery map: only the start and end point (only while switched on) | Germany (EU) | Data in the EU |
| [EMAIL PROVIDER] | Emails | [REGION] | [SAFEGUARD] |
| PRH (avoindata.prh.fi) | Business ID check | Finland | Public authority; receives only the business ID |
| OpenStreetMap Foundation | Maps and address search from the phone | United Kingdom | European Commission adequacy decision; independent recipient |
| Finnish Tax Administration | DAC7 report | Finland | Required by law |

### Changes

When this page or the privacy policy changes, we publish a new version with its date. We announce changes to the privacy policy in advance by push notification and email.
