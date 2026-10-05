import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:godafret_bank/config/app_config.dart';
import 'package:godafret_bank/main.dart';
import 'package:godafret_bank/services/auth/demo_auth.dart';
import 'package:godafret_bank/services/demo_repository.dart';
import 'package:godafret_bank/services/pin_service.dart';
import 'package:godafret_bank/services/secure_store.dart';
import 'package:godafret_bank/state/bank_controller.dart';
import 'package:godafret_bank/state/session_controller.dart';
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

    await tester.pumpWidget(GodaFretApp(session: session, bank: bank));
    await tester.pumpAndSettle();

    // 🔐 Connexion
    expect(find.text('Bienvenue'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), 'camille');
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

    // 📊 Tableau de bord
    expect(session.stage, SessionStage.unlocked);
    expect(find.textContaining('Camille'), findsWidgets);
    expect(find.text('Solde total'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Tableau de bord'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Tableau de bord'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Transfert'), -300, scrollable: find.byType(Scrollable).first);
    final before = bank.totalBalance;

    // 💸 Transfert interne vers le livret
    await tester.tap(find.text('Transfert'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Livret Épargne+').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '25');
    await tester.tap(find.text('Transférer'));
    await tester.pumpAndSettle();
    expect(find.text('Confirmer le transfert'), findsOneWidget);
    await typePin(tester, '274913');
    await settle(tester);
    expect(find.text('Transfert envoyé'), findsOneWidget);
    expect(bank.totalBalance, closeTo(before, 0.001)); // transfert entre mes comptes
    expect(bank.savings.firstWhere((a) => a.id == 102).balance, greaterThan(0));
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
    for (final tab in ['Comptes', 'Prêts', 'Historique', 'Profil']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
    }
    expect(find.text('Informations personnelles'), findsOneWidget);
  });
}
