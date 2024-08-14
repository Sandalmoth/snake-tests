const std = @import("std");
const rl = @import("raylib");

const State = @import("ecs/main.zig").State;
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

    while (!rl.windowShouldClose()) {
        // Update
        nextState(true, true); // free the old, init the new

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.white);
    }

    // free the gamestate(s)
    for (0..states.len) |_| nextState(false, true);
}
