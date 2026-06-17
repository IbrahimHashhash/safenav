class TextUtils {
  TextUtils._();

  static String normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool isSimilar(String a, String b, {double threshold = 0.3}) {
    final distance = levenshtein(a, b);
    final similarity = distance / (a.length > b.length ? a.length : b.length);
    return similarity <= threshold;
  }

  static double ratio(String a, String b) {
    final maxLen = a.length > b.length ? a.length : b.length;
    if (maxLen == 0) return 1;
    return 1 - levenshtein(a, b) / maxLen;
  }

  static double tokenSimilarity(String a, String b) {
    final edit = ratio(a, b);
    if (a.isEmpty || b.isEmpty) return edit;
    if (soundex(a) == soundex(b)) {
      return edit > 0.85 ? edit : 0.85;
    }
    return edit;
  }

  static String soundex(String s) {
    final letters = s.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
    if (letters.isEmpty) return '';

    String codeOf(String c) {
      if ('BFPV'.contains(c)) return '1';
      if ('CGJKQSXZ'.contains(c)) return '2';
      if ('DT'.contains(c)) return '3';
      if (c == 'L') return '4';
      if ('MN'.contains(c)) return '5';
      if (c == 'R') return '6';
      return '';
    }

    final buffer = StringBuffer(letters[0]);
    String prev = codeOf(letters[0]);
    for (int i = 1; i < letters.length && buffer.length < 4; i++) {
      final c = letters[i];
      final code = codeOf(c);
      if (code.isNotEmpty && code != prev) buffer.write(code);
      if (c != 'H' && c != 'W') prev = code;
    }

    return buffer.toString().padRight(4, '0').substring(0, 4);
  }

  static double tokenSetSimilarity(
    String a,
    String b, {
    double tokenThreshold = 0.6,
  }) {
    final aw = a.split(' ').where((w) => w.isNotEmpty).toList();
    final bw = b.split(' ').where((w) => w.isNotEmpty).toList();
    if (aw.isEmpty || bw.isEmpty) return 0;

    final precision = _coverage(aw, bw, tokenThreshold);
    final recall = _coverage(bw, aw, tokenThreshold);
    if (precision + recall == 0) return 0;
    return 2 * precision * recall / (precision + recall);
  }

  static double _coverage(
    List<String> from,
    List<String> to,
    double tokenThreshold,
  ) {
    double total = 0;
    for (final f in from) {
      double best = 0;
      for (final t in to) {
        final r = tokenSimilarity(f, t);
        if (r > best) best = r;
      }
      if (best >= tokenThreshold) total += best;
    }
    return total / from.length;
  }

  static int levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final dp = List.generate(
      a.length + 1,
      (i) => List.filled(b.length + 1, 0),
    );

    for (int i = 0; i <= a.length; i++) dp[i][0] = i;
    for (int j = 0; j <= b.length; j++) dp[0][j] = j;

    for (int i = 1; i <= a.length; i++) {
      for (int j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        dp[i][j] = [
          dp[i - 1][j] + 1,
          dp[i][j - 1] + 1,
          dp[i - 1][j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
    }

    return dp[a.length][b.length];
  }
}