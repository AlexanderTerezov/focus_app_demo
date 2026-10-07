package main

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/argon2"

	"github.com/golang-jwt/jwt/v5"
)

func connectDB() (*pgxpool.Pool, error) {
	databaseURL := ""

	db, err := pgxpool.New(context.Background(), databaseURL)

	if err != nil {
		return nil, err
	}

	err = db.Ping(context.Background())

	if err != nil {
		db.Close()
		return nil, err
	}

	return db, nil
}

func createUser(db *pgxpool.Pool, email string, username string, passwordHash string) error {
	_, err := db.Exec(
		context.Background(),
		`INSERT INTO users (email, username, password_hash)
		 VALUES ($1, $2, $3)`,
		email,
		username,
		passwordHash,
	)

	return err
}

func getUserByIdentifier(db *pgxpool.Pool, identifier string) (int64, string, error) {
	var id int64
	var passwordHash string

	err := db.QueryRow(
		context.Background(),
		`SELECT id, password_hash
         FROM users
         WHERE email = $1 OR username = $1`,
		identifier,
	).Scan(&id, &passwordHash)

	return id, passwordHash, err
}

func getUserByID(db *pgxpool.Pool, userID int64) (string, string, int, error) {
	var email string
	var username string
	var score int

	err := db.QueryRow(
		context.Background(),
		`SELECT email, username, score
         FROM users
         WHERE id = $1`,
		userID,
	).Scan(&email, &username, &score)

	return email, username, score, err
}

func verifyPassword(password string, storedHash string) bool {
	parts := strings.Split(storedHash, ":")

	if len(parts) != 2 {
		return false
	}

	salt, err := base64.RawStdEncoding.DecodeString(parts[0])
	if err != nil {
		return false
	}

	expectedHash, err := base64.RawStdEncoding.DecodeString(parts[1])
	if err != nil {
		return false
	}

	actualHash := argon2.IDKey(
		[]byte(password),
		salt,
		1,
		64*1024,
		4,
		32,
	)

	return subtle.ConstantTimeCompare(actualHash, expectedHash) == 1
}

func createAccessToken(userID int64) (string, error) {
	secret := os.Getenv("JWT_SECRET")

	if secret == "" {
		return "", errors.New("JWT_SECRET is not set")
	}

	now := time.Now()

	claims := jwt.RegisteredClaims{
		Subject:   strconv.FormatInt(userID, 10),
		IssuedAt:  jwt.NewNumericDate(now),
		ExpiresAt: jwt.NewNumericDate(now.Add(15 * time.Minute)),
	}

	token := jwt.NewWithClaims(
		jwt.SigningMethodHS256,
		claims,
	)

	return token.SignedString([]byte(secret))
}

type FocusSessionResponse struct {
	ID                        int64     `json:"id"`
	StudyDurationSeconds      int       `json:"study_duration_seconds"`
	ShortBreakDurationSeconds int       `json:"short_break_duration_seconds"`
	LongBreakDurationSeconds  int       `json:"long_break_duration_seconds"`
	SessionsUntilLongBreak    int       `json:"sessions_until_long_break"`
	CompletedFocusSessions    int       `json:"completed_focus_sessions"`
	CurrentType               string    `json:"current_type"`
	CurrentStartedAt          time.Time `json:"current_started_at"`
	CurrentDurationSeconds    int       `json:"current_duration_seconds"`
	StartedAt                 time.Time `json:"started_at"`
	Status                    string    `json:"status"`
	IsInfinite                bool      `json:"is_infinite"`
}

