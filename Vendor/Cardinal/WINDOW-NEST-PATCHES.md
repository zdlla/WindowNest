# WindowNest security patches

Based on upstream commit 4c50734f9a09d88110f96652b43634b412f79449. Original MIT notices are retained.

As of WindowNest 0.15.0:

- search-cache/Cargo.toml: zstd and thin-vec minimum versions updated; tempfile used for private atomic cache persistence.
- file-tags/Cargo.toml: plist upgraded to obtain fixed quick-xml.
- file-tags/src/lib.rs: use /usr/bin/mdfind, independently of PATH.
- search-cache/src/persistent.rs: exclusively-created random 0600 temporary index; compression errors are propagated before atomic replacement.
- Cargo.lock: compatible dependency updates for upstream workspace tests. The shipped helper uses the separate CardinalBridge/Cargo.lock.

Full validation and dependency audit are documented in ../../SECURITY.md. These files are no longer described as an unmodified vendor tree.
