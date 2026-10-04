import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: const PurchaseList());
  }
}

class PurchaseList extends StatefulWidget {
  const PurchaseList({super.key});

  @override
  State<PurchaseList> createState() => _PurchaseListState();
}

class _PurchaseListState extends State<PurchaseList> {
  final List<Purchase> _items = [
    const Purchase(
      description: 'Milk',
      price: 3.49,
      imagePath: 'assets/images/milk.png',
    ),
    const Purchase(
      description: 'Bread',
      price: 2.99,
      imagePath: 'assets/images/bread.png',
    ),
  ];
  Future<void> _createItem() async {
    final item = await Navigator.of(context).push<Purchase>(
      MaterialPageRoute(builder: (context) => const NewPurchaseScreen()),
    );

    if (item == null || !mounted) return;

    setState(() {
      _items.add(
        Purchase(
          description: item.description,
          price: item.price,
          imagePath: _items.length.isEven
              ? 'assets/images/milk.png'
              : 'assets/images/bread.png',
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F8F6),
        foregroundColor: const Color(0xFF1D2B24),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 8,
        leading: const Icon(Icons.shopping_bag_outlined),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'My Purchase Tracker',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            Text(
              '${_items.length} items',
              style: TextStyle(
                fontSize: 12,
                color: const Color(0xFF1D2B24).withValues(alpha: 0.65),
              ),
            ),
          ],
        ),
      ),
      body: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: _items.length,
                itemBuilder: (context, index) {
                  return PurchaseItem(item: _items[index]);
                },
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.bottomRight,
              child: SizedBox(
                width: 60,
                height: 60,
                child: ElevatedButton(
                  onPressed: _createItem,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                    fixedSize: const Size(60, 60),
                  ),
                  child: const Icon(Icons.add),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class Purchase {
  const Purchase({
    required this.description,
    required this.price,
    required this.imagePath,
  });

  final String description;
  final double price;
  final String imagePath;
}

class PurchaseItem extends StatelessWidget {
  const PurchaseItem({required this.item, super.key});

  final Purchase item;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(8),
      color: Colors.grey.shade200,
      child: Row(
        children: [
          SizedBox(
            width: 100,
            height: 80,
            child: Container(
              color: Colors.deepPurple.shade50,
              child: Image.asset(item.imagePath, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              item.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 80,
            child: Text(
              '\$${item.price.toStringAsFixed(2)}',
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class NewPurchaseScreen extends StatefulWidget {
  const NewPurchaseScreen({super.key});

  @override
  State<NewPurchaseScreen> createState() => _NewPurchaseScreenState();
}

class _NewPurchaseScreenState extends State<NewPurchaseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();

  @override
  void dispose() {
    _descriptionController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pop(
      Purchase(
        description: _descriptionController.text.trim(),
        price: double.parse(_priceController.text.trim()),
        imagePath: 'assets/images/milk.png',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New item'),
        backgroundColor: const Color(0xFFF6F8F6),
        foregroundColor: const Color(0xFF1D2B24),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Item details', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),
            TextFormField(
              controller: _descriptionController,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a description'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _priceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Price',
                prefixText: r'$ ',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                final price = double.tryParse(value?.trim() ?? '');
                if (price == null || !price.isFinite || price < 0) {
                  return 'Enter a valid price';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.add),
              label: const Text('Add item'),
            ),
          ),
        ),
      ),
    );
  }
}