func createFocusSession(
	db *pgxpool.Pool,
	userID int64,
	studyDurationSeconds int,
	shortBreakDurationSeconds int,
	longBreakDurationSeconds int,
	sessionsUntilLongBreak int,
	isInfinite bool,
) (FocusSessionResponse, error) {
	var session FocusSessionResponse

	err := db.QueryRow(
		context.Background(),
		`INSERT INTO focus_sessions (
			user_id,
			study_duration_seconds,
			short_break_duration_seconds,
			long_break_duration_seconds,
			sessions_until_long_break,
			completed_focus_sessions,
			current_type,
			current_started_at,
			current_duration_seconds,
			status,
			is_infinite
		)
		VALUES (
			$1, $2, $3, $4, $5, $6, $7, NOW(), $8, $9, $10
		)
		RETURNING
			id,
			study_duration_seconds,
			short_break_duration_seconds,
			long_break_duration_seconds,
			sessions_until_long_break,
			completed_focus_sessions,
			current_type,
			current_started_at,
			current_duration_seconds,
			started_at,
			status,
			is_infinite`,
		userID,
		studyDurationSeconds,
		shortBreakDurationSeconds,
		longBreakDurationSeconds,
		sessionsUntilLongBreak,
		0,
		"study",
		studyDurationSeconds,
		"active",
		isInfinite,
	).Scan(
		&session.ID,
		&session.StudyDurationSeconds,
		&session.ShortBreakDurationSeconds,
		&session.LongBreakDurationSeconds,
		&session.SessionsUntilLongBreak,
		&session.CompletedFocusSessions,
		&session.CurrentType,
		&session.CurrentStartedAt,
		&session.CurrentDurationSeconds,
		&session.StartedAt,
		&session.Status,
		&session.IsInfinite,
	)

	return session, err
}

func getActiveFocusSession(
	db *pgxpool.Pool,
	userID int64,
) (FocusSessionResponse, error) {
	tx, err := db.Begin(context.Background())

	if err != nil {
		return FocusSessionResponse{}, err
	}

	defer tx.Rollback(context.Background())

	var session FocusSessionResponse

	err = tx.QueryRow(
		context.Background(),
		`SELECT
			id,
			study_duration_seconds,
			short_break_duration_seconds,
			long_break_duration_seconds,
			sessions_until_long_break,
			completed_focus_sessions,
			current_type,
			current_started_at,
			current_duration_seconds,
			started_at,
			status,
			is_infinite
		FROM focus_sessions
		WHERE user_id = $1
		  AND status = 'active'
		FOR UPDATE`,
		userID,
	).Scan(
		&session.ID,
		&session.StudyDurationSeconds,
		&session.ShortBreakDurationSeconds,
		&session.LongBreakDurationSeconds,
		&session.SessionsUntilLongBreak,
		&session.CompletedFocusSessions,
		&session.CurrentType,
		&session.CurrentStartedAt,
		&session.CurrentDurationSeconds,
		&session.StartedAt,
		&session.Status,
		&session.IsInfinite,
	)

	if err != nil {
		return FocusSessionResponse{}, err
	}

	// The current timer expired while no completion request was made.
	if !session.IsInfinite && !time.Now().Before(
		session.CurrentStartedAt.Add(
			time.Duration(session.CurrentDurationSeconds)*time.Second,
		),
	) {
		_, err = tx.Exec(
			context.Background(),
			`UPDATE focus_sessions
			 SET status = 'ended',
			     ended_at = NOW()
			 WHERE id = $1`,
			session.ID,
		)

		if err != nil {
			return FocusSessionResponse{}, err
		}

		err = tx.Commit(context.Background())

		if err != nil {
			return FocusSessionResponse{}, err
		}

		return FocusSessionResponse{}, pgx.ErrNoRows
	}

	err = tx.Commit(context.Background())

	if err != nil {
		return FocusSessionResponse{}, err
	}

	return session, nil
}
func completeFocusSession(
	db *pgxpool.Pool,
	sessionID int64,
	userID int64,
) (string, int, error) {
	tx, err := db.Begin(context.Background())
	if err != nil {
		return "", 0, err
	}
	defer tx.Rollback(context.Background())

	var currentType string
	var currentStartedAt time.Time
	var currentDuration int
	var studyDuration int
	var shortBreakDuration int
	var longBreakDuration int
	var sessionsUntilLongBreak int
	var completedFocusSessions int
	var isInfinite bool

	err = tx.QueryRow(
		context.Background(),
		`SELECT
			current_type,
			current_started_at,
			current_duration_seconds,
			study_duration_seconds,
			short_break_duration_seconds,
			long_break_duration_seconds,
			sessions_until_long_break,
			completed_focus_sessions,
			is_infinite
		FROM focus_sessions
		WHERE id = $1
		  AND user_id = $2
		  AND status = 'active'
		FOR UPDATE`,
		sessionID,
		userID,
	).Scan(
		&currentType,
		&currentStartedAt,
		&currentDuration,
		&studyDuration,
		&shortBreakDuration,
		&longBreakDuration,
		&sessionsUntilLongBreak,
		&completedFocusSessions,
		&isInfinite,
	)

	if err != nil {
		return "", 0, err
	}

	// Infinite Focus sessions do not have phases to complete.
	if isInfinite {
		return "", 0, errors.New(
			"cannot complete a phase for an infinite focus session",
		)
	}

	// Make sure the current timer has actually finished.
	if time.Now().Before(
		currentStartedAt.Add(time.Duration(currentDuration) * time.Second),
	) {
		return "", 0, errors.New("timer has not finished")
	}

	var nextType string
	var nextDuration int

	if currentType == "study" {
		completedFocusSessions++

		if completedFocusSessions%sessionsUntilLongBreak == 0 {
			nextType = "long_break"
			nextDuration = longBreakDuration
		} else {
			nextType = "short_break"
			nextDuration = shortBreakDuration
		}
	} else {
		nextType = "study"
		nextDuration = studyDuration
	}

	_, err = tx.Exec(
		context.Background(),
		`UPDATE focus_sessions
		SET
			current_type = $1,
			current_started_at = NOW(),
			current_duration_seconds = $2,
			completed_focus_sessions = $3
		WHERE id = $4`,
		nextType,
		nextDuration,
		completedFocusSessions,
		sessionID,
	)

	if err != nil {
		return "", 0, err
	}

	err = tx.Commit(context.Background())
	if err != nil {
		return "", 0, err
	}

	return nextType, completedFocusSessions, nil
}

