package main

import (
	"bufio"
	"bytes"
	"errors"
	"fmt"
	"io"
	"os"

	"filippo.io/age/armor"
	"filippo.io/age/internal/format"
)

// This command is built inside age's source tree to reuse its format parser.
// It checks public structure only: authentication still requires an identity.
func validate(path string) error {
	f, err := os.Open(path)
	if err != nil {
		return errors.New("cannot read ciphertext")
	}
	defer f.Close()

	r := bufio.NewReader(f)
	intro, _ := r.Peek(len("age-encryption.org/v1\n"))
	var input io.Reader = r
	if !bytes.Equal(intro, []byte("age-encryption.org/v1\n")) {
		input = armor.NewReader(r)
	}
	_, payload, err := format.Parse(input)
	if err != nil {
		// Parser errors can quote input. Never echo accidentally supplied plaintext.
		return errors.New("invalid age header or armor")
	}
	n, err := io.Copy(io.Discard, payload)
	if err != nil {
		return errors.New("invalid ciphertext or armor")
	}
	// A 16-byte nonce precedes authenticated chunks of at most 64 KiB + 16 bytes.
	// Even empty plaintext has a final chunk containing its authentication tag.
	lastChunk := (n - 16) % (65536 + 16)
	if n < 32 || (lastChunk > 0 && lastChunk < 16) {
		return errors.New("truncated encrypted payload")
	}
	return nil
}

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: agenix-validate CIPHERTEXT")
		os.Exit(2)
	}
	if err := validate(os.Args[1]); err != nil {
		fmt.Fprintf(os.Stderr, "agenix: %q: %v\n", os.Args[1], err)
		os.Exit(1)
	}
}
