/// Password rules — briefing §9.3 step 2: "minimum 10 characters, checked
/// against a common-password list, no composition rules." Deliberately no
/// "must contain a symbol" style requirements — those are exactly what the
/// brief says NOT to add.
const int kMinPasswordLength = 10;

enum PasswordStrength { tooShort, common, weak, fair, good, strong }

/// A short, well-known list of the passwords most likely to appear in a
/// breach dictionary. This is not a substitute for a real breach-corpus
/// check (e.g. HaveIBeenPwned's k-anonymity API) — that's a reasonable
/// upgrade once there's a backend endpoint willing to make that outbound
/// call — but it catches the overwhelming majority of trivially bad
/// choices for zero infrastructure cost.
const Set<String> _commonPasswords = <String>{
  '123456789', '1234567890', 'password1', 'password123', 'qwertyuiop',
  'letmein123', 'welcome123', 'iloveyou1', 'football1', 'baseball1',
  'dragon123', 'monkey123', 'trustno1', 'sunshine1', 'princess1',
  'superman1', 'starwars1', 'whatever1', '1qaz2wsx3edc', 'zxcvbnm123',
  'abc123456', 'passw0rd1', 'p@ssw0rd1', 'p@ssword1', 'changeme1',
  'letmein00', 'admin12345', 'administrator', 'qwerty12345',
  'aaaaaaaaaa', '0123456789', '9876543210', 'nicolejones', 'michaeljordan',
  'password1234', 'correcthorsebatterystaple',
};

bool _isCommonPassword(String password) => _commonPasswords.contains(password.toLowerCase());

PasswordStrength evaluatePasswordStrength(String password) {
  if (password.length < kMinPasswordLength) return PasswordStrength.tooShort;
  if (_isCommonPassword(password)) return PasswordStrength.common;

  final hasLower = password.contains(RegExp('[a-z]'));
  final hasUpper = password.contains(RegExp('[A-Z]'));
  final hasDigit = password.contains(RegExp(r'[0-9]'));
  final hasSymbol = password.contains(RegExp(r'[^a-zA-Z0-9]'));
  final varietyScore = [hasLower, hasUpper, hasDigit, hasSymbol].where((v) => v).length;

  // Informational only — never blocks submission (§9.3: "no composition rules").
  if (password.length >= 16 && varietyScore >= 3) return PasswordStrength.strong;
  if (password.length >= 14 || varietyScore >= 3) return PasswordStrength.good;
  if (password.length >= 12 || varietyScore >= 2) return PasswordStrength.fair;
  return PasswordStrength.weak;
}

/// The only hard gate: long enough, and not a known-common password.
/// Everything above that is shown as a strength meter, never enforced.
bool isPasswordAcceptable(String password) {
  final strength = evaluatePasswordStrength(password);
  return strength != PasswordStrength.tooShort && strength != PasswordStrength.common;
}

String passwordStrengthLabel(PasswordStrength strength) => switch (strength) {
      PasswordStrength.tooShort => 'Too short — at least $kMinPasswordLength characters',
      PasswordStrength.common => 'That password is too easy to guess',
      PasswordStrength.weak => 'Weak',
      PasswordStrength.fair => 'Fair',
      PasswordStrength.good => 'Good',
      PasswordStrength.strong => 'Strong',
    };
