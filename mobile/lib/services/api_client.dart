import 'package:dio/dio.dart';

import '../config/app_config.dart';
import 'http/configure_adapter.dart';

/// Erreur lisible par l'utilisateur.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;

  /// Traduit une erreur Dio (Fineract ou Keycloak) en message français.
  static ApiException from(Object error) {
    if (error is ApiException) return error;
    if (error is DioException) {
      final code = error.response?.statusCode;
      final data = error.response?.data;
      String? msg;
      if (data is Map) {
        final errors = data['errors'];
        if (errors is List && errors.isNotEmpty && errors.first is Map) {
          msg = (errors.first as Map)['defaultUserMessage'] as String?;
        }
        msg ??= data['defaultUserMessage'] as String?;
        msg ??= _keycloak(data['error'] as String?, data['error_description'] as String?);
      }
      if (msg == null) {
        switch (error.type) {
          case DioExceptionType.connectionTimeout:
          case DioExceptionType.receiveTimeout:
          case DioExceptionType.sendTimeout:
            msg = 'Le serveur ne répond pas. Réessayez dans un instant.';
          case DioExceptionType.connectionError:
            msg = 'Connexion impossible. Vérifiez votre accès Internet.';
          case DioExceptionType.badCertificate:
            msg = 'Certificat du serveur invalide.';
          default:
            msg = switch (code) {
              401 => 'Session expirée. Reconnectez-vous.',
              403 => "Vous n'êtes pas autorisé à effectuer cette opération.",
              404 => 'Élément introuvable.',
              _ => 'Une erreur est survenue (${code ?? 'réseau'}).',
            };
        }
      }
      return ApiException(msg, statusCode: code);
    }
    return ApiException(error.toString());
  }

  static String? _keycloak(String? error, String? description) {
    if (error == null) return null;
    final d = (description ?? '').toLowerCase();
    if (d.contains('not fully set up')) {
      return "Votre compte doit être finalisé (activation de l'authentificateur). "
          'Ouvrez votre espace sécurité Keycloak pour configurer le code OTP.';
    }
    if (d.contains('disabled')) return 'Ce compte est désactivé. Contactez votre agence.';
    if (d.contains('temporarily')) return 'Compte temporairement bloqué après plusieurs échecs.';
    if (error == 'invalid_grant') return 'Identifiant, mot de passe ou code OTP incorrect.';
    return description ?? error;
  }
}

/// Fournit les en-têtes d'authentification avant chaque requête.
typedef AuthHeadersProvider = Future<Map<String, String>> Function();

/// Client HTTP pour l'API Apache Fineract.
class FineractApi {
  FineractApi(this.config, {AuthHeadersProvider? authHeaders})
      : dio = Dio(
          BaseOptions(
            baseUrl: config.fineractUrl,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
            headers: {
              'Fineract-Platform-TenantId': config.tenant,
              'Accept': 'application/json',
            },
            contentType: Headers.jsonContentType,
          ),
        ) {
    configureAdapter(
      dio,
      allowSelfSigned: const bool.fromEnvironment('ALLOW_SELF_SIGNED', defaultValue: false),
    );
    if (authHeaders != null) {
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            try {
              options.headers.addAll(await authHeaders());
              handler.next(options);
            } catch (e) {
              handler.reject(DioException(requestOptions: options, error: e));
            }
          },
        ),
      );
    }
  }

  final AppConfig config;
  final Dio dio;

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) => _wrap(() => dio.get(path, queryParameters: query));

  Future<dynamic> post(String path, {Object? body, Map<String, dynamic>? query}) =>
      _wrap(() => dio.post(path, data: body ?? const {}, queryParameters: query));

  Future<dynamic> put(String path, {Object? body, Map<String, dynamic>? query}) =>
      _wrap(() => dio.put(path, data: body ?? const {}, queryParameters: query));

  Future<dynamic> _wrap(Future<Response<dynamic>> Function() call) async {
    try {
      final res = await call();
      return res.data;
    } on DioException catch (e) {
      if (e.error is ApiException) throw e.error as ApiException;
      throw ApiException.from(e);
    }
  }
}
