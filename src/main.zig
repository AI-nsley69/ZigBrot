const std = @import("std");
const zimg = @import("zigimg/zigimg.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = &gpa.allocator;

    const input = std.io.getStdIn().reader();
    const output = std.io.getStdOut().writer();

    const width: u64 = 1920;
    const height: u64 = 1080;

    const threads_to_use = while (true) {
        try output.writeAll("Threads to use : ");
        const inputted_cores = try input.readUntilDelimiterAlloc(allocator, '\n', 2);
        defer allocator.free(inputted_cores);
        const max_cores = try std.Thread.cpuCount();
        const cores_int = std.fmt.parseInt(u8, inputted_cores, 10) catch continue;
        if (cores_int >= 1 and cores_int <= max_cores) break cores_int;
    } else unreachable;

    const frames_to_render = while (true) {
        try output.writeAll("Frames to render : ");
        const inputted_frames = try input.readUntilDelimiterAlloc(allocator, '\n', 16);
        defer allocator.free(inputted_frames);
        const frames_int = std.fmt.parseInt(u32, inputted_frames, 10) catch continue;
        if (frames_int > 0 and frames_int <= std.math.maxInt(u32)) break frames_int;
    } else unreachable;

    const timer = try std.time.Timer.start();

    try output.writeAll("Creating your mandelbrot set..\n");
    const img = try zimg.Image.create(allocator, width, height, .Rgb24, .Ppm);
    defer img.deinit();

    const img_out_buf = try allocator.alloc(u8, width * height * 3 + 1024);
    defer allocator.free(img_out_buf);

    var scale: f64 = 1;
    var counter: u4 = 0;
    while (counter < frames_to_render) : (counter += 1) {
        var buf: [20]u8 = undefined;
        const filename = std.fmt.bufPrint(&buf, "mandelbrot{}.ppm", .{counter}) catch unreachable;

        var threads = try allocator.alloc(*std.Thread, threads_to_use);
        defer allocator.free(threads);

        const section_height = (height - 1) / threads_to_use + 1;
        var i: u64 = 0;
        while (i * section_height < height) : (i += 1) {
            const thread_config = ThreadConfig{
                .allocator = allocator,
                .img = img,
                .scale = scale,
                .width = width,
                .min_y = i * section_height,
                .max_y = std.math.min((i + 1) * section_height, height),
            };
            threads[i] = try std.Thread.spawn(mandelThread, thread_config);
        }
        std.debug.assert(i == threads.len);
        for (threads) |thr| {
            thr.wait();
        }
        const render_time = timer.read();
        // std.debug.print("Rendered 1 frame in  {}\n", .{std.fmt.fmtDuration(render_time)});

        scale -= 0.05;
        const data = try img.writeToMemory(img_out_buf, .Ppm, .{ .ppm = .{ .binary = true } });
        const f = try std.fs.cwd().createFile(filename, .{});
        defer f.close();
        defer f.close();
    }
    const elapsed_time = timer.read();
    std.debug.print("{} to render & write {} frames.\n", .{ std.fmt.fmtDuration(elapsed_time), frames_to_render });
}

pub fn mandelThread(thread_config: ThreadConfig) !void {
    try mandelbrot(thread_config.allocator, thread_config.img, thread_config.scale, thread_config.width, thread_config.min_y, thread_config.max_y);
}

pub fn mandelbrot(allocator: *std.mem.Allocator, img: zimg.Image, scale: f64, width: u64, min_y: u64, max_y: u64) !void {
    const palette = [16]zimg.color.Rgb24{
        zimg.color.Rgb24.initRGB(0x2E, 0x34, 0x40),
        zimg.color.Rgb24.initRGB(0x3B, 0x42, 0x52),
        zimg.color.Rgb24.initRGB(0x43, 0x4C, 0x5E),
        zimg.color.Rgb24.initRGB(0x4C, 0x56, 0x6A),
        zimg.color.Rgb24.initRGB(0xD8, 0xDE, 0xE9),
        zimg.color.Rgb24.initRGB(0xE5, 0xE9, 0xF0),
        zimg.color.Rgb24.initRGB(0xEC, 0xEF, 0xF4),
        zimg.color.Rgb24.initRGB(0x8F, 0xBC, 0xBB),
        zimg.color.Rgb24.initRGB(0x88, 0xC0, 0xD0),
        zimg.color.Rgb24.initRGB(0x81, 0xA1, 0xC1),
        zimg.color.Rgb24.initRGB(0x5E, 0x81, 0xAC),
        zimg.color.Rgb24.initRGB(0xBF, 0x61, 0x6A),
        zimg.color.Rgb24.initRGB(0xD0, 0x87, 0x70),
        zimg.color.Rgb24.initRGB(0xEB, 0xCB, 0x8B),
        zimg.color.Rgb24.initRGB(0xA3, 0xBE, 0x8C),
        zimg.color.Rgb24.initRGB(0xB4, 0x8E, 0xAD),
    };
    const pix = img.pixels.?.Rgb24;
    const x_offset = 0.551302083333;
    const y_offset = 0.625925925926;
    var y_pixel = min_y;
    while (y_pixel < max_y) : (y_pixel += 1) {
        var x_pixel: u64 = 0;
        while (x_pixel < width) : (x_pixel += 1) {
            var x0 = 3.5 * @intToFloat(f64, x_pixel) / @intToFloat(f64, 1920) - 2.5;
            var y0 = 2 * @intToFloat(f64, y_pixel) / @intToFloat(f64, 1080) - 1;
            x0 += x_offset;
            y0 += y_offset;
            x0 *= scale;
            y0 *= scale;
            x0 -= x_offset;
            y0 -= y_offset;

            var x: f64 = 0.0;
            var y: f64 = 0.0;
            var iteration: u32 = 0;
            const max_iterations: u32 = 1000;
            while (x * x + y * y <= 2 * 2 and iteration < max_iterations) {
                const tmp = x * x - y * y + x0;
                y = 2 * x * y + y0;
                x = tmp;
                iteration += 1;
            }
            const colour = @floatToInt(u32, (15 / 3) * std.math.log10(@intToFloat(f64, iteration)));
            pix[y_pixel * width + x_pixel] = palette[colour];
        }
    }
}

const ThreadConfig = struct {
    allocator: *std.mem.Allocator,
    img: zimg.Image,
    scale: f64,
    width: u64,
    min_y: u64,
    max_y: u64,
};
