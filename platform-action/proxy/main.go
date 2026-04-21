// Lightweight reverse proxy for Cloud Run SSO frontends.
// Serves static files and proxies /api/* to the backend with an identity token.
package main

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	backendURL := os.Getenv("BACKEND_URL")

	mux := http.NewServeMux()

	// Serve static files from /app/dist
	fs := http.FileServer(http.Dir("/app/dist"))

	// /api/* proxy to backend — manual HTTP request to rule out ReverseProxy issues
	if backendURL != "" {
		mux.HandleFunc("/api/", func(w http.ResponseWriter, r *http.Request) {
			// Build target URL
			targetURL := backendURL + r.URL.Path
			if r.URL.RawQuery != "" {
				targetURL += "?" + r.URL.RawQuery
			}

			// Fetch identity token
			token, err := fetchIdentityToken(backendURL)
			if err != nil {
				log.Printf("ERROR: failed to fetch identity token: %v", err)
				http.Error(w, "proxy error: "+err.Error(), 502)
				return
			}
			logJWTClaims(token)

			// Create new request
			proxyReq, err := http.NewRequest(r.Method, targetURL, r.Body)
			if err != nil {
				http.Error(w, "proxy error: "+err.Error(), 502)
				return
			}
			proxyReq.Header.Set("Authorization", "Bearer "+token)
			proxyReq.Header.Set("Content-Type", r.Header.Get("Content-Type"))

			log.Printf("Proxying %s %s -> %s (token len=%d)", r.Method, r.URL.Path, targetURL, len(token))

			// Send request
			resp, err := http.DefaultClient.Do(proxyReq)
			if err != nil {
				log.Printf("ERROR: backend request failed: %v", err)
				http.Error(w, "proxy error: "+err.Error(), 502)
				return
			}
			defer resp.Body.Close()

			body, _ := io.ReadAll(resp.Body)
			log.Printf("Backend response: %d (len=%d)", resp.StatusCode, len(body))
			if resp.StatusCode >= 400 {
				log.Printf("Backend %d body: %.500s", resp.StatusCode, string(body))
			}

			// Forward response
			for k, v := range resp.Header {
				for _, vv := range v {
					w.Header().Add(k, vv)
				}
			}
			w.WriteHeader(resp.StatusCode)
			w.Write(body)
		})
	}

	// SPA catch-all: serve index.html for all non-file routes
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		// Try serving the file directly
		path := "/app/dist" + r.URL.Path
		if _, err := os.Stat(path); err == nil && !strings.HasSuffix(r.URL.Path, "/") {
			fs.ServeHTTP(w, r)
			return
		}
		// Fall back to index.html for SPA routing
		http.ServeFile(w, r, "/app/dist/index.html")
	})

	log.Printf("Listening on :%s (backend: %s)", port, backendURL)
	log.Fatal(http.ListenAndServe(":"+port, mux))
}

// logJWTClaims decodes and logs key claims from a JWT token (for debugging).
func logJWTClaims(token string) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		log.Printf("WARNING: token is not a valid JWT (parts=%d)", len(parts))
		return
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		log.Printf("WARNING: failed to decode JWT payload: %v", err)
		return
	}
	var claims map[string]interface{}
	if err := json.Unmarshal(payload, &claims); err != nil {
		log.Printf("WARNING: failed to parse JWT claims: %v", err)
		return
	}
	log.Printf("JWT claims: iss=%v aud=%v email=%v sub=%v", claims["iss"], claims["aud"], claims["email"], claims["sub"])
}

// fetchIdentityToken gets an identity token from the GCE metadata server.
func fetchIdentityToken(audience string) (string, error) {
	metaURL := fmt.Sprintf(
		"http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/identity?audience=%s",
		url.QueryEscape(audience),
	)
	req, err := http.NewRequest("GET", metaURL, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("Metadata-Flavor", "Google")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("metadata server returned %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}

	return strings.TrimSpace(string(body)), nil
}
