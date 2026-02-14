fn main() {
    tauri_build::try_build(
        tauri_build::Attributes::new().app_manifest(
            tauri_build::AppManifest::new().commands(&["capture_region", "close_capture_window", "get_debug_log_path", "log_from_frontend"]),
        ),
    )
    .expect("tauri build failed");
}
