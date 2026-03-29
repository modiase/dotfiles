package main

import (
	"crypto/sha1"
	"database/sql"
	"encoding/json"
	"fmt"
	"math/rand"
	"strings"
	"time"

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

type CreateNoteRequest struct {
	Deck   string            `json:"deck"`
	Model  string            `json:"model"`
	Fields map[string]string `json:"fields"`
	Tags   string            `json:"tags"`
}

type CreateNoteResponse struct {
	NoteID  int64   `json:"note_id"`
	CardIDs []int64 `json:"card_ids"`
}

type noteType struct {
	ID     int64
	Name   string
	Fields []string
	Tmpls  []noteTemplate
}

type noteTemplate struct {
	Name string `json:"name"`
	Ord  int    `json:"ord"`
}

func OpenAnkiDB(path string) (*AnkiDB, error) {
	db, err := sql.Open("sqlite3", path+"?_busy_timeout=30000&_journal_mode=WAL&_txlock=immediate")
	if err != nil {
		return nil, fmt.Errorf("opening sqlite: %w", err)
	}
	db.SetMaxOpenConns(1)
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

func (a *AnkiDB) CreateDeck(name string) (int64, error) {
	tx, err := a.db.Begin()
	if err != nil {
		return 0, err
	}
	defer func() { _ = tx.Rollback() }()

	row := tx.QueryRow("SELECT decks FROM col")
	var decksJSON string
	if err := row.Scan(&decksJSON); err != nil {
		return 0, fmt.Errorf("reading decks: %w", err)
	}

	var raw map[string]json.RawMessage
	if err := json.Unmarshal([]byte(decksJSON), &raw); err != nil {
		return 0, fmt.Errorf("parsing decks JSON: %w", err)
	}

	for _, v := range raw {
		var d struct {
			Name string `json:"name"`
		}
		if err := json.Unmarshal(v, &d); err == nil && d.Name == name {
			return 0, fmt.Errorf("deck %q already exists", name)
		}
	}

	id := time.Now().UnixMilli()
	deck := map[string]any{
		"id":               id,
		"name":             name,
		"mod":              time.Now().Unix(),
		"usn":              -1,
		"lrnToday":         [2]int{0, 0},
		"revToday":         [2]int{0, 0},
		"newToday":         [2]int{0, 0},
		"timeToday":        [2]int{0, 0},
		"collapsed":        false,
		"browserCollapsed": false,
		"desc":             "",
		"dyn":              0,
		"conf":             1,
		"extendNew":        0,
		"extendRev":        0,
	}
	deckBytes, err := json.Marshal(deck)
	if err != nil {
		return 0, err
	}

	idStr := fmt.Sprintf("%d", id)
	raw[idStr] = deckBytes
	updated, err := json.Marshal(raw)
	if err != nil {
		return 0, err
	}

	_, err = tx.Exec("UPDATE col SET decks = ?, mod = ?", string(updated), time.Now().Unix())
	if err != nil {
		return 0, fmt.Errorf("updating decks: %w", err)
	}
	return id, tx.Commit()
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

func (a *AnkiDB) CreateNote(req CreateNoteRequest) (*CreateNoteResponse, error) {
	decks, err := a.ListDecks()
	if err != nil {
		return nil, err
	}
	var deckID int64
	for _, d := range decks {
		if d.Name == req.Deck {
			deckID = d.ID
			break
		}
	}
	if deckID == 0 {
		return nil, fmt.Errorf("deck %q not found", req.Deck)
	}

	models, err := a.getNoteTypes()
	if err != nil {
		return nil, err
	}
	var model *noteType
	for _, m := range models {
		if m.Name == req.Model {
			model = &m
			break
		}
	}
	if model == nil {
		return nil, fmt.Errorf("model %q not found", req.Model)
	}

	fieldValues := make([]string, len(model.Fields))
	for i, name := range model.Fields {
		fieldValues[i] = req.Fields[name]
	}
	flds := strings.Join(fieldValues, "\x1f")

	now := time.Now()
	noteID := now.UnixMilli()
	guid := generateGUID()
	sortField := fieldValues[0]
	csum := checksumField(sortField)
	tags := normaliseTags(req.Tags)

	tx, err := a.db.Begin()
	if err != nil {
		return nil, err
	}
	defer func() { _ = tx.Rollback() }()

	_, err = tx.Exec(`
		INSERT INTO notes (id, guid, mid, mod, usn, tags, flds, sfld, csum, flags, data)
		VALUES (?, ?, ?, ?, -1, ?, ?, ?, ?, 0, '')
	`, noteID, guid, model.ID, now.Unix(), tags, flds, sortField, csum)
	if err != nil {
		return nil, fmt.Errorf("inserting note: %w", err)
	}

	var cardIDs []int64
	for _, tmpl := range model.Tmpls {
		cardID := now.UnixMilli() + int64(tmpl.Ord) + 1
		_, err = tx.Exec(`
			INSERT INTO cards (id, nid, did, ord, mod, usn, type, queue, due, ivl, factor, reps, lapses, left, odue, odid, flags, data)
			VALUES (?, ?, ?, ?, ?, -1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, '')
		`, cardID, noteID, deckID, tmpl.Ord, now.Unix())
		if err != nil {
			return nil, fmt.Errorf("inserting card: %w", err)
		}
		cardIDs = append(cardIDs, cardID)
	}

	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return &CreateNoteResponse{NoteID: noteID, CardIDs: cardIDs}, nil
}

func (a *AnkiDB) DeleteNote(noteID int64) error {
	tx, err := a.db.Begin()
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	res, err := tx.Exec("DELETE FROM notes WHERE id = ?", noteID)
	if err != nil {
		return fmt.Errorf("deleting note: %w", err)
	}
	affected, _ := res.RowsAffected()
	if affected == 0 {
		return fmt.Errorf("note %d not found", noteID)
	}

	rows, err := tx.Query("SELECT id FROM cards WHERE nid = ?", noteID)
	if err != nil {
		return fmt.Errorf("querying cards for graves: %w", err)
	}
	var cardIDs []int64
	for rows.Next() {
		var cid int64
		if err := rows.Scan(&cid); err != nil {
			_ = rows.Close()
			return err
		}
		cardIDs = append(cardIDs, cid)
	}
	_ = rows.Close()
	if err := rows.Err(); err != nil {
		return fmt.Errorf("iterating card IDs: %w", err)
	}

	_, err = tx.Exec("DELETE FROM cards WHERE nid = ?", noteID)
	if err != nil {
		return fmt.Errorf("deleting cards: %w", err)
	}

	for _, cid := range cardIDs {
		_, err = tx.Exec("INSERT INTO graves (usn, oid, type) VALUES (-1, ?, 0)", cid)
		if err != nil {
			return fmt.Errorf("recording card grave: %w", err)
		}
	}
	_, err = tx.Exec("INSERT INTO graves (usn, oid, type) VALUES (-1, ?, 1)", noteID)
	if err != nil {
		return fmt.Errorf("recording note grave: %w", err)
	}

	return tx.Commit()
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
			Tmpls []noteTemplate `json:"tmpls"`
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
			Tmpls:  m.Tmpls,
		})
	}
	return types, nil
}

const base91Chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&()*+,-./:;<=>?@[]^_`{|}~"

func generateGUID() string {
	b := make([]byte, 10)
	for i := range b {
		b[i] = base91Chars[rand.Intn(len(base91Chars))]
	}
	return string(b)
}

func checksumField(field string) int64 {
	h := sha1.Sum([]byte(field))
	hexStr := fmt.Sprintf("%x", h)
	var csum int64
	_, _ = fmt.Sscanf(hexStr[:8], "%x", &csum)
	return csum
}

// normaliseTags pads with leading/trailing spaces as Anki expects.
func normaliseTags(tags string) string {
	t := strings.TrimSpace(tags)
	if t == "" {
		return ""
	}
	return " " + t + " "
}
