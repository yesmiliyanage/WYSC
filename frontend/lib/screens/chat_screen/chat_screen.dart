import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';

import '../../services/api_service.dart';
import '../options_screen/options_screen.dart';

class ChatScreen extends StatefulWidget {
  final String userName;

  const ChatScreen({
    Key? key,
    this.userName = 'Arun',
  }) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _cravingController = TextEditingController();
  late AnimationController _pulseController;
  bool _isVoiceActive = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _cravingController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _toggleVoiceInput() {
    setState(() {
      _isVoiceActive = !_isVoiceActive;
    });

    if (_isVoiceActive) {
      // TODO: Implement voice input functionality
      // For now, simulate voice input
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && _isVoiceActive) {
          setState(() {
            _cravingController.text = "Pizza";
            _isVoiceActive = false;
          });
        }
      });
    }
  }

  void _findOptions() async {
    if (_cravingController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please tell us what you\'re craving!'),
          backgroundColor: Color(0xFFEF5350),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Get user's current location, fall back to Colombo if unavailable.
      double latitude = 6.9271;
      double longitude = 79.8612;

      try {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.whileInUse ||
            permission == LocationPermission.always) {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
            ),
          );
          latitude = position.latitude;
          longitude = position.longitude;
        }
      } catch (_) {
        // Location unavailable — fall back to default coordinates.
      }

      // Call the API to get craving options
      final response = await ApiService().submitCrave(
        _cravingController.text.trim(),
        latitude,
        longitude,
      );

      if (!mounted) return;

      final sessionId = response['session_id'] as String? ?? '';

      List<Map<String, dynamic>> options = [];
      final rawOptions = response['options'];

      if (rawOptions != null && rawOptions is List) {
        for (var item in rawOptions) {
          if (item is Map<String, dynamic>) {
            options.add(item);
          } else if (item is Map) {
            options.add(Map<String, dynamic>.from(item));
          }
        }
      }

      // Navigate to options screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OptionsScreen(
            sessionId: sessionId,
            options: options,
            craving: _cravingController.text.trim(),
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: const Color(0xFFEF5350),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: const Color(0xFFEF5350),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.height < 700;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFF8F9FA),
              const Color(0xFFE8F5E9).withOpacity(0.3),
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Animated background circles
              ...List.generate(2, (index) {
                return AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Positioned(
                      top: 100 + (index * 400.0),
                      right: -150 + (index * 100.0),
                      child: Opacity(
                        opacity: 0.03 + (_pulseController.value * 0.02),
                        child: Container(
                          width: 350,
                          height: 350,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                const Color(0xFF66BB6A).withOpacity(0.3),
                                const Color(0xFF66BB6A).withOpacity(0.0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              }),
              // Main content
              SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: size.height - 100),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: isSmallScreen ? 40 : 60),
                        // Greeting
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.0, end: 1.0),
                          duration: const Duration(milliseconds: 800),
                          builder: (context, value, child) {
                            return Opacity(
                              opacity: value,
                              child: Transform.translate(
                                offset: Offset(0, 20 * (1 - value)),
                                child: child,
                              ),
                            );
                          },
                          child: Text(
                            'Hey ${widget.userName} 👋',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 32 : 38,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF1B5E20),
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                        SizedBox(height: isSmallScreen ? 12 : 16),
                        // Subtitle
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.0, end: 1.0),
                          duration: const Duration(milliseconds: 1000),
                          builder: (context, value, child) {
                            return Opacity(
                              opacity: value,
                              child: Transform.translate(
                                offset: Offset(0, 20 * (1 - value)),
                                child: child,
                              ),
                            );
                          },
                          child: Text(
                            'What\'s on your mind today?',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 16 : 18,
                              color: const Color(0xFF1B5E20).withOpacity(0.6),
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                        SizedBox(height: isSmallScreen ? 40 : 60),
                        // Craving input card
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.0, end: 1.0),
                          duration: const Duration(milliseconds: 1200),
                          builder: (context, value, child) {
                            return Opacity(
                              opacity: value,
                              child: Transform.scale(
                                scale: 0.9 + (0.1 * value),
                                child: child,
                              ),
                            );
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF66BB6A).withOpacity(0.1),
                                  blurRadius: 30,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(24.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'What are you craving right now?',
                                        style: TextStyle(
                                          fontSize: isSmallScreen ? 20 : 24,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF1B5E20),
                                          height: 1.3,
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                      // Text input
                                      TextField(
                                        controller: _cravingController,
                                        maxLines: 3,
                                        style: const TextStyle(
                                          fontSize: 17,
                                          color: Color(0xFF1B5E20),
                                          fontWeight: FontWeight.w500,
                                        ),
                                        decoration: InputDecoration(
                                          hintText: 'e.g., Chocolate cake, Pizza, Ice cream...',
                                          hintStyle: TextStyle(
                                            color: const Color(0xFF1B5E20).withOpacity(0.3),
                                            fontWeight: FontWeight.w400,
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(16),
                                            borderSide: BorderSide(
                                              color: const Color(0xFF66BB6A).withOpacity(0.2),
                                              width: 2,
                                            ),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(16),
                                            borderSide: BorderSide(
                                              color: const Color(0xFF66BB6A).withOpacity(0.2),
                                              width: 2,
                                            ),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(16),
                                            borderSide: const BorderSide(
                                              color: Color(0xFF66BB6A),
                                              width: 2.5,
                                            ),
                                          ),
                                          filled: true,
                                          fillColor: const Color(0xFF66BB6A).withOpacity(0.05),
                                          contentPadding: const EdgeInsets.all(16),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      // Voice input button
                                      GestureDetector(
                                        onTap: _toggleVoiceInput,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _isVoiceActive
                                                ? const Color(0xFF66BB6A).withOpacity(0.15)
                                                : const Color(0xFF66BB6A).withOpacity(0.08),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: _isVoiceActive
                                                  ? const Color(0xFF66BB6A)
                                                  : const Color(0xFF66BB6A).withOpacity(0.3),
                                              width: 2,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              AnimatedBuilder(
                                                animation: _pulseController,
                                                builder: (context, child) {
                                                  return Icon(
                                                    _isVoiceActive
                                                        ? Icons.mic_rounded
                                                        : Icons.mic_none_rounded,
                                                    color: const Color(0xFF66BB6A),
                                                    size: _isVoiceActive
                                                        ? 22 + (_pulseController.value * 4)
                                                        : 22,
                                                  );
                                                },
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                _isVoiceActive
                                                    ? 'Listening...'
                                                    : 'Use Voice Input',
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF66BB6A),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: isSmallScreen ? 32 : 48),
                        // Find Options button
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.0, end: 1.0),
                          duration: const Duration(milliseconds: 1400),
                          builder: (context, value, child) {
                            return Opacity(
                              opacity: value,
                              child: Transform.translate(
                                offset: Offset(0, 20 * (1 - value)),
                                child: child,
                              ),
                            );
                          },
                          child: SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _findOptions,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF66BB6A),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                disabledBackgroundColor:
                                const Color(0xFF66BB6A).withOpacity(0.6),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                                  : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(
                                    Icons.search_rounded,
                                    size: 22,
                                  ),
                                  SizedBox(width: 10),
                                  Text(
                                    'Find Options',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: isSmallScreen ? 40 : 60),
                        // Quick suggestions
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.0, end: 1.0),
                          duration: const Duration(milliseconds: 1600),
                          builder: (context, value, child) {
                            return Opacity(
                              opacity: value,
                              child: child,
                            );
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Quick suggestions',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF1B5E20).withOpacity(0.7),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  _buildSuggestionChip('🍕 Pizza'),
                                  _buildSuggestionChip('🍫 Chocolate'),
                                  _buildSuggestionChip('🍦 Ice Cream'),
                                  _buildSuggestionChip('🍔 Burger'),
                                  _buildSuggestionChip('🍰 Cake'),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionChip(String label) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _cravingController.text = label.split(' ')[1];
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF66BB6A).withOpacity(0.2),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF66BB6A).withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1B5E20),
          ),
        ),
      ),
    );
  }
}