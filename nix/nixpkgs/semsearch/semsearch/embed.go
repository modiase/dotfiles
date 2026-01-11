package semsearch

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"time"
)

// GetEmbeddings returns embeddings for the given texts.
func GetEmbeddings(texts []string, cfg Config) ([][]float64, error) {
	payload := map[string]interface{}{
		"model": cfg.EmbedModel,
		"input": texts,
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}

	client := &http.Client{Timeout: 60 * time.Second}
	resp, err := client.Post(cfg.EmbedURL+"/embeddings", "application/json", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != 200 {
		respBody, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("embedding API error %d: %s", resp.StatusCode, string(respBody))
	}

	var result embeddingResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, err
	}

	embeddings := make([][]float64, len(texts))
	for _, d := range result.Data {
		embeddings[d.Index] = d.Embedding
	}
	return embeddings, nil
}

// IsEmbedServerAvailable checks if the embedding server is up.
func IsEmbedServerAvailable(cfg Config) bool {
	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Get(cfg.EmbedURL + "/models")
	if err != nil {
		return false
	}
	defer func() { _ = resp.Body.Close() }()
	return resp.StatusCode == 200
}

// CosineSimilarity computes similarity between two vectors.
func CosineSimilarity(a, b []float64) float64 {
	magA, magB := magnitude(a), magnitude(b)
	if magA == 0 || magB == 0 {
		return 0
	}
	return dotProduct(a, b) / (magA * magB)
}

func dotProduct(a, b []float64) float64 {
	var sum float64
	for i := range a {
		if i < len(b) {
			sum += a[i] * b[i]
		}
	}
	return sum
}

func magnitude(v []float64) float64 {
	var sum float64
	for _, x := range v {
		sum += x * x
	}
	return math.Sqrt(sum)
}
