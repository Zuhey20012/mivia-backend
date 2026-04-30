class CartItem {
  final int productId;
  final int? variantId;
  final String name;
  final double price;
  int quantity;

  CartItem({
    required this.productId,
    this.variantId,
    required this.name,
    required this.price,
    this.quantity = 1,
  });

  Map<String, dynamic> toOrderItem() {
    return {
      'productId': productId,
      'variantId': variantId,
      'quantity': quantity,
    };
  }
}
