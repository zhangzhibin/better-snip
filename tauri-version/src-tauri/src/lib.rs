// 极简 Mac 截图：菜单调起 → 主窗口全屏选区 → 截屏 → 剪贴板

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod capture_macos;

use capture_macos::{capture_region_png, main_display_rect, CaptureRect};
use image::{ImageEncoder, Rgba};
use serde::Deserialize;
use std::io::Write;
use std::sync::Mutex;
use tauri::menu::{MenuBuilder, MenuItemBuilder, SubmenuBuilder};
use tauri::tray::TrayIconBuilder;
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

/// 将前端 region 转为 CaptureRect（points，左上角原点）。前端坐标即逻辑像素，全屏窗口覆盖主屏，直接传递。
fn region_to_rect(region: &Region) -> (CaptureRect, bool) {
    let rect = CaptureRect {
        x: region.x,
        y: region.y,
        width: region.width,
        height: region.height,
    };
    let save_debug = std::env::var("MAC_SCREENSHOT_DEBUG").as_deref() == Ok("1");
    (rect, save_debug)
}

/// 将全屏图 + 红框(rect) 与裁切图保存到桌面
#[cfg(target_os = "macos")]
fn save_debug_overlay_and_crop(rect: &CaptureRect, png_bytes: &[u8]) {
    let desktop = std::env::var("HOME").ok().map(|h| std::path::PathBuf::from(h).join("Desktop"));
    let Some(desktop) = desktop else { return };
    let crop_path = desktop.join("debug_region_crop.png");
    let overlay_path = desktop.join("debug_region_overlay.png");
    let _ = std::fs::write(&crop_path, png_bytes);
    debug_log(&format!("debug crop saved: {}", crop_path.display()));
    let full = main_display_rect();
    if let Ok(full_png) = capture_region_png(full.clone()) {
        if let Ok(img) = image::load_from_memory(&full_png) {
            let mut rgba = img.to_rgba8();
            let (w, h) = (rgba.width() as f64, rgba.height() as f64);
            let scale_x = w / full.width;
            let scale_y = h / full.height;
            let left = (rect.x * scale_x).round() as i32;
            let top = (rect.y * scale_y).round() as i32;
            let rw = (rect.width * scale_x).round() as i32;
            let rh = (rect.height * scale_y).round() as i32;
            let stroke = 4i32;
            let red: [u8; 4] = [255, 0, 0, 255];
            let (wi, hi) = (rgba.width() as i32, rgba.height() as i32);
            let mut set = |x: i32, y: i32| {
                if x >= 0 && x < wi && y >= 0 && y < hi {
                    rgba.put_pixel(x as u32, y as u32, Rgba(red));
                }
            };
            for dx in 0..stroke {
                for py in top..(top + rh) {
                    set(left + dx, py);
                    set(left + rw - 1 - dx, py);
                }
            }
            for dy in 0..stroke {
                for px in left..(left + rw) {
                    set(px, top + dy);
                    set(px, top + rh - 1 - dy);
                }
            }
            let mut out = Vec::new();
            let mut cursor = std::io::Cursor::new(&mut out);
            if image::codecs::png::PngEncoder::new(&mut cursor)
                .write_image(
                    rgba.as_raw(),
                    rgba.width(),
                    rgba.height(),
                    image::ExtendedColorType::Rgba8,
                )
                .is_ok()
            {
                let _ = std::fs::write(&overlay_path, &out);
                debug_log(&format!("debug overlay saved: {}", overlay_path.display()));
            }
        }
    }
}

