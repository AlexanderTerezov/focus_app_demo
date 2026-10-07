package main

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"strconv"
	"strings"

	"github.com/golang-jwt/jwt/v5"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/argon2"
)

type contextKey string

const userIDKey contextKey = "userID"

// Hashes passwords using argon2
func hashPassword(password string) (string, error) {
	salt := make([]byte, 16)

	_, err := rand.Read(salt)
	if err != nil {
		return "", err
	}

	hash := argon2.IDKey(
		[]byte(password),
		salt,
		1,
		64*1024,
		4,
		32,
	)

	return fmt.Sprintf(
		"%s:%s",
		base64.RawStdEncoding.EncodeToString(salt),
		base64.RawStdEncoding.EncodeToString(hash),
	), nil
}

type RegisterRequest struct {
	Email    string `json:"email"`
	Username string `json:"username"`
	Password string `json:"password"`
}

// Handles user registration. It accepts username email and password.
func registerHandler(db *pgxpool.Pool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var request RegisterRequest

		err := json.NewDecoder(r.Body).Decode(&request)
		if err != nil {
			http.Error(w, "Invalid request body", http.StatusBadRequest)
			return
		}

		if request.Email == "" || request.Username == "" || request.Password == "" {
			http.Error(w, "Email, username and password are required", http.StatusBadRequest)
			return
		}

		passwordHash, err := hashPassword(request.Password)
		if err != nil {
			http.Error(w, "Failed to hash password", http.StatusInternalServerError)
			return
		}

		err = createUser(
			db,
			request.Email,
			request.Username,
			passwordHash,
		)

		if err != nil {
			fmt.Println("Create user error:", err)

			var pgErr *pgconn.PgError

			if errors.As(err, &pgErr) && pgErr.Code == "23505" {
				http.Error(w, "Email or username already exists", http.StatusConflict)
				return
			}

			http.Error(w, "Failed to create user", http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusCreated)

		json.NewEncoder(w).Encode(map[string]string{
			"message": "User created successfully",
		})
	}
}

type LoginRequest struct {
	Identifier string `json:"identifier"`
	Password   string `json:"password"`
}

// Handles the login. It accepts identifier and password
func loginHandler(db *pgxpool.Pool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var request LoginRequest

		err := json.NewDecoder(r.Body).Decode(&request)
		if err != nil {
			http.Error(w, "Invalid request body", http.StatusBadRequest)
			return
		}

		if request.Identifier == "" || request.Password == "" {
			http.Error(w, "Username/email and password are required", http.StatusBadRequest)
			return
		}

		userID, storedHash, err := getUserByIdentifier(
			db,
			request.Identifier,
		)

		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				http.Error(w, "Invalid username/email or password", http.StatusUnauthorized)
				return
			}

			fmt.Println("Get user error:", err)
			http.Error(w, "Internal server error", http.StatusInternalServerError)
			return
		}

		if !verifyPassword(request.Password, storedHash) {
			http.Error(w, "Invalid username/email or password", http.StatusUnauthorized)
			return
		}

		token, err := createAccessToken(userID)

		if err != nil {
			fmt.Println("Create access token error:", err)
			http.Error(w, "Internal server error", http.StatusInternalServerError)
			return
		}

		refreshToken, err := generateRefreshToken()

		if err != nil {
			fmt.Println("Generate refresh token error:", err)
			http.Error(w, "Internal server error", http.StatusInternalServerError)
			return
		}

		refreshTokenHash := hashRefreshToken(refreshToken)

		_, err = db.Exec(
			context.Background(),
			`INSERT INTO refresh_tokens (
        user_id,
        token_hash,
        expires_at
    )
    VALUES ($1, $2, NOW() + INTERVAL '30 days')`,
			userID,
			refreshTokenHash,
		)

		if err != nil {
			fmt.Println("Store refresh token error:", err)
			http.Error(w, "Internal server error", http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)

		json.NewEncoder(w).Encode(map[string]string{
			"access_token":  token,
			"refresh_token": refreshToken,
			"token_type":    "Bearer",
		})
	}
}

// Returns info of the user
func meHandler(db *pgxpool.Pool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID, ok := r.Context().Value(userIDKey).(int64)

		if !ok {
			http.Error(w, "User ID not found", http.StatusInternalServerError)
			return
		}

		email, username, score, err := getUserByID(db, userID)

		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				http.Error(w, "User not found", http.StatusNotFound)
				return
			}

			fmt.Println("Get user error:", err)
			http.Error(w, "Internal server error", http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "application/json")

		json.NewEncoder(w).Encode(map[string]interface{}{
			"id":       userID,
			"email":    email,
			"username": username,
			"score":    score,
		})
	}
}

