# Security Policy

jsonette parses **untrusted input**: JSON text that arrives from the network, a
file, or any other source the program does not control. Robust handling of
hostile input is a primary design goal, not an afterthought.

## Supported versions

jsonette is pre-1.0. Security fixes are made against the latest released
version and `main`.

| Version | Supported |
| ------- | --------- |
| 0.1.x   | yes       |
| < 0.1.0 | no        |

## Hardening

The parser is built to fail safely on adversarial input:

- **Strict RFC 8259 grammar.** The tape builder validates the grammar inline as
  it builds (a single pass), so malformed documents are rejected rather than
  silently accepted. The DOM, the On-Demand reader, and the standalone validator
  agree on which inputs are valid.
- **UTF-8 validation.** Input is checked for well-formed UTF-8 before structural
  parsing, including non-ASCII bytes inside strings. Invalid encodings are
  rejected.
- **Bounded nesting depth.** Nested objects and arrays are limited to a depth of
  **1024**; deeper nesting is rejected, so a pathologically nested document
  cannot exhaust the stack or run away.
- **Input size limit.** Input must be smaller than **4 GiB** (structural offsets
  are 32-bit). Larger input is rejected up front, before any parsing, so offsets
  can never wrap into out-of-bounds reads.
- **Encoder refuses non-finite floats.** The JSON encoder rejects `NaN` and
  `Infinity` (which JSON cannot represent) rather than emitting invalid output.

All of the above raise a normal error that the caller can handle; they do not
crash the process or read out of bounds.

## Reporting a vulnerability

Please report security issues **privately** so they can be fixed before public
disclosure. Use GitHub's private vulnerability reporting:

1. Go to the repository's **Security** tab.
2. Click **Report a vulnerability** to open a private Security Advisory.

Please do not open a public issue for a suspected vulnerability. Include enough
detail to reproduce — ideally a minimal input that triggers the problem — and we
will coordinate a fix and disclosure with you.
