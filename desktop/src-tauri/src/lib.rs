use serde_json::{json, Value};
use std::{
    fs,
    path::{Path, PathBuf},
    thread,
    time::Duration,
};
use tauri::{AppHandle, Manager};

const KEYRING_SERVICE: &str = "com.nextup.watchtracker.watchmode";
const KEYRING_ACCOUNT: &str = "api-key";

fn data_folder(app: &AppHandle) -> Result<PathBuf, String> {
    app.path().app_data_dir().map_err(|error| error.to_string())
}

fn library_path(app: &AppHandle) -> Result<PathBuf, String> {
    Ok(data_folder(app)?.join("library.json"))
}

struct LibraryLock(PathBuf);

impl Drop for LibraryLock {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn acquire_library_lock(folder: &Path) -> Result<LibraryLock, String> {
    let path = folder.join("library.lock");
    for _ in 0..40 {
        match fs::create_dir(&path) {
            Ok(()) => return Ok(LibraryLock(path)),
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {
                thread::sleep(Duration::from_millis(25));
            }
            Err(error) => return Err(error.to_string()),
        }
    }
    Err("The library is busy. Try again in a moment.".into())
}

fn default_library() -> Value {
    json!({
        "schemaVersion": 8,
        "setupComplete": false,
        "profiles": ["You"],
        "subscribedProviders": [],
        "collections": [],
        "items": [],
        "watchEvents": [],
        "ratings": [],
        "viewingSessions": [],
        "auditLog": [],
        "appSettings": {
            "aiEnabled": false,
            "ratingReveal": "when-everyone-rates",
            "spoilerProtection": true
        }
    })
}

fn migrate_legacy_library(destination: &PathBuf) -> Result<(), String> {
    if destination.exists() {
        return Ok(());
    }
    #[cfg(target_os = "macos")]
    if let Some(home) = dirs::home_dir() {
        let legacy = home.join("Library/Application Support/Next Up/library.json");
        if legacy.exists() {
            if let Some(parent) = destination.parent() {
                fs::create_dir_all(parent).map_err(|error| error.to_string())?;
            }
            fs::copy(legacy, destination).map_err(|error| error.to_string())?;
        }
    }
    Ok(())
}

#[tauri::command]
fn load_library(app: AppHandle) -> Result<Value, String> {
    let path = library_path(&app)?;
    migrate_legacy_library(&path)?;
    if !path.exists() {
        return Ok(default_library());
    }
    let raw = fs::read_to_string(path).map_err(|error| error.to_string())?;
    serde_json::from_str(&raw)
        .map_err(|error| format!("The library file is not valid JSON: {error}"))
}

#[tauri::command]
fn save_library(app: AppHandle, library: Value) -> Result<(), String> {
    let folder = data_folder(&app)?;
    fs::create_dir_all(&folder).map_err(|error| error.to_string())?;
    let _lock = acquire_library_lock(&folder)?;
    let path = folder.join("library.json");
    let backup = folder.join("library.backup.json");
    let temporary = folder.join("library.tmp.json");
    if path.exists() {
        fs::copy(&path, backup).map_err(|error| error.to_string())?;
    }
    let bytes = serde_json::to_vec_pretty(&library).map_err(|error| error.to_string())?;
    fs::write(&temporary, bytes).map_err(|error| error.to_string())?;

    // std::fs::rename replaces an existing file on Unix but not on Windows.
    // The backup above makes the short Windows replacement window recoverable.
    #[cfg(target_os = "windows")]
    if path.exists() {
        fs::remove_file(&path).map_err(|error| error.to_string())?;
    }
    fs::rename(temporary, path).map_err(|error| error.to_string())
}

fn keyring_entry() -> Result<keyring::Entry, String> {
    keyring::Entry::new(KEYRING_SERVICE, KEYRING_ACCOUNT).map_err(|error| error.to_string())
}

#[tauri::command]
fn has_watchmode_key() -> bool {
    keyring_entry()
        .and_then(|entry| entry.get_password().map_err(|error| error.to_string()))
        .is_ok()
}

#[tauri::command]
fn save_watchmode_key(key: String) -> Result<(), String> {
    let clean = key.trim();
    if clean.is_empty() {
        return Err("Enter a Watchmode API key.".into());
    }
    keyring_entry()?
        .set_password(clean)
        .map_err(|error| error.to_string())
}

#[tauri::command]
fn remove_watchmode_key() -> Result<(), String> {
    match keyring_entry()?.delete_credential() {
        Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
        Err(error) => Err(error.to_string()),
    }
}

fn watchmode_key() -> Result<String, String> {
    keyring_entry()?
        .get_password()
        .map_err(|_| "Add a Watchmode key in Settings first.".into())
}

async fn watchmode_get(path: &str, parameters: &[(&str, String)]) -> Result<Value, String> {
    let key = watchmode_key()?;
    let url = format!("https://api.watchmode.com/v1/{path}");
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(20))
        .build()
        .map_err(|error| error.to_string())?;
    let response = client
        .get(url)
        .header("X-API-Key", key)
        .header("User-Agent", "Next-Up/0.2")
        .query(parameters)
        .send()
        .await
        .map_err(|error| error.to_string())?;
    let status = response.status();
    if status.as_u16() == 401 || status.as_u16() == 403 {
        return Err("Watchmode rejected the saved API key.".into());
    }
    if status.as_u16() == 429 {
        return Err("Watchmode request limit reached. Try again shortly.".into());
    }
    if !status.is_success() {
        return Err(format!("Watchmode returned HTTP {status}."));
    }
    response.json().await.map_err(|error| error.to_string())
}

#[tauri::command]
async fn search_watchmode(query: String) -> Result<Value, String> {
    let clean = query.trim();
    if clean.is_empty() {
        return Ok(json!({"results": []}));
    }
    watchmode_get(
        "autocomplete-search/",
        &[("search_value", clean.into()), ("search_type", "3".into())],
    )
    .await
}

#[tauri::command]
async fn watchmode_details(id: u64) -> Result<Value, String> {
    watchmode_get(
        &format!("title/{id}/details/"),
        &[
            ("append_to_response", "sources".into()),
            ("regions", "US".into()),
        ],
    )
    .await
}

async fn tvmaze_get(path: &str, parameters: &[(&str, String)]) -> Result<Value, String> {
    let url = format!("https://api.tvmaze.com/{path}");
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(20))
        .build()
        .map_err(|error| error.to_string())?;
    let response = client
        .get(url)
        .header("User-Agent", "Next-Up/0.2 (local watch tracker)")
        .query(parameters)
        .send()
        .await
        .map_err(|error| error.to_string())?;
    let status = response.status();
    if !status.is_success() {
        return Err(format!("TVmaze returned HTTP {status}."));
    }
    response.json().await.map_err(|error| error.to_string())
}

#[tauri::command]
async fn search_tvmaze(query: String) -> Result<Value, String> {
    let clean = query.trim();
    if clean.is_empty() {
        return Ok(json!([]));
    }
    tvmaze_get("search/shows", &[("q", clean.into())]).await
}

#[tauri::command]
async fn tvmaze_show(id: u64) -> Result<Value, String> {
    tvmaze_get(&format!("shows/{id}"), &[("embed", "episodes".into())]).await
}

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![
            load_library,
            save_library,
            has_watchmode_key,
            save_watchmode_key,
            remove_watchmode_key,
            search_watchmode,
            watchmode_details,
            search_tvmaze,
            tvmaze_show
        ])
        .run(tauri::generate_context!())
        .expect("error while running Next Up");
}
