const builtin = @import("builtin");
const std = @import("std");
const w = @import("../winsdk/winsdk.zig");
const assert = std.debug.assert;

pub inline fn vhr(hr: w.HRESULT) !void {
    if (hr != 0) {
        return error.HResult;
        //std.debug.panic("HRESULT function failed ({}).", .{hr});
    }
}

pub const GraphicsContext = struct {
    pub const max_num_buffered_frames = 2;
    pub const num_swapbuffers = 4;

    device: *w.ID3D12Device9,
    cmdqueue: *w.ID3D12CommandQueue,
    cmdlist: *w.ID3D12GraphicsCommandList6,
    cmdallocs: [max_num_buffered_frames]*w.ID3D12CommandAllocator,
    swapchain: *w.IDXGISwapChain3,
    swapbuffers: [num_swapbuffers]*w.ID3D12Resource,
    rtv_descriptor_heap: *w.ID3D12DescriptorHeap,
    viewport_width: u32,
    viewport_height: u32,
    frame_fence: *w.ID3D12Fence,
    frame_fence_event: w.HANDLE,
    frame_fence_counter: u64,
    frame_index: u32,
    back_buffer_index: u32,

    pub fn init(window: w.HWND) !GraphicsContext {
        const factory = blk: {
            var maybe_factory: ?*w.IDXGIFactory1 = null;
            try vhr(w.CreateDXGIFactory2(
                if (comptime builtin.mode == .Debug) w.DXGI_CREATE_FACTORY_DEBUG else 0,
                &w.IID_IDXGIFactory1,
                @ptrCast(*?*c_void, &maybe_factory),
            ));
            break :blk maybe_factory.?;
        };
        defer _ = factory.Release();

        if (comptime builtin.mode == .Debug) {
            var maybe_debug: ?*w.ID3D12Debug1 = null;
            _ = w.D3D12GetDebugInterface(&w.IID_ID3D12Debug1, @ptrCast(*?*c_void, &maybe_debug));
            if (maybe_debug) |debug| {
                debug.EnableDebugLayer();
                debug.SetEnableGPUBasedValidation(w.TRUE);
                _ = debug.Release();
            }
        }

        const device = blk: {
            var maybe_device: ?*w.ID3D12Device9 = null;
            try vhr(w.D3D12CreateDevice(null, ._11_1, &w.IID_ID3D12Device9, @ptrCast(*?*c_void, &maybe_device)));
            break :blk maybe_device.?;
        };
        errdefer _ = device.Release();

        var dheap = try DescriptorHeap.init(device, 1024, .RTV, .{});
        defer dheap.deinit();

        var mheap = try GpuMemoryHeap.init(device, 1024, .UPLOAD);
        defer mheap.deinit();

        const mem = mheap.allocate(100);
        _ = mem;

        const des = dheap.allocateDescriptors(10);
        _ = des;

        const cmdqueue = blk: {
            var maybe_cmdqueue: ?*w.ID3D12CommandQueue = null;
            try vhr(device.CreateCommandQueue(&.{
                .Type = .DIRECT,
                .Priority = @enumToInt(w.D3D12_COMMAND_QUEUE_PRIORITY.NORMAL),
                .Flags = .{},
                .NodeMask = 0,
            }, &w.IID_ID3D12CommandQueue, @ptrCast(*?*c_void, &maybe_cmdqueue)));
            break :blk maybe_cmdqueue.?;
        };
        errdefer _ = cmdqueue.Release();

        var rect: w.RECT = undefined;
        _ = w.GetClientRect(window, &rect);
        const viewport_width = @intCast(u32, rect.right - rect.left);
        const viewport_height = @intCast(u32, rect.bottom - rect.top);

        const swapchain = blk: {
            var maybe_swapchain: ?*w.IDXGISwapChain = null;
            try vhr(factory.CreateSwapChain(
                @ptrCast(*w.IUnknown, cmdqueue),
                &w.DXGI_SWAP_CHAIN_DESC{
                    .BufferDesc = .{
                        .Width = viewport_width,
                        .Height = viewport_height,
                        .RefreshRate = .{ .Numerator = 0, .Denominator = 0 },
                        .Format = .R8G8B8A8_UNORM,
                        .ScanlineOrdering = .UNSPECIFIED,
                        .Scaling = .UNSPECIFIED,
                    },
                    .SampleDesc = .{ .Count = 1, .Quality = 0 },
                    .BufferUsage = .{ .RENDER_TARGET_OUTPUT = true },
                    .BufferCount = num_swapbuffers,
                    .OutputWindow = window,
                    .Windowed = w.TRUE,
                    .SwapEffect = .FLIP_DISCARD,
                    .Flags = .{},
                },
                &maybe_swapchain,
            ));
            defer _ = maybe_swapchain.?.Release();
            var maybe_swapchain3: ?*w.IDXGISwapChain3 = null;
            try vhr(maybe_swapchain.?.QueryInterface(&w.IID_IDXGISwapChain3, @ptrCast(*?*c_void, &maybe_swapchain3)));
            break :blk maybe_swapchain3.?;
        };
        errdefer _ = swapchain.Release();

        const rtv_descriptor_heap = blk: {
            var maybe_heap: ?*w.ID3D12DescriptorHeap = null;
            try vhr(device.CreateDescriptorHeap(&.{
                .Type = .RTV,
                .NumDescriptors = num_swapbuffers,
                .Flags = .{},
                .NodeMask = 0,
            }, &w.IID_ID3D12DescriptorHeap, @ptrCast(*?*c_void, &maybe_heap)));
            break :blk maybe_heap.?;
        };
        errdefer _ = rtv_descriptor_heap.Release();

        const swapbuffers = blk: {
            var maybe_swapbuffers = [_]?*w.ID3D12Resource{null} ** num_swapbuffers;
            errdefer {
                for (maybe_swapbuffers) |swapbuffer| {
                    if (swapbuffer) |sb| _ = sb.Release();
                }
            }
            var descriptor = rtv_descriptor_heap.GetCPUDescriptorHandleForHeapStart();
            for (maybe_swapbuffers) |*swapbuffer, buffer_idx| {
                try vhr(swapchain.GetBuffer(
                    @intCast(u32, buffer_idx),
                    &w.IID_ID3D12Resource,
                    @ptrCast(*?*c_void, &swapbuffer.*),
                ));
                device.CreateRenderTargetView(swapbuffer.*, null, descriptor);
                descriptor.ptr += device.GetDescriptorHandleIncrementSize(.RTV);
            }
            var swapbuffers: [num_swapbuffers]*w.ID3D12Resource = undefined;
            for (maybe_swapbuffers) |swapbuffer, i| swapbuffers[i] = swapbuffer.?;
            break :blk swapbuffers;
        };
        errdefer {
            for (swapbuffers) |swapbuffer| _ = swapbuffer.Release();
        }

        const frame_fence = blk: {
            var maybe_frame_fence: ?*w.ID3D12Fence = null;
            try vhr(device.CreateFence(0, .{}, &w.IID_ID3D12Fence, @ptrCast(*?*c_void, &maybe_frame_fence)));
            break :blk maybe_frame_fence.?;
        };
        errdefer _ = frame_fence.Release();

        const frame_fence_event = w.CreateEventEx(null, "frame_fence_event", 0, w.EVENT_ALL_ACCESS) catch unreachable;

        const cmdallocs = blk: {
            var maybe_cmdallocs = [_]?*w.ID3D12CommandAllocator{null} ** max_num_buffered_frames;
            errdefer {
                for (maybe_cmdallocs) |cmdalloc| {
                    if (cmdalloc) |ca| _ = ca.Release();
                }
            }
            for (maybe_cmdallocs) |*cmdalloc| {
                try vhr(device.CreateCommandAllocator(
                    .DIRECT,
                    &w.IID_ID3D12CommandAllocator,
                    @ptrCast(*?*c_void, &cmdalloc.*),
                ));
            }
            var cmdallocs: [max_num_buffered_frames]*w.ID3D12CommandAllocator = undefined;
            for (maybe_cmdallocs) |cmdalloc, i| cmdallocs[i] = cmdalloc.?;
            break :blk cmdallocs;
        };
        errdefer {
            for (cmdallocs) |cmdalloc| _ = cmdalloc.Release();
        }

        const cmdlist = blk: {
            var maybe_cmdlist: ?*w.ID3D12GraphicsCommandList6 = null;
            try vhr(device.CreateCommandList(
                0,
                .DIRECT,
                cmdallocs[0],
                null,
                &w.IID_ID3D12GraphicsCommandList6,
                @ptrCast(*?*c_void, &maybe_cmdlist),
            ));
            break :blk maybe_cmdlist.?;
        };
        errdefer _ = cmdlist.Release();
        try vhr(cmdlist.Close());

        return GraphicsContext{
            .device = device,
            .cmdqueue = cmdqueue,
            .cmdlist = cmdlist,
            .cmdallocs = cmdallocs,
            .swapchain = swapchain,
            .swapbuffers = swapbuffers,
            .frame_fence = frame_fence,
            .frame_fence_event = frame_fence_event,
            .frame_fence_counter = 0,
            .rtv_descriptor_heap = rtv_descriptor_heap,
            .viewport_width = viewport_width,
            .viewport_height = viewport_height,
            .frame_index = 0,
            .back_buffer_index = swapchain.GetCurrentBackBufferIndex(),
        };
    }

    pub fn deinit(gr: *GraphicsContext) void {
        _ = gr.device.Release();
        _ = gr.cmdqueue.Release();
        _ = gr.swapchain.Release();
        _ = gr.frame_fence.Release();
        _ = gr.cmdlist.Release();
        _ = gr.rtv_descriptor_heap.Release();
        for (gr.cmdallocs) |cmdalloc| _ = cmdalloc.Release();
        for (gr.swapbuffers) |swapbuffer| _ = swapbuffer.Release();
        gr.* = undefined;
    }

    pub fn beginFrame(gr: *GraphicsContext) !void {
        const cmdalloc = gr.cmdallocs[gr.frame_index];
        try vhr(cmdalloc.Reset());
        try vhr(gr.cmdlist.Reset(cmdalloc, null));

        gr.cmdlist.RSSetViewports(1, &[_]w.D3D12_VIEWPORT{.{
            .TopLeftX = 0.0,
            .TopLeftY = 0.0,
            .Width = @intToFloat(f32, gr.viewport_width),
            .Height = @intToFloat(f32, gr.viewport_height),
            .MinDepth = 0.0,
            .MaxDepth = 1.0,
        }});
        gr.cmdlist.RSSetScissorRects(1, &[_]w.D3D12_RECT{.{
            .left = 0,
            .top = 0,
            .right = @intCast(c_long, gr.viewport_width),
            .bottom = @intCast(c_long, gr.viewport_height),
        }});
    }

    pub fn endFrame(gr: *GraphicsContext) !void {
        try vhr(gr.cmdlist.Close());
        gr.cmdqueue.ExecuteCommandLists(
            1,
            &[_]*w.ID3D12CommandList{@ptrCast(*w.ID3D12CommandList, gr.cmdlist)},
        );

        gr.frame_fence_counter += 1;
        try vhr(gr.swapchain.Present(0, .{}));
        try vhr(gr.cmdqueue.Signal(gr.frame_fence, gr.frame_fence_counter));

        const gpu_frame_counter = gr.frame_fence.GetCompletedValue();
        if ((gr.frame_fence_counter - gpu_frame_counter) >= max_num_buffered_frames) {
            try vhr(gr.frame_fence.SetEventOnCompletion(gpu_frame_counter + 1, gr.frame_fence_event));
            w.WaitForSingleObject(gr.frame_fence_event, w.INFINITE) catch unreachable;
        }

        gr.frame_index = (gr.frame_index + 1) % max_num_buffered_frames;
        gr.back_buffer_index = gr.swapchain.GetCurrentBackBufferIndex();
    }

    pub fn waitForGpu(gr: *GraphicsContext) !void {
        gr.frame_fence_counter += 1;
        try vhr(gr.cmdqueue.Signal(gr.frame_fence, gr.frame_fence_counter));
        try vhr(gr.frame_fence.SetEventOnCompletion(gr.frame_fence_counter, gr.frame_fence_event));
        w.WaitForSingleObject(gr.frame_fence_event, w.INFINITE) catch unreachable;
    }
};

