package com.malvoya.customer

import io.flutter.embedding.android.FlutterFragmentActivity

// Stripe's PaymentSheet (flutter_stripe) only starts from a FlutterFragmentActivity with an AppCompat/Material
// theme (res/values*/styles.xml); with a plain FlutterActivity every payment fails before the sheet opens.
class MainActivity : FlutterFragmentActivity()
