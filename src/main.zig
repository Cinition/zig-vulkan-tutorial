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

// Validation Layer array
const enableValidationLayers = if (builtin.mode == .Debug) true else false;
const validationLayers = &[_][*:0]const u8{"VK_LAYER_KHRONOS_validation"};

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

        if (enableValidationLayers and try checkValidationLayerSupport() == false) {
            std.log.err("validation layers requested, but not available!", .{});
            return error.InitializationFailed;
        }

        const appInfo = vk.ApplicationInfo{
            .p_application_name = "Hello Triangle",
            .application_version = vk.makeApiVersion(0, 1, 0, 0),
            .p_engine_name = "No Engine",
            .engine_version = vk.makeApiVersion(0, 1, 0, 0),
            .api_version = vk.API_VERSION_1_0,
        };

        var extensionCount: u32 = 0;
        _ = try vkb.enumerateInstanceExtensionProperties(null, &extensionCount, null);

        const extensionProperties = try allocator.alloc(vk.ExtensionProperties, extensionCount);
        _ = try vkb.enumerateInstanceExtensionProperties(null, &extensionCount, extensionProperties.ptr);

        std.log.info("Available extensions:\n", .{});
        for (extensionProperties) |name| {
            std.log.info("{s}", .{name.extension_name});
        }

        var createInfo = vk.InstanceCreateInfo{
            .p_application_info = &appInfo,
        };

        const extensions = try getRequiredExtensions();
        createInfo.enabled_extension_count = @intCast(extensions.items.len);
        createInfo.pp_enabled_extension_names = extensions.items.ptr;

        if (enableValidationLayers) {
            createInfo.enabled_layer_count = validationLayers.len;
            createInfo.pp_enabled_layer_names = validationLayers.ptr;
        } else {
            createInfo.enabled_layer_count = 0;
        }

        const vkbInstance = try vkb.createInstance(&createInfo, null);

        const vki = try allocator.create(InstanceDispatch);
        vki.* = try InstanceDispatch.load(vkbInstance, vkb.dispatch.vkGetInstanceProcAddr);
        instance = Instance.init(vkbInstance, vki);
    }

    fn getRequiredExtensions() !std.ArrayList([*:0]const u8) {
        var extensions = std.ArrayList([*:0]const u8).init(allocator);

        switch (builtin.os.tag) {
            .windows => {
                try extensions.append("VK_KHR_surface");
                try extensions.append("VK_KHR_win32_surface");
            },
            .macos => {
                try extensions.append("VK_KHR_surface");
                try extensions.append("VK_MVK_macos_surface");
            },
            .linux => switch (wio.backend.active) {
                .x11 => {
                    try extensions.append("VK_KHR_surface");
                    try extensions.append("VK_KHR_xlib_surface");
                },
                .wayland => {
                    try extensions.append("VK_KHR_surface");
                    try extensions.append("VK_KHR_wayland_surface");
                },
            },
            else => {},
        }

        if (enableValidationLayers) {
            try extensions.append("VK_EXT_debug_utils");
        }

        return extensions;
    }

    fn checkValidationLayerSupport() !bool {
        const vkb = try BaseDispatch.load(instanceProcAddress);

        var layerCount: u32 = 0;
        _ = try vkb.enumerateInstanceLayerProperties(&layerCount, null);

        const availableLayers = try allocator.alloc(vk.LayerProperties, layerCount);
        _ = try vkb.enumerateInstanceLayerProperties(&layerCount, availableLayers.ptr);

        for (validationLayers) |layerName| {
            var layerFound = false;
            for (availableLayers) |layerProperties| {
                if (std.mem.orderZ(u8, layerName, @ptrCast(&layerProperties.layer_name)) == .eq) {
                    layerFound = true;
                    return true;
                }
            }

            if (layerFound == false) {
                return false;
            }
        }

        return true;
    }

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
