import 'package:flutter/material.dart';
import 'package:nexus_comm/l10n/app_localizations.dart';
import '../chats/chats_screen.dart';
import '../mesh/mesh_screen.dart';
import '../dialer/dialer_screen.dart';
import '../settings/settings_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pages = const [
      ChatsScreen(),
      MeshScreen(),
      DialerScreen(),
      SettingsScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.chat_bubble_outline), label: l10n.tabChats),
          NavigationDestination(icon: const Icon(Icons.radar), label: l10n.tabMesh),
          NavigationDestination(icon: const Icon(Icons.dialpad), label: l10n.tabDialer),
          NavigationDestination(icon: const Icon(Icons.settings_outlined), label: l10n.tabSettings),
        ],
      ),
    );
  }
}
