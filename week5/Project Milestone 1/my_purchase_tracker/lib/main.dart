import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => PurchaseProvider()..initialize(),
      child: const MaterialApp(home: PurchaseList()),
    );
  }
}

class PurchaseProvider extends ChangeNotifier {
  static const _guestItemsKey = 'guest_purchases';

  final List<Purchase> _items = [];
  SharedPreferences? _preferences;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _itemsSubscription;
  String? _userId;
  String? _errorMessage;
  bool _isLoading = true;
  int _accountChange = 0;
  Timer? _loadingTimeout;

  List<Purchase> get items => List.unmodifiable(_items);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> initialize() async {
    try {
      _preferences = await SharedPreferences.getInstance();
      _loadGuestItems();
    } catch (_) {
      _errorMessage = 'Unable to load the saved list from this device.';
    }
    _isLoading = false;
    notifyListeners();
    try {
      _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
        (user) => unawaited(_switchAccount(user)),
        onError: (Object error) {
          _errorMessage = 'Unable to check the signed-in account.';
          _isLoading = false;
          notifyListeners();
        },
      );
    } catch (_) {
      _errorMessage = 'Unable to check the signed-in account.';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _switchAccount(User? user) async {
    final change = ++_accountChange;
    _loadingTimeout?.cancel();
    await _itemsSubscription?.cancel();
    _itemsSubscription = null;
    _userId = user?.uid;
    _errorMessage = null;

    if (user == null) {
      _loadGuestItems();
      _isLoading = false;
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();
    _loadingTimeout = Timer(const Duration(seconds: 12), () {
      if (change != _accountChange || !_isLoading) return;
      _errorMessage ??= 'The cloud list is taking longer to load.';
      _isLoading = false;
      notifyListeners();
    });

    try {
      _itemsSubscription = _userItems(user.uid)
          .orderBy('sortOrder')
          .snapshots()
          .listen(
            (snapshot) {
              if (change != _accountChange) return;
              _loadingTimeout?.cancel();
              _errorMessage = null;
              final localImages = _readAccountImages(user.uid);
              _items
                ..clear()
                ..addAll(
                  snapshot.docs.map(
                    (document) => Purchase.fromCloudDocument(
                      document,
                      imageData: localImages[document.id],
                    ),
                  ),
                );
              _isLoading = false;
              notifyListeners();
            },
            onError: (Object error) {
              if (change != _accountChange) return;
              _loadingTimeout?.cancel();
              _errorMessage =
                  'Unable to load your cloud list. Check your connection.';
              _isLoading = false;
              notifyListeners();
            },
          );
    } catch (_) {
      _loadingTimeout?.cancel();
      _errorMessage = 'Unable to load your cloud list. Check your connection.';
      _isLoading = false;
      notifyListeners();
      return;
    }

    unawaited(
      _migrateGuestItems(user.uid).catchError((Object error) {
        if (change != _accountChange) return;
        _errorMessage = 'Some guest items could not be synced. Check your connection and Firebase setup.';
        notifyListeners();
      }),
    );
  }

  CollectionReference<Map<String, dynamic>> _userItems(String userId) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('purchases');

  String _accountImagesKey(String userId) => 'purchase_images_$userId';

  Map<String, String> _readAccountImages(String userId) {
    final encoded = _preferences?.getString(_accountImagesKey(userId));
    if (encoded == null) return {};
    try {
      return Map<String, String>.from(jsonDecode(encoded) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveAccountImages(
    String userId,
    Map<String, String> images,
  ) async {
    final key = _accountImagesKey(userId);
    if (images.isEmpty) {
      await _preferences?.remove(key);
    } else {
      await _preferences?.setString(key, jsonEncode(images));
    }
  }

  void _loadGuestItems() {
    final encoded = _preferences?.getString(_guestItemsKey);
    if (encoded == null) {
      _items.clear();
      return;
    }
    try {
      final values = jsonDecode(encoded) as List<dynamic>;
      _items
        ..clear()
        ..addAll(
          values.map(
            (value) =>
                Purchase.fromLocalMap(Map<String, dynamic>.from(value as Map)),
          ),
        );
    } catch (_) {
      _items.clear();
      _errorMessage = 'The saved guest list could not be read.';
    }
  }

  Future<void> _saveGuestItems() async {
    await _preferences?.setString(
      _guestItemsKey,
      jsonEncode(_items.map((item) => item.toLocalMap()).toList()),
    );
  }

  Future<void> _migrateGuestItems(String userId) async {
    final encoded = _preferences?.getString(_guestItemsKey);
    if (encoded == null) return;
    final values = jsonDecode(encoded) as List<dynamic>;
    if (values.isEmpty) {
      await _preferences?.remove(_guestItemsKey);
      return;
    }

    final collection = _userItems(userId);
    final existing = await collection.orderBy('sortOrder').get();
    final guestIds = values
        .map((value) => (value as Map)['id'] as String)
        .toSet();
    var sortOrder = existing.docs
        .where((document) => !guestIds.contains(document.id))
        .length;
    final localImages = _readAccountImages(userId);
    for (final value in values) {
      final item = Purchase.fromLocalMap(
        Map<String, dynamic>.from(value as Map),
      );
      if (item.imageData != null) localImages[item.id] = item.imageData!;
      await collection.doc(item.id).set({
        'description': item.description,
        'price': item.price,
        'sortOrder': sortOrder++,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await _saveAccountImages(userId, localImages);
    await _preferences?.remove(_guestItemsKey);
  }

  Future<void> add(Purchase item) async {
    if (_userId == null) {
      _items.add(item);
      await _saveGuestItems();
      notifyListeners();
      return;
    }

    final userId = _userId!;
    final localImages = _readAccountImages(userId);
    if (item.imageData == null) {
      localImages.remove(item.id);
    } else {
      localImages[item.id] = item.imageData!;
    }
    await _saveAccountImages(userId, localImages);
    final sortOrder = _items.length;
    await _userItems(userId).doc(item.id).set({
      'description': item.description,
      'price': item.price,
      'sortOrder': sortOrder,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> removeAt(int index) async {
    final item = _items[index];
    if (_userId != null) {
      await _userItems(_userId!).doc(item.id).delete();
      final localImages = _readAccountImages(_userId!);
      localImages.remove(item.id);
      await _saveAccountImages(_userId!, localImages);
    } else {
      _items.removeAt(index);
      await _saveGuestItems();
      notifyListeners();
    }
  }

  Future<void> move(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        oldIndex >= _items.length ||
        newIndex < 0 ||
        newIndex >= _items.length ||
        oldIndex == newIndex) {
      return;
    }
    final reordered = List<Purchase>.of(_items);
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);
    if (_userId != null) {
      final batch = FirebaseFirestore.instance.batch();
      for (var index = 0; index < reordered.length; index++) {
        batch.update(_userItems(_userId!).doc(reordered[index].id), {
          'sortOrder': index,
        });
      }
      await batch.commit();
    }
    _items
      ..clear()
      ..addAll(reordered);
    if (_userId == null) await _saveGuestItems();
    notifyListeners();
  }

  @override
  void dispose() {
    _loadingTimeout?.cancel();
    unawaited(_authSubscription?.cancel());
    unawaited(_itemsSubscription?.cancel());
    super.dispose();
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
    final provider = context.watch<PurchaseProvider>();
    final items = provider.items;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F8F6),
        foregroundColor: const Color(0xFF1D2B24),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 8,
        leading: const Icon(Icons.shopping_bag_outlined),
        actions: [
          StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            initialData: FirebaseAuth.instance.currentUser,
            builder: (context, snapshot) {
              final user = snapshot.data;
              return IconButton(
                tooltip: user == null ? 'Log in' : 'Sign out',
                onPressed: () => user == null
                    ? _showLoginDialog(context)
                    : FirebaseAuth.instance.signOut(),
                icon: Icon(user == null ? Icons.login : Icons.logout),
              );
            },
          ),
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
            if (provider.errorMessage != null) ...[
              Text(
                provider.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: provider.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : items.isEmpty
                  ? const Center(child: Text('There are currently no items'))
                  : _isManagingItems
                  ? ReorderableListView.builder(
                      itemCount: items.length,
                      onReorderItem: (oldIndex, newIndex) {
                        unawaited(
                          context.read<PurchaseProvider>().move(
                            oldIndex,
                            newIndex,
                          ),
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

  Future<void> _showLoginDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => const _LoginDialog(),
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
          ? () => unawaited(context.read<PurchaseProvider>().removeAt(index))
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

class _LoginDialog extends StatefulWidget {
  const _LoginDialog();

  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSigningIn = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit(bool createAccount) async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (createAccount && password.length < 6) {
      setState(() {
        _errorMessage = 'Password must be at least 6 characters.';
      });
      return;
    }
    setState(() {
      _isSigningIn = true;
      _errorMessage = null;
    });

    try {
      final auth = FirebaseAuth.instance;
      if (createAccount) {
        await auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        await auth.signInWithEmailAndPassword(email: email, password: password);
      }
      if (mounted) Navigator.of(context).pop();
    } on FirebaseAuthException catch (error) {
      setState(() {
        _errorMessage = switch (error.code) {
          'invalid-credential' || 'wrong-password' || 'user-not-found' => 'Email or password is incorrect. If you are new, create an account.',
          'email-already-in-use' =>
            'An account already exists for this email. Log in instead.',
          'weak-password' => 'Password must be at least 6 characters.',
          'invalid-email' => 'Enter a valid email address.',
          _ => error.message ?? 'Unable to authenticate. Please try again.',
        };
        _isSigningIn = false;
      });
    } catch (_) {
      setState(() {
        _errorMessage = 'Unable to log in. Please try again.';
        _isSigningIn = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Log in'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _emailController,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter your email'
                    : null,
              ),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: const InputDecoration(labelText: 'Password'),
                validator: (value) => value == null || value.isEmpty
                    ? 'Enter your password'
                    : null,
                onFieldSubmitted: (_) => _submit(false),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSigningIn ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _isSigningIn ? null : () => _submit(true),
          child: const Text('Sign up'),
        ),
        FilledButton(
          onPressed: _isSigningIn ? null : () => _submit(false),
          child: _isSigningIn
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Log in'),
        ),
      ],
    );
  }
}

class Purchase {
  Purchase({
    String? id,
    required this.description,
    required this.price,
    this.imageData,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();

  final String id;
  final String description;
  final double price;
  final String? imageData;

  factory Purchase.fromLocalMap(Map<String, dynamic> data) => Purchase(
    id: data['id'] as String,
    description: data['description'] as String,
    price: (data['price'] as num).toDouble(),
    imageData: data['imageData'] as String?,
  );

  factory Purchase.fromCloudDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document, {
    String? imageData,
  }) {
    final data = document.data();
    return Purchase(
      id: document.id,
      description: data['description'] as String,
      price: (data['price'] as num).toDouble(),
      imageData: imageData,
    );
  }

  Map<String, dynamic> toLocalMap() => {
    'id': id,
    'description': description,
    'price': price,
    'imageData': imageData,
  };
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
    final image = item.imageData == null
        ? _placeholderImage()
        : Image.memory(
            base64Decode(item.imageData!),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => _placeholderImage(),
          );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(8),
      color: Colors.grey.shade200,
      child: Row(
        children: [
          SizedBox(
            width: 100,
            height: 80,
            child: ColoredBox(color: Colors.deepPurple.shade50, child: image),
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

  Widget _placeholderImage() =>
      Image.asset('assets/images/Placeholder.png', fit: BoxFit.contain);
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
  Uint8List? _selectedImageBytes;
  bool _isSaving = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final image = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1280,
        imageQuality: 75,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (mounted) setState(() => _selectedImageBytes = bytes);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the selected image source.'),
        ),
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      await context.read<PurchaseProvider>().add(
        Purchase(
          description: _descriptionController.text.trim(),
          price: double.parse(_priceController.text.trim()),
          imageData: _selectedImageBytes == null
              ? null
              : base64Encode(_selectedImageBytes!),
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save this item. Please try again.'),
        ),
      );
    }
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
            Text('Photo', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            AspectRatio(
              aspectRatio: 16 / 10,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: _selectedImageBytes == null
                    ? const Center(child: Icon(Icons.image_outlined, size: 44))
                    : Image.memory(_selectedImageBytes!, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Take photo'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Choose photo'),
                  ),
                ),
              ],
            ),
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
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                  label: Text(_isSaving ? 'Saving' : 'Add item'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
