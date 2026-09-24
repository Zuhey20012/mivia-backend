import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config/constants.dart';
import 'config/theme.dart';
import 'auth_service.dart';
import 'cart.dart';
import 'realtime_notification_service.dart';
import 'local_notification_service.dart';
import 'l10n.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key});
  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  bool _loading = false;
  String? _errorMessage;
  final _addressCtrl = TextEditingController();
  
  // Payment details are entered only in Stripe's payment sheet (card, Apple/Google Pay, SEPA…)
  final String _selectedPaymentMethod = 'stripe';

  @override
  void initState() {
    super.initState();
    _loadSavedAddress();
  }

  Future<void> _loadSavedAddress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedAddr = prefs.getString('malvoya_active_address') ??
                        prefs.getString('saved_default_address') ?? 
                        prefs.getString('user_delivery_address');
      if (savedAddr != null && savedAddr.isNotEmpty && mounted) {
        setState(() {
          _addressCtrl.text = savedAddr;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    super.dispose();
  }

  // European SEPA IBAN Modulo-97 Algorithm

  Future<void> _placeOrder(CartService cart) async {
    if (_addressCtrl.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please enter your delivery address.');
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_delivery_address', _addressCtrl.text.trim());
      await prefs.setString('saved_default_address', _addressCtrl.text.trim());
      await prefs.setString('malvoya_active_address', _addressCtrl.text.trim());
    } catch (_) {}

    setState(() { _loading = true; _errorMessage = null; });
    HapticFeedback.mediumImpact();

    final auth = Provider.of<AuthService>(context, listen: false);
    if (!auth.isAuthenticated) {
      setState(() { _errorMessage = 'You must be logged in to checkout.'; _loading = false; });
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('${AppConstants.apiBase}/orders'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${auth.accessToken}',
        },
        body: jsonEncode({
          'storeId': cart.storeId,
          'deliveryAddress': _addressCtrl.text.trim(),
          'items': cart.items.map((i) => {
            'productId': i.productId,
            'quantity': i.quantity,
          }).toList(),
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final resData = jsonDecode(response.body);
        final orderData = resData['order'];
        final clientSecret = resData['clientSecret'];
        // The server calculates the price; show exactly what is charged.
        final totalCharged = ((orderData['totalCents'] as num?) ?? 0) / 100;
        final orderId = orderData['id'].toString();
        if (clientSecret == null || clientSecret.toString().isEmpty) {
          throw Exception('Payment could not be started. Please try again.');
        }

        // Stripe PaymentSheet: card details never touch Malvoya; 3-D Secure (PSD2 SCA) is handled by Stripe.
        await Stripe.instance.initPaymentSheet(
          paymentSheetParameters: SetupPaymentSheetParameters(
            paymentIntentClientSecret: clientSecret.toString(),
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

        // Reached ONLY after payment verification succeeds
        await _dispatchRealtimeAlerts(totalCharged, auth, orderId: orderId);

        HapticFeedback.heavyImpact();
        cart.clear();
        if (mounted) _showSuccessDialog(orderData, totalCharged, auth);
      } else {
        final errBody = jsonDecode(response.body);
        throw Exception(errBody['error'] ?? 'Failed to place order');
      }

    } on StripeException catch (e) {
      if (mounted) {
        final isCancelled = e.error.code == FailureCode.Canceled;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(isCancelled ? 'Payment Cancelled' : 'Payment Failed', style: const TextStyle(fontWeight: FontWeight.bold)),
            content: Text(isCancelled ? 'Your order was not placed and your card was not charged.' : (e.error.localizedMessage ?? 'Transaction was declined by your bank.')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK', style: TextStyle(color: Color(0xFF6D2E8C), fontWeight: FontWeight.bold)),
              ),
            ],
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Checkout Failed', style: TextStyle(fontWeight: FontWeight.bold)),
            content: Text('Could not complete order: ${e.toString().replaceAll("Exception: ", "")}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK', style: TextStyle(color: Color(0xFF6D2E8C), fontWeight: FontWeight.bold)),
              ),
            ],
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _dispatchRealtimeAlerts(double amount, AuthService auth, {String? orderId}) async {
    // The confirmation email is sent by the server once Stripe confirms the payment.
    try {
      await LocalNotificationService.showNotification(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: 'Tilaus #$orderId vastaanotettu / Order #$orderId received',
        body: 'Payment of €${amount.toStringAsFixed(2)} submitted. We will email you when it is confirmed.',
      );
    } catch (_) {}

    if (!mounted) return;
    RealtimeNotificationService.notifyOrderPlaced(
      context,
      orderId: orderId ?? '',
      total: amount,
      paymentMethod: _selectedPaymentMethod,
      email: auth.currentUser?.email ?? '',
      phone: auth.currentUser?.phone,
    );
  }

  void _showSuccessDialog(dynamic order, double total, AuthService auth) {
    final orderId = order?['id']?.toString() ?? '';
    final email = auth.currentUser?.email ?? '';
    final hasRealEmail = email.isNotEmpty && !email.endsWith('@phone.malvoya.app');
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark ? const Color(0xFF98989D) : const Color(0xFF6E6E73);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog.adaptive(
        title: const Text('Kiitos! / Thank you!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const Icon(Icons.check_circle_rounded, color: Color(0xFF34C759), size: 56),
            const SizedBox(height: 12),
            Text(
              'Order #$orderId • €${total.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              hasRealEmail
                  ? 'Your payment was submitted. We will email the order confirmation to $email once the payment is confirmed. The store will then prepare your order.'
                  : 'Your payment was submitted. You can follow your order in the Orders tab once the payment is confirmed.',
              style: TextStyle(color: secondary, fontSize: 14, height: 1.4),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cart = Provider.of<CartService>(context);
    final subtotal = cart.total;
    const deliveryFee = 2.99;
    final total = subtotal + deliveryFee;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = AppTheme.cardBackground(context);
    final borderColor = AppTheme.cardBorder(context);
    final textPrimary = AppTheme.primaryText(context);
    final textSecondary = AppTheme.secondaryText(context);
    final inputBg = AppTheme.inputBackground(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.translate('checkout'), style: const TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: true,
      ),
      body: cart.items.isEmpty
          ? _buildEmptyCart(textPrimary, textSecondary)
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      // Address section
                      _buildSection(
                        title: '📍 ${l10n.translate('deliveryAddress')}',
                        cardBg: cardBg,
                        borderColor: borderColor,
                        textPrimary: textPrimary,
                        children: [
                          TextField(
                            controller: _addressCtrl,
                            style: TextStyle(color: textPrimary),
                            decoration: InputDecoration(
                              hintText: 'Street address, apartment, postal code',
                              hintStyle: TextStyle(color: textSecondary),
                              prefixIcon: const Icon(Icons.location_on_outlined, size: 20),
                              filled: true,
                              fillColor: inputBg,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Payment Method Selector
                      _buildPaymentMethodSelector(
                        cardBg: cardBg,
                        borderColor: borderColor,
                        inputBg: inputBg,
                        textPrimary: textPrimary,
                        textSecondary: textSecondary,
                        isDark: isDark,
                      ),
                      const SizedBox(height: 16),

                      // Order items
                      _buildSection(
                        title: l10n.locale.languageCode == 'fi' ? '🛍️ Valitsemasi tuotteet' : '🛍️ Your Boutique Pieces',
                        cardBg: cardBg,
                        borderColor: borderColor,
                        textPrimary: textPrimary,
                        children: [
                          ...cart.items.map((item) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    gradient: AppTheme.primaryGradient,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(Icons.checkroom_rounded, color: Colors.white, size: 24),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: textPrimary),
                                      ),
                                      Text(
                                        '${item.price.toStringAsFixed(2)} € / kpl',
                                        style: TextStyle(color: textSecondary, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                _QuantityControl(
                                  quantity: item.quantity,
                                  textPrimary: textPrimary,
                                  onDecrement: () => cart.changeQuantity(item, item.quantity - 1),
                                  onIncrement: () => cart.changeQuantity(item, item.quantity + 1),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  '${(item.price * item.quantity).toStringAsFixed(2)} €',
                                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: textPrimary),
                                ),
                              ],
                            ),
                          )),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Order summary
                      _buildSection(
                        title: l10n.locale.languageCode == 'fi' ? '💳 Tilauksen yhteenveto' : '💳 Order Summary',
                        cardBg: cardBg,
                        borderColor: borderColor,
                        textPrimary: textPrimary,
                        children: [
                          _summaryRow(l10n.locale.languageCode == 'fi' ? 'Välisumma' : 'Subtotal', '${subtotal.toStringAsFixed(2)} €', textPrimary, textSecondary),
                          const SizedBox(height: 8),
                          _summaryRow(l10n.locale.languageCode == 'fi' ? 'Lähikuriirin toimitus' : 'Local Courier Delivery', '${deliveryFee.toStringAsFixed(2)} €', textPrimary, textSecondary),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Divider(color: borderColor),
                          ),
                          _summaryRow(l10n.locale.languageCode == 'fi' ? 'Yhteensä (sis. ALV)' : 'Total (incl. VAT)', '${total.toStringAsFixed(2)} €', textPrimary, textSecondary, bold: true),
                        ],
                      ),

                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFFECACA)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.error_outline_rounded, color: Color(0xFFD93025), size: 20),
                            const SizedBox(width: 10),
                            Expanded(child: Text(_errorMessage!, style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 13, fontWeight: FontWeight.w600))),
                          ]),
                        ),
                      ],

                      const SizedBox(height: 100),
                    ],
                  ),
                ),

                // Master 1-Swipe & Google Pay Action Zone (Bottom 35% Thumb Zone)
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    border: Border(top: BorderSide(color: borderColor, width: 1)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                        blurRadius: 18,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: _loading
                      ? const Center(child: SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.primary)))
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Sticky Checkout Slider in Thumb Zone
                            SwipeToPaySlider(
                              total: total,
                              label: 'Slide to Pay • €${total.toStringAsFixed(2)}',
                              isLoading: _loading,
                              isDark: isDark,
                              onConfirmed: () async {
                                await _placeOrder(cart);
                              },
                            ),

                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.shield_outlined, size: 14, color: textSecondary),
                                const SizedBox(width: 5),
                                Text(
                                  'Encrypted via Stripe / Adyen PCI-DSS Level 1 • 256-Bit SSL Security',
                                  style: TextStyle(fontSize: 10, color: textSecondary, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildPaymentMethodSelector({
    required Color cardBg,
    required Color borderColor,
    required Color inputBg,
    required Color textPrimary,
    required Color textSecondary,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '💳 ${AppLocalizations.of(context).translate('paymentMethods')}',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: textPrimary),
        ),
        const SizedBox(height: 10),
        _paymentOptionTile(
          id: 'stripe',
          title: 'Card, Apple Pay, Google Pay or bank',
          subtitle: 'Choose in the secure Stripe payment sheet',
          icon: Icons.lock_rounded,
          iconColor: const Color(0xFF6D2E8C),
          cardBg: cardBg,
          borderColor: borderColor,
          textPrimary: textPrimary,
          textSecondary: textSecondary,
          isDark: isDark,
        ),
        const SizedBox(height: 10),
        Text(
          'Malvoya never sees or stores your card or bank details. Your bank may ask you to confirm the payment (3-D Secure).',
          style: TextStyle(color: textSecondary, fontSize: 12, height: 1.35),
        ),
      ],
    );
  }

  Widget _paymentOptionTile({
    required String id,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    String? badge,
    required Color cardBg,
    required Color borderColor,
    required Color textPrimary,
    required Color textSecondary,
    required bool isDark,
  }) {
    final isSelected = _selectedPaymentMethod == id;
    return GestureDetector(
      onTap: () => HapticFeedback.lightImpact(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary.withValues(alpha: isDark ? 0.25 : 0.08) : cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? AppTheme.primary : borderColor,
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: textPrimary)),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF248A52),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(badge, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 11, color: textSecondary)),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: isSelected ? AppTheme.primary : (isDark ? Colors.white30 : Colors.grey.shade400),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyCart(Color textPrimary, Color textSecondary) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_bag_outlined, size: 80, color: textSecondary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text('Your cart is empty', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: textPrimary)),
            const SizedBox(height: 8),
            Text('Discover boutique pieces to get started', style: TextStyle(color: textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
    required Color cardBg,
    required Color borderColor,
    required Color textPrimary,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: textPrimary, letterSpacing: -0.2)),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, Color textPrimary, Color textSecondary, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: bold ? textPrimary : textSecondary,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
            fontSize: bold ? 15 : 13,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
            fontSize: bold ? 17 : 13,
            color: bold ? AppTheme.primary : textPrimary,
          ),
        ),
      ],
    );
  }
}

