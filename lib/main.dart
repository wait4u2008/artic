import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'src/screens/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize libmpv-backed media player (video playback).
  MediaKit.ensureInitialized();
  // Never show a blank white screen on a build error — render the error
  // text instead (release builds otherwise go white on any build exception).
  ErrorWidget.builder = (FlutterErrorDetails details) => Material(
        color: const Color(0xFFF6F1E3),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SelectableText(
            'Something went wrong.\n${details.exception}',
            style: const TextStyle(color: Color(0xFF33302B)),
          ),
        ),
      );
  runApp(const NotesApp());
}

class NotesApp extends StatelessWidget {
  const NotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Artic',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C6CF0),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF111318),
      ),
      home: const LoginScreen(),
    );
  }
}
