const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan");
const wio = @import("wio");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
pub const allocator = gpa.allocator();

const WIDTH: u32 = 800;
const HEIGHT: u32 = 600;

var window: wio.Window = undefined;

const apis: []const vk.ApiInfo = &.{
    vk.features.version_1_0,
    vk.extensions.khr_surface,
    vk.extensions.khr_swapchain,
};

// Wrappers for dispatch tables
const BaseDispatch = vk.BaseWrapper(apis);
const InstanceDispatch = vk.InstanceWrapper(apis);

// Proxy wrappers
const Instance = vk.InstanceProxy(apis);

// Dynamically loaded vulkan functions
var dynHandle: std.DynLib = undefined;
var instanceProcAddress: vk.PfnGetInstanceProcAddr = undefined;

const HelloTriangleApplication = struct {
    var instance: Instance = undefined;

    pub fn run(self: *HelloTriangleApplication) !void {
        _ = self;
        try initWindow();
        try initVulkan();
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

    fn initVulkan() !void {
        try createInstance();
    }

    fn createInstance() !void {
        const vkb = try BaseDispatch.load(instanceProcAddress);

        const appInfo = vk.ApplicationInfo{
            .p_application_name = "Hello Triangle",
            .application_version = vk.makeApiVersion(0, 1, 0, 0),
            .p_engine_name = "No Engine",
            .engine_version = vk.makeApiVersion(0, 1, 0, 0),
            .api_version = vk.API_VERSION_1_0,
        };

        const extensionNames: ?[*]const [*:0]const u8 = switch (builtin.os.tag) {
            .windows => &[_][*:0]const u8{ "VK_KHR_surface", "VK_KHR_win32_surface" },
            .macos => &[_][*:0]const u8{ "VK_KHR_surface", "VK_MVK_macos_surface" },
            .linux => switch (wio.backend.active) {
                .x11 => &[_][*:0]const u8{ "VK_KHR_surface", "VK_MVK_xlib_surface" },
                .wayland => [_][*:0]const u8{ "VK_KHR_surface", "VK_MVK_wayland_surface" },
            },
            else => &[_][]const u8{},
        };

        var extensionCount: u32 = 0;
        _ = try vkb.enumerateInstanceExtensionProperties(null, &extensionCount, null);

        const extensions = try allocator.alloc(vk.ExtensionProperties, extensionCount);
        _ = try vkb.enumerateInstanceExtensionProperties(null, &extensionCount, extensions.ptr);

        std.log.info("Available extensions:\n", .{});
        for (extensions) |name| {
            std.log.info("{s}", .{name.extension_name});
        }

        const createInfo = vk.InstanceCreateInfo{
            .p_application_info = &appInfo,
            .enabled_extension_count = 2,
            .pp_enabled_extension_names = extensionNames,
            .enabled_layer_count = 0,
        };

        const vkbInstance = try vkb.createInstance(&createInfo, null);

        const vki = try allocator.create(InstanceDispatch);
        vki.* = try InstanceDispatch.load(vkbInstance, vkb.dispatch.vkGetInstanceProcAddr);
        instance = Instance.init(vkbInstance, vki);
    }

    fn mainLoop() !bool {
        while (window.getEvent()) |event| {
            switch (event) {
                .close => {
                    return false;
                },
                else => {},
            }
        }

        return true;
    }

    fn cleanup() void {
        instance.destroyInstance(null);
        window.destroy();
        wio.deinit();
    }
};

fn loadDynamicFunctions() !void {
    const libraries = switch (builtin.os.tag) {
        .windows => &[_][]const u8{"vulkan-1.dll"},
        .macos => &[_][]const u8{ "libvulkan.dylib", "libvulkan.1.dylib", "libMoltenVK.dylib" },
        else => &[_][]const u8{ "libvulkan.so.1", "libvulkan.so" },
    };

    for (libraries) |lib| {
        var libHandle = try std.DynLib.open(lib);
        errdefer libHandle.close();

        dynHandle = libHandle;
        instanceProcAddress = libHandle.lookup(vk.PfnGetInstanceProcAddr, "vkGetInstanceProcAddr") orelse return error.InitializationFailed;

        return;
    }

    return error.InitializationFailed;
}

pub fn main() !void {
    try loadDynamicFunctions();
    var app: HelloTriangleApplication = .{};
    try app.run();
}
