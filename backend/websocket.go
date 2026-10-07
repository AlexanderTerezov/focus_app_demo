package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"sync"

	"github.com/gorilla/websocket"
)

type WebSocketEvent struct {
	Type    string      `json:"type"`
	Session interface{} `json:"session,omitempty"`
}

type WebSocketManager struct {
	mu          sync.Mutex
	connections map[int64]map[*websocket.Conn]bool
}

func NewWebSocketManager() *WebSocketManager {
	return &WebSocketManager{
		connections: make(map[int64]map[*websocket.Conn]bool),
	}
}

func (manager *WebSocketManager) AddConnection(
	userID int64,
	conn *websocket.Conn,
) {
	manager.mu.Lock()
	defer manager.mu.Unlock()

	if manager.connections[userID] == nil {
		manager.connections[userID] = make(map[*websocket.Conn]bool)
	}

	manager.connections[userID][conn] = true
}

func (manager *WebSocketManager) RemoveConnection(
	userID int64,
	conn *websocket.Conn,
) {
	manager.mu.Lock()
	defer manager.mu.Unlock()

	delete(manager.connections[userID], conn)

	if len(manager.connections[userID]) == 0 {
		delete(manager.connections, userID)
	}
}

func (manager *WebSocketManager) BroadcastToUser(
	userID int64,
	message []byte,
) {
	manager.mu.Lock()
	defer manager.mu.Unlock()

	for conn := range manager.connections[userID] {
		err := conn.WriteMessage(
			websocket.TextMessage,
			message,
		)

		if err != nil {
			conn.Close()
			delete(manager.connections[userID], conn)
		}
	}
}

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

func webSocketHandler(manager *WebSocketManager) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID, ok := r.Context().Value(userIDKey).(int64)

		if !ok {
			http.Error(w, "User ID not found", http.StatusInternalServerError)
			return
		}

		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			fmt.Println("WebSocket upgrade error:", err)
			return
		}

		manager.AddConnection(userID, conn)

		defer func() {
			manager.RemoveConnection(userID, conn)
			conn.Close()
		}()

		for {
			messageType, message, err := conn.ReadMessage()

			if err != nil {
				break
			}

			if err := conn.WriteMessage(messageType, message); err != nil {
				break
			}
		}
	}
}

func (manager *WebSocketManager) BroadcastEvent(userID int64, event WebSocketEvent) {
	message, err := json.Marshal(event)

	if err != nil {
		fmt.Println("WebSocket event marshal error:", err)
		return
	}

	manager.BroadcastToUser(userID, message)
}
