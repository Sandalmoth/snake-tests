const std = @import("std");

const rl = @import("raylib");
const ecs = @import("scethy");

const SnakePart = struct {
    x: f32,
    y: f32,
    life: u32,
};

const Food = struct {
    x: f32,
    y: f32,
};

const Behaviour = struct {
    ctx: *anyopaque,
    vtable: VTable,

    const VTable = struct {
        update: *const fn (*anyopaque, *anyopaque) void,
    };

    fn update(b: Behaviour, payload: *anyopaque) void {
        b.vtable.update(b.ctx, payload);
    }
};

const SnakeHead = struct {
    x: f32,
    y: f32,
    dir: u8,
    len: u32,
    e_food: ecs.Entity,
    rng: std.Random.DefaultPrng,

    fn update(ctx: *anyopaque, payload: *anyopaque) void {
        const head: *SnakeHead = @alignCast(@ptrCast(ctx));

        // doesn't feel very good with the slow ticks
        // we shoudl really buffer the input if the framerate is slower than the update rate
        // but this is just because we're mis/ab-using raylib
        if (rl.isKeyDown(.key_right) and head.dir != 2) head.dir = 0;
        if (rl.isKeyDown(.key_up) and head.dir != 3) head.dir = 1;
        if (rl.isKeyDown(.key_left) and head.dir != 0) head.dir = 2;
        if (rl.isKeyDown(.key_down) and head.dir != 1) head.dir = 3;

        switch (head.dir) {
            0 => head.x += 1,
            1 => head.y -= 1,
            2 => head.x -= 1,
            3 => head.y += 1,
            else => unreachable,
        }

        if (hasSnake(head.x, head.y)) {
            should_reset = true;
            return;
        }

        // for a multithreading we really should constrain a component to only modifying itself...
        const food = this().getPtr(.food, head.e_food).?;
        if (hasSnake(food.x, food.y)) {
            head.len += 1;
            food.x = @floatFromInt(head.rng.random().intRangeLessThan(u32, 1, 79));
            food.y = @floatFromInt(head.rng.random().intRangeLessThan(u32, 1, 44));
            logic_tick *= 0.95;
        }
        // example of passing in some shared data to work on
        const create_queue: *std.ArrayList(SnakePart) = @alignCast(@ptrCast(payload));
        create_queue.append(.{ .x = head.x, .y = head.y, .life = head.len }) catch unreachable;
    }

    // implementations of an interface must define a public function called interface
    // that returns an instance of the interface
    pub fn interface(head: *SnakeHead) Behaviour {
        return .{ .ctx = @alignCast(@ptrCast(head)), .vtable = .{
            .update = update,
        } };
    }
};

const Table = ecs.Table(.{
    .snake_part = .{ .type = SnakePart },
    .food = .{ .type = Food },
    .behaviour = .{ .type = Behaviour, .interface = true },
});

var logic_tick: f32 = 250.0; // ms
var should_reset = false;
var states: [10]*Table = undefined;
var current_state: usize = 0;

fn nextState(init: bool, deinit: bool) void {
    const next_state = (current_state + 1) % states.len;
    if (!init) {
        // release our old copy
        states[next_state].deinit();
    }
    if (!deinit) {
        // then make a copy of the current state, and move the ticker forward
        states[next_state] = states[current_state].copy();

        std.debug.print("current_state: {}\nnext_state: {}\n", .{ current_state, next_state });
        {
            var it = states[current_state].entities.entityIterator();
            while (it.next()) |e| std.debug.print("{}:{} ", .{ e, states[current_state].exists(e) });
            std.debug.print("\n", .{});
        }
        {
            var it = states[next_state].entities.entityIterator();
            while (it.next()) |e| std.debug.print("{}:{} ", .{ e, states[next_state].exists(e) });
            std.debug.print("\n", .{});
        }

        // make sure the copy works?
        {
            var it = states[next_state].entities.entityIterator();
            while (it.next()) |e| {
                std.debug.assert(states[current_state].exists(e));
                if (states[next_state].has(.snake_part, e))
                    std.debug.assert(states[current_state].has(.snake_part, e));
                if (states[next_state].has(.food, e))
                    std.debug.assert(states[current_state].has(.food, e));
                if (states[next_state].has(.behaviour, e))
                    std.debug.assert(states[current_state].has(.behaviour, e));
            }
        }
        {
            var it = states[current_state].entities.entityIterator();
            while (it.next()) |e| {
                std.debug.assert(states[next_state].exists(e));
                if (states[current_state].has(.snake_part, e))
                    std.debug.assert(states[next_state].has(.snake_part, e));
                if (states[current_state].has(.food, e))
                    std.debug.assert(states[next_state].has(.food, e));
                if (states[current_state].has(.behaviour, e))
                    std.debug.assert(states[next_state].has(.behaviour, e));
            }
        }
    }
    current_state = next_state;
}

fn this() *Table {
    return states[current_state];
}

// fn prev() *Table {
//     return states[(current_state + states.len - 1) % states.len];
// }

