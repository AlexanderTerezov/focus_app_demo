# FocusApp (Still Work In Progress Demo For Portfolio)

A working demo of a cross-platform productivity application built with Flutter,
Go and PostgreSQL.

## Architecture

Flutter frontend
|
| HTTP / WebSocket
v
Go backend
|
v
PostgreSQL

## Features

- User registration and authentication
- JWT authentication
- Configurable Pomodoro sessions
- Infinite Focus sessions
- Persistent focus sessions
- Real-time session synchronization
- PostgreSQL persistence
- Cross-platform Flutter client

## Technologies

Frontend:

- Flutter
- Dart

Backend:

- Go
- PostgreSQL
- pgx
- WebSockets
- JWT
- Argon2id

## Project Structure

frontend/ Flutter application
backend/ Go REST/WebSocket API

## Setup

### Prerequisites

Make sure the following are installed:

- Flutter
- Dart
- Go
- PostgreSQL

### 1. Clone the repository

```bash
git clone https://github.com/AlexanderTerezov/focus_app_demo.git
```

### 2. Configure the backend

# Windows PowerShell

```bash
$env:DATABASE_URL="postgres://focus_app_user:<password>@localhost:5432/focus_app"
$env:JWT_SECRET="your-local-secret"
```

Run the backend:

```bash
cd backend
go mod download
go run .
```

### 3. Configure the frontend

Open a second terminal:

```bash
cd frontend
flutter pub get
```

Run the application:

```bash
flutter run
```

Select the desired Flutter target when prompted.

### Database

The backend requires PostgreSQL. Database migrations are located in:

```text
backend/migrations/
```

Apply the migrations to your local database before starting the application.

### About Multiple Devices

By default, the application connects to the backend running on the same device:

// HTTP
static const String baseUrl = 'http://localhost:8080';

// WebSocket
static const String baseUrl = 'ws://localhost:8080';

To test the application across multiple devices on the same network, replace localhost with the local network IP address of the device running the backend.

For example:

// HTTP
static const String baseUrl = 'http://192.168.0.101:8080';

// WebSocket
static const String baseUrl = 'ws://192.168.0.101:8080';

Make sure the backend is configured to accept connections from the network and that port 8080 is allowed through the host machine's firewall.
