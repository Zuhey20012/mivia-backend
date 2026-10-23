/**
 * The category tree (docs/compliance/product-data-spec.md §1.3) and the import keyword lists (§1.4), in one data file.
 * Seeded into the Category table at start-up (catalog/seed.ts): slugs are stable forever; names, order and visibility
 * can be changed by an admin afterwards (the seed never overwrites them). Icons are Material icon names; tile colours
 * are Birch palette names. No leaf or planet icons (AB §5).
 */

export const TEMPLATES = [
  "APPAREL", "APPAREL_ACCESSORY", "FOOTWEAR", "BAG", "ACCESSORY", "EYEWEAR", "WATCH", "JEWELLERY",
  "COSMETIC_MAKEUP", "COSMETIC_SKIN", "COSMETIC_HAIR", "COSMETIC_NAIL", "FRAGRANCE", "BEAUTY_TOOL", "HAIR_TOOL",
] as const;
export type Template = (typeof TEMPLATES)[number];

/** Cosmetics law applies (Reg. 1223/2009): label facts on the listing, business sellers only, hygiene seal allowed. */
export const COSMETIC_TEMPLATES: Template[] = ["COSMETIC_MAKEUP", "COSMETIC_SKIN", "COSMETIC_HAIR", "COSMETIC_NAIL", "FRAGRANCE"];
export const isCosmetic = (t: string | null | undefined) => !!t && (COSMETIC_TEMPLATES as string[]).includes(t);

/** Beauty products default to Unisex and are never promoted in Kids sections (owner rule, category-sections-v2 §2). */
export const BEAUTY_TOPS = ["makeup", "skincare", "haircare", "fragrance"];

export type Sub = {
  slug: string; fi: string; en: string; icon: string; tile: string; template: Template;
  kwFi?: string[]; kwEn?: string[]; productTypes?: string[];
};
export type Collection = {
  slug: string; fi: string; en: string; icon: string; tile: string;
  /** The saved filter: second-hand items of a top level, designer/vintage attribute, or kids audience */
  filter: { top?: string; facet?: [string, string]; audience?: "KIDS" };
};
export type Top = {
  slug: string; fi: string; en: string; icon: string; tile: string;
  kwFi?: string[]; kwEn?: string[];
  children?: Sub[];
  collections?: Collection[];
};

