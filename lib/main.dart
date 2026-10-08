import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'screens/root_shell.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'AIzaSyAMg51XV48MTRu_cAYsuN0lFYXIp5FSVWM',
      appId: '1:157810342197:web:5707cf3466bd987bb2747c',
      messagingSenderId: '157810342197',
      projectId: 'termite-detector-69393',
      databaseURL: 'https://termite-detector-69393-default-rtdb.asia-southeast1.firebasedatabase.app/',
    ),
  );

  runApp(const TermiguardApp());
}

class TermiguardApp extends StatelessWidget {
  const TermiguardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Termiguard',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const RootShell(),
    );
  }
}