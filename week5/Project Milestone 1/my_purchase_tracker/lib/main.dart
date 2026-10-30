import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => PurchaseProvider(),
      child: const MaterialApp(home: PurchaseList()),
    );
  }
}

class PurchaseProvider extends ChangeNotifier {
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

  List<Purchase> get items => List.unmodifiable(_items);

  void add(Purchase item) {
    _items.add(
      Purchase(
        description: item.description,
        price: item.price,
        imagePath: _items.length.isEven
            ? 'assets/images/milk.png'
            : 'assets/images/bread.png',
      ),
    );
    notifyListeners();
  }

  void removeAt(int index) {
    _items.removeAt(index);
    notifyListeners();
  }

  void move(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= _items.length ||
        newIndex < 0 ||
        newIndex >= _items.length ||
        oldIndex == newIndex) {
      return;
    }
    final item = _items.removeAt(oldIndex);
    _items.insert(newIndex, item);
    notifyListeners();
  }
}

enum _PurchaseMenuAction { manageItems }

class PurchaseList extends StatefulWidget {
  const PurchaseList({super.key});

  @override
  State<PurchaseList> createState() => _PurchaseListState();
}

class _PurchaseListState extends State<PurchaseList> {
  bool _isManagingItems = false;

  void _createItem(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (context) => const NewPurchaseScreen()),
    );
  }

  void _selectMenuAction(_PurchaseMenuAction action) {
    switch (action) {
      case _PurchaseMenuAction.manageItems:
        setState(() => _isManagingItems = !_isManagingItems);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = context.watch<PurchaseProvider>().items;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F8F6),
        foregroundColor: const Color(0xFF1D2B24),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 8,
        leading: const Icon(Icons.shopping_bag_outlined),
        actions: [
          PopupMenuButton<_PurchaseMenuAction>(
            tooltip: 'More options',
            onSelected: _selectMenuAction,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _PurchaseMenuAction.manageItems,
                child: Text(_isManagingItems ? 'Done' : 'Manage items'),
              ),
            ],
          ),
        ],
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'My Purchase Tracker',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            Text(
              '${items.length} items',
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
              child: _isManagingItems
                  ? ReorderableListView.builder(
                      itemCount: items.length,
                      onReorderItem: (oldIndex, newIndex) {
                        context.read<PurchaseProvider>().move(
                          oldIndex,
                          newIndex,
                        );
                      },
                      itemBuilder: (context, index) =>
                          _buildPurchaseItem(items, index, isReorderable: true),
                    )
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) => _buildPurchaseItem(
                        items,
                        index,
                        isReorderable: false,
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.bottomRight,
              child: SizedBox(
                width: 60,
                height: 60,
                child: ElevatedButton(
                  onPressed: () => _createItem(context),
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

  Widget _buildPurchaseItem(
    List<Purchase> items,
    int index, {
    required bool isReorderable,
  }) {
    final item = items[index];
    return PurchaseItem(
      key: ValueKey(item),
      item: item,
      onDelete: _isManagingItems
          ? () => context.read<PurchaseProvider>().removeAt(index)
          : null,
      dragHandle: isReorderable
          ? ReorderableDragStartListener(
              index: index,
              child: const Icon(Icons.drag_handle),
            )
          : null,
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
  const PurchaseItem({
    required this.item,
    this.onDelete,
    this.dragHandle,
    super.key,
  });

  final Purchase item;
  final VoidCallback? onDelete;
  final Widget? dragHandle;

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
          if (onDelete != null)
            IconButton(
              tooltip: 'Delete ${item.description}',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
          if (dragHandle != null) ...[const SizedBox(width: 8), dragHandle!],
        ],
      ),
    );
  }
}

class Post {
  final String title;
  final String body;

  Post({required this.title, required this.body});

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(title: json['title'], body: json['body']);
  }
}

class PostListScreen extends StatefulWidget {
  const PostListScreen({super.key});

  @override
  State<PostListScreen> createState() => _PostListScreenState();
}

class _PostListScreenState extends State<PostListScreen> {
  late Future<List<Post>> futurePosts;

  @override
  void initState() {
    super.initState();
    futurePosts = fetchPosts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Popular Items')),
      body: FutureBuilder<List<Post>>(
        future: futurePosts,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('Failed to load posts'));
          }
          final posts = snapshot.data ?? [];
          if (posts.isEmpty) {
            return const Center(child: Text('No posts found'));
          }
          return ListView.builder(
            itemCount: posts.length,
            itemBuilder: (context, index) => ListTile(
              title: Text(posts[index].title),
              subtitle: Text(posts[index].body),
            ),
          );
        },
      ),
    );
  }
}

Future<List<Post>> fetchPosts() async {
  final response = await http.get(
    Uri.parse('https://jsonplaceholder.typicode.com/posts'),
  );

  if (response.statusCode == 200) {
    //return jsonDecode(response.body);
    List<dynamic> data = jsonDecode(response.body);
    return data.map((json) => Post.fromJson(json)).toList();
  } else {
    throw Exception('Failed to load posts');
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

    context.read<PurchaseProvider>().add(
      Purchase(
        description: _descriptionController.text.trim(),
        price: double.parse(_priceController.text.trim()),
        imagePath: 'assets/images/milk.png',
      ),
    );
    Navigator.of(context).pop();
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (context) => const PostListScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.trending_up),
                  label: const Text('Show most popular items this week'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 52,
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.add),
                  label: const Text('Add item'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
