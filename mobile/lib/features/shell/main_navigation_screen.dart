// v1 shell — four tabs only: Chats · Calls · Nearby · Settings.
//
// DECISION LOCKED: previous Cloud/Mesh/Dialer/Portal destinations are rebased
// in place (Cloud->Chats, Dialer->Calls, Mesh->Nearby, Portal->Settings). No
// fifth tab. Legacy screens remain in the repo but are no longer destinations
// here; the hybrid prototypes replace them as tab bodies.

import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_tokens.dart';
import '../hybrid/hybrid_calls_screen.dart';
import '../hybrid/hybrid_chats_screen.dart';
import '../hybrid/hybrid_nearby_screen.dart';
import '../hybrid/hybrid_settings_screen.dart';
import 'connection_status_badge.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _index = 0;

  static const _pages = [
    HybridChatsScreen(),
    HybridCallsScreen(),
    HybridNearbyScreen(),
    HybridSettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.canvas,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('dsaialap', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(child: ConnectionStatusBadge()),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppTokens.surface.withValues(alpha: 0.92),
        indicatorColor: AppTokens.primaryBright.withValues(alpha: 0.2),
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: AppStrings.tabChats),
          NavigationDestination(icon: Icon(Icons.call_outlined), selectedIcon: Icon(Icons.call), label: AppStrings.tabCalls),
          NavigationDestination(icon: Icon(Icons.radar), selectedIcon: Icon(Icons.radar), label: AppStrings.tabNearby),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: AppStrings.tabSettings),
        ],
      ),
    );
  }
}