class _QuantityControl extends StatelessWidget {
  final int quantity;
  final Color textPrimary;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  const _QuantityControl({
    required this.quantity,
    required this.textPrimary,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _btn(Icons.remove_rounded, onDecrement),
        SizedBox(
          width: 28,
          child: Text(
            '$quantity',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: textPrimary),
          ),
        ),
        _btn(Icons.add_rounded, onIncrement),
      ],
    );
  }

  Widget _btn(IconData icon, VoidCallback cb) {
    return GestureDetector(
      onTap: cb,
      child: Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          color: AppTheme.primaryLight,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: AppTheme.primary),
      ),
    );
  }
}

class SwipeToPaySlider extends StatefulWidget {
  final double total;
  final String label;
  final Future<void> Function() onConfirmed;
  final bool isDark;
  final bool isLoading;

  const SwipeToPaySlider({
    super.key,
    required this.total,
    required this.label,
    required this.onConfirmed,
    required this.isDark,
    this.isLoading = false,
  });

  @override
  State<SwipeToPaySlider> createState() => _SwipeToPaySliderState();
}

class _SwipeToPaySliderState extends State<SwipeToPaySlider> with SingleTickerProviderStateMixin {
  double _dragPosition = 0.0;
  bool _confirmed = false;
  late AnimationController _springController;
  late Animation<double> _springAnimation;
  double _lastHapticStep = 0.0;

