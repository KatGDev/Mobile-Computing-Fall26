import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> saveName(String name) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('username', name);
}

Future<String> loadName() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('username') ?? 'Guest';
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(debugShowCheckedModeBanner: false, home: Homepage());
  }
}

class Homepage extends StatefulWidget {
  const Homepage({super.key});

  @override
  State<Homepage> createState() => _HomePageState();
}

class _HomePageState extends State<Homepage> {
  var _loadedName = '';
  var _showLoadedName = false;
  final _nameController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 250,
              height: 100,
              child: TextField(
                controller: _nameController,
                decoration: const InputDecoration(hintText: 'Your name'),
              ),
            ),
            if (_showLoadedName && _loadedName.isNotEmpty)
              Text('Hello $_loadedName'),
            ElevatedButton(
              onPressed: () async {
                final name = _nameController.text;
                await saveName(name);
                if (!mounted) return;
                setState(() {
                  _loadedName = name;
                });
              },
              child: const Text('Save'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = await loadName();
                if (!mounted) return;
                setState(() {
                  _loadedName = name;
                  _showLoadedName = true;
                });
              },
              child: const Text('Load'),
            ),
          ],
        ),
      ),
    );
  }
}
