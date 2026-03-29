package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
)

func main() {
	dbPath := flag.String("db", "", "path to Anki collection.anki21 database")
	port := flag.Int("port", 27702, "HTTP listen port")
	apiKeyFile := flag.String("api-key-file", "", "path to file containing API key")
	flag.Parse()

	if *dbPath == "" {
		log.Fatal("-db flag is required")
	}
	if *apiKeyFile == "" {
		log.Fatal("-api-key-file flag is required")
	}

	keyBytes, err := os.ReadFile(*apiKeyFile)
	if err != nil {
		log.Fatalf("reading API key file: %v", err)
	}
	apiKey := strings.TrimSpace(string(keyBytes))

	db, err := OpenAnkiDB(*dbPath)
	if err != nil {
		log.Fatalf("opening database: %v", err)
	}
	defer func() { _ = db.Close() }()

	h := &Handler{db: db, apiKey: apiKey}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/health", h.Health)
	mux.HandleFunc("GET /api/decks", h.ListDecks)
	mux.HandleFunc("POST /api/decks", h.CreateDeck)
	mux.HandleFunc("DELETE /api/decks/{id}", h.DeleteDeck)
	mux.HandleFunc("GET /api/notes/search", h.SearchNotes)
	mux.HandleFunc("GET /api/notes/{id}", h.GetNote)
	mux.HandleFunc("PUT /api/notes/{id}", h.UpdateNote)
	mux.HandleFunc("GET /api/notes", h.ListNotes)
	mux.HandleFunc("POST /api/notes", h.CreateNote)
	mux.HandleFunc("DELETE /api/notes/{id}", h.DeleteNote)
	mux.HandleFunc("PUT /api/decks/{id}", h.UpdateDeck)
	mux.HandleFunc("GET /api/models", h.ListModels)
	mux.HandleFunc("GET /api/stats", h.Stats)

	addr := fmt.Sprintf("127.0.0.1:%d", *port)
	log.Printf("listening on %s", addr)
	log.Fatal(http.ListenAndServe(addr, h.authMiddleware(mux)))
}
