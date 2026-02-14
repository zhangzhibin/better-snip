// 极简 Mac 截图：菜单调起 → 主窗口全屏选区 → 截屏 → 剪贴板

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod capture_macos;

use capture_macos::{capture_region_png, CaptureRect};
use serde::Deserialize;
use std::io::Write;
use std::sync::Mutex;
use tauri::menu::{MenuBuilder, SubmenuBuilder};
use tauri::Emitter;
use tauri::Manager;
use tauri::State;
use tauri::window::Color;

const MAIN_WINDOW_LABEL: &str = "main";

/// 主窗口进入选区模式前保存的尺寸/位置，退出时恢复
struct MainWindowSavedState {
    width: u32,
    height: u32,
    x: i32,
    y: i32,
    decorations: bool,
}

/// 调试日志路径：系统临时目录下的 mac-screenshot-debug.log
fn debug_log_path() -> std::path::PathBuf {
    std::env::temp_dir().join("mac-screenshot-debug.log")
}

/// 追加一行到调试日志（不阻塞、忽略错误）
fn debug_log(msg: &str) {
    let path = debug_log_path();
    if let Ok(mut f) = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)
    {
        let ts = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis().to_string())
            .unwrap_or_else(|_| "?".into());
        let _ = writeln!(f, "[{}] {}", ts, msg);
    }
}

#[derive(Deserialize)]
struct Region {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
}

/// 前端选区完成后调用：截屏 → 写剪贴板 → 可选保存 → 主窗口退回 index
#[tauri::command]
async fn capture_region(
    app: tauri::AppHandle,
    state: State<'_, Mutex<Option<MainWindowSavedState>>>,
    region: Region,
    save_to_file: Option<String>,
) -> Result<(), String> {
    let msg = format!("capture_region called x={} y={} w={} h={}", region.x, region.y, region.width, region.height);
    debug_log(&msg);
    eprintln!("[capture_region] {}", msg);
    let rect = CaptureRect {
        x: region.x,
        y: region.y,
        width: region.width,
        height: region.height,
    };
    let png_bytes = capture_region_png(rect).map_err(|e| {
        let err_msg = format!("capture_region_png error: {}", e);
        debug_log(&err_msg);
        eprintln!("[capture_region] {}", err_msg);
        e
    })?;

    // 剪贴板写入图片（macOS 用 arboard）
    #[cfg(target_os = "macos")]
    {
        let img = image::load_from_memory(&png_bytes).map_err(|e| e.to_string())?;
        let rgba = img.to_rgba8();
        let mut clipboard = arboard::Clipboard::new().map_err(|e| e.to_string())?;
        clipboard
            .set_image(arboard::ImageData {
                width: rgba.width() as usize,
                height: rgba.height() as usize,
                bytes: rgba.into_raw().into(),
            })
            .map_err(|e| e.to_string())?;
    }

    // 可选：保存到文件
    if let Some(path) = save_to_file {
        if !path.is_empty() {
            match tauri::async_runtime::spawn_blocking(move || std::fs::write(&path, &png_bytes)).await {
                Ok(Ok(())) => {}
                Ok(Err(e)) => return Err(e.to_string()),
                Err(e) => return Err(e.to_string()),
            }
        }
    }

    exit_capture_mode(&app, &state);
    debug_log("capture_region ok");
    Ok(())
}

/// 关闭选区（取消时前端调用）：主窗口退回 index 并恢复尺寸
#[tauri::command]
fn close_capture_window(app: tauri::AppHandle, state: State<'_, Mutex<Option<MainWindowSavedState>>>) {
    debug_log("close_capture_window called");
    exit_capture_mode(&app, &state);
}

/// 退出选区模式：eval 切回主视图并恢复背景，再发事件兜底，最后恢复窗口尺寸
fn exit_capture_mode(app: &tauri::AppHandle, state: &State<'_, Mutex<Option<MainWindowSavedState>>>) {
    if let Some(w) = app.get_webview_window(MAIN_WINDOW_LABEL) {
        let js = r#"
          (function(){
            if(window.__exitCaptureMode){window.__exitCaptureMode();}
            else{
              var m=document.getElementById('main-view');
              var c=document.getElementById('capture-view');
              if(c){c.classList.remove('active');}
              if(m){m.style.display='';}
              document.body.style.background='#fff';
            }
          })();
        "#;
        let _ = w.eval(js);
    }
    let _ = app.emit_to(tauri::EventTarget::WebviewWindow { label: MAIN_WINDOW_LABEL.to_string() }, "exit-capture-mode", ());
    let Some(w) = app.get_webview_window(MAIN_WINDOW_LABEL) else { return };
    if let Ok(mut guard) = state.lock() {
        if let Some(s) = guard.take() {
            let _ = w.set_decorations(s.decorations);
            let _ = w.set_size(tauri::PhysicalSize::new(s.width, s.height));
            let _ = w.set_position(tauri::PhysicalPosition::new(s.x, s.y));
        }
    }
}