export const TAXONOMY: Top[] = [
  {
    slug: "clothing", fi: "Vaatteet", en: "Clothing", icon: "checkroom", tile: "lilac",
    kwFi: ["vaatteet", "vaate"], kwEn: ["clothing", "clothes", "apparel"],
    children: [
      { slug: "clothing-dresses", fi: "Mekot", en: "Dresses", icon: "checkroom", tile: "lilac", template: "APPAREL",
        kwFi: ["mekko", "mekot", "leninki", "tunikamekko"], kwEn: ["dress", "gown", "sundress"] },
      { slug: "clothing-tops", fi: "Paidat ja topit", en: "T-shirts & tops", icon: "checkroom", tile: "lilac", template: "APPAREL",
        kwFi: ["t-paita", "paita", "paidat", "toppi", "top", "body", "pitkähihainen"], kwEn: ["t-shirt", "tee", "tshirt", "top", "tank", "camisole", "bodysuit", "longsleeve"] },
      { slug: "clothing-shirts-blouses", fi: "Kauluspaidat ja puserot", en: "Shirts & blouses", icon: "dry_cleaning", tile: "lilac", template: "APPAREL",
        kwFi: ["kauluspaita", "pusero", "paitapusero"], kwEn: ["shirt", "blouse", "button-down"] },
      { slug: "clothing-knitwear", fi: "Neuleet ja hupparit", en: "Knitwear & hoodies", icon: "checkroom", tile: "clay", template: "APPAREL",
        kwFi: ["neule", "neuleet", "villapaita", "neuletakki", "huppari", "college", "collegepaita", "svetari"], kwEn: ["sweater", "jumper", "knit", "knitwear", "cardigan", "hoodie", "sweatshirt", "pullover"] },
      { slug: "clothing-jackets-coats", fi: "Takit", en: "Jackets & coats", icon: "dry_cleaning", tile: "clay", template: "APPAREL",
        kwFi: ["takki", "takit", "toppatakki", "untuvatakki", "parka", "liivi"], kwEn: ["jacket", "coat", "parka", "puffer", "down jacket", "gilet", "vest", "windbreaker"] },
      { slug: "clothing-trousers-jeans", fi: "Housut ja farkut", en: "Trousers & jeans", icon: "checkroom", tile: "sand", template: "APPAREL",
        kwFi: ["housut", "farkut", "legginsit", "chinot", "verkkarit", "collegehousut"], kwEn: ["trousers", "pants", "jeans", "denim", "leggings", "chinos", "joggers"] },
      { slug: "clothing-skirts-shorts", fi: "Hameet ja shortsit", en: "Skirts & shorts", icon: "checkroom", tile: "peach", template: "APPAREL",
        kwFi: ["hame", "hameet", "shortsit", "sortsit"], kwEn: ["skirt", "shorts"] },
      { slug: "clothing-suits-blazers", fi: "Puvut ja bleiserit", en: "Suits & blazers", icon: "dry_cleaning", tile: "sand", template: "APPAREL",
        kwFi: ["puku", "bleiseri", "pikkutakki", "smokki"], kwEn: ["suit", "blazer", "tuxedo"] },
      { slug: "clothing-underwear-nightwear", fi: "Alusvaatteet ja sukat", en: "Underwear & socks", icon: "checkroom", tile: "peach", template: "APPAREL",
        kwFi: ["alusvaate", "alusvaatteet", "alushousut", "rintaliivit", "rintaliivi", "bokserit", "sukat", "sukkahousut"], kwEn: ["underwear", "briefs", "boxers", "bra", "lingerie", "socks", "tights"] },
      { slug: "clothing-nightwear-loungewear", fi: "Yöasut ja oleiluvaatteet", en: "Nightwear & loungewear", icon: "nightlight", tile: "lilac", template: "APPAREL",
        kwFi: ["yöpaita", "yöasu", "pyjama", "aamutakki", "oleiluasu"], kwEn: ["pyjamas", "pajamas", "nightwear", "nightdress", "robe", "loungewear"] },
      { slug: "clothing-swimwear", fi: "Uima-asut ja rantavaatteet", en: "Swimwear & beachwear", icon: "pool", tile: "mint", template: "APPAREL",
        kwFi: ["uimapuku", "bikinit", "uimahousut", "uima-asu", "rantamekko", "kaftaani"], kwEn: ["swimsuit", "swimwear", "bikini", "swim shorts", "trunks", "beachwear", "kaftan"] },
      { slug: "clothing-outdoor-rainwear", fi: "Ulkoilu- ja sadevaatteet", en: "Outdoor & rainwear", icon: "umbrella", tile: "sand", template: "APPAREL",
        kwFi: ["sadetakki", "sadeasu", "sadehousut", "sadevaatteet", "kuoritakki", "kuorihousut", "ulkoiluhousut", "välikausitakki"], kwEn: ["raincoat", "rain jacket", "rainwear", "shell jacket", "outdoor jacket"] },
      { slug: "clothing-workwear", fi: "Työvaatteet", en: "Workwear", icon: "work", tile: "clay", template: "APPAREL",
        kwFi: ["työvaate", "työvaatteet", "työhousut", "työtakki", "kokkitakki"], kwEn: ["workwear", "work trousers", "work jacket", "chef jacket"] },
      { slug: "clothing-festive-traditional", fi: "Juhlavaatteet ja kansallispuvut", en: "Traditional & festive wear", icon: "celebration", tile: "peach", template: "APPAREL",
        kwFi: ["juhlavaate", "juhlavaatteet", "kansallispuku", "iltapuku", "juhlamekko"], kwEn: ["festive wear", "national costume", "evening gown", "ball gown"] },
      { slug: "clothing-other", fi: "Muut vaatteet", en: "Other clothing", icon: "checkroom", tile: "sand", template: "APPAREL" },
    ],
  },
  {
    slug: "shoes", fi: "Kengät", en: "Shoes", icon: "snowshoeing", tile: "clay",
    kwFi: ["kengät", "kenkä", "jalkineet"], kwEn: ["shoes", "shoe", "footwear"],
    children: [
      { slug: "shoes-sneakers", fi: "Tennarit", en: "Sneakers", icon: "directions_run", tile: "clay", template: "FOOTWEAR",
        kwFi: ["tennarit", "tennari", "lenkkarit", "sneakerit"], kwEn: ["sneakers", "trainers", "sneaker"] },
      { slug: "shoes-boots", fi: "Saappaat ja nilkkurit", en: "Boots & ankle boots", icon: "snowshoeing", tile: "clay", template: "FOOTWEAR",
        kwFi: ["saappaat", "nilkkurit", "maiharit", "chelsea"], kwEn: ["boots", "ankle boots", "chelsea boots"] },
      { slug: "shoes-winter-rubber-boots", fi: "Talvikengät", en: "Winter boots", icon: "ac_unit", tile: "sand", template: "FOOTWEAR",
        kwFi: ["talvikengät", "talvikenkä", "talvisaappaat", "toppakengät"], kwEn: ["winter boots", "snow boots", "winter shoes"] },
      { slug: "shoes-rubber-boots", fi: "Kumisaappaat", en: "Rubber boots", icon: "water_drop", tile: "mint", template: "FOOTWEAR",
        kwFi: ["kumisaappaat", "kumisaapas", "sadesaappaat"], kwEn: ["rain boots", "rubber boots", "wellies", "wellingtons"] },
      { slug: "shoes-first-shoes", fi: "Ensikengät", en: "Kids' first shoes", icon: "child_care", tile: "peach", template: "FOOTWEAR",
        kwFi: ["ensikengät", "vauvankengät", "nahkatossut"], kwEn: ["first shoes", "baby shoes", "pram shoes"] },
      { slug: "shoes-heels", fi: "Korkokengät", en: "Heels", icon: "snowshoeing", tile: "lilac", template: "FOOTWEAR",
        kwFi: ["korkokengät", "avokkaat", "piikkikorot"], kwEn: ["heels", "pumps", "stilettos"] },
      { slug: "shoes-flats-loafers", fi: "Ballerinat ja loaferit", en: "Flats & loafers", icon: "snowshoeing", tile: "peach", template: "FOOTWEAR",
        kwFi: ["ballerinat", "loaferit", "mokkasiinit"], kwEn: ["flats", "ballet flats", "loafers", "moccasins", "brogues"] },
      { slug: "shoes-sandals", fi: "Sandaalit ja varvastossut", en: "Sandals & slides", icon: "beach_access", tile: "sunshineLight", template: "FOOTWEAR",
        kwFi: ["sandaalit", "varvastossut", "sandaletit", "puukengät"], kwEn: ["sandals", "slides", "flip-flops", "clogs", "mules"] },
      { slug: "shoes-slippers", fi: "Tohvelit ja sisäkengät", en: "Slippers & indoor shoes", icon: "weekend", tile: "sand", template: "FOOTWEAR",
        kwFi: ["tohvelit", "sisäkengät", "aamutossut"], kwEn: ["slippers", "house shoes"] },
    ],
  },
  {
    slug: "bags", fi: "Laukut", en: "Bags", icon: "shopping_bag", tile: "mint",
    kwFi: ["laukut", "laukku"], kwEn: ["bags", "bag"],
    children: [
      { slug: "bags-handbags", fi: "Käsilaukut", en: "Handbags", icon: "shopping_bag", tile: "mint", template: "BAG",
        kwFi: ["käsilaukku", "käsilaukut"], kwEn: ["handbag", "purse"] },
      { slug: "bags-shoulder-crossbody", fi: "Olka- ja crossbody-laukut", en: "Shoulder & crossbody bags", icon: "shopping_bag", tile: "mint", template: "BAG",
        kwFi: ["olkalaukku", "olkalaukut", "crossbody"], kwEn: ["shoulder bag", "crossbody", "messenger"] },
      { slug: "bags-totes", fi: "Kangas- ja ostoskassit", en: "Totes & shoppers", icon: "local_mall", tile: "sand", template: "BAG",
        kwFi: ["kangaskassi", "kassi", "ostoskassi", "shopperi"], kwEn: ["tote", "shopper", "canvas bag"] },
      { slug: "bags-backpacks", fi: "Reput", en: "Backpacks", icon: "backpack", tile: "clay", template: "BAG",
        kwFi: ["reppu", "selkäreppu", "reput"], kwEn: ["backpack", "rucksack"] },
      { slug: "bags-clutches", fi: "Pikkulaukut ja clutchit", en: "Clutches & evening bags", icon: "shopping_bag", tile: "lilac", template: "BAG",
        kwFi: ["pikkulaukku", "iltalaukku", "clutch"], kwEn: ["clutch", "evening bag"] },
      { slug: "bags-wallets", fi: "Lompakot ja korttikotelot", en: "Wallets & card holders", icon: "account_balance_wallet", tile: "sand", template: "BAG",
        kwFi: ["lompakko", "kukkaro", "korttikotelo"], kwEn: ["wallet", "card holder", "coin purse"] },
      { slug: "bags-travel", fi: "Matka- ja viikonloppulaukut", en: "Travel & weekend bags", icon: "luggage", tile: "clay", template: "BAG",
        kwFi: ["matkalaukku", "weekend-laukku", "urheilukassi"], kwEn: ["travel bag", "weekender", "duffel", "suitcase"] },
      { slug: "bags-belt-bags", fi: "Vyölaukut", en: "Belt bags", icon: "shopping_bag", tile: "peach", template: "BAG",
        kwFi: ["vyölaukku"], kwEn: ["belt bag", "bum bag", "fanny pack"] },
    ],
  },
  {
    slug: "accessories", fi: "Asusteet", en: "Accessories", icon: "watch", tile: "sunshineLight",
    kwFi: ["asusteet", "asuste"], kwEn: ["accessories", "accessory"],
    children: [
      { slug: "accessories-hats-beanies", fi: "Pipot ja hatut", en: "Beanies & hats", icon: "face", tile: "sunshineLight", template: "APPAREL_ACCESSORY",
        kwFi: ["pipo", "hattu", "lippis", "lippalakki", "myssy"], kwEn: ["beanie", "hat", "cap", "bucket hat"] },
      { slug: "accessories-scarves", fi: "Huivit", en: "Scarves & shawls", icon: "waves", tile: "peach", template: "APPAREL_ACCESSORY",
        kwFi: ["huivi", "kaulahuivi", "kaulaliina", "tuubihuivi"], kwEn: ["scarf", "scarves", "shawl", "snood"] },
      { slug: "accessories-gloves-mittens", fi: "Käsineet ja lapaset", en: "Gloves & mittens", icon: "back_hand", tile: "sand", template: "APPAREL_ACCESSORY",
        kwFi: ["käsineet", "hanskat", "lapaset", "sormikkaat"], kwEn: ["gloves", "mittens"] },
      { slug: "accessories-belts", fi: "Vyöt", en: "Belts", icon: "straighten", tile: "clay", template: "ACCESSORY",
        kwFi: ["vyö", "vyöt", "nahkavyö"], kwEn: ["belt"] },
      { slug: "accessories-sunglasses", fi: "Aurinkolasit", en: "Sunglasses", icon: "visibility", tile: "sunshineLight", template: "EYEWEAR",
        kwFi: ["aurinkolasit"], kwEn: ["sunglasses", "shades"] },
      { slug: "accessories-watches", fi: "Kellot", en: "Watches", icon: "watch", tile: "lilac", template: "WATCH",
        kwFi: ["kello", "rannekello", "kellot"], kwEn: ["watch", "wristwatch"] },
      { slug: "accessories-hair", fi: "Hiusasusteet", en: "Hair accessories", icon: "content_cut", tile: "peach", template: "ACCESSORY",
        kwFi: ["hiuspinni", "panta", "scrunchie", "hiussolki", "hiuskoru"], kwEn: ["hair clip", "headband", "scrunchie", "hair tie", "barrette"] },
      { slug: "accessories-small", fi: "Solmiot ja muut asusteet", en: "Ties & small accessories", icon: "style", tile: "sand", template: "ACCESSORY",
        kwFi: ["solmio", "rusetti", "taskuliina", "avaimenperä"], kwEn: ["tie", "bow tie", "pocket square", "keyring"] },
    ],
  },
  {
    slug: "jewellery", fi: "Korut", en: "Jewellery", icon: "diamond", tile: "lilac",
    kwFi: ["korut", "koru"], kwEn: ["jewellery", "jewelry"],
    children: [
      { slug: "jewellery-earrings", fi: "Korvakorut", en: "Earrings", icon: "hearing", tile: "lilac", template: "JEWELLERY",
        kwFi: ["korvakorut", "korvakoru", "nappikorvikset"], kwEn: ["earrings", "studs", "hoops"] },
      { slug: "jewellery-necklaces", fi: "Kaulakorut ja riipukset", en: "Necklaces & pendants", icon: "diamond", tile: "lilac", template: "JEWELLERY",
        kwFi: ["kaulakoru", "riipus", "ketju"], kwEn: ["necklace", "pendant", "chain", "choker"] },
      { slug: "jewellery-rings", fi: "Sormukset", en: "Rings", icon: "radio_button_unchecked", tile: "sunshineLight", template: "JEWELLERY",
        kwFi: ["sormus", "sormukset"], kwEn: ["ring"] },
      { slug: "jewellery-bracelets", fi: "Rannekorut", en: "Bracelets & bangles", icon: "diamond", tile: "peach", template: "JEWELLERY",
        kwFi: ["rannekoru", "rannerengas", "ranneketju"], kwEn: ["bracelet", "bangle", "cuff"] },
      { slug: "jewellery-piercing", fi: "Lävistyskorut", en: "Piercing jewellery", icon: "diamond", tile: "sand", template: "JEWELLERY",
        kwFi: ["lävistyskoru", "nenäkoru", "napakoru"], kwEn: ["piercing", "nose ring", "belly ring", "body jewellery"] },
      { slug: "jewellery-brooches", fi: "Rintaneulat", en: "Brooches & pins", icon: "push_pin", tile: "clay", template: "JEWELLERY",
        kwFi: ["rintaneula", "rintakoru"], kwEn: ["brooch", "pin"] },
      { slug: "jewellery-sets-charms", fi: "Korusetit ja hely", en: "Jewellery sets & charms", icon: "auto_awesome", tile: "lilac", template: "JEWELLERY",
        kwFi: ["korusetti", "hela", "berloki"], kwEn: ["jewellery set", "jewelry set", "charm"] },
    ],
  },
  {
    slug: "makeup", fi: "Meikit", en: "Makeup", icon: "brush", tile: "peach",
    kwFi: ["meikit", "meikki", "kosmetiikka"], kwEn: ["makeup", "make-up", "cosmetics"],
    children: [
      { slug: "makeup-face", fi: "Kasvot", en: "Face", icon: "face_retouching_natural", tile: "peach", template: "COSMETIC_MAKEUP",
        kwFi: ["meikkivoide", "peitevoide", "puuteri", "poskipuna", "aurinkopuuteri", "korostus", "pohjustusvoide"], kwEn: ["foundation", "concealer", "powder", "blush", "bronzer", "highlighter", "primer", "bb cream", "cc cream"],
        productTypes: ["foundation", "concealer", "powder", "blush", "bronzer", "highlighter", "primer", "setting_spray", "bb_cc_cream"] },
      { slug: "makeup-eyes", fi: "Silmät", en: "Eyes", icon: "visibility", tile: "lilac", template: "COSMETIC_MAKEUP",
        kwFi: ["ripsiväri", "silmänrajaus", "rajauskynä", "luomiväri", "kulmakynä", "kulmageeli"], kwEn: ["mascara", "eyeliner", "eyeshadow", "brow pencil", "brow gel"],
        productTypes: ["mascara", "eyeliner", "eyeshadow", "eyeshadow_palette", "brow", "lash_serum"] },
      { slug: "makeup-lips", fi: "Huulet", en: "Lips", icon: "brush", tile: "peach", template: "COSMETIC_MAKEUP",
        kwFi: ["huulipuna", "huulikiilto", "huultenrajauskynä", "sävyttävä huulivoide", "huulivoide"], kwEn: ["lipstick", "lip gloss", "lip liner", "lip tint"],
        productTypes: ["lipstick", "liquid_lipstick", "lip_gloss", "lip_liner", "tinted_lip_balm"] },
      { slug: "makeup-nails", fi: "Kynnet", en: "Nails", icon: "back_hand", tile: "sunshineLight", template: "COSMETIC_NAIL",
        kwFi: ["kynsilakka", "geelilakka", "aluslakka", "päällyslakka", "kynsilakanpoistoaine"], kwEn: ["nail polish", "gel polish", "base coat", "top coat", "nail polish remover"],
        productTypes: ["nail_polish", "gel_polish", "top_base_coat", "nail_care", "nail_polish_remover"] },
      { slug: "makeup-tools", fi: "Siveltimet ja välineet", en: "Brushes & tools", icon: "brush", tile: "sand", template: "BEAUTY_TOOL",
        kwFi: ["sivellin", "meikkisieni", "ripsitaivutin", "meikkisivellin"], kwEn: ["makeup brush", "makeup sponge", "eyelash curler", "false lashes"],
        productTypes: ["brush", "sponge", "eyelash_curler", "mirror", "bag", "false_lashes"] },
      { slug: "makeup-sets", fi: "Meikkisetit ja paletit", en: "Sets & palettes", icon: "palette", tile: "clay", template: "COSMETIC_MAKEUP",
        kwFi: ["meikkisetti", "paletti"], kwEn: ["makeup set", "palette"], productTypes: ["set", "palette"] },
    ],
  },
  {
    slug: "skincare", fi: "Ihonhoito", en: "Skincare", icon: "spa", tile: "mint",
    kwFi: ["ihonhoito"], kwEn: ["skincare", "skin care"],
    children: [
      { slug: "skincare-cleansers", fi: "Puhdistus ja meikinpoisto", en: "Cleansers & makeup removers", icon: "water_drop", tile: "mint", template: "COSMETIC_SKIN",
        kwFi: ["puhdistusaine", "puhdistusgeeli", "meikinpoistoaine", "misellivesi", "puhdistusöljy"], kwEn: ["cleanser", "face wash", "makeup remover", "micellar water", "cleansing oil"] },
      { slug: "skincare-toners-mists", fi: "Kasvovedet ja suihkeet", en: "Toners & mists", icon: "water_drop", tile: "sand", template: "COSMETIC_SKIN",
        kwFi: ["kasvovesi", "kasvosuihke", "esanssi"], kwEn: ["toner", "face mist", "essence"] },
      { slug: "skincare-serums", fi: "Seerumit ja tehohoidot", en: "Serums & treatments", icon: "science", tile: "lilac", template: "COSMETIC_SKIN",
        kwFi: ["seerumi", "kasvoseerumi", "ampulli"], kwEn: ["serum", "face serum", "ampoule"] },
      { slug: "skincare-moisturisers", fi: "Kosteusvoiteet", en: "Moisturisers", icon: "spa", tile: "mint", template: "COSMETIC_SKIN",
        kwFi: ["kosteusvoide", "päivävoide", "yövoide", "kasvovoide"], kwEn: ["moisturiser", "moisturizer", "day cream", "night cream", "face cream"] },
      { slug: "skincare-eye", fi: "Silmänympärysvoiteet", en: "Eye care", icon: "visibility", tile: "peach", template: "COSMETIC_SKIN",
        kwFi: ["silmänympärysvoide", "silmävoide"], kwEn: ["eye cream", "eye serum"] },
      { slug: "skincare-masks-exfoliators", fi: "Naamiot ja kuorinnat", en: "Masks & exfoliators", icon: "face", tile: "clay", template: "COSMETIC_SKIN",
        kwFi: ["kasvonaamio", "naamio", "kuorinta", "kuorinta-aine"], kwEn: ["face mask", "sheet mask", "exfoliator", "scrub", "peel"] },
      { slug: "skincare-sun-selftan", fi: "Aurinkosuojat ja itseruskettavat", en: "Sun care & self-tan", icon: "wb_sunny", tile: "sunshineLight", template: "COSMETIC_SKIN",
        kwFi: ["aurinkosuoja", "aurinkovoide", "itseruskettava"], kwEn: ["sunscreen", "spf", "sun cream", "self-tan", "after sun"] },
      { slug: "skincare-body", fi: "Vartalonhoito ja deodorantit", en: "Body care & deodorants", icon: "shower", tile: "mint", template: "COSMETIC_SKIN",
        kwFi: ["vartalovoide", "suihkusaippua", "suihkugeeli", "deodorantti", "vartaloöljy"], kwEn: ["body lotion", "body cream", "shower gel", "body wash", "deodorant", "body oil"] },
      { slug: "skincare-hands-feet", fi: "Käsien ja jalkojen hoito", en: "Hand & foot care", icon: "back_hand", tile: "sand", template: "COSMETIC_SKIN",
        kwFi: ["käsivoide", "jalkavoide"], kwEn: ["hand cream", "foot cream"] },
      { slug: "skincare-mens-grooming", fi: "Miesten hoito", en: "Men's grooming", icon: "face_6", tile: "clay", template: "COSMETIC_SKIN",
        kwFi: ["partaöljy", "partavaha", "partabalsami", "parranajovaahto", "parranajogeeli", "partasaippua"], kwEn: ["beard oil", "beard balm", "shaving foam", "shaving gel", "shaving cream", "aftershave balm"] },
    ],
  },
  {
    slug: "haircare", fi: "Hiustenhoito", en: "Haircare", icon: "content_cut", tile: "sunshineLight",
    kwFi: ["hiustenhoito"], kwEn: ["haircare", "hair care"],
    children: [
      { slug: "haircare-shampoo", fi: "Shampoot", en: "Shampoo", icon: "water_drop", tile: "sunshineLight", template: "COSMETIC_HAIR",
        kwFi: ["shampoo", "kuivashampoo"], kwEn: ["shampoo", "dry shampoo"] },
      { slug: "haircare-conditioner", fi: "Hoitoaineet", en: "Conditioner", icon: "water_drop", tile: "peach", template: "COSMETIC_HAIR",
        kwFi: ["hoitoaine", "hoitosuihke"], kwEn: ["conditioner", "leave-in"] },
      { slug: "haircare-masks-treatments", fi: "Hiusnaamiot ja tehohoidot", en: "Masks & treatments", icon: "spa", tile: "lilac", template: "COSMETIC_HAIR",
        kwFi: ["hiusnaamio", "hiusten tehohoito"], kwEn: ["hair mask", "hair treatment"] },
      { slug: "haircare-oils-serums", fi: "Hiusöljyt ja seerumit", en: "Oils & serums", icon: "opacity", tile: "sunshineLight", template: "COSMETIC_HAIR",
        kwFi: ["hiusöljy", "hiusseerumi"], kwEn: ["hair oil", "hair serum"] },
      { slug: "haircare-styling", fi: "Muotoilutuotteet", en: "Styling", icon: "air", tile: "mint", template: "COSMETIC_HAIR",
        kwFi: ["muotoilutuote", "hiuslakka", "hiusvaha", "muotovaahto", "lämpösuoja"], kwEn: ["hairspray", "hair wax", "hair gel", "mousse", "heat protectant"] },
      { slug: "haircare-colour", fi: "Hiusvärit", en: "Hair colour", icon: "palette", tile: "clay", template: "COSMETIC_HAIR",
        kwFi: ["hiusväri", "sävyte", "hennaväri"], kwEn: ["hair dye", "hair colour", "hair color", "henna"] },
      { slug: "haircare-scalp", fi: "Hiuspohjan hoito", en: "Scalp care", icon: "spa", tile: "sand", template: "COSMETIC_HAIR",
        kwFi: ["hiuspohja", "hiuspohjan"], kwEn: ["scalp", "scalp serum"] },
      { slug: "haircare-brushes-tools", fi: "Harjat ja välineet", en: "Brushes & tools", icon: "brush", tile: "sand", template: "BEAUTY_TOOL",
        kwFi: ["hiusharja", "kampa"], kwEn: ["hairbrush", "hair brush", "comb"], productTypes: ["brush", "comb"] },
      // Electrical (owner decision 22 Oct 2026): CE marking and the electrical safety information are required to publish
      { slug: "haircare-hair-tools", fi: "Hiustenmuotoilulaitteet", en: "Hair tools", icon: "electrical_services", tile: "lilac", template: "HAIR_TOOL",
        kwFi: ["hiustenkuivaaja", "suoristusrauta", "kiharrin", "kihartimet", "muotoiluharja", "lämpöharja"], kwEn: ["hair dryer", "hairdryer", "straightener", "flat iron", "curling iron", "curling wand", "hot brush"],
        productTypes: ["hair_dryer", "straightener", "curler", "hot_brush"] },
    ],
  },
  {
    slug: "fragrance", fi: "Tuoksut", en: "Fragrance", icon: "local_florist", tile: "peach",
    kwFi: ["tuoksut", "tuoksu"], kwEn: ["fragrance", "fragrances"],
    children: [
      { slug: "fragrance-parfum-edp", fi: "Parfyymit ja eau de parfumit", en: "Parfum & eau de parfum", icon: "local_florist", tile: "peach", template: "FRAGRANCE",
        kwFi: ["hajuvesi", "parfyymi", "eau de parfum", "edp"], kwEn: ["perfume", "parfum", "eau de parfum", "edp"] },
      { slug: "fragrance-edt-cologne", fi: "Eau de toiletteet ja colognet", en: "Eau de toilette & cologne", icon: "local_florist", tile: "lilac", template: "FRAGRANCE",
        kwFi: ["eau de toilette", "edt", "cologne", "partavesi"], kwEn: ["eau de toilette", "edt", "cologne", "aftershave"] },
      { slug: "fragrance-body-hair-mists", fi: "Vartalo- ja hiussuihkeet", en: "Body & hair mists", icon: "air", tile: "mint", template: "FRAGRANCE",
        kwFi: ["vartalosuihke", "hiustuoksu"], kwEn: ["body mist", "hair mist"] },
      { slug: "fragrance-oils-solid", fi: "Tuoksuöljyt ja kiinteät tuoksut", en: "Perfume oils & solid perfume", icon: "opacity", tile: "sand", template: "FRAGRANCE",
        kwFi: ["tuoksuöljy", "kiinteä hajuvesi"], kwEn: ["perfume oil", "solid perfume"] },
      { slug: "fragrance-gift-sets", fi: "Tuoksulahjapakkaukset", en: "Gift sets", icon: "redeem", tile: "clay", template: "FRAGRANCE",
        kwFi: ["tuoksulahjapakkaus"], kwEn: ["fragrance gift set", "perfume gift set"] },
      { slug: "fragrance-travel", fi: "Matkakoot", en: "Travel sizes", icon: "luggage", tile: "sunshineLight", template: "FRAGRANCE",
        kwFi: ["matkakoko", "minikoko"], kwEn: ["travel size", "travel spray"] },
    ],
  },
  {
    slug: "sport-outdoor", fi: "Urheilu ja ulkoilu", en: "Sport & outdoor", icon: "directions_run", tile: "mint",
    kwFi: ["urheilu", "ulkoilu"], kwEn: ["sport", "sports", "outdoor"],
    children: [
      { slug: "sport-activewear", fi: "Treenivaatteet", en: "Activewear", icon: "fitness_center", tile: "mint", template: "APPAREL",
        kwFi: ["urheiluvaate", "urheiluvaatteet", "treenivaate", "treenivaatteet", "treenitrikoot", "urheilurintaliivit", "treenitoppi"], kwEn: ["sportswear", "activewear", "gym wear", "sports bra", "training tights", "workout"] },
      { slug: "sport-running", fi: "Juoksu", en: "Running", icon: "directions_run", tile: "sunshineLight", template: "APPAREL",
        kwFi: ["juoksutrikoot", "juoksupaita", "juoksutakki", "juoksushortsit"], kwEn: ["running tights", "running shirt", "running jacket", "running shorts"] },
      { slug: "sport-hiking", fi: "Retkeily ja vaellus", en: "Hiking", icon: "hiking", tile: "sand", template: "APPAREL",
        kwFi: ["vaellushousut", "retkeilyhousut", "vaellustakki", "fleece", "fleecetakki"], kwEn: ["hiking trousers", "hiking pants", "hiking jacket", "fleece"] },
      { slug: "sport-ski-winter", fi: "Laskettelu ja talviurheilu", en: "Ski & winter sports", icon: "downhill_skiing", tile: "lilac", template: "APPAREL",
        kwFi: ["laskettelutakki", "laskettelupuku", "laskettelu", "hiihtoasu", "hiihtohousut", "kerrastot", "kerrasto"], kwEn: ["ski jacket", "ski pants", "ski suit", "snowboard jacket", "base layer", "thermal underwear"] },
      { slug: "sport-shoes", fi: "Urheilu- ja ulkoilukengät", en: "Sports & outdoor shoes", icon: "hiking", tile: "clay", template: "FOOTWEAR",
        kwFi: ["juoksukengät", "ulkoilukengät", "vaelluskengät", "urheilukengät", "salikengät", "maastojuoksukengät"], kwEn: ["running shoes", "hiking shoes", "hiking boots", "trail shoes", "sports shoes", "training shoes"] },
    ],
  },
  {
    slug: "second-hand", fi: "Käytetty ja vintage", en: "Second-hand & vintage", icon: "recycling", tile: "sand",
    collections: [
      { slug: "second-hand-clothing", fi: "Käytetyt vaatteet", en: "Second-hand clothing", icon: "checkroom", tile: "sand", filter: { top: "clothing" } },
      { slug: "second-hand-shoes", fi: "Käytetyt kengät", en: "Second-hand shoes", icon: "snowshoeing", tile: "clay", filter: { top: "shoes" } },
      { slug: "second-hand-bags", fi: "Käytetyt laukut", en: "Second-hand bags", icon: "shopping_bag", tile: "mint", filter: { top: "bags" } },
      { slug: "second-hand-accessories", fi: "Käytetyt asusteet", en: "Second-hand accessories", icon: "watch", tile: "sunshineLight", filter: { top: "accessories" } },
      { slug: "second-hand-jewellery", fi: "Käytetyt korut", en: "Second-hand jewellery", icon: "diamond", tile: "lilac", filter: { top: "jewellery" } },
      { slug: "second-hand-designer", fi: "Merkkituotteet", en: "Designer & luxury", icon: "auto_awesome", tile: "peach", filter: { facet: ["brandTier", "designer"] } },
      { slug: "second-hand-vintage", fi: "Vintage", en: "Vintage", icon: "history", tile: "clay", filter: { facet: ["vintage", "true"] } },
      { slug: "second-hand-kids", fi: "Käytetyt lastenvaatteet", en: "Second-hand kids' clothes", icon: "child_care", tile: "sand", filter: { audience: "KIDS" } },
    ],
  },
];

