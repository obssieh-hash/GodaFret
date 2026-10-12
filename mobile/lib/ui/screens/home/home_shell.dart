import 'package:flutter/material.dart';

import '../accounts/history_screen.dart';
import '../loans/loans_screen.dart';
import 'dashboard_screen.dart';
import 'payments_screen.dart';

/// Navigation principale : Accueil, Paiements, Prêts, Historique.
/// Le profil s'ouvre depuis l'avatar en haut de l'accueil.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  static HomeShellState? of(BuildContext context) => context.findAncestorStateOfType<HomeShellState>();

  @override
  State<HomeShell> createState() => HomeShellState();
}

class HomeShellState extends State<HomeShell> {
  int _index = 0;

  void go(int index) => setState(() => _index = index);

  static const tabHome = 0;
  static const tabPayments = 1;
  static const tabLoans = 2;
  static const tabHistory = 3;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          DashboardScreen(),
          PaymentsScreen(),
          LoansScreen(),
          HistoryScreen(),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: go,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Accueil'),
            NavigationDestination(icon: Icon(Icons.swap_horiz_rounded), label: 'Paiements'),
            NavigationDestination(
              icon: Icon(Icons.account_balance_outlined),
              selectedIcon: Icon(Icons.account_balance_rounded),
              label: 'Prêts',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long_rounded),
              label: 'Historique',
            ),
          ],
        ),
      ),
    );
  }
}

Future<T?> push<T>(BuildContext context, Widget screen) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => screen));
