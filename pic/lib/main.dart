import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local Images Demo',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text('4 Local Images')),
        body: const Center(
          child: FourImageRow(),
        ),
      ),
    );
  }
}

class FourImageRow extends StatelessWidget {
  const FourImageRow({super.key});

  @override
  Widget build(BuildContext context) {
    final imagePaths = [
      'demo/1.png',
      'demo/2.png',
      'demo/3.png',
      'demo/4.png',
      'demo/5.png',
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: imagePaths.map((path) {
          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: Image.asset(
              path,
              width: 150,
              fit: BoxFit.cover,
            ),
          );
        }).toList(),
      ),
    );
  }
}