  @override
  void initState() {
    super.initState();
    _springController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _springController.addListener(() {
      setState(() {
        _dragPosition = _springAnimation.value;
      });
    });
  }

  @override
  void dispose() {
    _springController.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details, double maxDrag) {
    if (_confirmed || widget.isLoading) return;
    setState(() {
      _dragPosition = (_dragPosition + details.delta.dx).clamp(0.0, maxDrag);
      final progress = maxDrag > 0 ? _dragPosition / maxDrag : 0.0;
      if ((progress - _lastHapticStep).abs() >= 0.2) {
        _lastHapticStep = progress;
        HapticFeedback.selectionClick();
      }
    });
  }

  void _onDragEnd(DragEndDetails details, double maxDrag) async {
    if (_confirmed || widget.isLoading) return;
    final progress = maxDrag > 0 ? _dragPosition / maxDrag : 0.0;
    if (progress >= 0.82) {
      setState(() {
        _dragPosition = maxDrag;
        _confirmed = true;
      });
      HapticFeedback.heavyImpact();
      await widget.onConfirmed();
      if (mounted) {
        setState(() {
          _confirmed = false;
          _dragPosition = 0.0;
        });
      }
    } else {
      _springAnimation = Tween<double>(begin: _dragPosition, end: 0.0).animate(
        CurvedAnimation(parent: _springController, curve: Curves.easeOutBack),
      );
      _springController.forward(from: 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    const height = 58.0;
    const handleSize = 50.0;
    const padding = 4.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxDrag = constraints.maxWidth - handleSize - (padding * 2);
        final progress = maxDrag > 0 ? (_dragPosition / maxDrag).clamp(0.0, 1.0) : 0.0;

        return Container(
          height: height,
          decoration: BoxDecoration(
            color: widget.isDark ? const Color(0xFF2A2331) : const Color(0xFFF1EFF8),
            borderRadius: BorderRadius.circular(height / 2),
            border: Border.all(
              color: AppTheme.primary.withValues(alpha: widget.isDark ? 0.4 : 0.25),
              width: 1.5,
            ),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Dynamic progress fill
              Container(
                width: (_dragPosition + handleSize + padding).clamp(height, constraints.maxWidth),
                height: height,
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(height / 2),
                ),
              ),

              // Centered label (fading during drag)
              Center(
                child: Opacity(
                  opacity: (1.0 - progress * 1.6).clamp(0.0, 1.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _confirmed ? 'Authorizing Payment...' : widget.label,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: widget.isDark ? Colors.white : AppTheme.textPrimary,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: widget.isDark ? Colors.white70 : AppTheme.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),

              // Draggable Handle
              Positioned(
                left: padding + _dragPosition,
                child: GestureDetector(
                  onHorizontalDragUpdate: (d) => _onDragUpdate(d, maxDrag),
                  onHorizontalDragEnd: (d) => _onDragEnd(d, maxDrag),
                  child: Container(
                    width: handleSize,
                    height: handleSize,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withValues(alpha: 0.45),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: widget.isLoading || _confirmed
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: AppTheme.primary,
                              ),
                            )
                          : const Icon(
                              Icons.arrow_forward_rounded,
                              color: AppTheme.primary,
                              size: 24,
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
