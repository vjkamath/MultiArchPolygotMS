package main

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"runtime"
)

type EncryptRequest struct {
	Data string `json:"data"`
}

type EncryptResponse struct {
	EncryptedData string `json:"encrypted_data"`
	Architecture string `json:"architecture"`
	TimeMs 	int64 `json:"time_ms"`
}

var key = make([]byte, 32) // AES-256 key

func init() {
	_, err := rand.Read(key)
	if err != nil {
		panic(err)
	}
}

func encrypt(data []byte) ([]byte, error) {
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}

	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}

	nonce := make([]byte, gcm.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return nil, err
	}

	return gcm.Seal(nonce, nonce, data, nil), nil
}

func handleEncrypt(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req EncryptRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	encrypted, err := encrypt([]byte(req.Data))
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	response := EncryptResponse{
		EncryptedData: base64.StdEncoding.EncodeToString(encrypted),
		Architecture: runtime.GOARCH,
		TimeMs:0, // Placeholder for time in milliseconds
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func main() {
	http.HandleFunc("/encrypt", handleEncrypt)
	log.Printf("Starting server on :8080 (Architecture: %s)", runtime.GOARCH)
	log.Fatal(http.ListenAndServe(":8080", nil))
}
