class AppConstants {
  static const String apiBase = 'https://malvoya-api-n065.onrender.com/api/v1';

  // ── Stripe ────────────────────────────────────────────────────────────────
  // Replace with your live key before production release:
  // pk_live_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
  static const String stripePublishableKey =
      'pk_test_51TOjJo3M5GqLVxWTAIEdDZp3kAAzXu3OMwkhDkFhxGWlsEswMvu28mBFgQzzFs2ncWy79XQJOE2rZAk3ZfydJYss00ia1w0Cw2';

  // ── Delivery ──────────────────────────────────────────────────────────────
  static const double deliveryFeeCents = 299; // €2.99
}
