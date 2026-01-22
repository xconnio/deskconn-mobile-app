class Validators {
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
    if (v.length < 8) return 'Password too short';
    if (!RegExp(r'[A-Z]').hasMatch(v)) return 'Add uppercase letter';
    if (!RegExp(r'[a-z]').hasMatch(v)) return 'Add lowercase letter';
    if (!RegExp(r'[0-9]').hasMatch(v)) return 'Add number';
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(v)) {
      return 'Add special character';
    }
    return null;
  }

  static String? otp(String v) {
    if (v.trim().isEmpty) return 'OTP required';
    if (v.trim().length < 4) return 'Invalid OTP';
    return null;
  }
}
