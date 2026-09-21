class AppConstants {
  static const String apiBase = 'https://malvoya-api-n065.onrender.com/api/v1';

  // ── Stripe ────────────────────────────────────────────────────────────────
  // Replace with your live key before production release:
  // pk_live_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
  static const String stripePublishableKey =
      'pk_test_51REPLACE_WITH_YOUR_STRIPE_PUBLISHABLE_KEY';

  // ── Delivery ──────────────────────────────────────────────────────────────
  static const double deliveryFeeCents = 299; // €2.99
}
