# Release checklist

1. Update versions in `desktop/package.json`, `desktop/src-tauri/Cargo.toml`, and
   `desktop/src-tauri/tauri.conf.json`.
2. Run the local secret scan, tests, npm audit, Rust check, and a macOS bundle build.
3. Push a branch and let CI pass on Windows and macOS. The release workflow
   builds separate Apple Silicon and Intel Mac artifacts.
4. Tag the commit, for example `git tag v0.2.0 && git push origin v0.2.0`.
5. Inspect both GitHub-built installer artifacts before publishing the draft release.
6. Verify a clean install, onboarding, import/export, offline manual tracking,
   and migration from the previous public version.

Friend builds use an ad-hoc macOS signature and an unsigned Windows installer.
Public releases should use Apple Developer ID notarization and a Windows
code-signing certificate, with credentials stored only in encrypted GitHub
Actions secrets.
