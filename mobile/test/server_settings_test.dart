import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:godafret_bank/main.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

void main() {
  setUpAll(() async {
    Intl.defaultLocale = 'fr_FR';
    await initializeDateFormatting('fr_FR');
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  testWidgets("l'adresse du serveur saisie dans l'app est enregistrée et appliquée", (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    FlutterSecureStorage.setMockInitialValues({});

    await tester.pumpWidget(const AppRoot());
    await settle(tester);
    expect(find.text('Mode démo · OTP 123456'), findsOneWidget);

    await tester.tap(find.byTooltip('Serveur'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mon serveur'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Adresse du serveur'), '192.168.1.50');
    await tester.tap(find.text('Avancé'));
    await tester.pumpAndSettle();
    expect(find.text('http://192.168.1.50:8081'), findsOneWidget);
    expect(find.text('http://192.168.1.50:8082/fineract-provider/api/v1'), findsOneWidget);
    await tester.tap(find.text('Enregistrer'));
    await settle(tester);

    expect(find.text('Serveur 192.168.1.50 · MFA'), findsOneWidget);
    final stored = await const FlutterSecureStorage().readAll();
    expect(stored['server_mode'], 'keycloak');
    expect(stored['server_keycloak_url'], 'http://192.168.1.50:8081');
  });
}
