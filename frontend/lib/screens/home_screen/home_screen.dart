import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/api_service.dart';
import '../options_screen/options_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _cravingController = TextEditingController();
  late AnimationController _pulseController;
  bool _isLoading = false;

  String _userName = '';
  int _totalPoints = 0;
  String _rank = 'Bronze';
  bool _profileLoaded = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _loadProfile();
  }

  @override
  void dispose() {
    _cravingController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final data = await ApiService().getProfile();
      if (mounted) {
        final profileName = data['name'] as String?;
        final loginName = ApiService().userName;
        // Use profile name if available, otherwise the name from login
        final name = (profileName != null && profileName.isNotEmpty)
            ? profileName
            : (loginName != null && loginName.isNotEmpty)
                ? loginName
                : 'there';
        setState(() {
          _userName = name;
          _totalPoints = data['total_points'] as int? ?? 0;
          _rank = data['rank'] as String? ?? 'Bronze';
          _profileLoaded = true;
        });
      }
    } catch (e) {
      if (mounted) {
        final loginName = ApiService().userName;
        setState(() {
          _userName = (loginName != null && loginName.isNotEmpty)
              ? loginName
              : 'there';
          _profileLoaded = true;
        });
      }
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
      // Get user's current location
      double latitude = 6.9271;  // Default to Colombo, Sri Lanka
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

      final data = await ApiService().submitCrave(
        _cravingController.text.trim(),
        latitude,
        longitude,
      );

      if (!mounted) return;

      final sessionId = data['session_id'] as String? ?? '';
      final rawOptions = data['options'];

      List<Map<String, dynamic>> options = [];
      if (rawOptions != null && rawOptions is List) {
        for (var o in rawOptions) {
          if (o is Map<String, dynamic>) {
            options.add(o);
          } else if (o is Map) {
            options.add(Map<String, dynamic>.from(o));
          } else {
            options.add(<String, dynamic>{'option': o.toString()});
          }
        }
      }

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
      if (mounted) setState(() => _isLoading = false);
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
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: isSmallScreen ? 24 : 32),
                        // Greeting & Stats Row
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hey ${_userName.isNotEmpty ? _userName : 'there'} ',
                                style: TextStyle(
                                  fontSize: isSmallScreen ? 32 : 38,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF1B5E20),
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Stats badges
                              Row(
                                children: [
                                  _buildStatBadge(
                                    Icons.stars_rounded,
                                    '$_totalPoints pts',
                                    const Color(0xFFFFB300),
                                  ),
                                  const SizedBox(width: 12),
                                  _buildStatBadge(
                                    Icons.emoji_events_rounded,
                                    _rank,
                                    const Color(0xFFFF6F00),
                                  ),
                                ],
                              ),
                            ],
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
                        SizedBox(height: isSmallScreen ? 32 : 48),
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
                            child: Padding(
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
                                ],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: isSmallScreen ? 24 : 36),
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
                                  : const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.search_rounded, size: 22),
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
                        SizedBox(height: isSmallScreen ? 32 : 48),
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
                                  _buildSuggestionChip('Pizza'),
                                  _buildSuggestionChip('Chocolate'),
                                  _buildSuggestionChip('Ice Cream'),
                                  _buildSuggestionChip('Burger'),
                                  _buildSuggestionChip('Cake'),
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

  Widget _buildStatBadge(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionChip(String label) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _cravingController.text = label;
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
