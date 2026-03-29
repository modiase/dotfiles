package main

import (
	"crypto/subtle"
	"encoding/json"
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

func (h *Handler) CreateDeck(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Name string `json:"name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid JSON"}`, http.StatusBadRequest)
		return
	}
	if req.Name == "" {
		http.Error(w, `{"error":"name is required"}`, http.StatusBadRequest)
		return
	}
	id, err := h.db.CreateDeck(req.Name)
	if err != nil {
		serverError(w, "creating deck", err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]int64{"id": id})
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

func (h *Handler) CreateNote(w http.ResponseWriter, r *http.Request) {
	var req CreateNoteRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid JSON"}`, http.StatusBadRequest)
		return
	}
	if req.Deck == "" || req.Model == "" || len(req.Fields) == 0 {
		http.Error(w, `{"error":"deck, model, and fields are required"}`, http.StatusBadRequest)
		return
	}
	note, err := h.db.CreateNote(req)
	if err != nil {
		serverError(w, "creating note", err)
		return
	}
	writeJSON(w, http.StatusCreated, note)
}

func (h *Handler) DeleteNote(w http.ResponseWriter, r *http.Request) {
	idStr := r.PathValue("id")
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		http.Error(w, `{"error":"invalid note id"}`, http.StatusBadRequest)
		return
	}
	if err := h.db.DeleteNote(id); err != nil {
		serverError(w, "deleting note", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
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