fn hasSnake(x: f32, y: f32) bool {
    var it = this().query(&.{.snake_part}, &.{});
    while (it.next()) |e| {
        const part = this().getPtrConst(.snake_part, e).?;
        if (std.math.approxEqAbs(f32, part.x, @floatCast(x), 0.1) and
            std.math.approxEqAbs(f32, part.y, @floatCast(y), 0.1))
        {
            return true;
        }
    }
    return false;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var frame_arena = std.heap.ArenaAllocator.init(alloc);
    defer frame_arena.deinit();
    const arena_alloc = frame_arena.allocator();

    var pool = ecs.Pool.init(std.heap.page_allocator);
    defer pool.deinit();

    const screenWidth = 640;
    const screenHeight = 360;

    rl.initWindow(screenWidth, screenHeight, "snaaaaaake");
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    states[current_state] = Table.init(alloc, &pool);

    {
        const e_food = this().create();
        this().incl(.food, e_food, .{ .x = 41, .y = 22 }, .dynamic);
        const e_head = this().create();
        this().inclInterface(.behaviour, e_head, SnakeHead, .{
            .x = 40,
            .y = 22,
            .dir = 0,
            .len = 4,
            .e_food = e_food,
            // for a more fun game, should be a global and not get reset...
            .rng = std.Random.DefaultPrng.init(@bitCast(std.time.microTimestamp())),
        });
        std.debug.print("e_food: {}\n", .{e_food});
        std.debug.print("e_head: {}\n", .{e_head});
    }

    // fill the entire state buffer with the first state
    for (0..states.len) |_| nextState(true, false);

    const reset = this().copy();
    defer reset.deinit();

    var lag: f32 = 0.0;
    var timer = try std.time.Timer.start();

    var reset_timer: usize = 11;

    while (!rl.windowShouldClose()) {
        _ = frame_arena.reset(.retain_capacity);
        std.debug.print("1: {}\n", .{current_state});

        // revert to the oldest saved state in the chain (mostly for demonstration)
        if (reset_timer == 0 and rl.isKeyPressed(.key_space)) {
            current_state = (current_state + 1) % states.len;
            for (0..states.len - 1) |_| nextState(false, false);
            std.debug.print("###: {}\n", .{current_state});
            reset_timer = 11;
        }

        // Update
        lag += @as(f32, @floatFromInt(timer.lap())) * 1e-6;
        while (lag > logic_tick) {
            nextState(false, false); // free the old, init the new

            {
                // ECS will need a queue_free/queue_create, this is very inconvenient
                var to_destroy = std.ArrayList(ecs.Entity).init(arena_alloc);
                var it = this().query(&.{.snake_part}, &.{});
                while (it.next()) |e| {
                    const part = this().getPtr(.snake_part, e).?;
                    if (part.life == 0) {
                        to_destroy.append(e) catch unreachable;
                    } else {
                        part.life -= 1;
                    }
                }
                for (to_destroy.items) |e| {
                    std.debug.print("{}\n", .{e});
                    this().destroy(e);
                }
            }

            {
                var it = this().query(&.{.behaviour}, &.{});
                var create_queue = std.ArrayList(SnakePart).init(arena_alloc);
                while (it.next()) |e| {
                    this().getPtr(.behaviour, e).?.update(@alignCast(@ptrCast(&create_queue)));
                }
                for (create_queue.items) |part| {
                    const e = this().create();
                    this().incl(.snake_part, e, part, .dynamic);
                }
            }

            // snake update could signal death -> restart
            if (should_reset) {
                states[current_state] = reset;
                for (0..states.len - 1) |_| nextState(false, false);
                logic_tick = 250;
                should_reset = false;
                continue;
            }
            lag -= logic_tick;

            if (reset_timer > 0) reset_timer -= 1;
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();
        const alpha = lag / logic_tick;

        {
            var it = this().query(&.{.snake_part}, &.{});
            while (it.next()) |e| {
                // if (!this().has(.snake_part, e)) continue;
                const this_part = this().getPtr(.snake_part, e).?;
                // const prev_part = this().getPtr(.snake_part, e).?;
                const size = if (this_part.life == 0) 8 * (1 - alpha) else 8;
                rl.drawRectangle(
                    @intFromFloat(this_part.x * 8 + 8 - size / 2),
                    @intFromFloat(this_part.y * 8 + 8 - size / 2),
                    @intFromFloat(size),
                    @intFromFloat(size),
                    rl.Color.red,
                );
            }
        }

        {
            var it = this().query(&.{.food}, &.{});
            while (it.next()) |e| {
                const this_part = this().getPtr(.food, e).?;
                const size = 6;
                rl.drawRectangle(
                    @intFromFloat(this_part.x * 8 + 8 - size / 2),
                    @intFromFloat(this_part.y * 8 + 8 - size / 2),
                    @intFromFloat(size),
                    @intFromFloat(size),
                    rl.Color.sky_blue,
                );
            }
        }

        rl.clearBackground(rl.Color.white);
    }

    // free the gamestates
    for (0..states.len) |_| nextState(false, true);
}
