import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vartalap/config/app_config.dart';
import 'package:vartalap/screens/chats/chats.dart';
import 'package:vartalap/screens/chat/chat.dart';
import 'package:vartalap/screens/login/introduction.dart';
import 'package:vartalap/screens/login/verify_otp.dart';
import 'package:vartalap/screens/new_chat/create_group.dart';
import 'package:vartalap/screens/new_chat/new_chat.dart';
import 'package:vartalap/screens/new_chat/select_group_member.dart';
import 'package:vartalap/screens/profile/profile.dart';
import 'package:vartalap/screens/startup/startup.dart';
import 'package:vartalap/services/otp/firebase_otp_provider.dart';
import 'package:vartalap/services/otp/iotp_provider.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/widgets/Inherited/current_user.dart';
import 'package:vartalap/widgets/Inherited/vartalap_client_provider.dart';
import 'package:vartalap/widgets/mock_developer_menu.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';
import 'package:vartalap_testing/vartalap_testing.dart';

void main() async {
  final startTime = DateTime.now();
  debugPrint('🚀 [PERF] App main() started at: ${startTime.millisecondsSinceEpoch}');

  final bindingStart = DateTime.now();
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('⏱️ [PERF] WidgetsFlutterBinding took: ${DateTime.now().difference(bindingStart).inMilliseconds}ms');

  final configStart = DateTime.now();
  await AppConfig.initialize();
  debugPrint('⏱️ [PERF] AppConfig.initialize took: ${DateTime.now().difference(configStart).inMilliseconds}ms');

  // Create and initialize auth client before running the app
  final authClientStart = DateTime.now();
  final client = _createClient();
  
  // Restore session
  await client.auth.checkAuth();
  
  debugPrint('⏱️ [PERF] AuthClient initialization took: ${DateTime.now().difference(authClientStart).inMilliseconds}ms');

  final runAppStart = DateTime.now();
  runApp(VartalapApp(client: client));
  debugPrint('⏱️ [PERF] runApp() took: ${DateTime.now().difference(runAppStart).inMilliseconds}ms');
  debugPrint('🎯 [PERF] Total main() time: ${DateTime.now().difference(startTime).inMilliseconds}ms');

  // Analytics will initialize lazily when first used - no Firebase blocking!
  debugPrint('✅ [PERF] Firebase deferred to lazy initialization');
}

VartalapChatClientFlutter _createClient() {
  // Create appropriate client based on MOCK_MODE flag
  final tokenManager = SecureStorageTokenManager();
  final chatClient = AppConfig.isMockMode
      ? MockVartalapChatClient(tokenManager: tokenManager)
      : VartalapChatClient(
          apiKey: AppConfig.apiKey,
          apiBaseUrl: AppConfig.apiUrl,
          wsUrl: AppConfig.wsUrl,
          tokenManager: tokenManager,
        );

  // Create appropriate OTP provider based on MOCK_MODE flag
  final otpProvider = AppConfig.isMockMode
      ? MockOTPProvider()
      : FirebaseOTPProvider();

  final client = VartalapChatClientFlutter(
    apiKey: AppConfig.apiKey,
    apiBaseUrl: AppConfig.apiUrl,
    wsUrl: AppConfig.wsUrl,
    client: chatClient,
  );
  
  client.initAuth(otpProvider);

  if (AppConfig.isMockMode) {
    debugPrint('🎭 [MOCK] Running in MOCK MODE - no server required!');
  }

  return client;
}


/// Main App Widget with Unified Authentication
class VartalapApp extends StatefulWidget {
  final VartalapChatClientFlutter client;

  const VartalapApp({super.key, required this.client});

  @override
  State<VartalapApp> createState() => _VartalapAppState();
}

