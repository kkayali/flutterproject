import 'package:flutter/material.dart';
import 'radio_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Otantik Radyo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const RadioScreen(),
    );
  }
}
