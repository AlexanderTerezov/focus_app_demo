import 'foreground_activity.dart';

enum ActivityClassification {
  focused,
  distracting,
  unknown,
}

class ClassificationEngine {
  const ClassificationEngine({
    required this.focusedKeywords,
    required this.distractingKeywords,
  });

  final List<String> focusedKeywords;
  final List<String> distractingKeywords;

  ActivityClassification classify(
    ForegroundActivity activity,
  ) {
    final searchableText = [
      activity.applicationName,
      if (activity.windowTitle != null) activity.windowTitle!,
    ].join(' ').toLowerCase();

    if (_containsAny(searchableText, distractingKeywords)) {
      return ActivityClassification.distracting;
    }

    if (_containsAny(searchableText, focusedKeywords)) {
      return ActivityClassification.focused;
    }

    return ActivityClassification.unknown;
  }

  bool _containsAny(
    String searchableText,
    List<String> keywords,
  ) {
    return keywords.any(
      (keyword) => searchableText.contains(keyword.toLowerCase()),
    );
  }
}
