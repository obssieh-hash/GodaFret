import 'package:flutter/services.dart';

/// État de sécurité de l'appareil, fourni par le code natif Android
/// (`MainActivity.kt`). Sur les autres plateformes, valeurs neutres.
class DeviceStatus {
  const DeviceStatus({
    this.rooted = false,
    this.emulator = false,
    this.developerMode = false,
    this.screenProtected = false,
    this.known = false,
  });

  /// Appareil « rooté » : les protections du système ne sont plus garanties.
  final bool rooted;
  final bool emulator;
  final bool developerMode;

  /// Captures et enregistrements d'écran bloqués (FLAG_SECURE).
  final bool screenProtected;

  /// `false` si la vérification native n'est pas disponible.
  final bool known;

  bool get compromised => rooted;
}

class DeviceSecurity {
  static const _channel = MethodChannel('com.goldenbridge.pay/security');

  static Future<DeviceStatus> check() async {
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>('deviceStatus');
      if (m == null) return const DeviceStatus();
      return DeviceStatus(
        rooted: m['rooted'] == true,
        emulator: m['emulator'] == true,
        developerMode: m['developerMode'] == true,
        screenProtected: m['screenProtected'] == true,
        known: true,
      );
    } on MissingPluginException {
      return const DeviceStatus();
    } on PlatformException {
      return const DeviceStatus();
    }
  }
}
