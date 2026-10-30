import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/collections/product.dart';
import '../../../core/database/isar_provider.dart';
import '../../../core/services/product_repository.dart';
import '../../sync/providers/sync_poviders.dart';

// --- Infrastructure ---

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepository(
    ref.watch(isarProvider),
    syncService: ref.watch(syncServiceProvider),
  );
});

// --- Streams réactifs ---

final productsStreamProvider = StreamProvider<List<Product>>((ref) {
  return ref.watch(productRepositoryProvider).watchAll();
});

final pendingCountStreamProvider = StreamProvider<int>((ref) {
  return ref.watch(productRepositoryProvider).watchPendingCount();
});

/// Stream réactif de la corbeille.
final trashedProductsStreamProvider = StreamProvider<List<Product>>((ref) {
  return ref.watch(productRepositoryProvider).watchDeleted();
});

// --- État UI ---

enum ProductSort { code, name, dateDesc }

final productSortProvider = StateProvider<ProductSort>(
  (ref) => ProductSort.code,
);

final productSearchProvider = StateProvider<String>((ref) => '');

// --- Provider dérivé : liste filtrée + triée ---

final filteredProductsProvider = Provider<AsyncValue<List<Product>>>((ref) {
  final productsAsync = ref.watch(productsStreamProvider);
  final query = ref.watch(productSearchProvider);
  final sort = ref.watch(productSortProvider);

  return productsAsync.whenData(
    (products) =>
        applyFilterAndSort(products: products, query: query, sort: sort),
  );
});

/// Fonction pure de filtrage et tri (testable sans Isar).
List<Product> applyFilterAndSort({
  required List<Product> products,
  required String query,
  required ProductSort sort,
}) {
  var result = products;
  final q = query.trim().toLowerCase();
  if (q.isNotEmpty) {
    result = products.where((p) {
      return p.internalCode.toLowerCase().contains(q) ||
          p.name.toLowerCase().contains(q) ||
          p.format.toLowerCase().contains(q) ||
          p.containment.toLowerCase().contains(q);
    }).toList();
  } else {
    result = List.of(products);
  }

  switch (sort) {
    case ProductSort.code:
      result.sort((a, b) => a.internalCode.compareTo(b.internalCode));
      break;
    case ProductSort.name:
      result.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      break;
    case ProductSort.dateDesc:
      result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      break;
  }
  return result;
}
