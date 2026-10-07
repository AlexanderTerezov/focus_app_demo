class FocusSessionSummary {
  final DateTime startedAt;
  final DateTime endedAt;
  final Duration totalDuration;
  final Duration focusedDuration;
  final Duration breakDuration;
  final int completedFocusSessions;
  final int distractions;
  final int pointsEarned;

  const FocusSessionSummary({
    required this.startedAt,
    required this.endedAt,
    required this.totalDuration,
    required this.focusedDuration,
    required this.breakDuration,
    required this.completedFocusSessions,
    required this.distractions,
    required this.pointsEarned,
  });

  double get focusRate {
    if (totalDuration.inSeconds <= 0) {
      return 0;
    }

    return focusedDuration.inSeconds / totalDuration.inSeconds;
  }
}
