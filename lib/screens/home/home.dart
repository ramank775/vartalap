/// Home: Chats and, next to it, the private Timeline (decision 223),
/// WhatsApp's bottom bar. A new post wakes nobody, so the Timeline tab
/// shows a dot when something was shared since it was last opened,
/// checked when the app starts or comes back.
library vartalap.screens.home;

import 'package:flutter/material.dart';
import 'package:vartalap/config/config_store.dart';
import 'package:vartalap/screens/chats/chats.dart';
import 'package:vartalap/screens/timeline/timeline.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/services/crash_reports.dart';

class HomeScreen extends StatefulWidget {
  final ChatService chatService;
  final AuthService authService;
  final ConfigStore config;

  const HomeScreen({
    super.key,
    required this.chatService,
    required this.authService,
    required this.config,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _tab = 0;

  /// Bumped on every switch to Timeline: a fresh screen, so a fresh load.
  int _opened = 0;
  bool _new = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkNew();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => CrashReports.instance?.offer(context));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkNew();
  }

  Future<void> _checkNew() async {
    if (_tab == 1) return;
    final fresh = await widget.chatService.timelineHasNew();
    if (mounted && _tab != 1) setState(() => _new = fresh);
  }

  void _select(int tab) => setState(() {
        if (tab == 1 && _tab != 1) _opened++;
        _tab = tab;
        if (tab == 1) _new = false;
      });

  @override
  Widget build(BuildContext context) => PopScope(
        // Back on Timeline goes to Chats first, as WhatsApp's tabs do.
        canPop: _tab == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _select(0);
        },
        child: Scaffold(
          body: IndexedStack(
            index: _tab,
            children: [
              ChatsScreen(
                chatService: widget.chatService,
                authService: widget.authService,
                config: widget.config,
              ),
              // Built only while shown: it loads from the server.
              _tab == 1
                  ? TimelineScreen(
                      key: ValueKey(_opened),
                      chatService: widget.chatService,
                      authService: widget.authService,
                    )
                  : const SizedBox.shrink(),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: _select,
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.chat_outlined),
                selectedIcon: Icon(Icons.chat),
                label: 'Chats',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: _new,
                  smallSize: 10,
                  child: const Icon(Icons.dynamic_feed_outlined),
                ),
                selectedIcon: const Icon(Icons.dynamic_feed),
                label: 'Timeline',
                tooltip: _new ? 'Timeline, new posts' : 'Timeline',
              ),
            ],
          ),
        ),
      );
}