// Middleware for JWT
func authMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {

		authHeader := r.Header.Get("Authorization")

		if authHeader == "" {
			http.Error(w, "Missing Authorization header", http.StatusUnauthorized)
			return
		}

		if !strings.HasPrefix(authHeader, "Bearer ") {
			http.Error(w, "Invalid Authorization header", http.StatusUnauthorized)
			return
		}

		tokenString := strings.TrimPrefix(authHeader, "Bearer ")

		secret := os.Getenv("JWT_SECRET")

		if secret == "" {
			http.Error(w, "Internal server error", http.StatusInternalServerError)
			return
		}

		claims := &jwt.RegisteredClaims{}

		token, err := jwt.ParseWithClaims(
			tokenString,
			claims,
			func(token *jwt.Token) (interface{}, error) {
				if token.Method != jwt.SigningMethodHS256 {
					return nil, errors.New("unexpected signing method")
				}

				return []byte(secret), nil
			},
		)

		if err != nil || !token.Valid {
			http.Error(w, "Invalid or expired token", http.StatusUnauthorized)
			return
		}

		userID, err := strconv.ParseInt(claims.Subject, 10, 64)

		if err != nil {
			http.Error(w, "Invalid token", http.StatusUnauthorized)
			return
		}

		ctx := context.WithValue(
			r.Context(),
			userIDKey,
			userID,
		)

		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

type CreateFocusSessionRequest struct {
	StudyDurationSeconds      int  `json:"study_duration_seconds"`
	ShortBreakDurationSeconds int  `json:"short_break_duration_seconds"`
	LongBreakDurationSeconds  int  `json:"long_break_duration_seconds"`
	SessionsUntilLongBreak    int  `json:"sessions_until_long_break"`
	IsInfinite                bool `json:"is_infinite"`
}

// Creates a focus sessions accepts info about the session
func createFocusSessionHandler(db *pgxpool.Pool, webSocketManager *WebSocketManager) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID, ok := r.Context().Value(userIDKey).(int64)

		if !ok {
			http.Error(w, "User ID not found", http.StatusInternalServerError)
			return
		}

		var request CreateFocusSessionRequest

		err := json.NewDecoder(r.Body).Decode(&request)
		if err != nil {
			http.Error(w, "Invalid request body", http.StatusBadRequest)
			return
		}

		if request.StudyDurationSeconds <= 0 ||
			request.ShortBreakDurationSeconds <= 0 ||
			request.LongBreakDurationSeconds <= 0 ||
			request.SessionsUntilLongBreak <= 0 {
			http.Error(w, "Invalid focus cycle data", http.StatusBadRequest)
			return
		}

		session, err := createFocusSession(
			db,
			userID,
			request.StudyDurationSeconds,
			request.ShortBreakDurationSeconds,
			request.LongBreakDurationSeconds,
			request.SessionsUntilLongBreak,
			request.IsInfinite,
		)

		if err != nil {
			fmt.Println("Create focus cycle error:", err)

			var pgErr *pgconn.PgError

			if errors.As(err, &pgErr) && pgErr.Code == "23505" {
				http.Error(
					w,
					"An active focus cycle already exists",
					http.StatusConflict,
				)
				return
			}

			http.Error(w, "Internal server error", http.StatusInternalServerError)
			return
		}

		webSocketManager.BroadcastEvent(
			userID,
			WebSocketEvent{
				Type:    "focus_session_started",
				Session: session,
			},
		)

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusCreated)

		json.NewEncoder(w).Encode(session)
	}
}

// Returns the current active session
func getActiveFocusSessionHandler(db *pgxpool.Pool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID, ok := r.Context().Value(userIDKey).(int64)

		if !ok {
			http.Error(w, "User ID not found", http.StatusInternalServerError)
			return
		}

		session, err := getActiveFocusSession(db, userID)

		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				http.Error(
					w,
					"No active focus cycle",
					http.StatusNotFound,
				)
				return
			}

			fmt.Println("Get active focus cycle error:", err)

			http.Error(
				w,
				"Internal server error",
				http.StatusInternalServerError,
			)
			return
		}

		w.Header().Set("Content-Type", "application/json")

		json.NewEncoder(w).Encode(session)
	}
}

// Completes a session meaning incrementing it by 1 in the database field completed_sessions (Done by Flutter when timer ends)
func completeFocusSessionHandler(
	db *pgxpool.Pool,
	webSocketManager *WebSocketManager,
) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {

		userID, ok := r.Context().Value(userIDKey).(int64)
		if !ok {
			http.Error(w, "User ID not found", http.StatusInternalServerError)
			return
		}

		sessionID, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil {
			http.Error(w, "Invalid session ID", http.StatusBadRequest)
			return
		}

		nextType, completedFocusSessions, err :=
			completeFocusSession(db, sessionID, userID)

		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				http.Error(
					w,
					"Active focus cycle not found",
					http.StatusNotFound,
				)
				return
			}

			if err.Error() == "cannot complete a phase for an infinite focus session" {
				http.Error(
					w,
					"Infinite Focus sessions do not have phases",
					http.StatusConflict,
				)
				return
			}

			if err.Error() == "timer has not finished" {
				http.Error(
					w,
					"Timer has not finished",
					http.StatusConflict,
				)
				return
			}

			fmt.Println("Complete focus cycle error:", err)

			http.Error(
				w,
				"Internal server error",
				http.StatusInternalServerError,
			)
			return
		}

		// Get the updated session from the database.
		session, err := getActiveFocusSession(db, userID)
		if err != nil {
			fmt.Println("Get updated focus session error:", err)

			http.Error(
				w,
				"Internal server error",
				http.StatusInternalServerError,
			)
			return
		}

		// Notify every connected device.
		webSocketManager.BroadcastEvent(
			userID,
			WebSocketEvent{
				Type:    "focus_session_phase_changed",
				Session: session,
			},
		)

		w.Header().Set("Content-Type", "application/json")

		json.NewEncoder(w).Encode(map[string]interface{}{
			"id":                       sessionID,
			"next_type":                nextType,
			"completed_focus_sessions": completedFocusSessions,
			"status":                   "active",
		})
	}
}