export const SECOND_HAND_TOP = "second-hand";

/** Flat lookups over the static tree. */
export const SUBS = new Map<string, Sub & { top: string }>();
export const TOPS = new Map<string, Top>();
export const COLLECTIONS = new Map<string, Collection>();
for (const top of TAXONOMY) {
  TOPS.set(top.slug, top);
  for (const c of top.children ?? []) SUBS.set(c.slug, { ...c, top: top.slug });
  for (const c of top.collections ?? []) COLLECTIONS.set(c.slug, c);
}

export function templateOf(slug: string | null | undefined): Template | null {
  return (slug && SUBS.get(slug)?.template) || null;
}

// ─── Import words that are not categories (§1.4) ───────────────────────────────

/** Audience words. "nais-", "mies-" are prefixes of Finnish compounds (naistenmekko, miestentakki). */
export const AUDIENCE_WORDS: { audience: "WOMEN" | "MEN" | "KIDS" | "UNISEX"; words: string[]; prefixes?: string[] }[] = [
  { audience: "WOMEN", words: ["naiset", "naisten", "women", "womens", "ladies", "woman", "dam", "tytöt", "tyttöjen", "girls"], prefixes: ["naisten", "nais"] },
  { audience: "MEN", words: ["miehet", "miesten", "men", "mens", "man", "herr", "pojat", "poikien", "boys"], prefixes: ["miesten"] },
  { audience: "KIDS", words: ["lapset", "lasten", "junior", "vauva", "vauvan", "kids", "children", "child", "baby", "barn"], prefixes: ["lasten", "vauvan"] },
  { audience: "UNISEX", words: ["unisex"] },
];
// Girls / boys are children: they also set KIDS (handled in the matcher)
export const CHILD_GENDER_WORDS = ["tytöt", "tyttöjen", "girls", "pojat", "poikien", "boys"];

