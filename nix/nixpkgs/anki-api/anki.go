package main

import (
	"crypto/sha1"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
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

type UpdateNoteRequest struct {
	Fields map[string]string `json:"fields"`
	Tags   *string           `json:"tags"`
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
	a := &AnkiDB{db: db}
	if err := a.ensureSchema(); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("ensuring schema: %w", err)
	}
	return a, nil
}

func (a *AnkiDB) ensureSchema() error {
	var name string
	err := a.db.QueryRow("SELECT name FROM sqlite_master WHERE type='table' AND name='col'").Scan(&name)
	if err == nil {
		return nil
	}
	if err != sql.ErrNoRows {
		return fmt.Errorf("checking for col table: %w", err)
	}

	now := time.Now()
	crt := now.Unix()
	modelID := now.UnixMilli()

	models := map[string]any{
		fmt.Sprintf("%d", modelID): map[string]any{
			"id":    modelID,
			"name":  "Basic",
			"type":  0,
			"mod":   crt,
			"usn":   -1,
			"sortf": 0,
			"flds": []map[string]any{
				{"name": "Front", "ord": 0, "sticky": false, "rtl": false, "font": "Arial", "size": 20, "media": []any{}},
				{"name": "Back", "ord": 1, "sticky": false, "rtl": false, "font": "Arial", "size": 20, "media": []any{}},
			},
			"tmpls": []map[string]any{
				{"name": "Card 1", "ord": 0, "qfmt": "{{Front}}", "afmt": "{{FrontSide}}<hr id=answer>{{Back}}", "did": nil, "bqfmt": "", "bafmt": ""},
			},
			"tags": []any{},
			"did":  1,
			"css":  ".card { font-family: arial; font-size: 20px; text-align: center; color: black; background-color: white; }",
		},
	}

	decks := map[string]any{
		"1": map[string]any{
			"id": 1, "name": "Default", "mod": crt, "usn": -1,
			"lrnToday": [2]int{0, 0}, "revToday": [2]int{0, 0},
			"newToday": [2]int{0, 0}, "timeToday": [2]int{0, 0},
			"collapsed": false, "browserCollapsed": false,
			"desc": "", "dyn": 0, "conf": 1, "extendNew": 0, "extendRev": 0,
		},
	}

	dconf := map[string]any{
		"1": map[string]any{
			"id": 1, "name": "Default", "mod": 0, "usn": 0, "maxTaken": 60,
			"autoplay": true, "timer": 0, "replayq": true,
			"new":   map[string]any{"delays": []float64{1, 10}, "ints": []int{1, 4, 7}, "initialFactor": 2500, "order": 1, "perDay": 20},
			"rev":   map[string]any{"perDay": 200, "ease4": 1.3, "fuzz": 0.05, "minSpace": 1, "ivlFct": 1, "maxIvl": 36500},
			"lapse": map[string]any{"delays": []float64{10}, "mult": 0, "minInt": 1, "leechFails": 8, "leechAction": 0},
		},
	}

	modelsJSON, _ := json.Marshal(models)
	decksJSON, _ := json.Marshal(decks)
	dconfJSON, _ := json.Marshal(dconf)

	schema := `
		CREATE TABLE IF NOT EXISTS col (
			id INTEGER PRIMARY KEY, crt INTEGER NOT NULL, mod INTEGER NOT NULL,
			scm INTEGER NOT NULL, ver INTEGER NOT NULL, dty INTEGER NOT NULL,
			usn INTEGER NOT NULL, ls INTEGER NOT NULL, conf TEXT NOT NULL,
			models TEXT NOT NULL, decks TEXT NOT NULL, dconf TEXT NOT NULL, tags TEXT NOT NULL
		);
		CREATE TABLE IF NOT EXISTS notes (
			id INTEGER PRIMARY KEY, guid TEXT NOT NULL, mid INTEGER NOT NULL,
			mod INTEGER NOT NULL, usn INTEGER NOT NULL, tags TEXT NOT NULL,
			flds TEXT NOT NULL, sfld TEXT NOT NULL, csum INTEGER NOT NULL,
			flags INTEGER NOT NULL, data TEXT NOT NULL
		);
		CREATE TABLE IF NOT EXISTS cards (
			id INTEGER PRIMARY KEY, nid INTEGER NOT NULL, did INTEGER NOT NULL,
			ord INTEGER NOT NULL, mod INTEGER NOT NULL, usn INTEGER NOT NULL,
			type INTEGER NOT NULL, queue INTEGER NOT NULL, due INTEGER NOT NULL,
			ivl INTEGER NOT NULL, factor INTEGER NOT NULL, reps INTEGER NOT NULL,
			lapses INTEGER NOT NULL, "left" INTEGER NOT NULL, odue INTEGER NOT NULL,
			odid INTEGER NOT NULL, flags INTEGER NOT NULL, data TEXT NOT NULL
		);
		CREATE TABLE IF NOT EXISTS revlog (
			id INTEGER PRIMARY KEY, cid INTEGER NOT NULL, usn INTEGER NOT NULL,
			ease INTEGER NOT NULL, ivl INTEGER NOT NULL, lastIvl INTEGER NOT NULL,
			factor INTEGER NOT NULL, time INTEGER NOT NULL, type INTEGER NOT NULL
		);
		CREATE TABLE IF NOT EXISTS graves (
			usn INTEGER NOT NULL, oid INTEGER NOT NULL, type INTEGER NOT NULL
		);
		CREATE INDEX IF NOT EXISTS ix_notes_usn ON notes (usn);
		CREATE INDEX IF NOT EXISTS ix_notes_csum ON notes (csum);
		CREATE INDEX IF NOT EXISTS ix_cards_usn ON cards (usn);
		CREATE INDEX IF NOT EXISTS ix_cards_nid ON cards (nid);
		CREATE INDEX IF NOT EXISTS ix_cards_sched ON cards (did, queue, due);
		CREATE INDEX IF NOT EXISTS ix_revlog_usn ON revlog (usn);
		CREATE INDEX IF NOT EXISTS ix_revlog_cid ON revlog (cid);
	`
	if _, err := a.db.Exec(schema); err != nil {
		return fmt.Errorf("creating tables: %w", err)
	}

	_, err = a.db.Exec(
		`INSERT INTO col (id, crt, mod, scm, ver, dty, usn, ls, conf, models, decks, dconf, tags)
		 VALUES (1, ?, ?, ?, 11, 0, 0, 0, '{}', ?, ?, ?, '{}')`,
		crt, crt, crt*1000, string(modelsJSON), string(decksJSON), string(dconfJSON),
	)
	if err != nil {
		return fmt.Errorf("inserting default col: %w", err)
	}
	log.Println("initialised empty Anki collection with Basic model and Default deck")
	return nil
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

func (a *AnkiDB) DeleteDeck(deckID int64) error {
	if deckID == 1 {
		return fmt.Errorf("cannot delete the Default deck")
	}

	tx, err := a.db.Begin()
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	row := tx.QueryRow("SELECT decks FROM col")
	var decksJSON string
	if err := row.Scan(&decksJSON); err != nil {
		return fmt.Errorf("reading decks: %w", err)
	}

	var raw map[string]json.RawMessage
	if err := json.Unmarshal([]byte(decksJSON), &raw); err != nil {
		return fmt.Errorf("parsing decks JSON: %w", err)
	}

	idStr := fmt.Sprintf("%d", deckID)
	if _, ok := raw[idStr]; !ok {
		return fmt.Errorf("deck %d not found", deckID)
	}
	delete(raw, idStr)

	// Collect note IDs for cards in this deck
	noteRows, err := tx.Query("SELECT DISTINCT nid FROM cards WHERE did = ?", deckID)
	if err != nil {
		return fmt.Errorf("querying notes in deck: %w", err)
	}
	var noteIDs []int64
	for noteRows.Next() {
		var nid int64
		if err := noteRows.Scan(&nid); err != nil {
			_ = noteRows.Close()
			return err
		}
		noteIDs = append(noteIDs, nid)
	}
	_ = noteRows.Close()
	if err := noteRows.Err(); err != nil {
		return fmt.Errorf("iterating note IDs: %w", err)
	}

	// Collect card IDs and record graves
	cardRows, err := tx.Query("SELECT id FROM cards WHERE did = ?", deckID)
	if err != nil {
		return fmt.Errorf("querying cards in deck: %w", err)
	}
	var cardIDs []int64
	for cardRows.Next() {
		var cid int64
		if err := cardRows.Scan(&cid); err != nil {
			_ = cardRows.Close()
			return err
		}
		cardIDs = append(cardIDs, cid)
	}
	_ = cardRows.Close()
	if err := cardRows.Err(); err != nil {
		return fmt.Errorf("iterating card IDs: %w", err)
	}

	if _, err := tx.Exec("DELETE FROM cards WHERE did = ?", deckID); err != nil {
		return fmt.Errorf("deleting cards: %w", err)
	}

	for _, nid := range noteIDs {
		// Only delete notes that have no cards remaining in other decks
		var remaining int
		if err := tx.QueryRow("SELECT COUNT(*) FROM cards WHERE nid = ?", nid).Scan(&remaining); err != nil {
			return fmt.Errorf("checking remaining cards: %w", err)
		}
		if remaining == 0 {
			if _, err := tx.Exec("DELETE FROM notes WHERE id = ?", nid); err != nil {
				return fmt.Errorf("deleting note: %w", err)
			}
			if _, err := tx.Exec("INSERT INTO graves (usn, oid, type) VALUES (-1, ?, 1)", nid); err != nil {
				return fmt.Errorf("recording note grave: %w", err)
			}
		}
	}

	for _, cid := range cardIDs {
		if _, err := tx.Exec("INSERT INTO graves (usn, oid, type) VALUES (-1, ?, 0)", cid); err != nil {
			return fmt.Errorf("recording card grave: %w", err)
		}
	}
	if _, err := tx.Exec("INSERT INTO graves (usn, oid, type) VALUES (-1, ?, 2)", deckID); err != nil {
		return fmt.Errorf("recording deck grave: %w", err)
	}

	updated, err := json.Marshal(raw)
	if err != nil {
		return err
	}
	if _, err := tx.Exec("UPDATE col SET decks = ?, mod = ?", string(updated), time.Now().Unix()); err != nil {
		return fmt.Errorf("updating decks: %w", err)
	}

	return tx.Commit()
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

func (a *AnkiDB) UpdateNote(id int64, req UpdateNoteRequest) error {
	models, err := a.getNoteTypes()
	if err != nil {
		return err
	}
	modelsByID := make(map[int64]noteType, len(models))
	for _, m := range models {
		modelsByID[m.ID] = m
	}

	tx, err := a.db.Begin()
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	var mid int64
	var flds, tags string
	err = tx.QueryRow("SELECT mid, flds, tags FROM notes WHERE id = ?", id).Scan(&mid, &flds, &tags)
	if err == sql.ErrNoRows {
		return fmt.Errorf("note %d not found", id)
	}
	if err != nil {
		return fmt.Errorf("reading note: %w", err)
	}

	m, ok := modelsByID[mid]
	if !ok {
		return fmt.Errorf("model %d not found for note", mid)
	}

	parts := strings.Split(flds, "\x1f")
	for len(parts) < len(m.Fields) {
		parts = append(parts, "")
	}

	if req.Fields != nil {
		for name, val := range req.Fields {
			for i, fname := range m.Fields {
				if fname == name {
					parts[i] = val
				}
			}
		}
	}

	newFlds := strings.Join(parts, "\x1f")
	sortField := parts[0]
	csum := checksumField(sortField)

	newTags := tags
	if req.Tags != nil {
		newTags = normaliseTags(*req.Tags)
	}

	_, err = tx.Exec(
		"UPDATE notes SET flds = ?, sfld = ?, csum = ?, tags = ?, mod = ?, usn = -1 WHERE id = ?",
		newFlds, sortField, csum, newTags, time.Now().Unix(), id,
	)
	if err != nil {
		return fmt.Errorf("updating note: %w", err)
	}

	return tx.Commit()
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

func (a *AnkiDB) UpdateDeck(deckID int64, name string) error {
	tx, err := a.db.Begin()
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	var decksJSON string
	if err := tx.QueryRow("SELECT decks FROM col").Scan(&decksJSON); err != nil {
		return fmt.Errorf("reading decks: %w", err)
	}

	var raw map[string]json.RawMessage
	if err := json.Unmarshal([]byte(decksJSON), &raw); err != nil {
		return fmt.Errorf("parsing decks JSON: %w", err)
	}

	idStr := fmt.Sprintf("%d", deckID)
	existing, ok := raw[idStr]
	if !ok {
		return fmt.Errorf("deck %d not found", deckID)
	}

	for k, v := range raw {
		if k == idStr {
			continue
		}
		var d struct {
			Name string `json:"name"`
		}
		if err := json.Unmarshal(v, &d); err == nil && d.Name == name {
			return fmt.Errorf("deck %q already exists", name)
		}
	}

	var deck map[string]any
	if err := json.Unmarshal(existing, &deck); err != nil {
		return fmt.Errorf("parsing deck: %w", err)
	}
	deck["name"] = name
	deck["mod"] = time.Now().Unix()
	deck["usn"] = -1

	deckBytes, err := json.Marshal(deck)
	if err != nil {
		return err
	}
	raw[idStr] = deckBytes

	updated, err := json.Marshal(raw)
	if err != nil {
		return err
	}
	if _, err := tx.Exec("UPDATE col SET decks = ?, mod = ?", string(updated), time.Now().Unix()); err != nil {
		return fmt.Errorf("updating decks: %w", err)
	}

	return tx.Commit()
}

func (a *AnkiDB) GetNoteTypes() ([]Model, error) {
	types, err := a.getNoteTypes()
	if err != nil {
		return nil, err
	}
	models := make([]Model, len(types))
	for i, t := range types {
		models[i] = Model{ID: t.ID, Name: t.Name, Fields: t.Fields}
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
