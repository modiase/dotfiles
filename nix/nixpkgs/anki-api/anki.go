package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"strings"

	_ "github.com/mattn/go-sqlite3"
)

type AnkiDB struct {
	db *sql.DB
}

type Deck struct {
	ID   int64  `json:"id"`
	Name string `json:"name"`
}

type Note struct {
	ID     int64             `json:"id"`
	Model  string            `json:"model"`
	Fields map[string]string `json:"fields"`
	Tags   string            `json:"tags"`
}

type Model struct {
	ID     int64    `json:"id"`
	Name   string   `json:"name"`
	Fields []string `json:"fields"`
}

type Stats struct {
	Notes  int `json:"notes"`
	Cards  int `json:"cards"`
	Decks  int `json:"decks"`
	Models int `json:"models"`
}

type noteType struct {
	ID     int64
	Name   string
	Fields []string
}

func OpenAnkiDB(path string) (*AnkiDB, error) {
	db, err := sql.Open("sqlite3", path+"?_busy_timeout=30000&mode=ro")
	if err != nil {
		return nil, fmt.Errorf("opening sqlite: %w", err)
	}
	db.SetMaxOpenConns(1)
	db.SetMaxIdleConns(0)
	if err := db.Ping(); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("pinging sqlite: %w", err)
	}
	return &AnkiDB{db: db}, nil
}

func (a *AnkiDB) Close() error {
	return a.db.Close()
}

func (a *AnkiDB) ListDecks() ([]Deck, error) {
	row := a.db.QueryRow("SELECT decks FROM col")
	var decksJSON string
	if err := row.Scan(&decksJSON); err != nil {
		return nil, fmt.Errorf("reading decks: %w", err)
	}

	var raw map[string]json.RawMessage
	if err := json.Unmarshal([]byte(decksJSON), &raw); err != nil {
		return nil, fmt.Errorf("parsing decks JSON: %w", err)
	}

	decks := make([]Deck, 0, len(raw))
	for idStr, v := range raw {
		var d struct {
			Name string `json:"name"`
		}
		if err := json.Unmarshal(v, &d); err != nil {
			continue
		}
		var id int64
		_, _ = fmt.Sscanf(idStr, "%d", &id)
		decks = append(decks, Deck{ID: id, Name: d.Name})
	}
	return decks, nil
}

func (a *AnkiDB) ListNotes(deckName string) ([]Note, error) {
	decks, err := a.ListDecks()
	if err != nil {
		return nil, err
	}

	var deckID int64
	for _, d := range decks {
		if d.Name == deckName {
			deckID = d.ID
			break
		}
	}
	if deckID == 0 {
		return nil, fmt.Errorf("deck %q not found", deckName)
	}

	models, err := a.getNoteTypes()
	if err != nil {
		return nil, err
	}
	modelsByID := make(map[int64]noteType, len(models))
	for _, m := range models {
		modelsByID[m.ID] = m
	}

	rows, err := a.db.Query(`
		SELECT n.id, n.mid, n.flds, n.tags
		FROM notes n
		JOIN cards c ON c.nid = n.id
		WHERE c.did = ?
		GROUP BY n.id
	`, deckID)
	if err != nil {
		return nil, fmt.Errorf("querying notes: %w", err)
	}
	defer func() { _ = rows.Close() }()

	var notes []Note
	for rows.Next() {
		var id, mid int64
		var flds, tags string
		if err := rows.Scan(&id, &mid, &flds, &tags); err != nil {
			return nil, err
		}

		fields := make(map[string]string)
		parts := strings.Split(flds, "\x1f")
		if m, ok := modelsByID[mid]; ok {
			for i, name := range m.Fields {
				if i < len(parts) {
					fields[name] = parts[i]
				}
			}
		}

		notes = append(notes, Note{
			ID:     id,
			Model:  modelsByID[mid].Name,
			Fields: fields,
			Tags:   strings.TrimSpace(tags),
		})
	}
	if notes == nil {
		notes = []Note{}
	}
	return notes, rows.Err()
}

func (a *AnkiDB) GetNote(id int64) (*Note, error) {
	models, err := a.getNoteTypes()
	if err != nil {
		return nil, err
	}
	modelsByID := make(map[int64]noteType, len(models))
	for _, m := range models {
		modelsByID[m.ID] = m
	}

	var mid int64
	var flds, tags string
	err = a.db.QueryRow("SELECT mid, flds, tags FROM notes WHERE id = ?", id).Scan(&mid, &flds, &tags)
	if err == sql.ErrNoRows {
		return nil, fmt.Errorf("note %d not found", id)
	}
	if err != nil {
		return nil, fmt.Errorf("querying note: %w", err)
	}

	fields := make(map[string]string)
	parts := strings.Split(flds, "\x1f")
	if m, ok := modelsByID[mid]; ok {
		for i, name := range m.Fields {
			if i < len(parts) {
				fields[name] = parts[i]
			}
		}
	}

	return &Note{
		ID:     id,
		Model:  modelsByID[mid].Name,
		Fields: fields,
		Tags:   strings.TrimSpace(tags),
	}, nil
}

