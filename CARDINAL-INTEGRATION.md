# Cardinal integration

Source: https://github.com/cardisoft/cardinal

Pinned upstream commit: `4c50734f9a09d88110f96652b43634b412f79449` (retrieved 2026-10-31).

## Reuse and architecture

The upstream engine crates under `Vendor/Cardinal` have narrow security patches as of 0.15.0: dependency upgrades, absolute `/usr/bin/mdfind`, and private atomic index persistence. See SECURITY.md for versions and verification. The Tauri/React desktop frontend is not embedded. `CardinalBridge` links Cardinal's search-cache, cardinal-sdk, fswalk and search-cancel crates into a private Rust helper. The SwiftUI file page talks to this helper over bounded JSON-line pipe responses. There is no local TCP server, shell command interpolation or runtime network search.

The helper performs a parallel name/path walk, constructs Cardinal's search index, persists a compressed cache and uses the public FSEvents stream API for changes. Queries use Cardinal's parser and case-insensitive matching. It expands metadata only for at most 300 displayed rows, reports the actual match count and cancels outdated query tokens. The native client also rejects results with old request IDs.

FSEvents startup is checked explicitly. If unavailable, the helper reports this state, reconciles a restored cache by scanning and supports explicit refresh. The application does not silently label an unmonitored index as live. Scan cancellation and helper termination are scoped to this application.

## Search scope and data

Default root is `/`. The duplicate macOS data-volume view `/System/Volumes/Data`, device nodes `/dev`, virtual-memory storage `/private/var/vm` and the application's own search-cache directory are excluded. macOS permissions may prevent reading additional locations; no permission is bypassed. Hidden dot components are omitted from results unless enabled in the range menu. Mounted volumes are reachable through normal traversal subject to accessibility and system permissions; disconnected volumes require subsequent updates/reindexing.

Names, paths and basic metadata are cached locally. File contents are only read when explicitly requested via Cardinal content filters or native preview/open actions. The UI's 300-result cap does not represent the full match count. No global sort across an arbitrarily truncated subset is claimed.

## Build

Use Rust nightly-2025-12-11, matching the upstream rust-toolchain.toml. `bash build-cardinal.sh` builds the release helper using CardinalBridge/Cargo.lock. `Engine/WindowNestCardinal` is included for rebuilding the native app without installing Rust. `bash build.sh` copies and signs the helper inside `Contents/Helpers`, embeds licenses, builds the native app and verifies its local signature.

The engine has signature identifier `local.windownest.cardinal`; the application retains `local.windownest.app`. Both enable hardened runtime. Default ad-hoc designated requirements bind code hashes; identifier-only requirements were removed. Developer ID can be configured explicitly, but the current local build is not Apple notarized.

## License preservation

Cardinal is MIT licensed; the original notice is retained in `Vendor/Cardinal/LICENSE`, `Licenses/Cardinal-MIT.txt` and the app bundle. The exact Rust dependency versions are locked. Dependency license expressions and bundled license/notice texts are collected in `Licenses/THIRD_PARTY_NOTICES.md` and `Licenses/Rust/`, and copied into the app bundle during build.

## Validation

- Native logic/motion: 69 checks passed.
- Native three-page navigation: 78 checks passed.
- Actual helper integration: 16 checks passed, including Unicode, type/folder/hidden/content filters, total vs limit, invalid syntax, cancellation, refresh, cache persistence and reload.
- Unmodified upstream search-cache library: 876 tests passed, 1 ignored.
- The standalone FSEvents test cannot start an event stream inside the execution sandbox. This is recorded rather than represented as a live-event pass; the integration test exercises explicit refresh in that environment.
- In the running app outside that execution sandbox, live watching started successfully. A newly created test text file appeared automatically; its Quick Look preview displayed the expected text. After the generated file was removed, its result automatically disappeared.