class _VartalapAppState extends State<VartalapApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  AuthState? _previousAuthState;

  @override
  void initState() {
    super.initState();
    _previousAuthState = widget.client.auth.state;
    // Listen to auth state changes
    widget.client.auth.addListener(_onAuthStateChanged);
  }

  void _onAuthStateChanged() {
    final currentState = widget.client.auth.state;

    // Detect logout: transition from authenticated to unauthenticated
    if (_previousAuthState == AuthState.authenticated &&
        currentState == AuthState.unauthenticated) {
      debugPrint('[AUTH] Detected logout, clearing navigation stack');
      // Clear all routes and return to home (login screen)
      _navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/',
        (route) => false,
      );
    }

    _previousAuthState = currentState;
  }

  @override
  void dispose() {
    widget.client.auth.removeListener(_onAuthStateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Provider<VartalapChatClientFlutter>(
      create: (_) => widget.client,
      child: ChangeNotifierProvider<AuthRepository>.value(
        value: widget.client.auth,
        child: Consumer<AuthRepository>(
          builder: (context, auth, _) {
            Widget app = MaterialApp(
              navigatorKey: _navigatorKey,
              title: AppConfig.packageInfo.appName,
              debugShowCheckedModeBanner: false,
              themeMode: VartalapTheme.themeMode,
              theme: VartalapTheme.lightTheme.appTheme,
              darkTheme: VartalapTheme.darkTheme.appTheme,
              onGenerateRoute: _routes,
              home: _buildHomeScreen(auth),
              builder: (context, child) {
                final content = child ?? const SizedBox.shrink();
                if (!AppConfig.isMockMode) return content;
                return MockDeveloperMenu(
                  child: content,
                  navigatorKey: _navigatorKey,
                );
              },
            );
            return app;
          },
        ),
      ),
    );
  }

  /// Build the appropriate home screen based on authentication state
  Widget _buildHomeScreen(AuthRepository auth) {
    switch (auth.state) {
      case AuthState.authenticated:
        return StartupScreen();
      case AuthState.error:
        return IntroductionScreen(); // Show login on error
      case AuthState.otpSent:
      case AuthState.verifyingOTP:
        return VerifyOtpWidget();
      case AuthState.unauthenticated:
      case AuthState.sendingOTP:
        return IntroductionScreen();
    }
  }

  /// Route factory for the application
  Route<dynamic>? _routes(RouteSettings settings) {
    return MaterialPageRoute(
      settings: settings,
      builder: (BuildContext context) {
        final client = Provider.of<VartalapChatClientFlutter>(context, listen: false);
        final auth = client.auth;

        // Define protected routes that require authentication
        final protectedRoutes = {'/chats', '/chat', '/new-chat', '/new-group', '/create-group', '/profile'};

        // Check if route requires authentication
        if (protectedRoutes.contains(settings.name) && !auth.isAuthenticated) {
          debugPrint('[ROUTE] Attempted to access ${settings.name} without authentication, redirecting to login');
          return IntroductionScreen();
        }

        Widget widget;
        switch (settings.name) {
          case '/':
            widget = StartupScreen();
            break;
          case '/verify-otp':
            widget = VerifyOtpWidget();
            break;
          case '/profile':
            widget = _buildAuthenticatedScreen(
              client: client,
              child: const ProfileScreen(),
            );
            break;
          case '/chats':
            // Wrap authenticated screens with CurrentUser provider
            widget = _buildAuthenticatedScreen(
              client: client,
              child: const Chats(),
            );
            break;
          case '/chat':
            widget = ChatScreen(settings.arguments as ChatClient);
            break;
          case '/new-chat':
            widget = _buildAuthenticatedScreen(
              client: client,
              child: NewChatScreen(),
            );
            break;
          case '/new-group':
            widget = _buildAuthenticatedScreen(
              client: client,
              child: SelectGroupMemberScreen(),
            );
            break;
          case '/create-group':
            widget = _buildAuthenticatedScreen(
              client: client,
              child: CreateGroup(settings.arguments as List<Contact>),
            );
            break;
          default:
            // Default route also wraps with authentication check
            if (auth.isAuthenticated) {
              widget = _buildAuthenticatedScreen(
                client: client,
                child: const Chats(),
              );
            } else {
              widget = IntroductionScreen();
            }
        }
        return widget;
      },
    );
  }

  /// Build authenticated screen with CurrentUser provider
  Widget _buildAuthenticatedScreen({
    required VartalapChatClientFlutter client,
    required Widget child,
  }) {
    // Wrap with VartalapClientManager and CurrentUser provider
    return VartalapClientManager(
      client: client,
      child: _CurrentUserProvider(
        client: client,
        child: child,
      ),
    );
  }
}

/// Provides CurrentUser Contact from authClient's profile
class _CurrentUserProvider extends StatefulWidget {
  final VartalapChatClientFlutter client;
  final Widget child;

  const _CurrentUserProvider({
    required this.client,
    required this.child,
  });

  @override
  State<_CurrentUserProvider> createState() => _CurrentUserProviderState();
}

class _CurrentUserProviderState extends State<_CurrentUserProvider> {
  Contact? _currentContact;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    try {
      final profile = widget.client.auth.currentUser;
      if (profile == null) {
        debugPrint('[CurrentUser] No profile available');
        setState(() => _isLoading = false);
        return;
      }

      // Fetch the Contact for the logged-in user using their userId (phone number)
      final contacts = await widget.client
          .getContacts(filter: ContactFilter(phone: profile.userId))
          .get();

      if (contacts.isNotEmpty) {
        setState(() {
          _currentContact = contacts.first;
          _isLoading = false;
        });
        debugPrint('[CurrentUser] Loaded contact: ${_currentContact?.username}');
      } else {
        debugPrint('[CurrentUser] No contact found for userId: ${profile.userId}');
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('[CurrentUser] Error loading current user: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return CurrentUser(
      user: _currentContact,
      child: widget.child,
    );
  }
}