/// 返回调试日志文件路径，便于用户打开查看
#[tauri::command]
fn get_debug_log_path() -> String {
    debug_log_path().display().to_string()
}

/// 前端写入一行到调试日志（用于排查 invoke 是否执行、错误是否传到前端）
#[tauri::command]
fn log_from_frontend(message: String) {
    debug_log(&format!("[frontend] {}", message));
}

/// 进入选区模式：主窗口全屏、无边框、透明，发事件让前端显示选区视图（不 navigate，__TAURI__ 保持）
fn open_capture_window(app: &tauri::AppHandle, state: &tauri::State<'_, Mutex<Option<MainWindowSavedState>>>) -> Result<(), String> {
    debug_log("open_capture_window start");
    let Some(w) = app.get_webview_window(MAIN_WINDOW_LABEL) else {
        return Err("main window not found".into());
    };
    let size = w.inner_size().map_err(|e| e.to_string())?;
    let pos = w.inner_position().map_err(|e| e.to_string())?;
    let decorations = w.is_decorated().unwrap_or(true);
    if let Ok(mut guard) = state.lock() {
        *guard = Some(MainWindowSavedState {
            width: size.width,
            height: size.height,
            x: pos.x,
            y: pos.y,
            decorations,
        });
    }
    w.set_decorations(false).map_err(|e| e.to_string())?;
    w.set_background_color(Some(Color(0, 0, 0, 0))).map_err(|e| e.to_string())?;
    if let Ok(Some(mon)) = app.primary_monitor() {
        let scale = mon.scale_factor();
        let sz = mon.size();
        let p = mon.position();
        let width = (sz.width as f64 / scale) as u32;
        let height = (sz.height as f64 / scale) as u32;
        let x = (p.x as f64 / scale) as i32;
        let y = (p.y as f64 / scale) as i32;
        let _ = w.set_size(tauri::PhysicalSize::new(width, height));
        let _ = w.set_position(tauri::PhysicalPosition::new(x, y));
    }
    // 用 eval 直接切视图并设透明背景，不依赖事件时序；再发事件兜底
    let js = r#"
      (function(){
        var m=document.getElementById('main-view');
        var c=document.getElementById('capture-view');
        if(m){m.style.display='none';}
        if(c){c.classList.add('active');}
        document.body.style.background='transparent';
        if(window.__enterCaptureMode){window.__enterCaptureMode();}
      })();
    "#;
    let _ = w.eval(js);
    let _ = app.emit_to(tauri::EventTarget::WebviewWindow { label: MAIN_WINDOW_LABEL.to_string() }, "enter-capture-mode", ());
    let _ = w.set_focus();
    debug_log("open_capture_window ok");
    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_clipboard_manager::init())
        .plugin(tauri_plugin_fs::init())
        .manage(Mutex::new(None::<MainWindowSavedState>))
        .invoke_handler(tauri::generate_handler![
            capture_region,
            close_capture_window,
            get_debug_log_path,
            log_from_frontend,
        ])
        .setup(|app| {
            debug_log("app setup: logging to file");
            eprintln!("[mac-screenshot] debug log: {}", debug_log_path().display());
            // macOS 要求应用菜单顶层为 Submenu
            let sub = SubmenuBuilder::new(app, "Screenshot")
                .text("capture", "Capture Region")
                .text("quit", "Quit")
                .build()?;
            let menu = MenuBuilder::new(app).item(&sub).build()?;
            app.set_menu(menu).map_err(|e| e.to_string())?;

            app.on_menu_event(move |app_handle, event| {
                let id = event.id().as_ref();
                if id == "capture" {
                    if let Some(state) = app_handle.try_state::<Mutex<Option<MainWindowSavedState>>>() {
                        if let Err(e) = open_capture_window(app_handle, &state) {
                            eprintln!("open_capture_window: {}", e);
                        }
                    }
                } else if id == "quit" {
                    app_handle.exit(0);
                }
            });

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("run");
}
