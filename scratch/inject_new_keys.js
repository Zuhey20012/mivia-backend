const fs = require('fs');
const path = require('path');

const l10nPath = path.resolve('c:/Users/Zuhey/mivia/Malvoya_customer/lib/l10n.dart');
let content = fs.readFileSync(l10nPath, 'utf8');

const newKeys = {
  categoriesComingSoon: {
    en: 'Categories Coming Soon',
    fi: 'Kategoriat tulossa pian',
    sv: 'Kategorier kommer snart',
    de: 'Kategorien bald verfügbar',
    fr: 'Catégories bientôt disponibles',
    nl: 'Categorieën binnenkort beschikbaar',
    it: 'Categorie presto disponibili',
    es: 'Categorías próximamente',
    pt: 'Categorias em breve',
    pl: 'Kategorie wkrótce dostępne',
    ro: 'Categorii în curând',
    cs: 'Kategorie již brzy',
    hu: 'Kategóriák hamarosan',
    el: 'Κατηγορίες σύντομα κοντά σας',
    da: 'Kategorier kommer snart',
    sk: 'Kategórie už čoskoro',
    bg: 'Категориите очаквайте скоро',
    hr: 'Kategorije uskoro dostupne',
    no: 'Kategorier kommer snart',
    ru: 'Категории скоро появятся',
    tr: 'Kategoriler yakında',
    uk: 'Категорії незабаром',
    ar: 'الفئات قريباً',
    zh: '分类即将上线',
    hi: 'श्रेणियां जल्द आ रही हैं'
  },
  categoriesComingSoonSub: {
    en: 'Curated boutique categories and collections will appear here upon launch.',
    fi: 'Boutique-kokoelmat ja kategoriat ilmestyvät tähän julkaisun myötä.',
    sv: 'Kurerade butikskategorier och kollektioner visas här vid lansering.',
    de: 'Kuratierte Boutique-Kategorien und Kollektionen erscheinen hier zum Start.',
    fr: 'Les catégories et collections des boutiques apparaîtront ici lors du lancement.',
    nl: 'Gecureerde boetiekcategorieën en collecties verschijnen hier bij de lancering.',
    it: 'Le collezioni e categorie delle boutique appariranno qui al lancio.',
    es: 'Las colecciones y categorías de boutiques aparecerán aquí tras el lanzamiento.',
    pt: 'As coleções e categorias de boutiques selecionadas aparecerão aqui no lançamento.',
    pl: 'Wyselekcjonowane kategorie i kolekcje butików pojawią się tutaj po uruchomieniu.',
    ro: 'Categoriile și colecțiile curatoriate vor apărea aici la lansare.',
    cs: 'Kategorie a kolekce butiků se zde zobrazí po spuštění.',
    hu: 'A válogatott butikkategóriák és kollekciók a megjelenéskor itt fognak megjelenni.',
    el: 'Οι επιλεγμένες κατηγορίες και συλλογές των μπουτίκ θα εμφανιστούν εδώ με την κυκλοφορία.',
    da: 'Kuraterede butikskategorier og kollektioner vises her ved lancering.',
    sk: 'Kategórie a kolekcie butikov sa tu zobrazia po spustení.',
    bg: 'Подбраните категории и колекции ще се появят тук при стартирането.',
    hr: 'Odabrane kategorije i kolekcije butika pojavit će se ovdje po pokretanju.',
    no: 'Kuraterte butikk-kategorier og kolleksjoner vises her ved lansering.',
    ru: 'Кураторские коллекции и категории бутиков появятся здесь после запуска.',
    tr: 'Seçkin butik kategorileri ve koleksiyonları açılışta burada yer alacak.',
    uk: 'Категорії та колекції бутиків зʼявляться тут після запуску.',
    ar: 'ستظهر الفئات ومجموعات المتاجر المنسقة هنا عند الإطلاق.',
    zh: '精品店分类与精选系列将在发布后在此显示。',
    hi: 'लॉन्च के समय बुटीक श्रेणियां और संग्रह यहां प्रदर्शित होंगे।'
  },
  swapVariantsComingSoon: {
    en: 'Variants Coming Soon',
    fi: 'Varianttitiedot tulossa pian',
    sv: 'Varianter kommer snart',
    de: 'Varianten bald verfügbar',
    fr: 'Variantes bientôt disponibles',
    nl: 'Varianten binnenkort beschikbaar',
    it: 'Varianti presto disponibili',
    es: 'Variantes próximamente',
    pt: 'Variantes em breve',
    pl: 'Warianty wkrótce dostępne',
    ro: 'Variante în curând',
    cs: 'Varianty již brzy',
    hu: 'Változatok hamarosan',
    el: 'Παραλλαγές σύντομα διαθέσιμες',
    da: 'Varianter kommer snart',
    sk: 'Varianty už čoskoro',
    bg: 'Вариантите очаквайте скоро',
    hr: 'Varijante uskoro dostupne',
    no: 'Varianter kommer snart',
    ru: 'Варианты скоро появятся',
    tr: 'Varyantlar yakında',
    uk: 'Варіанти незабаром',
    ar: 'الخيارات والبدائل قريباً',
    zh: '商品款式即将更新',
    hi: 'वैरिएंट जल्द आ रहे हैं'
  },
  swapVariantsComingSoonSub: {
    en: 'No color or fabric variants are listed for this item yet. Boutique inventory updates in real time.',
    fi: 'Tälle tuotteelle ei ole määritetty väri- tai materiaalivaihtoehtoja. Putiikin varastotiedot päivittyvät reaaliajassa.',
    sv: 'Inga färg- eller tygvarianter finns listade för denna vara ännu. Butikslager uppdateras i realtid.',
    de: 'Für diesen Artikel sind noch keine Farb- oder Stoffvarianten aufgeführt. Der Boutique-Bestand wird in Echtzeit aktualisiert.',
    fr: 'Aucune variante de couleur ou de matière n\'est encore répertoriée pour cet article. L\'inventaire de la boutique se met à jour en temps réel.',
    nl: 'Er zijn nog geen kleur- of stofvarianten vermeld voor dit item. Boetiekvoorraad wordt realtime bijgewerkt.',
    it: 'Non sono ancora elencate varianti di colore o tessuto per questo capo. L\'inventario della boutique si aggiorna in tempo reale.',
    es: 'Aún no hay variantes de color o tela para esta prenda. El inventario de la boutique se actualiza en tiempo real.',
    pt: 'Nenhuma variante de cor ou tecido está listada para esta peça ainda. O inventário da boutique é atualizado em tempo real.',
    pl: 'Brak wariantów kolorystycznych lub materiałowych dla tego produktu. Stany magazynowe butiku aktualizują się w czasie rzeczywistym.',
    ro: 'Nu există încă variante de culori sau materiale pentru acest articol. Stocul buticului se actualizează în timp real.',
    cs: 'Pro tuto položku zatím nejsou uvedeny žádné barevné ani materiálové varianty. Zásoby butiku se aktualizují v reálném čase.',
    hu: 'Ehhez a termékhez még nincsenek szín- vagy anyagváltozatok megadva. A butik készlete valós időben frissül.',
    el: 'Δεν υπάρχουν ακόμα παραλλαγές χρωμάτων ή υφασμάτων για αυτό το είδος. Το απόθεμα της μπουτίκ ενημερώνεται σε πραγματικό χρόνο.',
    da: 'Ingen farve- eller stofvarianter er opført for denne vare endnu. Butikslageret opdateres i realtid.',
    sk: 'Pre túto položku zatiaľ nie sú uvedené žiadne farebné ani materiálové varianty. Zásoby butiku sa aktualizujú v reálnom čase.',
    bg: 'Все още няма посочени варианти на цвят или материя за този артикул. Наличността се актуализира в реално време.',
    hr: 'Za ovaj artikl još nisu navedene varijante boja ili materijala. Zalihe butika ažuriraju se u stvarnom vremenu.',
    no: 'Ingen farge- eller stoffvarianter er oppført for denne varen ennå. Butikklageret oppdateres i sanntid.',
    ru: 'Для этого товара пока не указаны варианты расцветок или тканей. Наличие в бутике обновляется в реальном времени.',
    tr: 'Bu ürün için henüz renk veya kumaş varyantı listelenmedi. Butik stokları anlık güncellenir.',
    uk: 'Для цього товару ще не вказано варіантів кольорів чи тканин. Залишки бутика оновлюються в реальному часі.',
    ar: 'لم يتم إدراج أي ألوان أو أقمشة بديلة لهذا المنتج بعد. يتم تحديث مخزون المتاجر في الوقت الفعلي.',
    zh: '该商品暂未设置颜色或材质款式。精品店库存将实时同步。',
    hi: 'इस आइटम के लिए अभी कोई रंग या कपड़े के विकल्प सूचीबद्ध नहीं हैं। बुटीक इन्वेंट्री रीयल-टाइम में अपडेट होती है।'
  }
};

const locales = ['en','fi','sv','de','fr','nl','it','es','pt','pl','ro','cs','hu','el','da','sk','bg','hr','no','ru','tr','uk','ar','zh','hi'];

locales.forEach(loc => {
  const pattern = new RegExp(`('${loc}'\\s*:\\s*\\{)`);
  const match = content.match(pattern);
  if (match) {
    let injection = `${match[1]}\n`;
    for (const [k, vMap] of Object.entries(newKeys)) {
      const rawVal = (vMap[loc] || vMap['en']);
      // Escape backslashes first, then single quotes
      const val = rawVal.replace(/\\/g, '\\\\').replace(/'/g, "\\'");
      injection += `      '${k}': '${val}',\n`;
    }
    content = content.replace(match[1], injection);
  }
});

fs.writeFileSync(l10nPath, content, 'utf8');
console.log('Successfully injected properly escaped keys into l10n.dart');
