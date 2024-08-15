const std = @import("std");
const rl = @import("raylib");

const State = @import("ecs/main.zig").State;
const Entity = @import("ecs/main.zig").Entity;

const RT = @import("pmek/rt.zig").RT;
const GCA = @import("pmek/gc.zig").GCAllocator;
const Object = @import("pmek/object.zig").Object;
const debugPrint = @import("pmek/object.zig").debugPrint;
const champ = @import("pmek/object_champ.zig");

const SnakePart = struct {
    x: f32,
    y: f32,
    life: u32,
};

const GameState = struct {
    snake_parts: State,
};

var entity_counter: u64 = 1;
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

fn primitiveSpawnPart(gca: *GCA, objargs: ?*Object) ?*Object {
    debugPrint(objargs);
    _ = gca;
    std.debug.assert(objargs != null);
    var cons = objargs.?.as(.cons);
    const x = cons.car.?.as(.real).val;
    cons = cons.cdr.?.as(.cons);
    const y = cons.car.?.as(.real).val;
    cons = cons.cdr.?.as(.cons);
    const len = cons.car.?.as(.real).val;
    std.debug.assert(cons.cdr == null);

    const e = entity_counter;
    entity_counter += 1;
    states[current_state].snake_parts.set(SnakePart, e, .{
        .x = @floatCast(x),
        .y = @floatCast(y),
        .life = @intFromFloat(len),
    });
    std.debug.print("{} {} {}\n", .{ x, y, len });

    return null;
}

fn primitiveDrawFood(gca: *GCA, objargs: ?*Object) ?*Object {
    _ = gca;
    std.debug.assert(objargs != null);
    var cons = objargs.?.as(.cons);
    const x = cons.car.?.as(.real).val;
    cons = cons.cdr.?.as(.cons);
    const y = cons.car.?.as(.real).val;
    std.debug.assert(cons.cdr == null);

    const size = 6;
    rl.drawRectangle(
        @intFromFloat(x * 8 + 8 - size / 2),
        @intFromFloat(y * 8 + 8 - size / 2),
        @intFromFloat(size),
        @intFromFloat(size),
        rl.Color.sky_blue,
    );
    return null;
}

fn primitiveHasSnake(gca: *GCA, objargs: ?*Object) ?*Object {
    std.debug.assert(objargs != null);
    var cons = objargs.?.as(.cons);
    const x = cons.car.?.as(.real).val;
    cons = cons.cdr.?.as(.cons);
    const y = cons.car.?.as(.real).val;
    std.debug.assert(cons.cdr == null);

    const prev_state = (current_state + states.len - 1) % states.len;
    var it = states[prev_state].snake_parts.iterator();
    while (it.next()) |e| {
        const sp = states[prev_state].snake_parts.getPtr(SnakePart, e).?;
        if (std.math.approxEqAbs(f32, sp.x, @floatCast(x), 0.1) and
            std.math.approxEqAbs(f32, sp.y, @floatCast(y), 0.1))
        {
            std.debug.print("{} {} {} {}\n", .{ sp.x, sp.y, x, y });
            return gca.newTrue();
        }
    }
    return gca.newFalse();
}

var rng_state: u32 = 0;
fn primitiveRNG(gca: *GCA, objargs: ?*Object) ?*Object {
    if (rng_state == 0) {
        rng_state = @intCast(@as(u64, @intCast(std.time.microTimestamp())) & 0xffffffff);
        rng_state *%= 3633863399;
    }

    std.debug.assert(objargs != null);
    var cons = objargs.?.as(.cons);
    const ub = cons.car.?.as(.real).val;
    std.debug.assert(cons.cdr == null);

    var z: u64 = rng_state;
    z *%= z;
    rng_state = @intCast((z >> 16) & 0xffffffff);
    const a = (rng_state *% 3495318667) % @as(u32, @intFromFloat(ub));
    return gca.newReal(@floatFromInt(a));
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
    rt.addPrimitive("spawn-part", primitiveSpawnPart);
    rt.addPrimitive("has-snake", primitiveHasSnake);
    rt.addPrimitive("draw-food", primitiveDrawFood);
    rt.addPrimitive("randint-less-than", primitiveRNG);
    const stdout = std.io.getStdOut().writer();
    try rt.rep("(def head-x 40)", stdout); // NOTE supports only a single form per call
    try rt.rep("(def head-y 22)", stdout);
    try rt.rep("(def head-dir 0)", stdout);
    try rt.rep("(def snake-len 5)", stdout);
    try rt.rep("(def food-x (randint-less-than 80))", stdout);
    try rt.rep("(def food-y (randint-less-than 45))", stdout);

    const reset_env = rt.env;

    var logic_tick: f32 = 250.0; // ms
    var lag: f32 = 0.0;
    var timer = try std.time.Timer.start();

    while (!rl.windowShouldClose()) {
        if (rl.isKeyDown(.key_right)) try rt.rep("(def head-dir 0)", stdout);
        if (rl.isKeyDown(.key_up)) try rt.rep("(def head-dir 1)", stdout);
        if (rl.isKeyDown(.key_left)) try rt.rep("(def head-dir 2)", stdout);
        if (rl.isKeyDown(.key_down)) try rt.rep("(def head-dir 3)", stdout);

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

                try rt.rep("(def dead (has-snake head-x head-y))", stdout);
                if (champ.get(rt.env, rt.gca.newSymbol("dead")).?.kind == ._true) {
                    // strictly speaking, for full reversibility
                    // the random number generator and the logic ticki shoudl be part of
                    // either the ecs or the scripting state
                    // we lost, reset
                    rt.env = reset_env;
                    // more fun if we rerandomize the food
                    try rt.rep("(def food-x (randint-less-than 80))", stdout);
                    try rt.rep("(def food-y (randint-less-than 45))", stdout);
                    for (0..states.len) |_| nextState(false, true);
                    states[current_state] = .{
                        .snake_parts = State.init(alloc),
                    };
                    for (0..states.len - 1) |_| nextState(true, false);
                    logic_tick = 250;
                    continue;
                }

                try rt.rep("(spawn-part head-x head-y snake-len)", stdout);

                // oops, we should have implemented do, but this works
                try rt.rep("(def eating (has-snake food-x food-y))", stdout);
                debugPrint(rt.env);
                try rt.rep("(if eating (def food-x (randint-less-than 80)))", stdout);
                try rt.rep("(if eating (def food-y (randint-less-than 45)))", stdout);
                try rt.rep("(if eating (def snake-len (+ snake-len 1)))", stdout);
                // and we should probably have a utility for this or something
                if (champ.get(rt.env, rt.gca.newSymbol("eating")).?.kind == ._true) {
                    logic_tick *= 0.95;
                }
                try rt.rep("(def eating false)", stdout);
            }
            lag -= logic_tick;
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();
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
        try rt.rep("(draw-food food-x food-y)", stdout);

        rl.clearBackground(rl.Color.white);

        _ = frame_arena.reset(.retain_capacity);

        // garbage collector
        if (rt.gca.shouldTrace()) {
            rt.gca.traceRoot(rt.env);
            rt.gca.traceRoot(reset_env);
            rt.gca.endTrace();
        }
    }

    // free the gamestate(s)
    for (0..states.len) |_| nextState(false, true);
}
