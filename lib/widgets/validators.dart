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

  static String? name(String v, {String label = 'Name'}) {
    if (v.trim().isEmpty) return '$label is required';
    if (v.trim().length < 2) return '$label is too short';
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
    final value = v.trim();
    if (value.isEmpty) return 'OTP required';
    if (!RegExp(r'^\d{6}$').hasMatch(value)) return 'Enter the 6-digit code';
    return null;
  }
}
