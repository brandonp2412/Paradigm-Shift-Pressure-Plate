import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'logging.dart';
import 'services/auth_service.dart';
import 'services/background_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installTalkerErrorHandlers();
  talker.info('Starting FloorSense');
  await BackgroundWatch.init();
  await BackgroundWatch.syncRegistration();
  runApp(const FloorSenseApp());
}

/// App-wide navigator handle so the session layer can route to login from
/// outside the widget tree (e.g. a background reconnect that gives up).
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class FloorSenseApp extends StatefulWidget {
  const FloorSenseApp({super.key});

  @override
  State<FloorSenseApp> createState() => _FloorSenseAppState();
}

class _FloorSenseAppState extends State<FloorSenseApp> {
  late final AuthService _auth;
  AuthState _lastAuthState = AuthState.initial;

  @override
  void initState() {
    super.initState();
    _auth = AuthService();
    _auth.addListener(_routeOnSessionLoss);
  }

  /// Route to login when the session is *cleared* — a manual logout or the
  /// reconnect loop giving up on a permanently-rejected credential.
  ///
  /// We must key off the *transition into* [AuthState.initial], not the value
  /// itself: the state is also `initial` during normal startup before the first
  /// login completes, and the socket's status-change notifications fire this
  /// listener while still `initial` — keying off the value alone would wrongly
  /// bounce a healthy, just-restored session to the login screen.
  void _routeOnSessionLoss() {
    final s = _auth.state;
    final sessionLost =
        s == AuthState.initial && _lastAuthState != AuthState.initial;
    _lastAuthState = s;
    if (!sessionLost) return;

    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _auth.removeListener(_routeOnSessionLoss);
    _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AuthService>.value(
      value: _auth,
      child: MaterialApp(
        title: 'FloorSense',
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: const _SplashScreen(),
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: Colors.indigo,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: colorScheme.surfaceTint,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _SplashScreen extends StatefulWidget {
  const _SplashScreen();

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen> {
  @override
  void initState() {
    super.initState();
    _restoreOrLogin();
  }

  Future<void> _restoreOrLogin() async {
    final auth = context.read<AuthService>();
    final restored = await auth.tryRestoreSession();
    if (!mounted) return;
    if (restored) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
    } else {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
