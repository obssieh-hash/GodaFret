import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_bridge_pay/config/app_config.dart';
import 'package:golden_bridge_pay/main.dart';
import 'package:golden_bridge_pay/services/auth/demo_auth.dart';
import 'package:golden_bridge_pay/services/demo_repository.dart';
import 'package:golden_bridge_pay/services/pin_service.dart';
import 'package:golden_bridge_pay/services/secure_store.dart';
import 'package:golden_bridge_pay/state/bank_controller.dart';
import 'package:golden_bridge_pay/state/session_controller.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

void main() {
  setUpAll(() async {
    Intl.defaultLocale = 'fr_FR';
    await initializeDateFormatting('fr_FR');
  });

  Future<void> settle(WidgetTester tester) async {
    // Les appels « réseau » de démo et le hachage du PIN sont asynchrones réels.
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  Future<void> typePin(WidgetTester tester, String pin) async {
    for (final d in pin.split('')) {
      await tester.tap(find.text(d).last);
      await tester.pump();
    }
  }

  testWidgets('connexion, OTP, création du PIN, tableau de bord et transfert', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    FlutterSecureStorage.setMockInitialValues({});

    final config = AppConfig.fromEnvironment();
    expect(config.authMode, AuthMode.demo);
    final store = SecureStore();
    final session = SessionController(config: config, auth: DemoAuthService(store), pin: PinService(store), store: store);
    final bank = BankController(DemoRepository(), onUnauthorized: session.onUnauthorized);
    await tester.runAsync(session.init);

    await tester.pumpWidget(GoldenBridgeApp(session: session, bank: bank));
    await tester.pumpAndSettle();

    // 🔐 Connexion
    expect(find.text('Envoyez, payez, recevez. Simplement.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), '77 10 10 10');
    await tester.enterText(find.byType(TextFormField).at(1), 'secret');
    await tester.tap(find.text('Se connecter'));
    await settle(tester);

    // 🔑 MFA / OTP
    expect(find.text('Vérification en 2 étapes'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '000000');
    await settle(tester);
    expect(find.text('Code incorrect.'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, DemoAuthService.demoOtp);
    await settle(tester);

    // PIN
    expect(find.text('Créez votre code PIN'), findsOneWidget);
    await typePin(tester, '274913');
    expect(find.text('Confirmez votre code'), findsOneWidget);
    await typePin(tester, '274913');
    await settle(tester);

    // 📊 Accueil : solde centré et actions rondes
    expect(session.stage, SessionStage.unlocked);
    expect(find.text('Comptes'), findsOneWidget);
    for (final action in ['Envoyer', 'Recevoir', 'Payer', 'Plus']) {
      expect(find.text(action), findsWidgets, reason: action);
    }
    final before = bank.savings.first.balance;

    // 📥 Recevoir : numéro + QR code
    await tester.tap(find.text('Recevoir'));
    await tester.pumpAndSettle();
    expect(find.text('Mon numéro'), findsOneWidget);
    expect(find.text('77 10 10 10'), findsOneWidget);
    Navigator.of(tester.element(find.text('Mon numéro'))).pop();
    await tester.pumpAndSettle();

    // 💸 Envoyer : numéro → pavé numérique → PIN → reçu
    await tester.tap(find.text('Envoyer'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '77 20 20 20');
    await tester.tap(find.text('Continuer'));
    await settle(tester);
    expect(find.text('Ahmed Hassan Moussa'), findsOneWidget);
    for (final d in ['2', '5', '0', '0']) {
      await tester.tap(find.text(d).last);
      await tester.pump();
    }
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.textContaining('Envoyer 2'), findsWidgets);
    await typePin(tester, '274913');
    await settle(tester);
    expect(find.text('Argent envoyé'), findsOneWidget);
    expect(bank.savings.first.balance, closeTo(before - 2500, 0.001));
    await tester.tap(find.text('Terminé'));
    await tester.pumpAndSettle();

    // 🔒 Verrouillage puis déverrouillage par PIN
    session.lockNow();
    await tester.pumpAndSettle();
    expect(find.text('Saisissez votre code PIN'), findsOneWidget);
    await typePin(tester, '274913');
    await settle(tester);
    expect(session.stage, SessionStage.unlocked);

    // Onglets
    await tester.tap(find.text('Paiements').last);
    await tester.pumpAndSettle();
    expect(find.text('Envoyer et payer'), findsOneWidget);
    await tester.tap(find.text('Prêts').last);
    await tester.pumpAndSettle();
    expect(find.text('Demander un prêt'), findsOneWidget);
    await tester.tap(find.text('Historique').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accueil').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('FH').first); // avatar (initiales) → profil
    await tester.pumpAndSettle();
    expect(find.text('Informations personnelles'), findsOneWidget);
  });
}
