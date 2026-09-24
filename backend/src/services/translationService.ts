/**
 * Quick-reply phrasebook for courier ↔ customer chat.
 */
const COMMON_PHRASES: Record<string, Record<string, string>> = {
  arrived: {
    en: "I have arrived at your building entrance.",
    fi: "Olen saapunut rakennuksenne sisäänkäynnille.",
    sv: "Jag har anlänt till byggnadens entré.",
    de: "Ich bin am Eingang Ihres Gebäudes angekommen.",
    fr: "Je suis arrivé à l'entrée de votre bâtiment.",
    es: "He llegado a la entrada de su edificio.",
    it: "Sono arrivato all'ingresso del tuo edificio.",
    ar: "لقد وصلت إلى مدخل المبنى الخاص بك.",
    ru: "Я прибыл к входу в ваше здание.",
    zh: "我已经到达您的建筑入口。",
  },
  leave_at_door: {
    en: "Please leave the package at my doorstep. Thank you!",
    fi: "Jätä paketti kotiovelleni, kiitos!",
    sv: "Lämna gärna paketet vid dörren. Tack!",
    de: "Bitte stellen Sie das Paket vor meine Haustür. Danke!",
    fr: "Veuillez laisser le colis devant ma porte. Merci !",
    es: "Por favor, deje el paquete en mi puerta. ¡Gracias!",
    it: "Per favore lascia il pacco davanti alla mia porta. Grazie!",
    ar: "يرجى ترك الطرد عند باب منزلي. شكرًا لك!",
    ru: "Пожалуйста, оставьте посылку у моей двери. Спасибо!",
    zh: "请将包裹放在我家门口。谢谢！",
  },
  on_the_way: {
    en: "I am on my way with your order. See you soon!",
    fi: "Olen matkalla tilauksesi kanssa. Nähdään pian!",
    sv: "Jag är på väg med din beställning. Vi ses snart!",
    de: "Ich bin mit Ihrer Bestellung unterwegs. Bis gleich!",
    fr: "Je suis en route avec votre commande. À très vite !",
    es: "Voy de camino con tu pedido. ¡Nos vemos pronto!",
    it: "Sto arrivando con il tuo ordine. A presto!",
    ar: "أنا في طريقي مع طلبك. أراك قريبا!",
    ru: "Я в пути с вашим заказом. Скоро буду!",
    zh: "我正在给您配送订单的路上。一会儿见！",
  },
  door_code: {
    en: "The entrance door code is:",
    fi: "Alaoven ovikoodi on:",
    sv: "Portkoden är:",
    de: "Der Haustürcode lautet:",
    fr: "Le code de la porte d'entrée est :",
    es: "El código de la puerta principal es:",
    it: "Il codice del portone è:",
    ar: "رمز باب المدخل هو:",
    ru: "Код от входной двери:",
    zh: "大门密码是：",
  },
};

/**
 * Translates the courier/customer quick-reply phrases. Free text is returned unchanged with
 * `translated: false` — there is no machine translation provider wired up.
 */
export function translateChatMessage(req: { text: string; targetLanguage: string }) {
  const target = req.targetLanguage.toLowerCase().slice(0, 2);
  const normalized = req.text.trim().toLowerCase();

  for (const translations of Object.values(COMMON_PHRASES)) {
    for (const [lang, phrase] of Object.entries(translations)) {
      if (normalized === phrase.toLowerCase()) {
        const translatedText = translations[target];
        if (!translatedText) break;
        return { originalText: req.text, translatedText, sourceLanguage: lang, targetLanguage: target, translated: true };
      }
    }
  }
  return { originalText: req.text, translatedText: req.text, sourceLanguage: null, targetLanguage: target, translated: false };
}
