/// Privacy-first, local activity analytics for focus sessions.
///
/// Public API components are exported from this library as they are
/// implemented and approved.
library;

export 'src/analytics_client.dart' show AnalyticsPlugin;
export 'src/classification_engine.dart'
    show ActivityClassification, ClassificationEngine;
export 'src/foreground_activity.dart' show ForegroundActivity;
