import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

/// Mobile : accepte un certificat auto-signé UNIQUEMENT en mode debug
/// (serveur Fineract de développement sur https://…:8443).
void configureAdapter(Dio dio, {required bool allowSelfSigned}) {
  if (!allowSelfSigned || kReleaseMode) return;
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () => HttpClient()..badCertificateCallback = (cert, host, port) => true,
  );
}
