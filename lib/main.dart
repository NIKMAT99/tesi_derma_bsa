import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/main_provider.dart';
import 'ui/screens/interactive_mapper_screen.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MainProvider()),
      ],
      child: const DermaBsaApp(),
    ),
  );
}

class DermaBsaApp extends StatelessWidget {
  const DermaBsaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DermaBSA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.teal,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF008080),
          primary: const Color(0xFF008080),
          secondary: const Color(0xFF20B2AA),
        ),
        useMaterial3: true,
      ),
      home: const InteractiveMapperScreen(),
    );
  }
}