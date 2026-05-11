// Prevent additional console window on Windows in release.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use chrono::Local;
use serde::Serialize;
use std::fs;
use std::path::PathBuf;
use std::process::Command;
use tauri::WindowEvent;

/// Where the repo lives, so we can spawn `scripts/diary-process.sh`.
/// In dev (`npm run tauri dev`) the user can set DEARDIARY_REPO from their
/// shell. In a production .app the path is baked in at build time via
/// `option_env!("DEARDIARY_REPO")` so the bundled binary is self-contained.
fn repo_dir() -> Option<PathBuf> {
    if let Ok(p) = std::env::var("DEARDIARY_REPO") {
        return Some(PathBuf::from(p));
    }
    if let Some(p) = option_env!("DEARDIARY_REPO") {
        return Some(PathBuf::from(p));
    }
    None
}

fn diary_dir() -> PathBuf {
    if let Ok(p) = std::env::var("DEARDIARY_DIR") {
        return PathBuf::from(p);
    }
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    PathBuf::from(home).join("DearDiary")
}

fn inbox_dir() -> PathBuf {
    diary_dir().join("diary").join("inbox")
}

#[derive(Serialize)]
struct SaveResult {
    id: String,
    path: String,
}

#[tauri::command]
fn save_entry(text: String) -> Result<SaveResult, String> {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return Err("entry is empty".into());
    }
    let now_local = Local::now();
    let id = now_local.format("%Y-%m-%dT%H-%M-%S").to_string();
    let created_at = now_local.to_rfc3339();

    let body = format!(
        "---\ncreated_at: {created_at}\nid: {id}\n---\n\n{trimmed}\n",
        created_at = created_at,
        id = id,
        trimmed = trimmed
    );

    let inbox = inbox_dir();
    fs::create_dir_all(&inbox).map_err(|e| format!("mkdir inbox: {e}"))?;

    // Atomic-ish write: <id>.md.tmp -> mv to <id>.md
    let final_path = inbox.join(format!("{id}.md"));
    let tmp_path = inbox.join(format!("{id}.md.tmp"));
    fs::write(&tmp_path, body).map_err(|e| format!("write tmp: {e}"))?;
    fs::rename(&tmp_path, &final_path).map_err(|e| format!("rename: {e}"))?;

    Ok(SaveResult {
        id,
        path: final_path.display().to_string(),
    })
}

#[tauri::command]
fn process_now() -> Result<(), String> {
    let repo = repo_dir().ok_or_else(|| {
        "DEARDIARY_REPO not set; rebuild the app with the repo path baked in or export it"
            .to_string()
    })?;
    let script = repo.join("scripts").join("diary-process.sh");
    if !script.exists() {
        return Err(format!("missing {}", script.display()));
    }
    Command::new(&script)
        .arg("button")
        .spawn()
        .map_err(|e| format!("spawn diary-process.sh: {e}"))?;
    // Detached: don't wait, don't capture. The script's Phase A returns
    // immediately and forks Phase B in the background.
    Ok(())
}

fn main() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![save_entry, process_now])
        .on_window_event(|window, event| {
            // Closing the window hides it instead of quitting, so the app
            // stays alive in the Dock as the user expects. Cmd+Q still quits.
            if let WindowEvent::CloseRequested { api, .. } = event {
                let _ = window.hide();
                api.prevent_close();
            }
        })
        .setup(|_app| Ok(()))
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
