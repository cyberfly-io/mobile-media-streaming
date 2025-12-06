import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cyberfly_streaming/src/rust/api/simple.dart';
import 'package:cyberfly_streaming/src/rust/frb_generated.dart';
import 'package:cyberfly_streaming/src/rust/api/iroh_live_flutter_api.dart';
import 'screens/iroh_streaming_screen.dart';
import 'screens/live_stream_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  
  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CyberFly',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1), // Indigo
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0F0F1A),
      ),
      themeMode: ThemeMode.dark,
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  String _version = '';
  Map<String, bool> _features = {};
  late AnimationController _pulseController;
  late AnimationController _floatController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _floatAnimation;
  
  @override
  void initState() {
    super.initState();
    _loadInfo();
    
    // Pulse animation for the live indicator
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    // Float animation for the hero icon
    _floatController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    )..repeat(reverse: true);
    
    _floatAnimation = Tween<double>(begin: -10, end: 10).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );
  }
  
  @override
  void dispose() {
    _pulseController.dispose();
    _floatController.dispose();
    super.dispose();
  }
  
  void _loadInfo() {
    setState(() {
      _version = irohGetVersion();
      _features = irohGetFeatures();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      body: Stack(
        children: [
          // Animated background gradient
          _buildAnimatedBackground(),
          
          // Main content
          SafeArea(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // Hero section
                SliverToBoxAdapter(
                  child: _buildHeroSection(context),
                ),
                
                // Status card
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverToBoxAdapter(
                    child: _buildGlassStatusCard(context),
                  ),
                ),
                
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
                
                // Main feature card
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverToBoxAdapter(
                    child: _buildMainFeatureCard(context),
                  ),
                ),
                
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
                
                // Live Stream card (NEW iroh-live integration)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverToBoxAdapter(
                    child: _buildLiveStreamCard(context),
                  ),
                ),
                
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
                
                // Quick stats
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverToBoxAdapter(
                    child: _buildQuickStats(context),
                  ),
                ),
                
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
                
                // Footer
                SliverToBoxAdapter(
                  child: _buildFooter(context),
                ),
                
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildAnimatedBackground() {
    return Stack(
      children: [
        // Top right gradient blob
        Positioned(
          top: -100,
          right: -100,
          child: AnimatedBuilder(
            animation: _floatAnimation,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, _floatAnimation.value),
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF6366F1).withValues(alpha: 0.3),
                        const Color(0xFF6366F1).withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // Bottom left gradient blob
        Positioned(
          bottom: -50,
          left: -50,
          child: AnimatedBuilder(
            animation: _floatAnimation,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, -_floatAnimation.value),
                child: Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                        const Color(0xFF8B5CF6).withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
  
  Widget _buildHeroSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo and title
          Row(
            children: [
              AnimatedBuilder(
                animation: _floatAnimation,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(0, _floatAnimation.value * 0.3),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF6366F1),
                            Color(0xFF8B5CF6),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.stream,
                        size: 32,
                        color: Colors.white,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CyberFly',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: -1,
                      ),
                    ),
                    Text(
                      'P2P Streaming Platform',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.6),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          // Tagline
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFF6366F1), Color(0xFFA855F7), Color(0xFFEC4899)],
            ).createShader(bounds),
            child: const Text(
              'Stream Anywhere.\nNo Servers Required.',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                height: 1.2,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildGlassStatusCard(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  // Animated status indicator
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF22C55E),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF22C55E).withValues(alpha: _pulseAnimation.value * 0.5),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'System Online',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      greet(name: 'Connected'),
                      style: const TextStyle(
                        color: Color(0xFF22C55E),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Feature tags
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _features.entries.where((e) => e.value).map((entry) {
                  return _buildFeatureTag(entry.key);
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildFeatureTag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF6366F1).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF6366F1).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle,
            size: 14,
            color: const Color(0xFF6366F1).withValues(alpha: 0.8),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildMainFeatureCard(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => 
              const IrohStreamingScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(1, 0),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                )),
                child: child,
              );
            },
            transitionDuration: const Duration(milliseconds: 400),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF6366F1),
              Color(0xFF8B5CF6),
              Color(0xFFA855F7),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withValues(alpha: 0.4),
              blurRadius: 30,
              offset: const Offset(0, 15),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Background pattern
            Positioned(
              right: -30,
              top: -30,
              child: Icon(
                Icons.live_tv,
                size: 180,
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_awesome, size: 14, color: Colors.white),
                            SizedBox(width: 4),
                            Text(
                              'FEATURED',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Iroh Live\nStreaming',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.1,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Full-featured P2P broadcasting with multi-quality renditions. Capture, encode, publish, and subscribe.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.8),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Feature pills
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildPill('📹 Capture'),
                      _buildPill('📡 Publish'),
                      _buildPill('📺 Subscribe'),
                      _buildPill('🎚️ Multi-Quality'),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // CTA button
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Start Streaming',
                          style: TextStyle(
                            color: Color(0xFF6366F1),
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: Color(0xFF6366F1),
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
  
  Widget _buildLiveStreamCard(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => 
              const LiveStreamingScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(1, 0),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                )),
                child: child,
              );
            },
            transitionDuration: const Duration(milliseconds: 400),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF22C55E).withValues(alpha: 0.3),
                  const Color(0xFF10B981).withValues(alpha: 0.2),
                ],
              ),
              border: Border.all(
                color: const Color(0xFF22C55E).withValues(alpha: 0.3),
              ),
            ),
            child: Stack(
              children: [
                // Background pattern
                Positioned(
                  right: -20,
                  top: -20,
                  child: Icon(
                    Icons.sensors,
                    size: 120,
                    color: const Color(0xFF22C55E).withValues(alpha: 0.1),
                  ),
                ),
                // Content
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF22C55E).withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.fiber_new, size: 14, color: Color(0xFF22C55E)),
                                SizedBox(width: 4),
                                Text(
                                  'NEW',
                                  style: TextStyle(
                                    color: Color(0xFF22C55E),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Live Stream',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'iroh-live P2P with FFmpegKit encoding. Real camera capture with H264 encoding.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.7),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Feature pills
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildLivePill('📷 Camera'),
                          _buildLivePill('🎬 FFmpeg'),
                          _buildLivePill('🌐 P2P'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildLivePill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF22C55E).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.9),
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
  
  Widget _buildQuickStats(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _buildStatCard('Video Codecs', '5', Icons.videocam)),
        const SizedBox(width: 12),
        Expanded(child: _buildStatCard('Audio Codecs', '3', Icons.audiotrack)),
        const SizedBox(width: 12),
        Expanded(child: _buildStatCard('Quality Levels', '4', Icons.high_quality)),
      ],
    );
  }
  
  Widget _buildStatCard(String label, String value, IconData icon) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: const Color(0xFF6366F1),
                size: 24,
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildFooter(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildTechBadge('Flutter'),
            const SizedBox(width: 8),
            const Text('•', style: TextStyle(color: Colors.white24)),
            const SizedBox(width: 8),
            _buildTechBadge('Rust'),
            const SizedBox(width: 8),
            const Text('•', style: TextStyle(color: Colors.white24)),
            const SizedBox(width: 8),
            _buildTechBadge('Iroh'),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Version $_version',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 12,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
  
  Widget _buildTechBadge(String text) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.5),
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}
