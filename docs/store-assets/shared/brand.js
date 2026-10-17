// Malvoya brand data for the store-asset pages (feature graphic, screenshot kit).
// The mark geometry matches the launcher icons (generated from the same 100 x 100 view box).
window.MALVOYA = (() => {
  const C = {
    birch: '#F6F3EE', night: '#17131C', ink: '#1C1820', inkSecondary: '#6B6472', sunshine: '#F2C14E',
    lilac: '#F1E7F6', mint: '#E3F2E9', peach: '#FBEAE6', sand: '#F3EEE6', clay: '#E9DFD2',
  };
  const THREAD = 'M20 82 L20 36 C20 21 36 18 43 30 L50 43 L57 30 C64 18 80 21 80 36 L80 62';
  const ARROW = (() => {
    const s = 1.5, cx = 79, cy = 85;
    const p = [[21, 3], [3, 10.53], [9.84, 14.16], [12.48, 21]].map(([x, y]) => `${(cx + (x - 12) * s).toFixed(2)} ${(cy + (y - 12) * s).toFixed(2)}`);
    return `M${p[0]} L${p[1]} L${p[2]} L${p[3]} Z`;
  })();
  function accent(kind, color) {
    if (kind === 'dot') return `<circle cx="80" cy="85" r="12.5" fill="${color}"/>`;
    if (kind === 'square') return `<rect x="68.5" y="73.5" width="23" height="23" rx="5.5" fill="${color}"/>`;
    return `<path d="${ARROW}" fill="${color}" stroke="${color}" stroke-width="2.6" stroke-linejoin="round"/>`;
  }
  /** The Thread M as an inline SVG string (view box cropped to the ink, centred). */
  function markSvg(kind, fg = C.birch, ac = C.sunshine) {
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="3.5 8 100 100" aria-hidden="true">
      <path d="${THREAD}" fill="none" stroke="${fg}" stroke-width="10" stroke-linecap="round" stroke-linejoin="round"/>${accent(kind, ac)}</svg>`;
  }

  // Captions are the ones agreed in docs/play-store-listing.md (screenshot plans). Do not add claims.
  const APPS = {
    customer: {
      name: 'Malvoya', brand: '#6D2E8C', accent: 'dot', blobs: [C.lilac, C.peach, C.mint], back: C.sunshine,
      tagline: { en: 'Local fashion, from shops near you', fi: 'Muotia lähikaupoista' },
      badge: null,
      captions: [
        { en: 'Local stores, near you', fi: 'Lähikaupat, lähelläsi', screen: 'Home with nearby stores and "open now"' },
        { en: 'Drops from local shops', fi: 'Dropit lähikaupoista', screen: 'Drops feed, a store video playing' },
        { en: 'See it before you buy', fi: 'Katso ennen kuin ostat', screen: 'Product page with gallery and sizes' },
        { en: 'The whole price, up front', fi: 'Koko hinta etukäteen', screen: 'Checkout with the full price breakdown' },
        { en: 'Follow your courier', fi: 'Seuraa lähettiä', screen: 'Order tracking map with the courier' },
        { en: 'Your data, your choice', fi: 'Sinun tietosi, sinun päätöksesi', screen: 'Profile > Privacy (download / delete)' },
      ],
    },
    store: {
      name: 'Malvoya Store', brand: '#2E6B4F', accent: 'square', blobs: [C.mint, C.sand, C.mint], back: C.mint,
      tagline: { en: 'Sell to shoppers near you', fi: 'Myy lähellä oleville' },
      badge: { en: 'New order', fi: 'Uusi tilaus' },
      captions: [
        { en: 'Never miss an order', fi: 'Älä missaa tilausta', screen: 'Orders tab with a new order ringing' },
        { en: 'Products in minutes', fi: 'Tuotteet hetkessä', screen: 'Product editor with photos, options and a video' },
        { en: 'Post drops to local shoppers', fi: 'Julkaise dropeja lähiasiakkaille', screen: 'Create drop' },
        { en: 'Bring your catalogue', fi: 'Tuo valikoimasi', screen: 'Import screen (Shopify / CSV)' },
        { en: 'Open when you are', fi: 'Auki, kun sinä olet', screen: 'Store tab: opening hours and pause switch' },
        { en: 'Payouts through Stripe', fi: 'Tilitykset Stripen kautta', screen: 'Payouts screen (Stripe)' },
      ],
    },
    courier: {
      name: 'Malvoya Courier', brand: '#C2412D', accent: 'arrow', blobs: [C.peach, C.clay, C.peach], back: C.clay,
      tagline: { en: 'Deliver on your own schedule', fi: 'Toimita omaan tahtiisi' },
      badge: { en: 'Online', fi: 'Linjoilla' },
      captions: [
        { en: 'Go online when it suits you', fi: 'Linjoille, kun sinulle sopii', screen: 'Jobs tab, online, one offer with pay' },
        { en: 'See the pay before you accept', fi: 'Näet palkkion ennen hyväksymistä', screen: 'Offer with "How is this pay calculated?" open' },
        { en: 'Every step, clearly', fi: 'Jokainen vaihe selkeästi', screen: 'Delivery tab, step by step' },
        { en: 'Hand over with care', fi: 'Luovuta huolella', screen: 'Handover sheet' },
        { en: 'Your earnings in one place', fi: 'Ansiosi yhdessä paikassa', screen: 'Earnings tab' },
        { en: 'Location only while online', fi: 'Sijainti vain linjoilla', screen: 'Offline screen with the location note' },
      ],
    },
  };
  return { C, APPS, markSvg };
})();
