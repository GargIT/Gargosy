import 'package:flutter/material.dart';

class GargosyApp extends StatelessWidget {
  const GargosyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Gargosy',
      debugShowCheckedModeBanner: false,
      home: Scaffold(body: Center(child: Text('Gargosy'))),
    );
  }
}
