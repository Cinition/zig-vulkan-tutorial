const std = @import("std");
const vk = @import("vulkan");
const wio = @import("wio");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
pub const allocator = gpa.allocator();

const WIDTH: u32 = 800;
const HEIGHT: u32 = 600;

var window: wio.Window = undefined;

const HelloTriangleApplication = struct {
    pub fn run(self: *HelloTriangleApplication) !void {
        _ = self;
        try initWindow();
        initVulkan();
        try wio.run(mainLoop);
        cleanup();
    }

    fn initWindow() !void {
        try wio.init(allocator, .{});
        window = try wio.createWindow(.{
            .title = "Vulkan",
            .size = .{ .width = WIDTH, .height = HEIGHT },
        });
    }

    fn initVulkan() void {}

    fn mainLoop() !bool {
        while (window.getEvent()) |event| {
            switch (event) {
                .button_press => |button| {
                    if (button == .q or button == .escape) {
                        return false;
                    }
                },
                .close => {
                    return false;
                },
                else => {},
            }
        }

        return true;
    }

    fn cleanup() void {
        window.destroy();
        wio.deinit();
    }
};

pub fn main() !void {
    var app: HelloTriangleApplication = .{};
    try app.run();
}
