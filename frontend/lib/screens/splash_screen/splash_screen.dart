import 'package:flutter/material.dart';
import 'dart:async';

import 'package:frontend/main_navigation.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // Scale animation for logo
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    );

    // Fade animation for text
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );

    // Pulse animation for background
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // Start animations
    _scaleController.forward();
    Future.delayed(const Duration(milliseconds: 300), () {
      _fadeController.forward();
    });

    // Navigate directly to the main app after 3 seconds — no login required
    Timer(const Duration(seconds: 3), () {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const MainNavigationScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    });
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _fadeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [const Color(0xFF66BB6A), const Color(0xFF43A047)],
          ),
        ),
        child: Stack(
          children: [
            // Animated background circles
            ...List.generate(5, (index) {
              return AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final offset = (index * 0.2);
                  final value = (_pulseController.value + offset) % 1.0;
                  return Positioned(
                    top: -100 + (index * 150.0),
                    right: -150 + (index * 80.0),
                    child: Opacity(
                      opacity: 0.1 * (1 - value),
                      child: Container(
                        width: 250 + (value * 100),
                        height: 250 + (value * 100),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  );
                },
              );
            }),
            // Main content
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated logo
                  ScaleTransition(
                    scale: _scaleAnimation,
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 30,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Pulsing ring
                          AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, child) {
                              return Container(
                                width: 100 + (_pulseController.value * 20),
                                height: 100 + (_pulseController.value * 20),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFF66BB6A).withOpacity(
                                    0.2 * (1 - _pulseController.value),
                                  ),
                                ),
                              );
                            },
                          ),
                          // Icon
                          Container(
                            width: 80,
                            height: 80,
                            decoration: const BoxDecoration(
                              color: Color(0xFF66BB6A),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.restaurant_menu_rounded,
                              size: 45,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  // App name with fade
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: const Column(
                      children: [
                        Text(
                          'CraveBalance',
                          style: TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Smart Cravings, Healthy Choices',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 60),
                  // Loading indicator
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white.withOpacity(0.7),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            // Bottom tagline
            Positioned(
              bottom: 50,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: const Text(
                  'Balance Your Cravings',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white70,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
