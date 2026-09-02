/// Human-friendly ("natural") ordering used by SALU's smart queue.
///
/// Phase 5 · Step 2. A plain alphabetical sort produces
/// `Episode_1, Episode_10, Episode_2` — natural sorting compares embedded
/// digit runs numerically so the queue reads `Episode_1 … Episode_10`,
/// exactly like IINA.
class NaturalSort {
  NaturalSort._();

  /// Compares two strings, treating consecutive digits as one number.
  static int compare(String a, String b) {
    final String x = a.toLowerCase();
    final String y = b.toLowerCase();

    int i = 0;
    int j = 0;
    while (i < x.length && j < y.length) {
      final bool xDigit = _isDigit(x.codeUnitAt(i));
      final bool yDigit = _isDigit(y.codeUnitAt(j));

      if (xDigit && yDigit) {
        // Consume the full digit run on both sides and compare numerically.
        final int xStart = i;
        final int yStart = j;
        while (i < x.length && _isDigit(x.codeUnitAt(i))) {
          i++;
        }
        while (j < y.length && _isDigit(y.codeUnitAt(j))) {
          j++;
        }
        final String xNum = x.substring(xStart, i).replaceFirst(RegExp(r'^0+(?=\d)'), '');
        final String yNum = y.substring(yStart, j).replaceFirst(RegExp(r'^0+(?=\d)'), '');
        if (xNum.length != yNum.length) {
          return xNum.length - yNum.length;
        }
        final int cmp = xNum.compareTo(yNum);
        if (cmp != 0) return cmp;
        continue;
      }

      final int cmp = x.codeUnitAt(i).compareTo(y.codeUnitAt(j));
      if (cmp != 0) return cmp;
      i++;
      j++;
    }

    return (x.length - i) - (y.length - j);
  }

  /// Returns a new list sorted naturally by [key] (defaults to the value).
  static List<T> sorted<T>(Iterable<T> items, {String Function(T)? key}) {
    final List<T> list = items.toList();
    list.sort((T a, T b) => compare(
          key == null ? '$a' : key(a),
          key == null ? '$b' : key(b),
        ));
    return list;
  }

  static bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;
}
