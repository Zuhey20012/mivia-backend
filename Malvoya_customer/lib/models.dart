class CartItem {
  final int productId;
  final int? variantId;
  final int? storeId;
  final String? storeName;
  final String name;
  final String? variantLabel;
  final String? imageUrl;
  final double price;
  int quantity;

  CartItem({
    required this.productId,
    this.variantId,
    this.storeId,
    this.storeName,
    required this.name,
    this.variantLabel,
    this.imageUrl,
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
