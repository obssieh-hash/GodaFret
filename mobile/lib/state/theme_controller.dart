import 'package:flutter/material.dart';

class ThemeController extends ChangeNotifier {
  ThemeMode mode = ThemeMode.system;

  void set(ThemeMode value) {
    mode = value;
    notifyListeners();
  }
}
