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

/// Checkout: address, items, an optional courier tip and the exact price the server will charge.
/// Payment details are only ever entered in Stripe's own payment sheet.
class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key});
  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  static const _tips = [0, 100, 200, 300, 500];

  bool _paying = false;
  String? _errorMessage;
  final _addressCtrl = TextEditingController();
  int _tipCents = 0;

  /// The store as the server sees it for this address: real delivery fee and whether it is open.
  Map<String, dynamic>? _store;
  int? _quotedForStore;

  @override
  void initState() {
    super.initState();
    _loadSavedAddress();
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    super.dispose();
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

  /// Fetches the store with the pinned coordinates, so the fee shown is the fee charged.
  Future<void> _quote(int storeId) async {
    _quotedForStore = storeId;
    final auth = Provider.of<AuthService>(context, listen: false);
    final res = await ApiClient(auth).get('/stores/$storeId', query: _pinned ? DeliveryLocation.instance.query : null);
    if (mounted && res.ok) setState(() => _store = Map<String, dynamic>.from(res.data['store']));
  }

  Future<void> _pickAddress(int? storeId) async {
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
    if (addr != null && addr.isNotEmpty) setState(() => _addressCtrl.text = addr);
    if (storeId != null) _quote(storeId);
  }

  Future<void> _placeOrder(CartService cart) async {
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
    final res = await ApiClient(auth).post('/orders', {
      'storeId': cart.storeId,
      'deliveryAddress': address,
      // Coordinates only when this is the address that was pinned on the map
      if (_pinned) ...{'deliveryLat': loc.lat, 'deliveryLng': loc.lng},
      if (_tipCents > 0) 'tipCents': _tipCents,
      'items': cart.items.map((i) => i.toOrderItem()..removeWhere((_, v) => v == null)).toList(),
    });
    if (!mounted) return;
    if (!res.ok) {
      setState(() {
        _paying = false;
        _errorMessage = res.error ?? tr(context, 'The order could not be placed. Please try again.', 'Tilausta ei voitu tehdä. Yritä uudelleen.');
      });
      return;
    }

    final order = Map<String, dynamic>.from(res.data['order']);
    final clientSecret = res.data['clientSecret']?.toString() ?? '';
    final orderId = asInt(order['id'])!;
    final charged = asInt(order['totalCents']) ?? 0;
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

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartService>(context);
    final storeId = cart.storeId;
    if (storeId != null && _quotedForStore != storeId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _quote(storeId));
    }

    final subtotalCents = (cart.total * 100).round();
    final feeCents = asInt(_store?['deliveryFeeCents']);
    final totalCents = subtotalCents + (feeCents ?? 0) + _tipCents;
    final closed = closedLabel(context, _store);

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
                        _notice(Icons.schedule_rounded, '${_store?['name'] ?? ''}: $closed. ${tr(context, 'You can pay when it opens.', 'Voit maksaa, kun se aukeaa.')}'),
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
                            TextButton(onPressed: () => _pickAddress(storeId), child: Text(tr(context, 'Map', 'Kartta'))),
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
                      const SizedBox(height: 14),
                      _section(
                        tr(context, 'Summary', 'Yhteenveto'),
                        [
                          _summaryRow(tr(context, 'Items', 'Tuotteet'), euro(context, subtotalCents)),
                          const SizedBox(height: 8),
                          _summaryRow(
                            tr(context, 'Delivery', 'Toimitus'),
                            feeCents == null ? tr(context, 'calculating…', 'lasketaan…') : euro(context, feeCents),
                          ),
                          if (_tipCents > 0) ...[
                            const SizedBox(height: 8),
                            _summaryRow(tr(context, 'Courier tip', 'Tippi kuriirille'), euro(context, _tipCents)),
                          ],
                          const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider()),
                          _summaryRow(tr(context, 'Total (VAT incl.)', 'Yhteensä (sis. ALV)'), euro(context, totalCents), bold: true),
                          const SizedBox(height: 6),
                          Text(
                            tr(context, 'The final price is calculated by Malvoya and shown again in the payment sheet before you pay.',
                                'Lopullisen hinnan laskee Malvoya, ja se näytetään vielä maksuikkunassa ennen maksua.'),
                            style: TextStyle(fontSize: 12, color: AppTheme.secondaryText(context)),
                          ),
                        ],
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 14),
                        _notice(Icons.error_outline_rounded, _errorMessage!, error: true),
                      ],
                    ],
                  ),
                ),
                _payBar(cart, totalCents, enabled: closed == null && feeCents != null),
              ],
            ),
    );
  }

  Widget _payBar(CartService cart, int totalCents, {required bool enabled}) {
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
              onPressed: _paying || !enabled ? null : () => _placeOrder(cart),
              child: _paying
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : Text('${tr(context, 'Pay', 'Maksa')} ${euro(context, totalCents)}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
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
                  tr(context, 'Card, Google Pay or bank in Stripe’s secure payment sheet. Malvoya never sees your card.',
                      'Kortti, Google Pay tai pankki Stripen suojatussa maksuikkunassa. Malvoya ei näe korttiasi.'),
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

  Widget _summaryRow(String label, String value, {bool bold = false}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                color: bold ? AppTheme.primaryText(context) : AppTheme.secondaryText(context),
                fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                fontSize: bold ? 16 : 14,
              )),
          Text(value,
              style: TextStyle(
                color: AppTheme.primaryText(context),
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
