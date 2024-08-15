const std = @import("std");
const rl = @import("raylib");

const State = @import("ecs/main.zig").State;
const Entity = @import("ecs/main.zig").Entity;
const RT = @import("pmek/rt.zig").RT;

const SnakePart = struct {
    x: f32,
    y: f32,
    life: u32,
};

const GameState = struct {
    snake_parts: State,
};

var states: [2]GameState = undefined;
var current_state: usize = 0;

fn nextState(init: bool, deinit: bool) void {
    const next_state = (current_state + 1) % states.len;
    if (!init) {
        // release our old copy
        State.deinit(&states[next_state].snake_parts);
    }
    if (!deinit) {
        // then make a copy of the current state, and move the ticker forward
        states[next_state].snake_parts = State.copy(&states[current_state].snake_parts, SnakePart);
    }
    current_state = next_state;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var frame_arena = std.heap.ArenaAllocator.init(alloc);
    defer frame_arena.deinit();
    const arena_alloc = frame_arena.allocator();

    var rt = RT.create(alloc);
    defer rt.destroy();

    const screenWidth = 640;
    const screenHeight = 360;

    rl.initWindow(screenWidth, screenHeight, "snaaaaaake");
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    states[current_state] = .{
        .snake_parts = State.init(alloc),
    };
    for (0..states.len - 1) |_| nextState(true, false);

    // states[current_state].snake_parts.set(SnakePart, 1, .{ .x = 16, .y = 16, .life = 10 });
    const stdout = std.io.getStdOut().writer();
    try rt.rep("(def head-x 40)", stdout); // NOTE supports only a single form per call
    try rt.rep("(def head-x 22)", stdout);
    try rt.rep("(def head-dir 0)", stdout);
    try rt.rep("(def snake-len 5)", stdout);

    const logic_tick: f32 = 500.0; // ms
    var lag: f32 = 0.0;
    var timer = try std.time.Timer.start();

    while (!rl.windowShouldClose()) {
        // Update
        lag += @as(f32, @floatFromInt(timer.lap())) * 1e-6;
        if (lag > logic_tick) {
            nextState(false, false); // free the old, init the new

            {
                // ECS will need a queue_free/queue_create, this is very inconvenient
                var to_destroy = std.ArrayList(Entity).init(arena_alloc);
                var it = states[current_state].snake_parts.iterator();
                while (it.next()) |e| {
                    const this = states[current_state].snake_parts.getPtr(SnakePart, e).?;
                    if (this.life == 0) to_destroy.append(e) catch unreachable;
                }
                for (to_destroy.items) |e| {
                    states[current_state].snake_parts.del(SnakePart, e);
                }
            }

            {
                var it = states[current_state].snake_parts.iterator();
                while (it.next()) |e| {
                    const this = states[current_state].snake_parts.getPtr(SnakePart, e).?;
                    this.life -= 1;
                }
            }

            {
                // TODO add this as a primitive function
                try rt.rep("(spawn-part head-x head-y snake-len)", stdout);
                try rt.rep(
                    \\ (if (= head-dir 0)
                    \\   (def head-x (+ head-x 1))
                    \\   (if (= head-dir 1)
                    \\     (def head-y (- head-y 1))
                    \\     (if (= head-dir 2)
                    \\       (def head-x (- head-x 1))
                    \\       (if (= head-dir 3)
                    \\         (def head-y (+ head-y 1))
                    \\       )
                    \\     )
                    \\   )
                    \\ )
                , stdout);
            }
            lag -= logic_tick;
        }

        // Draw
        rl.beginDrawing();
        const alpha = lag / logic_tick;
        const prev_state = (current_state + states.len - 1) % states.len;

        {
            var it = states[current_state].snake_parts.iterator();
            while (it.next()) |e| {
                const this = states[current_state].snake_parts.getPtr(SnakePart, e).?;
                std.debug.print("{}\n", .{this});
                const prev = states[prev_state].snake_parts.getPtr(SnakePart, e) orelse this;
                _ = prev;
                const size = if (this.life == 0) 8 * (1 - alpha) else 8;
                rl.drawRectangle(
                    @intFromFloat(this.x * 8 + 8 - size / 2),
                    @intFromFloat(this.y * 8 + 8 - size / 2),
                    @intFromFloat(size),
                    @intFromFloat(size),
                    rl.Color.red,
                );
            }
        }

        defer rl.endDrawing();

        rl.clearBackground(rl.Color.white);

        _ = frame_arena.reset(.retain_capacity);
    }

    // free the gamestate(s)
    for (0..states.len) |_| nextState(false, true);
}
