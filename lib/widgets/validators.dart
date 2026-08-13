class Validators {
  static const passwordRequirement =
      'Password should be at least 8 characters and include uppercase, lowercase, number, and special character.';

  static String? required(String v, {String label = 'Field'}) {
    if (v.trim().isEmpty) return '$label is required';
    return null;
  }

  static String? email(String v) {
    if (v.trim().isEmpty) return 'Email is required';
    final r = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!r.hasMatch(v.trim())) return 'Invalid email';
    return null;
  }

  static String? name(String v) {
    if (v.trim().isEmpty) return 'Name is required';
    if (v.trim().length < 2) return 'Name is too short';
    return null;
  }

  static String? password(String v) {
    if (v.isEmpty) return 'Password is required';

    if (!isPasswordValid(v)) return passwordRequirement;
    return null;
  }

  static bool isPasswordValid(String v) {
    return v.length >= 8 &&
        RegExp(r'[A-Z]').hasMatch(v) &&
        RegExp(r'[a-z]').hasMatch(v) &&
        RegExp(r'[0-9]').hasMatch(v) &&
        RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(v);
  }

  static String? otp(String v) {
    if (v.trim().isEmpty) return 'OTP required';
    if (v.trim().length < 4) return 'Invalid OTP';
    return null;
  }
}
