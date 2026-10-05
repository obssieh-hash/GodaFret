import 'package:dio/dio.dart';

import '../../config/app_config.dart';
import '../api_client.dart';
import '../secure_store.dart';
import 'auth_service.dart';

/// Authentification native Fineract (`POST /authentication`) avec la
/// double authentification de Fineract (`/twofactor`, activée par
/// `FINERACT_SECURITY_2FA_ENABLED=true`). Le code est envoyé par e-mail ou SMS.
class FineractAuthService implements AuthService {
  FineractAuthService(this.config, this.store) : _api = FineractApi(config);

  final AppConfig config;
  final SecureStore store;
  final FineractApi _api;

  String? _basicKey;
  String? _tfaToken;
  String? _username;
  String? _deliveryMethod;

  @override
  bool get canResendOtp => true;

  @override
  String get mfaLabel => 'Code à usage unique par e-mail / SMS';

  @override
  String? get username => _username;

  @override
  String? get fullName => null;

  @override
  int? get clientIdHint => null;

  @override
  Future<LoginResult> login(String username, String password) async {
    final data = await _api.post(
      '/authentication',
      body: {'username': username, 'password': password},
    ) as Map;
    if (data['authenticated'] != true) {
      throw ApiException('Identifiant ou mot de passe incorrect.', statusCode: 401);
    }
    _username = username;
    _basicKey = data['base64EncodedAuthenticationKey'] as String?;
    _tfaToken = null;
    final needs2fa = data['isTwoFactorAuthenticationRequired'] == true;
    if (!needs2fa) {
      await _persist();
      return const LoginResult.done();
    }
    final hint = await resendOtp();
    return LoginResult.otp(otpHint: hint);
  }

  @override
  Future<String?> resendOtp() async {
    final methods = await _api.dio
        .get<List<dynamic>>('/twofactor', options: _basicOptions())
        .then((r) => r.data ?? const []);
    if (methods.isEmpty) {
      throw ApiException("Aucun moyen d'envoi du code n'est configuré sur votre profil.");
    }
    final method = methods.first as Map;
    _deliveryMethod = method['name'] as String?;
    await _api.dio.post<dynamic>(
      '/twofactor',
      queryParameters: {'deliveryMethod': _deliveryMethod},
      options: _basicOptions(),
    );
    return 'Code envoyé par ${_deliveryMethod == 'sms' ? 'SMS' : 'e-mail'} à ${method['target'] ?? 'votre contact'}.';
  }

  @override
  Future<void> verifyOtp(String code) async {
    try {
      final res = await _api.dio.post<Map<String, dynamic>>(
        '/twofactor/validate',
        queryParameters: {'token': code},
        options: _basicOptions(),
      );
      _tfaToken = res.data?['token'] as String?;
    } catch (e) {
      throw ApiException.from(e);
    }
    await _persist();
  }

  @override
  Future<bool> restore() async {
    _basicKey = await store.read(SecureStore.basicKey);
    _tfaToken = await store.read(SecureStore.tfaToken);
    _username = await store.read(SecureStore.username);
    // Si le jeton 2FA a expiré, le premier appel renverra 401 et l'application
    // repassera par l'écran de connexion complet.
    return _basicKey != null;
  }

  @override
  Future<Map<String, String>> authHeaders() async {
    if (_basicKey == null) throw ApiException('Non connecté.', statusCode: 401);
    return {
      'Authorization': 'Basic $_basicKey',
      'Fineract-Platform-TFA-Token': ?_tfaToken,
    };
  }

  @override
  Future<void> logout() async {
    if (_tfaToken != null) {
      try {
        await _api.dio.post<dynamic>(
          '/twofactor/invalidate',
          data: {'token': _tfaToken},
          options: _basicOptions(withTfa: true),
        );
      } catch (_) {}
    }
    _basicKey = null;
    _tfaToken = null;
    await store.clearSession();
  }

  Future<void> _persist() async {
    await store.write(SecureStore.basicKey, _basicKey);
    await store.write(SecureStore.tfaToken, _tfaToken);
    await store.write(SecureStore.username, _username);
  }

  Options _basicOptions({bool withTfa = false}) => Options(
        headers: {
          'Authorization': 'Basic $_basicKey',
          if (withTfa && _tfaToken != null) 'Fineract-Platform-TFA-Token': _tfaToken!,
        },
      );
}