/// 前端选区完成后调用：截屏 → 写剪贴板 → 可选保存 → 主窗口退回 index
#[tauri::command]
async fn capture_region(
    app: tauri::AppHandle,
    state: State<'_, Mutex<Option<MainWindowSavedState>>>,
    region: Region,
    save_to_file: Option<String>,
) -> Result<(), String> {
    let msg = format!(
        "capture_region x={} y={} w={} h={}",
        region.x, region.y, region.width, region.height
    );
    debug_log(&msg);
    eprintln!("[capture_region] {}", msg);

    let (rect, save_debug) = region_to_rect(&region);
    // 等待前端已隐藏蒙版并给合成器一帧时间，再截屏
    let _ = tauri::async_runtime::spawn_blocking(|| std::thread::sleep(std::time::Duration::from_millis(80))).await;
    let png_bytes = capture_region_png(rect.clone()).map_err(|e| {
        let err_msg = format!("capture_region_png error: {}", e);
        debug_log(&err_msg);
        eprintln!("[capture_region] {}", err_msg);
        e
    })?;

    #[cfg(target_os = "macos")]
    if save_debug {
        save_debug_overlay_and_crop(&rect, &png_bytes);
    }

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

    // 快门一闪提示截图完成，再退出选区
    let _ = app.emit_to(
        tauri::EventTarget::WebviewWindow { label: MAIN_WINDOW_LABEL.to_string() },
        "show-flash",
        (),
    );
    let _ = tauri::async_runtime::spawn_blocking(|| std::thread::sleep(std::time::Duration::from_millis(350))).await;
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

/// 全屏截图：截屏 → 立即闪白 → 闪白期间写剪贴板/文件 → 隐藏窗口。
#[tauri::command]
async fn capture_fullscreen(app: tauri::AppHandle, save_to_file: Option<String>) -> Result<(), String> {
    let rect = main_display_rect();
    debug_log(&format!("capture_fullscreen rect {:?}", rect));
    let png_bytes = capture_region_png(rect).map_err(|e| {
        let msg = format!("capture_fullscreen error: {}", e);
        debug_log(&msg);
        e
    })?;

    // 截图完成后立即触发闪屏反馈（不等剪贴板写入）
    if let Some(w) = app.get_webview_window(MAIN_WINDOW_LABEL) {
        if let Ok(Some(mon)) = app.primary_monitor() {
            let sz = mon.size();
            let p = mon.position();
            let _ = w.set_size(tauri::PhysicalSize::new(sz.width, sz.height));
            let _ = w.set_position(tauri::PhysicalPosition::new(p.x, p.y));
        }
        let _ = w.show();
        let _ = tauri::async_runtime::spawn_blocking(|| std::thread::sleep(std::time::Duration::from_millis(50))).await;
        let _ = app.emit_to(
            tauri::EventTarget::WebviewWindow { label: MAIN_WINDOW_LABEL.to_string() },
            "show-flash",
            (),
        );
    }

    // 闪屏动画期间并行写入剪贴板和文件
    #[cfg(target_os = "macos")]
    {
        let png_clone = png_bytes.clone();
        let _ = tauri::async_runtime::spawn_blocking(move || {
            let img = image::load_from_memory(&png_clone).ok()?;
            let rgba = img.to_rgba8();
            let mut clipboard = arboard::Clipboard::new().ok()?;
            clipboard
                .set_image(arboard::ImageData {
                    width: rgba.width() as usize,
                    height: rgba.height() as usize,
                    bytes: rgba.into_raw().into(),
                })
                .ok()
        })
        .await;
    }
    if let Some(path) = save_to_file {
        if !path.is_empty() {
            let _ = tauri::async_runtime::spawn_blocking(move || std::fs::write(&path, &png_bytes)).await;
        }
    }

    // 等闪屏动画完成后隐藏窗口
    let _ = tauri::async_runtime::spawn_blocking(|| std::thread::sleep(std::time::Duration::from_millis(450))).await;
    if let Some(w) = app.get_webview_window(MAIN_WINDOW_LABEL) {
        let _ = w.hide();
    }
    debug_log("capture_fullscreen ok");
    Ok(())
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
    // 不显示主窗口，仅通过托盘菜单操作
    let _ = w.hide();
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
    // 使用物理尺寸与位置，使窗口覆盖整个主屏，支持任意位置选区（不再用逻辑尺寸误传导致区域受限）
    if let Ok(Some(mon)) = app.primary_monitor() {
        let sz = mon.size();
        let p = mon.position();
        let _ = w.set_size(tauri::PhysicalSize::new(sz.width, sz.height));
        let _ = w.set_position(tauri::PhysicalPosition::new(p.x, p.y));
    }
    let _ = w.show();
    // 延迟再切视图，确保窗口已完成 resize，否则后续截图时前端坐标仍按旧尺寸导致选区错位
    let app_clone = app.clone();
    let label = MAIN_WINDOW_LABEL.to_string();
    let js = r#"
      (function(){
        var m=document.getElementById('main-view');
        var c=document.getElementById('capture-view');
        if(m){m.style.display='none';}
        if(c){c.classList.add('active');}
        document.body.style.background='transparent';
        if(window.__enterCaptureMode){window.__enterCaptureMode();}
      })();
    "#.to_string();
    std::thread::spawn(move || {
        std::thread::sleep(std::time::Duration::from_millis(120));
        let app_main = app_clone.clone();
        let _ = app_clone.run_on_main_thread(move || {
            if let Some(w) = app_main.get_webview_window(&label) {
                let _ = w.eval(&js);
                let _ = app_main.emit_to(
                    tauri::EventTarget::WebviewWindow { label: label.clone() },
                    "enter-capture-mode",
                    (),
                );
                let _ = w.set_focus();
            }
        });
    });
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
            capture_fullscreen,
            close_capture_window,
            get_debug_log_path,
            log_from_frontend,
        ])
        .setup(|app| {
            debug_log("app setup: logging to file");
            eprintln!("[mac-screenshot] debug log: {}", debug_log_path().display());

            // 显式设置主窗口图标（开发模式下 default_window_icon 可能因工作目录未解析到图标，需从可执行路径推算）
            if let Some(w) = app.get_webview_window(MAIN_WINDOW_LABEL) {
                let icon_loaded = app
                    .default_window_icon()
                    .and_then(|img| w.set_icon(img.clone()).ok())
                    .is_some();
                if !icon_loaded {
                    #[cfg(target_os = "macos")]
                    if let Ok(exe) = std::env::current_exe() {
                        // 开发时 exe 在 target/debug/，图标在 src-tauri/icons/
                        let icons_dir = exe
                            .parent()
                            .and_then(|p| p.parent())
                            .and_then(|p| p.parent())
                            .map(|p| p.join("src-tauri").join("icons"));
                        if let Some(dir) = icons_dir {
                            for name in ["128x128.png", "32x32.png", "icon.png"] {
                                let path = dir.join(name);
                                if path.exists() {
                                    if let Ok(img) = tauri::image::Image::from_path(&path) {
                                        let _ = w.set_icon(img);
                                        debug_log(&format!("window icon set from {:?}", path));
                                    }
                                    break;
                                }
                            }
                        }
                    }
                }
            }
            // macOS 要求应用菜单顶层为 Submenu
            let sub = SubmenuBuilder::new(app, "Screenshot")
                .text("capture_full", "Capture Full Screen")
                .text("capture", "Capture Region")
                .text("quit", "Quit")
                .build()?;
            let menu = MenuBuilder::new(app).item(&sub).build()?;
            app.set_menu(menu).map_err(|e| e.to_string())?;

            app.on_menu_event(move |app_handle, event| {
                let id = event.id().as_ref();
                if id == "capture_full" {
                    let app = app_handle.clone();
                    tauri::async_runtime::spawn(async move {
                        if let Err(e) = capture_fullscreen(app, None).await {
                            eprintln!("capture_fullscreen: {}", e);
                        }
                    });
                } else if id == "capture" {
                    if let Some(state) = app_handle.try_state::<Mutex<Option<MainWindowSavedState>>>() {
                        if let Err(e) = open_capture_window(app_handle, &state) {
                            eprintln!("open_capture_window: {}", e);
                        }
                    }
                } else if id == "quit" {
                    app_handle.exit(0);
                }
            });

            // 系统托盘图标（菜单栏右侧），仅通过托盘菜单操作，不显示 Dock 图标
            let tray_full = MenuItemBuilder::with_id("tray_full", "Capture Full Screen").build(app)?;
            let tray_capture = MenuItemBuilder::with_id("tray_capture", "Capture Region").build(app)?;
            let tray_quit = MenuItemBuilder::with_id("tray_quit", "Quit").build(app)?;
            let tray_menu = MenuBuilder::new(app)
                .items(&[&tray_full, &tray_capture, &tray_quit])
                .build()?;
            let tray_icon = app
                .default_window_icon()
                .cloned()
                .or_else(|| {
                    #[cfg(target_os = "macos")]
                    {
                        std::env::current_exe().ok().and_then(|exe| {
                            let icons_dir = exe
                                .parent()
                                .and_then(|p| p.parent())
                                .and_then(|p| p.parent())
                                .map(|p| p.join("src-tauri").join("icons"));
                            icons_dir.and_then(|dir| {
                                ["32x32.png", "128x128.png", "icon.png"]
                                    .iter()
                                    .find_map(|name| {
                                        let path = dir.join(name);
                                        (path.exists())
                                            .then(|| tauri::image::Image::from_path(&path).ok())
                                            .flatten()
                                    })
                            })
                        })
                    }
                    #[cfg(not(target_os = "macos"))]
                    None
                })
                .or_else(|| {
                    // 兜底：编译期嵌入图标，确保任何环境下都有托盘图标
                    tauri::image::Image::from_bytes(include_bytes!("../icons/32x32.png")).ok()
                });
            let mut tray_builder = TrayIconBuilder::new()
                .menu(&tray_menu)
                .tooltip("Simple Snip");
            if let Some(ref icon) = tray_icon {
                tray_builder = tray_builder.icon(icon.clone());
            }
            let _tray = tray_builder
                .on_menu_event(move |app_handle, event| {
                    match event.id().as_ref() {
                        "tray_full" => {
                            let app = app_handle.clone();
                            tauri::async_runtime::spawn(async move {
                                if let Err(e) = capture_fullscreen(app, None).await {
                                    eprintln!("tray capture_fullscreen: {}", e);
                                }
                            });
                        }
                        "tray_capture" => {
                            if let Some(state) =
                                app_handle.try_state::<Mutex<Option<MainWindowSavedState>>>()
                            {
                                if let Err(e) = open_capture_window(app_handle, &state) {
                                    eprintln!("tray open_capture_window: {}", e);
                                }
                            }
                        }
                        "tray_quit" => app_handle.exit(0),
                        _ => {}
                    }
                })
                .build(app)?;

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("run");
}
