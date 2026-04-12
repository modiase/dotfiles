package main

import (
	"crypto/subtle"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strconv"
)

type Handler struct {
	db     *AnkiDB
	apiKey string
}

func (h *Handler) authMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/api/health" {
			next.ServeHTTP(w, r)
			return
		}
		key := r.Header.Get("X-API-Key")
		if subtle.ConstantTimeCompare([]byte(key), []byte(h.apiKey)) != 1 {
			http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (h *Handler) Health(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (h *Handler) ListDecks(w http.ResponseWriter, r *http.Request) {
	decks, err := h.db.ListDecks()
	if err != nil {
		serverError(w, "listing decks", err)
		return
	}
	writeJSON(w, http.StatusOK, decks)
}

func (h *Handler) ListNotes(w http.ResponseWriter, r *http.Request) {
	deck := r.URL.Query().Get("deck")
	if deck == "" {
		http.Error(w, `{"error":"deck query parameter is required"}`, http.StatusBadRequest)
		return
	}
	notes, err := h.db.ListNotes(deck)
	if err != nil {
		serverError(w, "listing notes", err)
		return
	}
	writeJSON(w, http.StatusOK, notes)
}

func (h *Handler) GetNote(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		http.Error(w, `{"error":"invalid note id"}`, http.StatusBadRequest)
		return
	}
	note, err := h.db.GetNote(id)
	if err != nil {
		if err.Error() == fmt.Sprintf("note %d not found", id) {
			http.Error(w, `{"error":"note not found"}`, http.StatusNotFound)
			return
		}
		serverError(w, "getting note", err)
		return
	}
	writeJSON(w, http.StatusOK, note)
}

func (h *Handler) SearchNotes(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query().Get("q")
	if q == "" {
		http.Error(w, `{"error":"q query parameter is required"}`, http.StatusBadRequest)
		return
	}
	deck := r.URL.Query().Get("deck")
	notes, err := h.db.SearchNotes(q, deck)
	if err != nil {
		serverError(w, "searching notes", err)
		return
	}
	writeJSON(w, http.StatusOK, notes)
}

func (h *Handler) ListModels(w http.ResponseWriter, r *http.Request) {
	models, err := h.db.GetNoteTypes()
	if err != nil {
		serverError(w, "listing models", err)
		return
	}
	writeJSON(w, http.StatusOK, models)
}

func (h *Handler) Stats(w http.ResponseWriter, r *http.Request) {
	stats, err := h.db.GetStats()
	if err != nil {
		serverError(w, "getting stats", err)
		return
	}
	writeJSON(w, http.StatusOK, stats)
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func serverError(w http.ResponseWriter, context string, err error) {
	log.Printf("error %s: %v", context, err)
	http.Error(w, `{"error":"internal server error"}`, http.StatusInternalServerError)
}
