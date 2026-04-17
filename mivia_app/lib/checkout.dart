import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'cart.dart';
import 'models.dart';

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key});
  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  bool loading = false;
  String? message;

  Future<void> _placeOrder(CartService cart) async {
    setState(() {
      loading = true;
      message = null;
    });
    try {
      final order = await cart.checkout(1);
      setState(() {
        message = 'Order placed: id=${order['id']}';
      });
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
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Expanded(
            child: cart.items.isEmpty
                ? const Center(child: Text('Cart is empty'))
                : ListView.builder(
                    itemCount: cart.items.length,
                    itemBuilder: (context, i) {
                      final it = cart.items[i];
                      return ListTile(
                        title: Text(it.name),
                        subtitle: Text('\$${it.price} x ${it.quantity}'),
                        trailing:
                            Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                              icon: const Icon(Icons.remove),
                              onPressed: () =>
                                  cart.changeQuantity(it, it.quantity - 1)),
                          IconButton(
                              icon: const Icon(Icons.add),
                              onPressed: () =>
                                  cart.changeQuantity(it, it.quantity + 1)),
                        ]),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 12),
          Text('Total: \$${cart.total.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 12),
          loading
              ? const CircularProgressIndicator()
              : ElevatedButton(
                  onPressed:
                      cart.items.isEmpty ? null : () => _placeOrder(cart),
                  child: const Text('Place Order')),
          if (message != null) ...[
            const SizedBox(height: 12),
            Text(message!, style: const TextStyle(color: Colors.black87)),
          ]
        ]),
      ),
    );
  }
}
