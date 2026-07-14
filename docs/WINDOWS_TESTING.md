# Windows friend-testing guide

## For the repository owner

1. Push the repository to GitHub.
2. Open **Actions → Build desktop installers → Run workflow**.
3. When both matrix jobs finish, download the Windows artifact.
4. Send the extracted installer to the tester together with this guide.

A tagged build (`v0.2.0`, for example) is also attached to a draft GitHub
Release by the workflow. Windows installers must be built on Windows, which is
why GitHub Actions is used instead of cross-compiling from a Mac.

## For the tester

1. Extract the downloaded zip before running the installer.
2. Run the NSIS setup `.exe` (or MSI if included).
3. Windows SmartScreen may say the unsigned beta is unrecognized. Click **More
   info → Run anyway** only if the file came from the expected GitHub workflow.
4. Test onboarding with one profile or several profiles, then add a manual movie.
5. Resize the window narrow, mark partial progress, complete the movie, submit
   ratings separately, and export a JSON backup.

Report the Next Up version, Windows version, steps, expected result, actual
result, and a screenshot with personal information removed. Windows code signing
should be added before a broad public release; it is not required for a private beta.
