import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import 'cart.dart';
import 'config/constants.dart';
import 'config/theme.dart';
import 'core/api_client.dart';
import 'core/delivery_location.dart';
import 'core/store_hours.dart';
import 'core/strings.dart';
import 'local_notification_service.dart';
import 'models.dart';
import 'realtime_notification_service.dart';
import 'screens/location_selector_modal.dart';
import 'screens/order_detail.dart';

/// Checkout: address, items, an optional courier tip, a promo code and the exact price the
/// server will charge. Payment details are only ever entered in Stripe's own payment sheet.
class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key});
  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  static const _tips = [0, 100, 200, 300, 500];
  static const _quoteDebounce = Duration(milliseconds: 400);

  bool _paying = false;
  String? _errorMessage;
  final _addressCtrl = TextEditingController();
  final _promoCtrl = TextEditingController();
  int _tipCents = 0;

  /// The promo code the customer applied (the server validates it in every quote).
  String? _promoCode;

  // ── Price quote ──
  // Every line of the summary comes from the server's quote for exactly these inputs, so the
  // amount on the Pay button is the amount charged.
  Map<String, dynamic>? _quote;
  String? _quoteError;

  /// Inputs (store, items, pinned address, tip, promo) of the latest quote request…
  String? _wantedKey;

  /// …and of the quote or error currently held. They differ while a quote is loading.
  String? _quotedKey;

  /// The server has no quote endpoint (an older backend): estimate from the store's delivery fee
  /// as before, without promo codes or extra fees.
  bool _legacy = false;
  bool _quoteNow = true;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    DeliveryLocation.instance.addListener(_onLocation);
    _loadSavedAddress();
  }

  @override
  void dispose() {
    DeliveryLocation.instance.removeListener(_onLocation);
    _debounce?.cancel();
    _addressCtrl.dispose();
    _promoCtrl.dispose();
    super.dispose();
  }

  void _onLocation() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSavedAddress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await DeliveryLocation.instance.load();
      final saved = DeliveryLocation.instance.address ??
          prefs.getString('malvoya_active_address') ??
          prefs.getString('saved_default_address') ??
          prefs.getString('user_delivery_address');
      if (saved != null && saved.isNotEmpty && mounted) setState(() => _addressCtrl.text = saved);
    } catch (_) {}
  }

  bool get _pinned {
    final loc = DeliveryLocation.instance;
    return loc.hasCoordinates && loc.address?.trim() == _addressCtrl.text.trim();
  }

  // ── Quote ───────────────────────────────────────────────────────────────

  String _inputsKey(CartService cart) {
    final loc = DeliveryLocation.instance;
    final items = cart.items.map((i) => '${i.productId}:${i.variantId}:${i.quantity}').join(',');
    return [cart.storeId, items, _pinned ? '${loc.lat},${loc.lng}' : '-', _tipCents, _promoCode ?? ''].join('|');
  }

  /// Asks for a new quote when the inputs changed: right away the first time and after applying
  /// a promo code, otherwise once the customer pauses (quantity taps, tips, address).
  void _scheduleQuote(String key) {
    _wantedKey = key;
    _debounce?.cancel();
    final delay = _quoteNow ? Duration.zero : _quoteDebounce;
    _quoteNow = false;
    _debounce = Timer(delay, () => _fetchQuote(key));
  }

  /// Fetches the price again now; the summary shows "calculating" until it arrives.
  void _requote() => setState(_resetQuote);

  void _resetQuote() {
    _wantedKey = null;
    _quotedKey = null;
    _quoteNow = true;
  }

  Future<void> _fetchQuote(String key) async {
    if (!mounted) return;
    final cart = Provider.of<CartService>(context, listen: false);
    final auth = Provider.of<AuthService>(context, listen: false);
    final storeId = cart.storeId;
    if (storeId == null || cart.items.isEmpty) return;
    final loc = DeliveryLocation.instance;
    final pinned = _pinned;
    final api = ApiClient(auth);
    final fallbackError = tr(context, 'The price could not be calculated.', 'Hintaa ei voitu laskea.');

    Map<String, dynamic>? quote;
    String? error;
    if (!_legacy && auth.isAuthenticated) {
      final res = await api.post('/orders/quote', {
        'storeId': storeId,
        if (pinned) ...{'deliveryLat': loc.lat, 'deliveryLng': loc.lng},
        'items': _orderItems(cart),
        if (_tipCents > 0) 'tipCents': _tipCents,
        if (_promoCode != null) 'promoCode': _promoCode,
      });
      if (!mounted || key != _wantedKey) return;
      if (res.ok && res.data['quote'] is Map) {
        quote = Map<String, dynamic>.from(res.data['quote']);
      } else if ((res.status == 404 && res.data['error'] == 'Not found') || res.status == 405) {
        _legacy = true; // this server does not have the quote endpoint yet
      } else {
        error = res.errorText(context) ?? fallbackError;
      }
    }
    if (quote == null && error == null) {
      final res = await api.get('/stores/$storeId', query: pinned ? loc.query : null);
      if (!mounted || key != _wantedKey) return;
      if (res.ok && res.data['store'] is Map) {
        quote = _estimate(cart, Map<String, dynamic>.from(res.data['store']));
      } else {
        error = res.errorText(context) ?? fallbackError;
      }
    }
    setState(() {
      _quote = quote;
      _quoteError = error;
      _quotedKey = key;
    });
  }

  /// Older-backend estimate in the quote's shape: items + the store's distance-based delivery
  /// fee + tip. The store map carries openNow/closedReason/opensAt like the quote's store.
  Map<String, dynamic> _estimate(CartService cart, Map<String, dynamic> store) {
    final subtotal = (cart.total * 100).round();
    final fee = asInt(store['deliveryFeeCents']);
    return {
      'subtotalCents': subtotal,
      'deliveryFeeCents': fee,
      'tipCents': _tipCents,
      'totalCents': fee == null ? null : subtotal + fee + _tipCents,
      'store': store,
    };
  }

  List<Map<String, dynamic>> _orderItems(CartService cart) =>
      cart.items.map((i) => i.toOrderItem()..removeWhere((_, v) => v == null)).toList();

  /// The promo code the server accepted in the current quote, if any.
  String? get _validPromo {
    final promo = _quote?['promo'];
    if (_promoCode == null || promo is! Map) return null;
    return (promo['code'] ?? _promoCode)?.toString();
  }

  void _applyPromo() {
    final code = _promoCtrl.text.trim();
    if (code.isEmpty) return;
    FocusScope.of(context).unfocus();
    HapticFeedback.selectionClick();
    setState(() {
      _promoCode = code;
      _quoteNow = true;
    });
  }

  void _removePromo() {
    HapticFeedback.selectionClick();
    setState(() {
      _promoCode = null;
      _promoCtrl.clear();
      _quoteNow = true;
    });
  }

  // ── Address & payment ───────────────────────────────────────────────────

  Future<void> _pickAddress() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (_) => LocationSelectorModal(currentLocation: _addressCtrl.text),
    );
    await DeliveryLocation.instance.load();
    final addr = DeliveryLocation.instance.address;
    if (!mounted) return;
    // A new pin changes the quote inputs, so the next build asks for a fresh price
    if (addr != null && addr.isNotEmpty) setState(() => _addressCtrl.text = addr);
  }

  Future<void> _placeOrder(CartService cart, int quotedTotal) async {
    final address = _addressCtrl.text.trim();
    if (address.length < 5) {
      setState(() => _errorMessage = tr(context, 'Enter your delivery address.', 'Kirjoita toimitusosoitteesi.'));
      return;
    }
    final auth = Provider.of<AuthService>(context, listen: false);
    if (!auth.isAuthenticated) {
      setState(() => _errorMessage = tr(context, 'Sign in to place an order.', 'Kirjaudu sisään tehdäksesi tilauksen.'));
      return;
    }

    setState(() {
      _paying = true;
      _errorMessage = null;
    });
    HapticFeedback.mediumImpact();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('malvoya_active_address', address);
    } catch (_) {}

    final loc = DeliveryLocation.instance;
    final promo = _legacy ? null : _validPromo;
    final res = await ApiClient(auth).post('/orders', {
      'storeId': cart.storeId,
      'deliveryAddress': address,
      // Coordinates only when this is the address that was pinned on the map
      if (_pinned) ...{'deliveryLat': loc.lat, 'deliveryLng': loc.lng},
      if (_tipCents > 0) 'tipCents': _tipCents,
      if (promo != null) 'promoCode': promo,
      'items': _orderItems(cart),
    });
    if (!mounted) return;
    if (!res.ok) {
      setState(() {
        _paying = false;
        _errorMessage = res.errorText(context) ?? tr(context, 'The order could not be placed. Please try again.', 'Tilausta ei voitu tehdä. Yritä uudelleen.');
        // The store may have closed or the promo code stopped working: fetch the current price
        _resetQuote();
      });
      return;
    }

    final order = Map<String, dynamic>.from(res.data['order']);
    final clientSecret = res.data['clientSecret']?.toString() ?? '';
    final orderId = asInt(order['id'])!;
    final charged = asInt(order['totalCents']) ?? quotedTotal;
    try {
      if (clientSecret.isEmpty) throw StateError('no client secret');
      // Stripe PaymentSheet: card details never touch Malvoya; 3-D Secure (PSD2 SCA) is handled by Stripe.
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'Malvoya',
          style: ThemeMode.system,
          allowsDelayedPaymentMethods: true, // SEPA Direct Debit settles after a few days
          googlePay: PaymentSheetGooglePay(
            merchantCountryCode: 'FI',
            currencyCode: 'EUR',
            testEnv: AppConstants.stripePublishableKey.startsWith('pk_test_'),
          ),
        ),
      );
      await Stripe.instance.presentPaymentSheet();
    } on StripeException catch (e) {
      if (!mounted) return;
      final cancelled = e.error.code == FailureCode.Canceled;
      setState(() {
        _paying = false;
        _errorMessage = cancelled
            ? tr(context, 'Payment cancelled. You were not charged.', 'Maksu peruttiin. Sinua ei veloitettu.')
            : (e.error.localizedMessage ?? tr(context, 'Your bank declined the payment.', 'Pankkisi hylkäsi maksun.'));
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _paying = false;
        _errorMessage = tr(context, 'Payment could not be started. You were not charged.', 'Maksua ei voitu aloittaa. Sinua ei veloitettu.');
      });
      return;
    }

    // Paid in the sheet; the order is confirmed when Stripe tells the server
    HapticFeedback.heavyImpact();
    try {
      await LocalNotificationService.showNotification(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: tr(context, 'Order #$orderId received', 'Tilaus #$orderId vastaanotettu'),
        body: tr(context, 'Payment of ${euro(context, charged)} submitted. Follow your order live in the app.',
            'Maksu ${euro(context, charged)} lähetetty. Seuraa tilaustasi sovelluksessa.'),
      );
    } catch (_) {}
    if (!mounted) return;
    RealtimeNotificationService.notifyOrderPlaced(
      context,
      orderId: '$orderId',
      total: charged / 100,
      paymentMethod: 'stripe',
      email: auth.currentUser?.email ?? '',
      phone: auth.currentUser?.phone,
    );
    cart.clear();
    // Straight to live tracking, like the big delivery apps
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: orderId)));
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartService>(context);
    final auth = Provider.of<AuthService>(context, listen: false);
    final key = cart.items.isEmpty || cart.storeId == null ? null : _inputsKey(cart);
    if (key != null && key != _wantedKey) _scheduleQuote(key);

    final loading = key != null && _quotedKey != key;
    final q = _quote;
    final error = loading ? null : _quoteError;
    final totalCents = asInt(q?['totalCents']);
    final ready = !loading && error == null && q != null && totalCents != null;
    final quotedStore = q?['store'];
    final closed = closedLabel(context, quotedStore is Map ? Map<String, dynamic>.from(quotedStore) : null);
    final showPromo = !_legacy && auth.isAuthenticated;

    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'Checkout', 'Kassa'))),
      body: cart.items.isEmpty
          ? _emptyCart()
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      if (closed != null) ...[
                        _notice(Icons.schedule_rounded,
                            '${cart.storeName ?? tr(context, 'The store', 'Kauppa')}: $closed. ${tr(context, 'You can pay when it opens.', 'Voit maksaa, kun se aukeaa.')}'),
                        const SizedBox(height: 12),
                      ],
                      _section(
                        tr(context, 'Delivery address', 'Toimitusosoite'),
                        [
                          TextField(
                            controller: _addressCtrl,
                            onChanged: (_) => setState(() {}),
                            textInputAction: TextInputAction.done,
                            decoration: InputDecoration(
                              hintText: tr(context, 'Street, number, apartment, postcode', 'Katu, numero, asunto, postinumero'),
                              prefixIcon: const Icon(Icons.location_on_outlined),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(children: [
                            Icon(_pinned ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                                size: 18, color: _pinned ? AppTheme.success : AppTheme.secondaryText(context)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _pinned
                                    ? tr(context, 'Pinned on the map: exact fee and live tracking', 'Merkitty kartalle: tarkka hinta ja live-seuranta')
                                    : tr(context, 'Pin it on the map for the exact fee and live tracking', 'Merkitse kartalle tarkkaa hintaa ja live-seurantaa varten'),
                                style: TextStyle(fontSize: 12.5, color: AppTheme.secondaryText(context)),
                              ),
                            ),
                            TextButton(onPressed: _pickAddress, child: Text(tr(context, 'Map', 'Kartta'))),
                          ]),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _section(
                        cart.storeName ?? tr(context, 'Your bag', 'Ostoskassi'),
                        [for (final item in cart.items) _itemRow(cart, item)],
                      ),
                      const SizedBox(height: 14),
                      _section(
                        tr(context, 'Tip your courier', 'Tippi kuriirille'),
                        [
                          Text(tr(context, 'Optional. The whole tip goes to the courier.', 'Vapaaehtoinen. Koko tippi menee kuriirille.'),
                              style: TextStyle(fontSize: 13, color: AppTheme.secondaryText(context))),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [for (final t in _tips) _tipChip(t)],
                          ),
                        ],
                      ),
                      if (showPromo) ...[
                        const SizedBox(height: 14),
                        _section(tr(context, 'Promo code', 'Alennuskoodi'), [_promoRow(loading)]),
                      ],
                      const SizedBox(height: 14),
                      _section(tr(context, 'Summary', 'Yhteenveto'), _summary(q, loading: loading, error: error)),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 14),
                        _notice(Icons.error_outline_rounded, _errorMessage!, error: true),
                      ],
                    ],
                  ),
                ),
                _payBar(cart, ready ? totalCents : null, loading: loading, enabled: ready && closed == null),
              ],
            ),
    );
  }

  List<Widget> _summary(Map<String, dynamic>? q, {required bool loading, required String? error}) {
    if (error != null) {
      return [
        _notice(Icons.error_outline_rounded, error, error: true),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _requote,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(tr(context, 'Try again', 'Yritä uudelleen')),
          ),
        ),
      ];
    }
    final calculating = tr(context, 'calculating…', 'lasketaan…');
    String money(String field) {
      final cents = asInt(q?[field]);
      return cents == null ? calculating : euro(context, cents);
    }

    int cents(String field) => asInt(q?[field]) ?? 0;
    final smallFee = cents('smallOrderFeeCents');
    final missing = cents('smallOrderThresholdCents') - cents('subtotalCents');
    final discount = cents('discountCents');
    final promoCode = _validPromo;

    final rows = <Widget>[
      _summaryRow(tr(context, 'Items', 'Tuotteet'), money('subtotalCents')),
      const SizedBox(height: 8),
      _summaryRow(tr(context, 'Delivery', 'Toimitus'), money('deliveryFeeCents')),
      if (cents('serviceFeeCents') > 0) ...[
        const SizedBox(height: 8),
        _summaryRow(tr(context, 'Service fee', 'Palvelumaksu'), money('serviceFeeCents')),
      ],
      if (smallFee > 0) ...[
        const SizedBox(height: 8),
        _summaryRow(tr(context, 'Small-order fee', 'Pientilauslisä'), money('smallOrderFeeCents')),
        if (missing > 0)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              tr(context, 'Add ${euro(context, missing)} more to avoid it.',
                  'Lisää ostoksia vielä ${euro(context, missing)}, niin lisää ei peritä.'),
              style: TextStyle(fontSize: 12, color: AppTheme.secondaryText(context)),
            ),
          ),
      ],
      if (discount > 0) ...[
        const SizedBox(height: 8),
        _summaryRow(
          promoCode == null ? tr(context, 'Discount', 'Alennus') : '${tr(context, 'Discount', 'Alennus')} ($promoCode)',
          '−${euro(context, discount)}',
          highlight: true,
        ),
      ],
      if (cents('tipCents') > 0) ...[
        const SizedBox(height: 8),
        _summaryRow(tr(context, 'Courier tip', 'Tippi kuriirille'), money('tipCents')),
      ],
      const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider()),
      _summaryRow(tr(context, 'Total', 'Yhteensä'), money('totalCents'), bold: true),
      const SizedBox(height: 6),
      Text(
        _legacy
            ? tr(context, 'The final price is calculated by Malvoya and shown again in the payment sheet before you pay.',
                'Lopullisen hinnan laskee Malvoya, ja se näytetään vielä maksuikkunassa ennen maksua.')
            : tr(context, 'This is the exact amount you will pay. The payment sheet shows the same amount.',
                'Tämä on tarkka summa, jonka maksat. Maksuikkuna näyttää saman summan.'),
        style: TextStyle(fontSize: 12, color: AppTheme.secondaryText(context)),
      ),
    ];
    // While a new price is on its way the previous one stays visible, dimmed
    return [
      AnimatedOpacity(
        opacity: loading && q != null ? 0.45 : 1,
        duration: const Duration(milliseconds: 150),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
      ),
    ];
  }

  Widget _promoRow(bool loading) {
    final muted = AppTheme.secondaryText(context);
    if (_promoCode == null) {
      return Row(
        children: [
          Expanded(
            child: TextField(
              controller: _promoCtrl,
              maxLength: 40,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _applyPromo(),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                counterText: '',
                hintText: tr(context, 'Enter code', 'Syötä koodi'),
                prefixIcon: const Icon(Icons.local_offer_outlined),
              ),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.tonal(
            onPressed: _promoCtrl.text.trim().isEmpty ? null : _applyPromo,
            child: Text(tr(context, 'Apply', 'Käytä')),
          ),
        ],
      );
    }

    final promo = _quote?['promo'];
    final promoError = _quote?['promoError'];
    final valid = !loading && promo is Map;
    final String message;
    if (loading) {
      message = tr(context, 'Checking the code…', 'Tarkistetaan koodia…');
    } else if (promo is Map) {
      final description = (promo['description'] ?? '').toString();
      message = description.isNotEmpty ? description : tr(context, 'Code applied', 'Koodi käytössä');
    } else if (promoError is String && promoError.isNotEmpty) {
      message = promoError;
    } else {
      message = tr(context, 'This code can’t be used right now.', 'Koodia ei voi käyttää juuri nyt.');
    }
    const errorColor = Color(0xFFD93025);
    final code = (promo is Map && promo['code'] != null ? promo['code'] : _promoCode).toString();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      decoration: BoxDecoration(
        color: valid ? AppTheme.pastel(context, AppTheme.mint, AppTheme.moss) : AppTheme.inputBackground(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Row(
        children: [
          loading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(valid ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                  color: valid ? AppTheme.success : errorColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(code, style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.primaryText(context), letterSpacing: 0.4)),
                const SizedBox(height: 2),
                Text(message,
                    style: TextStyle(fontSize: 12.5, color: valid || loading ? muted : errorColor, fontWeight: FontWeight.w600, height: 1.3)),
              ],
            ),
          ),
          IconButton(
            tooltip: tr(context, 'Remove code', 'Poista koodi'),
            onPressed: _removePromo,
            icon: Icon(Icons.close_rounded, color: AppTheme.primaryText(context)),
          ),
        ],
      ),
    );
  }

  Widget _payBar(CartService cart, int? totalCents, {required bool loading, required bool enabled}) {
    final String label;
    if (loading) {
      label = tr(context, 'Calculating price…', 'Lasketaan hintaa…');
    } else if (totalCents != null) {
      label = '${tr(context, 'Pay', 'Maksa')} ${euro(context, totalCents)}';
    } else {
      label = tr(context, 'Pay', 'Maksa');
    }
    return Container(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.of(context).viewPadding.bottom),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, -4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              onPressed: _paying || !enabled || totalCents == null ? null : () => _placeOrder(cart, totalCents),
              child: _paying
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline_rounded, size: 14, color: AppTheme.secondaryText(context)),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  tr(context, 'You pay in Stripe’s secure payment sheet. Malvoya never sees your card details.',
                      'Maksat Stripen suojatussa maksuikkunassa. Malvoya ei näe korttitietojasi.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: AppTheme.secondaryText(context)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tipChip(int cents) {
    final selected = _tipCents == cents;
    final label = cents == 0 ? tr(context, 'No tip', 'Ei tippiä') : euro(context, cents);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _tipCents = cents);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppTheme.sunshine : AppTheme.cardBackground(context),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: selected ? AppTheme.sunshine : AppTheme.cardBorder(context), width: 1.5),
          ),
          child: Text(label,
              style: TextStyle(fontWeight: FontWeight.w800, color: selected ? AppTheme.ink : AppTheme.primaryText(context))),
        ),
      ),
    );
  }

  Widget _itemRow(CartService cart, CartItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 60,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppTheme.pastel(context, AppTheme.clay, AppTheme.clayInk),
              borderRadius: BorderRadius.circular(14),
            ),
            child: item.imageUrl != null
                ? Image.network(item.imageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.checkroom_outlined, color: AppTheme.clayInk))
                : const Icon(Icons.checkroom_outlined, color: AppTheme.clayInk),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primaryText(context))),
                Text(
                  [if (item.variantLabel != null) item.variantLabel, euro(context, (item.price * 100).round())].join(' · '),
                  style: TextStyle(color: AppTheme.secondaryText(context), fontSize: 12.5),
                ),
              ],
            ),
          ),
          _QuantityControl(
            quantity: item.quantity,
            onDecrement: () => cart.changeQuantity(item, item.quantity - 1),
            onIncrement: () => cart.changeQuantity(item, item.quantity + 1),
          ),
        ],
      ),
    );
  }

  Widget _emptyCart() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(color: AppTheme.pastel(context, AppTheme.sunshineLight, AppTheme.sunshine), shape: BoxShape.circle),
                child: const Icon(Icons.shopping_bag_outlined, size: 40, color: Color(0xFF8A5A00)),
              ),
              const SizedBox(height: 16),
              Text(tr(context, 'Your bag is empty', 'Ostoskassisi on tyhjä'), style: AppTheme.display(context, size: 21)),
              const SizedBox(height: 6),
              Text(tr(context, 'Find something you love from stores near you.', 'Löydä jotain ihanaa läheisistä kaupoista.'),
                  textAlign: TextAlign.center, style: TextStyle(color: AppTheme.secondaryText(context))),
            ],
          ),
        ),
      );

  Widget _notice(IconData icon, String text, {bool error = false}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: error ? const Color(0xFFFEF2F2) : AppTheme.pastel(context, AppTheme.sunshineLight, AppTheme.sunshine),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        child: Row(children: [
          Icon(icon, color: error ? const Color(0xFFD93025) : const Color(0xFF8A5A00), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                  color: error ? const Color(0xFFB91C1C) : AppTheme.primaryText(context),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                )),
          ),
        ]),
      );

  Widget _section(String title, List<Widget> children) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.cardBackground(context),
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          border: Border.all(color: AppTheme.cardBorder(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTheme.display(context, size: 18)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );

  Widget _summaryRow(String label, String value, {bool bold = false, bool highlight = false}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(label,
                style: TextStyle(
                  color: bold ? AppTheme.primaryText(context) : AppTheme.secondaryText(context),
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                  fontSize: bold ? 16 : 14,
                )),
          ),
          const SizedBox(width: 12),
          Text(value,
              style: TextStyle(
                color: highlight ? AppTheme.success : AppTheme.primaryText(context),
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                fontSize: bold ? 18 : 14,
              )),
        ],
      );
}

class _QuantityControl extends StatelessWidget {
  final int quantity;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  const _QuantityControl({required this.quantity, required this.onDecrement, required this.onIncrement});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppTheme.inputBackground(context), borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          _btn(context, Icons.remove_rounded, tr(context, 'Fewer', 'Vähemmän'), onDecrement),
          SizedBox(
            width: 24,
            child: Text('$quantity', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.primaryText(context))),
          ),
          _btn(context, Icons.add_rounded, tr(context, 'More', 'Lisää'), onIncrement),
        ],
      ),
    );
  }

  Widget _btn(BuildContext context, IconData icon, String label, VoidCallback cb) => IconButton(
        tooltip: label,
        onPressed: cb,
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, size: 18, color: AppTheme.primaryText(context)),
      );
}