func endFocusSession(
	db *pgxpool.Pool,
	sessionID int64,
	userID int64,
) (bool, int, int, error) {

	tx, err := db.Begin(context.Background())
	if err != nil {
		return false, 0, 0, err
	}
	defer tx.Rollback(context.Background())

	var (
		completedFocusSessions int
		studyDurationSeconds   int
	)

	err = tx.QueryRow(
		context.Background(),
		`SELECT completed_focus_sessions, study_duration_seconds
         FROM focus_sessions
         WHERE id = $1
           AND user_id = $2
           AND status = 'active'
         FOR UPDATE`,
		sessionID,
		userID,
	).Scan(
		&completedFocusSessions,
		&studyDurationSeconds,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return false, 0, 0, nil
		}

		return false, 0, 0, err
	}

	points := completedFocusSessions * (studyDurationSeconds / 60)

	var totalScore int

	err = tx.QueryRow(
		context.Background(),
		`UPDATE users
         SET score = score + $1
         WHERE id = $2
         RETURNING score`,
		points,
		userID,
	).Scan(&totalScore)

	if err != nil {
		return false, 0, 0, err
	}

	_, err = tx.Exec(
		context.Background(),
		`UPDATE focus_sessions
         SET status = 'ended',
             ended_at = NOW()
         WHERE id = $1`,
		sessionID,
	)

	if err != nil {
		return false, 0, 0, err
	}

	if err := tx.Commit(context.Background()); err != nil {
		return false, 0, 0, err
	}

	return true, points, totalScore, nil
}

func generateRefreshToken() (string, error) {
	bytes := make([]byte, 32)

	_, err := rand.Read(bytes)
	if err != nil {
		return "", err
	}

	return base64.RawURLEncoding.EncodeToString(bytes), nil
}

func hashRefreshToken(token string) string {
	hash := sha256.Sum256([]byte(token))
	return hex.EncodeToString(hash[:])
}