// Ends the session (Done by the user by clicking the button)
func endFocusSessionHandler(db *pgxpool.Pool, webSocketManager *WebSocketManager) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID, ok := r.Context().Value(userIDKey).(int64)

		if !ok {
			http.Error(w, "User ID not found", http.StatusInternalServerError)
			return
		}

		sessionID, err := strconv.ParseInt(r.PathValue("id"), 10, 64)

		if err != nil {
			http.Error(w, "Invalid session ID", http.StatusBadRequest)
			return
		}

		ended, points, totalScore, err := endFocusSession(
			db,
			sessionID,
			userID,
		)

		if err != nil {
			fmt.Println("End focus session error:", err)
			http.Error(w, "Internal server error", http.StatusInternalServerError)
			return
		}

		if !ended {
			http.Error(w, "Focus session not found", http.StatusNotFound)
			return
		}

		webSocketManager.BroadcastEvent(
			userID,
			WebSocketEvent{
				Type: "focus_session_ended",
				Session: map[string]interface{}{
					"id": sessionID,
				},
			},
		)

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)

		json.NewEncoder(w).Encode(map[string]interface{}{
			"id":            sessionID,
			"message":       "Focus cycle ended",
			"status":        "ended",
			"points_earned": points,
			"total_score":   totalScore,
		})
	}
}

type RefreshTokenRequest struct {
	RefreshToken string `json:"refresh_token"`
}

func refreshTokenHandler(db *pgxpool.Pool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var request RefreshTokenRequest

		if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
			http.Error(w, "Invalid request body", http.StatusBadRequest)
			return
		}

		if request.RefreshToken == "" {
			http.Error(w, "Missing refresh token", http.StatusBadRequest)
			return
		}

		tokenHash := hashRefreshToken(request.RefreshToken)

		var (
			refreshTokenID int64
			userID         int64
		)

		err := db.QueryRow(
			context.Background(),
			`SELECT id, user_id
             FROM refresh_tokens
             WHERE token_hash = $1
               AND revoked_at IS NULL
               AND expires_at > NOW()`,
			tokenHash,
		).Scan(&refreshTokenID, &userID)

		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				http.Error(w, "Invalid or expired refresh token", http.StatusUnauthorized)
				return
			}

			fmt.Println("Find refresh token error:", err)
			http.Error(w, "Internal server error", http.StatusInternalServerError)
			return
		}

		tx, err := db.Begin(context.Background())
		if err != nil {
			http.Error(w, "Internal server error", http.StatusInternalServerError)
			return
		}
		defer tx.Rollback(context.Background())

		_, err = tx.Exec(
			context.Background(),
			`UPDATE refresh_tokens
             SET revoked_at = NOW()
             WHERE id = $1`,
			refreshTokenID,
		)

		if err != nil {
			fmt.Println("Revoke refresh token error:", err)
			http.Error(w, "Internal server error", http.StatusInternalServerError)
			return
		}

		newRefreshToken, err := generateRefreshToken()
		if err != nil {
			http.Error(w, "Internal server error", http.StatusInternalServerError)
			return
		}

		newRefreshTokenHash := hashRefreshToken(newRefreshToken)

		_, err = tx.Exec(
			context.Background(),
			`INSERT INTO refresh_tokens (
                user_id,
                token_hash,
                expires_at
            )
            VALUES ($1, $2, NOW() + INTERVAL '30 days')`,
			userID,
			newRefreshTokenHash,
		)

		if err != nil {
			fmt.Println("Store new refresh token error:", err)
			http.Error(w, "Internal server error", http.StatusInternalServerError)
			return
		}

		newAccessToken, err := createAccessToken(userID)
		if err != nil {
			fmt.Println("Create access token error:", err)
			http.Error(w, "Internal server error", http.StatusInternalServerError)
			return
		}

		if err := tx.Commit(context.Background()); err != nil {
			fmt.Println("Commit refresh token transaction error:", err)
			http.Error(w, "Internal server error", http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)

		json.NewEncoder(w).Encode(map[string]string{
			"access_token":  newAccessToken,
			"refresh_token": newRefreshToken,
			"token_type":    "Bearer",
		})
	}
}
