import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'config/app_config.dart';
import 'core/theme.dart';
import 'services/api_client.dart';
import 'services/auth/auth_service.dart';
import 'services/auth/demo_auth.dart';
import 'services/auth/fineract_auth.dart';
import 'services/auth/keycloak_auth.dart';
import 'services/bank_repository.dart';
import 'services/demo_repository.dart';
import 'services/fineract_repository.dart';
import 'services/pin_service.dart';
import 'services/secure_store.dart';
import 'state/bank_controller.dart';
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

  final config = AppConfig.fromEnvironment();
  final store = SecureStore();
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
  session.init();

  runApp(GodaFretApp(session: session, bank: bank));
}

class GodaFretApp extends StatelessWidget {
  const GodaFretApp({super.key, required this.session, required this.bank});

  final SessionController session;
  final BankController bank;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: session),
        ChangeNotifierProvider.value(value: bank),
        ChangeNotifierProvider(create: (_) => ThemeController()),
      ],
      child: Consumer<ThemeController>(
        builder: (context, theme, _) => MaterialApp(
          title: 'GodaFret Banque',
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final session = context.read<SessionController>();
    if (state == AppLifecycleState.paused) session.onPaused();
    if (state == AppLifecycleState.resumed) session.onResumed();
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
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: KeyedSubtree(key: ValueKey(stage), child: screen),
    );
  }
}
