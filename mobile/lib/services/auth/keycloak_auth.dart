import 'dart:convert';

import 'package:dio/dio.dart';

import '../../config/app_config.dart';
import '../api_client.dart';
import '../http/configure_adapter.dart';
import '../secure_store.dart';
import 'auth_service.dart';

/// Authentification Keycloak (OpenID Connect) avec MFA TOTP.
///
/// L'application affiche ses propres écrans (identifiants puis code OTP) et
/// échange ces informations contre un jeton via le flux « Direct Access
/// Grant » du client public `godafret-mobile`, dont le flux est configuré
/// avec l'étape « OTP » obligatoire (voir `infra/keycloak/godafret-realm.json`).
/// Le jeton d'accès est ensuite envoyé à Fineract (OIDC Federation).
class KeycloakAuthService implements AuthService {
  KeycloakAuthService(this.config, this.store, {Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 15))) {
    configureAdapter(
      _dio,
      allowSelfSigned: const bool.fromEnvironment('ALLOW_SELF_SIGNED', defaultValue: false),
    );
  }

  final AppConfig config;
  final SecureStore store;
  final Dio _dio;

  String? _pendingUser;
  String? _pendingPassword;
  String? _accessToken;
  String? _refreshToken;
  DateTime _expiresAt = DateTime.fromMillisecondsSinceEpoch(0);
  Map<String, dynamic> _claims = const {};
  Future<void>? _refreshing;

  @override
  bool get canResendOtp => false;

  @override
  String get mfaLabel => 'Application d\'authentification (TOTP)';

  @override
  String? get username => _claims['preferred_username'] as String? ?? _pendingUser;

  @override
  String? get fullName => _claims['name'] as String?;

  @override
  int? get clientIdHint {
    final v = _claims['fineract_client_id'];
    if (v is int) return v;
    return int.tryParse('${v ?? ''}');
  }

  @override
  Future<LoginResult> login(String username, String password) async {
    if (config.mfaRequired) {
      // Le code OTP est envoyé avec les identifiants à l'étape suivante.
      _pendingUser = username;
      _pendingPassword = password;
      return const LoginResult.otp(otpHint: 'Saisissez le code à 6 chiffres affiché dans votre application d\'authentification.');
    }
    await _tokenRequest({'grant_type': 'password', 'username': username, 'password': password});
    return const LoginResult.done();
  }

  @override
  Future<void> verifyOtp(String code) async {
    if (_pendingUser == null || _pendingPassword == null) {
      throw ApiException('Session de connexion expirée, recommencez.');
    }
    await _tokenRequest({
      'grant_type': 'password',
      'username': _pendingUser,
      'password': _pendingPassword,
      // Keycloak lit « otp » (versions récentes) ou « totp » (anciennes).
      'otp': code,
      'totp': code,
    });
    _pendingPassword = null;
  }

  @override
  Future<String?> resendOtp() async => null;

  @override
  Future<bool> restore() async {
    final rt = await store.read(SecureStore.refreshToken);
    if (rt == null) return false;
    _refreshToken = rt;
    try {
      await _refresh();
      return true;
    } on ApiException {
      return false;
    }
  }

  @override
  Future<Map<String, String>> authHeaders() async {
    if (_accessToken == null) throw ApiException('Non connecté.', statusCode: 401);
    if (DateTime.now().isAfter(_expiresAt.subtract(const Duration(seconds: 30)))) {
      await (_refreshing ??= _refresh().whenComplete(() => _refreshing = null));
    }
    return {'Authorization': 'Bearer $_accessToken'};
  }

  @override
  Future<void> logout() async {
    final rt = _refreshToken;
    _accessToken = null;
    _refreshToken = null;
    _claims = const {};
    await store.clearSession();
    if (rt != null) {
      try {
        await _dio.post(
          config.keycloakLogoutUrl,
          data: {'client_id': config.keycloakClientId, 'refresh_token': rt},
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
      } catch (_) {
        // La session locale est déjà effacée.
      }
    }
  }

  Future<void> _refresh() => _tokenRequest({'grant_type': 'refresh_token', 'refresh_token': _refreshToken});

  Future<void> _tokenRequest(Map<String, dynamic> form) async {
    try {
      final res = await _dio.post(
        config.keycloakTokenUrl,
        data: {'client_id': config.keycloakClientId, 'scope': 'openid profile email', ...form},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final data = res.data as Map;
      _accessToken = data['access_token'] as String;
      _refreshToken = data['refresh_token'] as String?;
      _expiresAt = DateTime.now().add(Duration(seconds: (data['expires_in'] as num?)?.toInt() ?? 300));
      _claims = decodeJwt(_accessToken!);
      await store.write(SecureStore.refreshToken, _refreshToken);
      await store.write(SecureStore.username, username);
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  /// Décode la charge utile d'un JWT (sans vérifier la signature : c'est le
  /// rôle de Fineract ; on ne lit ici que des informations d'affichage).
  static Map<String, dynamic> decodeJwt(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return const {};
    try {
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      return jsonDecode(payload) as Map<String, dynamic>;
    } catch (_) {
      return const {};
    }
  }
}
