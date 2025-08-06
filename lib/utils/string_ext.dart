extension StringExt on String? {
  bool get isNullOrEmpty {
    return this == null || this == "";
  }

  String get breakWord {
    if (isNullOrEmpty) {
      return '';
    }
    String breakWord = ' ';
    for (var element in this!.runes) {
      breakWord += String.fromCharCode(element);
      breakWord += '\u200B';
    }
    return breakWord;
  }
}
