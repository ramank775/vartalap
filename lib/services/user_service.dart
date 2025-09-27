import 'package:vartalap/services/auth_service.dart';

class UserService {
  static final AuthService _authService = AuthService.instance;

  static Future<bool> sendOTP(String phoneNumber) {
    return _authService.sendOtp(phoneNumber);
  }

  static Future<bool> authenicate(String otp) async {
    AuthResponse result = await _authService.verify(otp);
    return result.status;
  }

  static Future<bool> isAuth() {
    return Future<bool>(() => _authService.isLoggedIn());
  }
}
