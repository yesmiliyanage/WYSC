import 'package:flutter/material.dart';
import 'package:frontend/main_navigation.dart';
import 'package:frontend/screens/splash_screen/splash_screen.dart';
import 'package:frontend/screens/auth_screens/login_screen.dart';
import 'package:frontend/services/api_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService().init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CraveBalance',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Poppins',
        primarySwatch: Colors.green,
        primaryColor: const Color(0xFF66BB6A),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF66BB6A),
          brightness: Brightness.light,
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const MainNavigationScreen(),
      },
    );
  }
}
