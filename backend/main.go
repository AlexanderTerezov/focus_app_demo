package main

import (
	"fmt"
	"net/http"
)

func main() {
	db, err := connectDB()

	if err != nil {
		panic(err)
	}

	defer db.Close()

	fmt.Println("Connected to PostgreSQL!")

	mux := http.NewServeMux()

	webSocketManager := NewWebSocketManager()

	mux.HandleFunc("GET /health", healthHandler)
	mux.HandleFunc("POST /auth/register", registerHandler(db))
	mux.HandleFunc("POST /auth/login", loginHandler(db))

	mux.Handle(
		"GET /me",
		authMiddleware(meHandler(db)),
	)

	mux.Handle(
		"GET /ws",
		authMiddleware(webSocketHandler(webSocketManager)),
	)

	mux.Handle(
		"POST /focus-sessions",
		authMiddleware(createFocusSessionHandler(db, webSocketManager)),
	)

	mux.Handle(
		"GET /focus-sessions/active",
		authMiddleware(getActiveFocusSessionHandler(db)),
	)

	mux.Handle(
		"POST /focus-sessions/{id}/complete",
		authMiddleware(completeFocusSessionHandler(
			db,
			webSocketManager,
		)),
	)

	mux.Handle(
		"POST /focus-sessions/{id}/end",
		authMiddleware(endFocusSessionHandler(db, webSocketManager)),
	)

	mux.HandleFunc("POST /auth/refresh", refreshTokenHandler(db))

	fmt.Println("Server listening on 0.0.0.0:8080")

	http.ListenAndServe("0.0.0.0:8080", mux)
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	w.WriteHeader(http.StatusOK)

	fmt.Fprintln(w, `{"status":"ok"}`)
}
