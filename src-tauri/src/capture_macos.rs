// macOS 原生截屏：全屏截取后裁剪指定区域，输出 PNG 字节

#[cfg(target_os = "macos")]
use core_graphics::display::CGDisplay;
#[cfg(target_os = "macos")]
use core_graphics::geometry::{CGPoint, CGRect, CGSize};
#[cfg(target_os = "macos")]
use core_graphics::image::CGImage;
#[cfg(target_os = "macos")]
use image::{ImageBuffer, ImageEncoder, RgbaImage};

#[derive(Debug)]
pub struct CaptureRect {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

#[cfg(target_os = "macos")]
/// 截取主显示器指定区域（坐标系：左上角为原点，单位 points），返回 PNG 字节。
pub fn capture_region_png(rect: CaptureRect) -> Result<Vec<u8>, String> {
    let display = CGDisplay::main();
    let bounds = display.bounds();
    // CG 坐标系 Y 向上，转为左下角原点
    let y_bottom = bounds.size.height - rect.y - rect.height;
    let origin = CGPoint::new(rect.x, y_bottom);
    let size = CGSize::new(rect.width, rect.height);
    let cg_rect = CGRect::new(&origin, &size);
    let cg_image = display
        .image_for_rect(cg_rect)
        .ok_or("CGDisplay::image_for_rect failed (need Screen Recording permission)")?;
    cgimage_to_png(&cg_image)
}

#[cfg(target_os = "macos")]
fn cgimage_to_png(cg_image: &CGImage) -> Result<Vec<u8>, String> {
    let width = cg_image.width() as u32;
    let height = cg_image.height() as u32;
    let bytes_per_row = cg_image.bytes_per_row();
    let bits_per_pixel = cg_image.bits_per_pixel();
    let bits_per_component = cg_image.bits_per_component();
    if bits_per_pixel != 32 || bits_per_component != 8 {
        return Err(format!(
            "unsupported pixel format: bpp={} bpc={}",
            bits_per_pixel, bits_per_component
        ));
    }
    let data = cg_image.data();
    let len = data.len() as usize;
    if len < (height as usize).saturating_mul(bytes_per_row) {
        return Err("CGImage data too short".to_string());
    }
    let data_ptr = data.bytes().as_ptr();
    // CGImage 多为 BGRA，转为 RGBA
    let mut buf: Vec<u8> = vec![0; (width * height * 4) as usize];
    for row in 0..height {
        let src_offset = (row as usize) * bytes_per_row;
        let dst_offset = (row as usize) * (width as usize) * 4;
        for col in 0..width {
            let s = src_offset + (col as usize) * 4;
            let d = dst_offset + (col as usize) * 4;
            if s + 4 <= len && d + 4 <= buf.len() {
                buf[d] = unsafe { *data_ptr.add(s + 2) };
                buf[d + 1] = unsafe { *data_ptr.add(s + 1) };
                buf[d + 2] = unsafe { *data_ptr.add(s) };
                buf[d + 3] = unsafe { *data_ptr.add(s + 3) };
            }
        }
    }
    let img: RgbaImage = ImageBuffer::from_raw(width, height, buf)
        .ok_or("ImageBuffer::from_raw failed")?;
    let mut out = Vec::new();
    let mut w = std::io::Cursor::new(&mut out);
    image::codecs::png::PngEncoder::new(&mut w)
        .write_image(
            img.as_raw(),
            width,
            height,
            image::ExtendedColorType::Rgba8,
        )
        .map_err(|e: image::ImageError| e.to_string())?;
    Ok(out)
}

#[cfg(not(target_os = "macos"))]
pub fn capture_region_png(_rect: CaptureRect) -> Result<Vec<u8>, String> {
    Err("macOS only".to_string())
}