export const SECOND_HAND_WORDS = ["käytetty", "käytetyt", "vintage", "second hand", "secondhand", "second-hand", "pre-owned", "preowned", "preloved", "pre-loved", "used", "retro", "kirpputori"];

/** Out-of-scope or restricted goods: the import puts the draft on hold with this reason (§1.4, AB §11). */
export const HOLD_WORDS: { key: string; words: string[]; reason: { en: string; fi: string } }[] = [
  { key: "home_decor", words: ["kynttilä", "kynttilät", "candle", "candles", "diffuser", "diffuusori", "sisustus", "home decor", "home décor", "sisustustuote"],
    reason: { en: "Home décor and candles are not sold on Malvoya.", fi: "Sisustustuotteita ja kynttilöitä ei myydä Malvoyassa." } },
  { key: "food_supplement", words: ["ravintolisä", "food supplement", "vitamiini", "vitamins", "kollageeni", "collagen drink", "kollageenijuoma"],
    reason: { en: "Food supplements are food (Ruokavirasto), not cosmetics, and are not sold on Malvoya.", fi: "Ravintolisät ovat elintarvikkeita (Ruokavirasto), eivät kosmetiikkaa, eikä niitä myydä Malvoyassa." } },
  { key: "medicine", words: ["lääke", "lääkkeet", "medicine", "medicinal"],
    reason: { en: "Medicines and medical devices are not sold on Malvoya.", fi: "Lääkkeitä ja lääkinnällisiä laitteita ei myydä Malvoyassa." } },
  { key: "biocide", words: ["käsidesi", "hand sanitiser", "hand sanitizer", "desinfiointiaine", "disinfectant"],
    reason: { en: "Biocides such as hand sanitiser are not sold on Malvoya.", fi: "Biosidejä, kuten käsidesiä, ei myydä Malvoyassa." } },
  { key: "chemical", words: ["kynsiliima", "nail glue", "tatuointiväri", "tattoo ink"],
    reason: { en: "Classified chemicals such as nail glue and tattoo ink are not sold on Malvoya.", fi: "Luokiteltuja kemikaaleja, kuten kynsiliimaa ja tatuointivärejä, ei myydä Malvoyassa." } },
];

export const HOLD_REASONS: Record<string, { en: string; fi: string }> = Object.fromEntries(HOLD_WORDS.map((h) => [h.key, h.reason]));
