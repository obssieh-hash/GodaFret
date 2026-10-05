import '../api_client.dart';
import '../secure_store.dart';
import 'auth_service.dart';

/// Mode démonstration : n'importe quel identifiant, code OTP `123456`.
class DemoAuthService implements AuthService {
  DemoAuthService(this.store);

  static const demoOtp = '123456';

  final SecureStore store;
  String? _username;
  bool _pending = false;
  bool _connected = false;

  @override
  bool get canResendOtp => true;

  @override
  String get mfaLabel => 'Code OTP de démonstration';

  @override
  String? get username => _username;

  @override
  String? get fullName => null;

  @override
  int? get clientIdHint => 1;

  @override
  Future<LoginResult> login(String username, String password) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (username.trim().isEmpty || password.isEmpty) {
      throw ApiException('Identifiant ou mot de passe incorrect.');
    }
    _username = username.trim();
    _pending = true;
    return const LoginResult.otp(otpHint: 'Mode démo : saisissez le code 123456.');
  }

  @override
  Future<String?> resendOtp() async => 'Mode démo : le code est 123456.';

  @override
  Future<void> verifyOtp(String code) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!_pending || code != demoOtp) throw ApiException('Code incorrect.');
    _pending = false;
    _connected = true;
    await store.write(SecureStore.refreshToken, 'demo');
    await store.write(SecureStore.username, _username);
  }

  @override
  Future<bool> restore() async {
    final token = await store.read(SecureStore.refreshToken);
    _username = await store.read(SecureStore.username);
    _connected = token == 'demo';
    return _connected;
  }

  @override
  Future<Map<String, String>> authHeaders() async => const {};

  @override
  Future<void> logout() async {
    _connected = false;
    await store.clearSession();
  }
}
