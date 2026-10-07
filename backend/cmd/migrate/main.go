package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"sort"
	"strconv"
	"strings"

	"focus_backend/migrations"

	"github.com/jackc/pgx/v5"
)

type migration struct {
	version int
	name    string
}

func main() {
	ctx := context.Background()

	databaseURL := os.Getenv("DATABASE_URL")

	if databaseURL == "" {
		log.Fatal("DATABASE_URL is not set")
	}

	conn, err := pgx.Connect(ctx, databaseURL)
	if err != nil {
		log.Fatal("Database connection failed:", err)
	}
	defer conn.Close(ctx)

	if err := runMigrations(ctx, conn); err != nil {
		log.Fatal("Migration failed:", err)
	}

	fmt.Println("Migrations complete.")
}

func runMigrations(ctx context.Context, conn *pgx.Conn) error {
	_, err := conn.Exec(ctx, `
		CREATE TABLE IF NOT EXISTS schema_migrations (
			version INTEGER PRIMARY KEY,
			applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)
	`)
	if err != nil {
		return err
	}

	entries, err := migrations.Files.ReadDir(".")
	if err != nil {
		return err
	}

	var migrationFiles []migration

	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".sql") {
			continue
		}

		parts := strings.SplitN(entry.Name(), "_", 2)
		if len(parts) != 2 {
			return fmt.Errorf("invalid migration filename: %s", entry.Name())
		}

		version, err := strconv.Atoi(parts[0])
		if err != nil {
			return fmt.Errorf("invalid migration version: %s", entry.Name())
		}

		migrationFiles = append(migrationFiles, migration{
			version: version,
			name:    entry.Name(),
		})
	}

	sort.Slice(migrationFiles, func(i, j int) bool {
		return migrationFiles[i].version < migrationFiles[j].version
	})

	for _, migration := range migrationFiles {
		var exists bool

		err := conn.QueryRow(
			ctx,
			`SELECT EXISTS (
				SELECT 1
				FROM schema_migrations
				WHERE version = $1
			)`,
			migration.version,
		).Scan(&exists)

		if err != nil {
			return err
		}

		if exists {
			fmt.Printf("Skipping %03d_%s\n", migration.version, migration.name[strings.Index(migration.name, "_")+1:])
			continue
		}

		fmt.Printf("Applying %03d_%s\n",
			migration.version,
			migration.name[strings.Index(migration.name, "_")+1:],
		)

		sqlBytes, err := migrations.Files.ReadFile(migration.name)
		if err != nil {
			return err
		}

		tx, err := conn.Begin(ctx)
		if err != nil {
			return err
		}

		_, err = tx.Exec(ctx, string(sqlBytes))
		if err != nil {
			tx.Rollback(ctx)
			return fmt.Errorf("migration %s failed: %w", migration.name, err)
		}

		_, err = tx.Exec(
			ctx,
			`INSERT INTO schema_migrations (version)
			 VALUES ($1)`,
			migration.version,
		)
		if err != nil {
			tx.Rollback(ctx)
			return err
		}

		if err := tx.Commit(ctx); err != nil {
			return err
		}
	}

	return nil
}
