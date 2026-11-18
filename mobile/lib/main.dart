import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'config/app_config.dart';
import 'core/brand.dart';
import 'core/theme.dart';
import 'services/api_client.dart';
import 'services/auth/auth_service.dart';
import 'services/auth/demo_auth.dart';
import 'services/auth/fineract_auth.dart';
import 'services/auth/keycloak_auth.dart';
import 'services/bank_repository.dart';
import 'services/demo_repository.dart';
import 'services/fineract_repository.dart';
import 'services/market_service.dart';
import 'services/pin_service.dart';
import 'services/secure_store.dart';
import 'services/server_settings.dart';
import 'state/bank_controller.dart';
import 'state/market_controller.dart';
import 'state/session_controller.dart';
import 'state/theme_controller.dart';
import 'ui/screens/auth/auth_scaffold.dart';
import 'ui/screens/auth/login_screen.dart';
import 'ui/screens/auth/otp_screen.dart';
import 'ui/screens/auth/pin_screens.dart';
import 'ui/screens/home/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'fr_FR';
  await initializeDateFormatting('fr_FR');
  runApp(const AppRoot());
}

/// Construit les services selon la configuration (compilation + serveur choisi
/// dans l'application) et les reconstruit quand l'utilisateur change de serveur.
class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  static AppRootState of(BuildContext context) => context.findAncestorStateOfType<AppRootState>()!;

  @override
  State<AppRoot> createState() => AppRootState();
}

class AppRootState extends State<AppRoot> {
  final store = SecureStore();
  late final settings = ServerSettings(store);
  final theme = ThemeController();
  late final markets = MarketController(MarketService(), store: store);
  SessionController? _session;
  BankController? _bank;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    restart();
  }

  /// (Re)crée l'authentification, l'accès aux données et la session.
  Future<void> restart() async {
    final config = await settings.apply(AppConfig.fromEnvironment());
    final AuthService auth = switch (config.authMode) {
      AuthMode.demo => DemoAuthService(store),
      AuthMode.keycloak => KeycloakAuthService(config, store),
      AuthMode.fineract => FineractAuthService(config, store),
    };
    final BankRepository repo = config.isDemo
        ? DemoRepository()
        : FineractRepository(FineractApi(config, authHeaders: auth.authHeaders), auth);
    final session = SessionController(config: config, auth: auth, pin: PinService(store), store: store);
    final bank = BankController(repo, onUnauthorized: session.onUnauthorized);
    await session.init();
    if (!mounted) return;
    setState(() {
      _session = session;
      _bank = bank;
      _generation++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final bank = _bank;
    if (session == null || bank == null) {
      return const MaterialApp(debugShowCheckedModeBanner: false, home: AuthScaffold(child: Center(child: BrandLogo(size: 84))));
    }
    return GoldenBridgeApp(key: ValueKey(_generation), session: session, bank: bank, theme: theme, markets: markets);
  }
}

class GoldenBridgeApp extends StatelessWidget {
  const GoldenBridgeApp({super.key, required this.session, required this.bank, this.theme, this.markets});

  final SessionController session;
  final BankController bank;
  final ThemeController? theme;
  final MarketController? markets;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: session),
        ChangeNotifierProvider.value(value: bank),
        if (theme != null) ChangeNotifierProvider.value(value: theme!) else ChangeNotifierProvider(create: (_) => ThemeController()),
        if (markets != null)
          ChangeNotifierProvider.value(value: markets!)
        else
          ChangeNotifierProvider(create: (_) => MarketController(MarketService(live: false))),
      ],
      child: Consumer<ThemeController>(
        builder: (context, theme, _) => MaterialApp(
          title: Brand.app,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: theme.mode,
          locale: const Locale('fr', 'FR'),
          supportedLocales: const [Locale('fr', 'FR')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const SessionGate(),
        ),
      ),
    );
  }
}

/// Affiche l'écran correspondant à l'état de la session et verrouille
/// l'application lorsqu'elle reste trop longtemps en arrière-plan.
class SessionGate extends StatefulWidget {
  const SessionGate({super.key});

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> with WidgetsBindingObserver {
  SessionStage? _previous;
  Timer? _idle;

  /// Masque le contenu quand l'application passe en arrière-plan
  /// (aperçu du multitâche, partage d'écran).
  bool _obscured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _idle?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final session = context.read<SessionController>();
    if (state == AppLifecycleState.paused) session.onPaused();
    if (state == AppLifecycleState.resumed) session.onResumed();
    final obscure = state != AppLifecycleState.resumed;
    if (obscure != _obscured) setState(() => _obscured = obscure);
  }

  /// Verrouillage après une période sans aucune interaction, application ouverte.
  void _touch() {
    final session = context.read<SessionController>();
    _idle?.cancel();
    if (session.stage != SessionStage.unlocked) return;
    _idle = Timer(session.config.idleLock, session.lockNow);
  }

  @override
  Widget build(BuildContext context) {
    final stage = context.select<SessionController, SessionStage>((s) => s.stage);
    if (stage != _previous) {
      final previous = _previous;
      _previous = stage;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final bank = context.read<BankController>();
        // Ferme les écrans ouverts au-dessus du tableau de bord.
        if (stage != SessionStage.unlocked) Navigator.of(context).popUntil((r) => r.isFirst);
        if (stage == SessionStage.loggedOut) bank.reset();
        if (stage == SessionStage.unlocked && (previous != SessionStage.locked || !bank.loaded)) bank.refresh();
        _touch();
      });
    }

    final Widget screen = switch (stage) {
      SessionStage.booting => const AuthScaffold(child: Center(child: BrandLogo(size: 84))),
      SessionStage.loggedOut => const LoginScreen(),
      SessionStage.otp => const OtpScreen(),
      SessionStage.pinSetup => const PinSetupScreen(),
      SessionStage.locked => const PinLockScreen(),
      SessionStage.unlocked => const HomeShell(),
    };
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _touch(),
      child: Stack(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: KeyedSubtree(key: ValueKey(stage), child: screen),
          ),
          if (_obscured && stage == SessionStage.unlocked)
            const Positioned.fill(child: AuthScaffold(child: Center(child: BrandLogo(size: 84)))),
        ],
      ),
    );
  }
}
