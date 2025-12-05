import 'package:flutter/material.dart';
import 'package:cyberfly_streaming/src/rust/api/simple.dart';
import 'package:cyberfly_streaming/src/rust/frb_generated.dart';
import 'screens/live_streaming_screen.dart';
import 'screens/video_streaming_screen.dart';
import 'screens/direct_video_streaming_screen.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CyberFly Streaming',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CyberFly P2P Streaming'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Welcome Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Icon(
                      Icons.cloud_sync,
                      size: 64,
                      color: Colors.deepPurple,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'CyberFly P2P Streaming',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Decentralized video streaming powered by Iroh',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Rust bridge status: ${greet(name: "Connected")}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: Colors.green[700],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Live Streaming Option
            _buildFeatureCard(
              context,
              icon: Icons.videocam,
              iconColor: Colors.red,
              title: 'Live Streaming',
              description: 'Broadcast your camera/screen live to peers',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const LiveStreamingScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            
            // Video File Streaming Option
            _buildFeatureCard(
              context,
              icon: Icons.video_library,
              iconColor: Colors.purple,
              title: 'Video File Streaming (Gossip)',
              description: 'Stream video files via gossip relay',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const VideoStreamingScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            
            // Direct Video Streaming Option (NEW)
            _buildFeatureCard(
              context,
              icon: Icons.link,
              iconColor: Colors.deepPurple,
              title: 'Direct Video Streaming',
              description: 'Stream via direct QUIC connection (recommended)',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DirectVideoStreamingScreen(),
                  ),
                );
              },
            ),
            
            const Spacer(),
            
            // Info footer
            Text(
              'Built with Flutter + Rust + Iroh\nP2P gossip protocol for real-time streaming',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