const Descriptor = struct {
    cpu_handle: w.D3D12_CPU_DESCRIPTOR_HANDLE,
    gpu_handle: w.D3D12_GPU_DESCRIPTOR_HANDLE,
};

const DescriptorHeap = struct {
    heap: *w.ID3D12DescriptorHeap,
    base: Descriptor,
    size: u32,
    size_temp: u32,
    capacity: u32,
    descriptor_size: u32,

    fn init(
        device: *w.ID3D12Device9,
        capacity: u32,
        heap_type: w.D3D12_DESCRIPTOR_HEAP_TYPE,
        flags: w.D3D12_DESCRIPTOR_HEAP_FLAGS,
    ) !DescriptorHeap {
        assert(capacity > 0);
        const heap = blk: {
            var maybe_heap: ?*w.ID3D12DescriptorHeap = null;
            try vhr(device.CreateDescriptorHeap(&.{
                .Type = heap_type,
                .NumDescriptors = capacity,
                .Flags = flags,
                .NodeMask = 0,
            }, &w.IID_ID3D12DescriptorHeap, @ptrCast(*?*c_void, &maybe_heap)));
            break :blk maybe_heap.?;
        };
        return DescriptorHeap{
            .heap = heap,
            .base = .{
                .cpu_handle = heap.GetCPUDescriptorHandleForHeapStart(),
                .gpu_handle = blk: {
                    if (flags.SHADER_VISIBLE == true)
                        break :blk heap.GetGPUDescriptorHandleForHeapStart();
                    break :blk w.D3D12_GPU_DESCRIPTOR_HANDLE{ .ptr = 0 };
                },
            },
            .size = 0,
            .size_temp = 0,
            .capacity = capacity,
            .descriptor_size = device.GetDescriptorHandleIncrementSize(heap_type),
        };
    }

    fn deinit(dheap: *DescriptorHeap) void {
        _ = dheap.heap.Release();
        dheap.* = undefined;
    }

    fn allocateDescriptors(dheap: *DescriptorHeap, num_descriptors: u32) Descriptor {
        assert(num_descriptors > 0);
        assert((dheap.size + num_descriptors) < dheap.capacity);

        const cpu_handle = w.D3D12_CPU_DESCRIPTOR_HANDLE{
            .ptr = dheap.base.cpu_handle.ptr + dheap.size * dheap.descriptor_size,
        };
        const gpu_handle = w.D3D12_GPU_DESCRIPTOR_HANDLE{
            .ptr = blk: {
                if (dheap.base.gpu_handle.ptr != 0)
                    break :blk dheap.base.gpu_handle.ptr + dheap.size * dheap.descriptor_size;
                break :blk 0;
            },
        };

        dheap.size += num_descriptors;
        return .{ .cpu_handle = cpu_handle, .gpu_handle = gpu_handle };
    }
};

