CREATE TABLE focus_sessions (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id),
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at TIMESTAMPTZ,
    status TEXT NOT NULL,
    study_duration_seconds INTEGER NOT NULL,
    short_break_duration_seconds INTEGER NOT NULL,
    long_break_duration_seconds INTEGER NOT NULL,
    sessions_until_long_break INTEGER NOT NULL,
    completed_focus_sessions INTEGER NOT NULL DEFAULT 0,
    current_type TEXT NOT NULL,
    current_started_at TIMESTAMPTZ NOT NULL,
    current_duration_seconds INTEGER NOT NULL
);

CREATE UNIQUE INDEX one_active_focus_cycle_per_user
ON focus_sessions(user_id)
WHERE status = 'active';

GRANT SELECT, INSERT, UPDATE, DELETE, REFERENCES
ON TABLE focus_sessions TO focus_app_user;

GRANT USAGE, SELECT
ON SEQUENCE focus_sessions_id_seq TO focus_app_user;