func (a *AnkiDB) SearchNotes(query string, deckName string) ([]Note, error) {
	models, err := a.getNoteTypes()
	if err != nil {
		return nil, err
	}
	modelsByID := make(map[int64]noteType, len(models))
	for _, m := range models {
		modelsByID[m.ID] = m
	}

	likeParam := "%" + query + "%"
	var rows *sql.Rows

	if deckName != "" {
		decks, err := a.ListDecks()
		if err != nil {
			return nil, err
		}
		var deckID int64
		for _, d := range decks {
			if d.Name == deckName {
				deckID = d.ID
				break
			}
		}
		if deckID == 0 {
			return nil, fmt.Errorf("deck %q not found", deckName)
		}
		rows, err = a.db.Query(`
			SELECT n.id, n.mid, n.flds, n.tags
			FROM notes n
			JOIN cards c ON c.nid = n.id
			WHERE (n.flds LIKE ? OR n.tags LIKE ?) AND c.did = ?
			GROUP BY n.id
		`, likeParam, likeParam, deckID)
		if err != nil {
			return nil, fmt.Errorf("searching notes: %w", err)
		}
	} else {
		rows, err = a.db.Query(`
			SELECT id, mid, flds, tags FROM notes
			WHERE flds LIKE ? OR tags LIKE ?
		`, likeParam, likeParam)
		if err != nil {
			return nil, fmt.Errorf("searching notes: %w", err)
		}
	}
	defer func() { _ = rows.Close() }()

	var notes []Note
	for rows.Next() {
		var nid, mid int64
		var flds, tags string
		if err := rows.Scan(&nid, &mid, &flds, &tags); err != nil {
			return nil, err
		}
		fields := make(map[string]string)
		parts := strings.Split(flds, "\x1f")
		if m, ok := modelsByID[mid]; ok {
			for i, name := range m.Fields {
				if i < len(parts) {
					fields[name] = parts[i]
				}
			}
		}
		notes = append(notes, Note{
			ID:     nid,
			Model:  modelsByID[mid].Name,
			Fields: fields,
			Tags:   strings.TrimSpace(tags),
		})
	}
	if notes == nil {
		notes = []Note{}
	}
	return notes, rows.Err()
}

func (a *AnkiDB) GetNoteTypes() ([]Model, error) {
	types, err := a.getNoteTypes()
	if err != nil {
		return nil, err
	}
	models := make([]Model, len(types))
	for i, t := range types {
		models[i] = Model(t)
	}
	return models, nil
}

func (a *AnkiDB) GetStats() (*Stats, error) {
	var noteCount, cardCount int
	if err := a.db.QueryRow("SELECT COUNT(*) FROM notes").Scan(&noteCount); err != nil {
		return nil, fmt.Errorf("counting notes: %w", err)
	}
	if err := a.db.QueryRow("SELECT COUNT(*) FROM cards").Scan(&cardCount); err != nil {
		return nil, fmt.Errorf("counting cards: %w", err)
	}

	var decksJSON, modelsJSON string
	if err := a.db.QueryRow("SELECT decks, models FROM col").Scan(&decksJSON, &modelsJSON); err != nil {
		return nil, fmt.Errorf("reading col: %w", err)
	}

	var decks map[string]json.RawMessage
	if err := json.Unmarshal([]byte(decksJSON), &decks); err != nil {
		return nil, fmt.Errorf("parsing decks: %w", err)
	}
	var models map[string]json.RawMessage
	if err := json.Unmarshal([]byte(modelsJSON), &models); err != nil {
		return nil, fmt.Errorf("parsing models: %w", err)
	}

	return &Stats{
		Notes:  noteCount,
		Cards:  cardCount,
		Decks:  len(decks),
		Models: len(models),
	}, nil
}

func (a *AnkiDB) getNoteTypes() ([]noteType, error) {
	row := a.db.QueryRow("SELECT models FROM col")
	var modelsJSON string
	if err := row.Scan(&modelsJSON); err != nil {
		return nil, fmt.Errorf("reading models: %w", err)
	}

	var raw map[string]json.RawMessage
	if err := json.Unmarshal([]byte(modelsJSON), &raw); err != nil {
		return nil, fmt.Errorf("parsing models JSON: %w", err)
	}

	var types []noteType
	for _, v := range raw {
		var m struct {
			ID   int64  `json:"id"`
			Name string `json:"name"`
			Flds []struct {
				Name string `json:"name"`
				Ord  int    `json:"ord"`
			} `json:"flds"`
		}
		if err := json.Unmarshal(v, &m); err != nil {
			continue
		}
		fields := make([]string, len(m.Flds))
		for _, f := range m.Flds {
			if f.Ord < len(fields) {
				fields[f.Ord] = f.Name
			}
		}
		types = append(types, noteType{
			ID:     m.ID,
			Name:   m.Name,
			Fields: fields,
		})
	}
	return types, nil
}
