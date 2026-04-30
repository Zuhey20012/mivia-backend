import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'cart.dart';
import 'models.dart';
import 'auth_service.dart';

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key});
  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  bool loading = false;
  String? message;

  Future<void> _placeOrder(CartService cart) async {
    // Show Stripe payment sheet simulation
    final paymentSuccess = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.credit_card, size: 64, color: Colors.blue),
            const SizedBox(height: 16),
            const Text('Secure Checkout via Stripe', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            TextField(
              decoration: InputDecoration(
                labelText: 'Card Number',
                prefixIcon: const Icon(Icons.credit_card),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: TextField(decoration: InputDecoration(labelText: 'MM/YY', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))))),
                const SizedBox(width: 16),
                Expanded(child: TextField(decoration: InputDecoration(labelText: 'CVC', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))))),
              ],
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                onPressed: () {
                  Navigator.pop(ctx, true);
                },
                child: const Text('Pay Now', style: TextStyle(color: Colors.white)),
              ),
            ),
            const SizedBox(height: 300), // Padding for keyboard
          ],
        ),
      ),
    );

    if (paymentSuccess != true) return;

    final auth = Provider.of<AuthService>(context, listen: false);
    if (!auth.isAuthenticated) {
      setState(() => message = 'You must be logged in to checkout.');
      return;
    }

    setState(() {
      loading = true;
      message = null;
    });
    try {
      final order = await cart.checkout(auth.currentUser!.id, auth.accessToken!);
      setState(() {
        message = 'Success! Order #${order['order']['id'] ?? ''} placed.';
      });
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Order Confirmed! 🎉'),
            content: const Text('Your order has been placed successfully.\nEstimated delivery: 15-25 min'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(ctx);
                },
                child: const Text('Back to Home'),
              )
            ],
          ),
        );
      }
    } catch (e) {
      setState(() {
        message = 'Error: ${e.toString()}';
      });
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartService>(context);
    final deliveryFee = 2.99;
    final total = cart.total + deliveryFee;

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: cart.items.isEmpty && message == null
          ? const Center(child: Text('Your cart is empty', style: TextStyle(fontSize: 18)))
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text('Your Order', style: Theme.of(context).textTheme.displayMedium),
                      const SizedBox(height: 16),
                      ...cart.items.map((it) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove, size: 18),
                                      onPressed: () => cart.changeQuantity(it, it.quantity - 1),
                                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                      padding: EdgeInsets.zero,
                                    ),
                                    Text('${it.quantity}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    IconButton(
                                      icon: const Icon(Icons.add, size: 18),
                                      onPressed: () => cart.changeQuantity(it, it.quantity + 1),
                                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                      padding: EdgeInsets.zero,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Text(it.name, style: const TextStyle(fontSize: 16))),
                              Text('\$${(it.price * it.quantity).toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        );
                      }).toList(),
                      const Divider(height: 32),
                      const Text('Adjustments & Instructions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 8),
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'e.g. Leave at the door, gift wrap please...',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Subtotal', style: TextStyle(color: Colors.grey)),
                          Text('\$${cart.total.toStringAsFixed(2)}'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Delivery Fee', style: TextStyle(color: Colors.grey)),
                          Text('\$$deliveryFee'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          Text('\$${total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      if (message != null) ...[
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                          child: Text(message!, style: const TextStyle(color: Colors.red)),
                        )
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
                  ),
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: cart.items.isEmpty ? null : () => _placeOrder(cart),
                            child: Text('Swipe to Pay \$$total', style: const TextStyle(fontSize: 18)),
                          ),
                        ),
                )
              ],
            ),
    );
  }
}