const GpuMemoryHeap = struct {
    const alloc_alignment: u32 = 512;

    heap: *w.ID3D12Resource,
    cpu_slice: []u8,
    gpu_base: w.D3D12_GPU_VIRTUAL_ADDRESS,
    size: u32,
    capacity: u32,

    fn init(device: *w.ID3D12Device9, capacity: u32, heap_type: w.D3D12_HEAP_TYPE) !GpuMemoryHeap {
        assert(capacity > 0);
        const resource = blk: {
            var maybe_resource: ?*w.ID3D12Resource = null;
            try vhr(device.CreateCommittedResource(
                &w.D3D12_HEAP_PROPERTIES{
                    .Type = heap_type,
                    .CPUPageProperty = .UNKNOWN,
                    .MemoryPoolPreference = .UNKNOWN,
                    .CreationNodeMask = 0,
                    .VisibleNodeMask = 0,
                },
                .{},
                &w.D3D12_RESOURCE_DESC.initBuffer(capacity),
                w.D3D12_RESOURCE_STATES.genericRead(),
                null,
                &w.IID_ID3D12Resource,
                @ptrCast(*?*c_void, &maybe_resource),
            ));
            break :blk maybe_resource.?;
        };
        errdefer _ = resource.Release();

        const cpu_base = blk: {
            var maybe_cpu_base: ?[*]u8 = null;
            try vhr(resource.Map(
                0,
                &w.D3D12_RANGE{ .Begin = 0, .End = 0 },
                @ptrCast(*?*c_void, &maybe_cpu_base),
            ));
            break :blk maybe_cpu_base.?;
        };
        return GpuMemoryHeap{
            .heap = resource,
            .cpu_slice = cpu_base[0..capacity],
            .gpu_base = resource.GetGPUVirtualAddress(),
            .size = 0,
            .capacity = capacity,
        };
    }

    fn deinit(mheap: *GpuMemoryHeap) void {
        _ = mheap.heap.Release();
        mheap.* = undefined;
    }

    fn allocate(
        mheap: *GpuMemoryHeap,
        size: u32,
    ) struct { cpu_slice: ?[]u8, gpu_base: ?w.D3D12_GPU_VIRTUAL_ADDRESS } {
        assert(size > 0);

        const aligned_size = (size + (alloc_alignment - 1)) & ~(alloc_alignment - 1);
        if ((mheap.size + aligned_size) >= mheap.capacity) {
            return .{ .cpu_slice = null, .gpu_base = null };
        }
        const cpu_slice = (mheap.cpu_slice.ptr + mheap.size)[0..size];
        const gpu_base = mheap.gpu_base + mheap.size;

        mheap.size += aligned_size;
        return .{ .cpu_slice = cpu_slice, .gpu_base = gpu_base };
    }
};