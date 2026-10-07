class FocusSession {
  final int id;
  final int? userId;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String status;

  final int studyDurationSeconds;
  final int shortBreakDurationSeconds;
  final int longBreakDurationSeconds;
  final int sessionsUntilLongBreak;

  final int completedFocusSessions;

  final String currentType;
  final DateTime? currentStartedAt;
  final int? currentDurationSeconds;

  final bool isInfinite;

  const FocusSession({
    required this.id,
    required this.userId,
    required this.startedAt,
    required this.endedAt,
    required this.status,
    required this.studyDurationSeconds,
    required this.shortBreakDurationSeconds,
    required this.longBreakDurationSeconds,
    required this.sessionsUntilLongBreak,
    required this.completedFocusSessions,
    required this.currentType,
    required this.currentStartedAt,
    required this.currentDurationSeconds,
    required this.isInfinite,
  });

  factory FocusSession.fromJson(Map<String, dynamic> json) {
    return FocusSession(
      id: json['id'] as int,
      userId: json['user_id'] as int?,
      startedAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'] as String)
          : null,
      endedAt: json['ended_at'] != null
          ? DateTime.parse(json['ended_at'] as String)
          : null,
      status: json['status'] as String,
      studyDurationSeconds: json['study_duration_seconds'] as int,
      shortBreakDurationSeconds: json['short_break_duration_seconds'] as int,
      longBreakDurationSeconds: json['long_break_duration_seconds'] as int,
      sessionsUntilLongBreak: json['sessions_until_long_break'] as int,
      completedFocusSessions: json['completed_focus_sessions'] as int,
      currentType: json['current_type'] as String,
      currentStartedAt: json['current_started_at'] != null
          ? DateTime.parse(json['current_started_at'] as String)
          : null,
      currentDurationSeconds: json['current_duration_seconds'] as int?,
      isInfinite: json['is_infinite'] as bool? ?? false,
    );
  }
}
