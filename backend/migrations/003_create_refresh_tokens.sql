 CREATE TABLE refresh_tokens (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked_at TIMESTAMPTZ
);

CREATE INDEX refresh_tokens_user_id_idx
ON refresh_tokens(user_id);

GRANT SELECT, INSERT, UPDATE, DELETE
ON TABLE refresh_tokens TO focus_app_user;

GRANT USAGE, SELECT
ON SEQUENCE refresh_tokens_id_seq TO focus_app_user;