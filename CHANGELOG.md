# Changelog

## v2.0.0 - 2026-08-13

- Rebuilt the stack around a private AdGuard -> BIND resolver path.
- Pinned AdGuard Home to v0.107.78 and moved BIND to Canonical 9.20/26.04 stable.
- Enabled DNSSEC validation and restricted recursive access to AdGuard.
- Removed BIND host port publication and broad `/etc/bind` bind mount.
- Separated AdGuard configuration and work data.
- Reduced published services to DNS and AdGuard administration/setup by default.
- Added resource guards and rotated Docker logging.
- Added BIND health gating, validation, smoke-test, backup, update and migration helpers.
- Added optional RFC 8375 `home.arpa` examples and GitHub Actions validation.
