const std = @import("std");

const Page = @import("gc.zig").Page;

const ObjectReal = @import("object_real.zig").ObjectReal;
const ObjectCons = @import("object_cons.zig").ObjectCons;
const ObjectString = @import("object_string.zig").ObjectString;
const ObjectChamp = @import("object_champ.zig").ObjectChamp;
const ObjectPrimitive = @import("object_primitive.zig").ObjectPrimitive;
const ObjectErr = @import("object_err.zig").ObjectErr;
const ObjectSymbol = @import("object_symbol.zig").ObjectSymbol;
const ObjectSpecial = @import("object_special.zig").ObjectSpecial;
const ObjectTrue = @import("object_bool.zig").ObjectTrue;
const ObjectFalse = @import("object_bool.zig").ObjectFalse;

pub const Kind = enum(u8) {
    real,
    cons,
    string,
    champ,
    primitive,
    err,
    symbol,
    special,
    _true,
    _false,
};

pub fn ObjectType(comptime kind: Kind) type {
    return switch (kind) {
        .real => ObjectReal,
        .cons => ObjectCons,
        .string => ObjectString,
        .champ => ObjectChamp,
        .primitive => ObjectPrimitive,
        .err => ObjectErr,
        .symbol => ObjectSymbol,
        .special => ObjectSpecial,
        ._true => ObjectTrue,
        ._false => ObjectFalse,
    };
}

pub const Object = extern struct {
    kind: Kind align(16),
    _pad: [7]u8,

    pub fn as(obj: *Object, comptime kind: Kind) *ObjectType(kind) {
        std.debug.assert(obj.kind == kind);
        return @alignCast(@ptrCast(obj));
    }

    pub fn page(obj: *Object) *Page {
        const mask: usize = ~(@as(usize, std.mem.page_size) - 1);
        return @ptrFromInt(@intFromPtr(obj) & mask);
    }

    pub fn hash(obj: ?*Object, level: usize) u64 {
        if (obj == null) {
            const seed = 11400714819323198393 *% (level + 1);
            return seed *% 12542518518317951677 +% 14939819388667570391;
        }
        return switch (obj.?.kind) {
            .real => obj.?.as(.real).hash(level),
            .cons => obj.?.as(.cons).hash(level),
            .string => obj.?.as(.string).hash(level),
            .champ => obj.?.as(.champ).hash(level),
            .primitive => obj.?.as(.primitive).hash(level),
            .err => obj.?.as(.err).hash(level),
            .symbol => obj.?.as(.symbol).hash(level),
            .special => obj.?.as(.special).hash(level),
            ._true => obj.?.as(._true).hash(level),
            ._false => obj.?.as(._false).hash(level),
        };
    }
};

comptime {
    std.debug.assert(@sizeOf(Object) <= 16);
    std.debug.assert(@alignOf(Object) == 16);
}

pub fn eql(obj1: ?*Object, obj2: ?*Object) bool {
    if (obj1 == obj2) return true;
    if (obj1 == null or obj2 == null) return false;
    if (obj1.?.kind != obj2.?.kind) return false;
    return switch (obj1.?.kind) {
        .real => obj1.?.as(.real).val == obj2.?.as(.real).val,
        .cons => blk: {
            const cons1 = obj1.?.as(.cons);
            const cons2 = obj2.?.as(.cons);
            break :blk eql(cons1.car, cons2.car) and eql(cons1.cdr, cons2.cdr);
        },
        .string => blk: {
            const string1 = obj1.?.as(.string);
            const string2 = obj2.?.as(.string);
            if (string1.len != string2.len) break :blk false;
            break :blk std.mem.eql(
                u8,
                string1.data()[0..string1.len],
                string2.data()[0..string2.len],
            );
        },
        .champ => blk: {
            const champ1 = obj1.?.as(.champ);
            const champ2 = obj2.?.as(.champ);
            if (champ1.datamask != champ2.datamask or
                champ1.nodemask != champ2.nodemask) break :blk false;
            std.debug.assert(champ1.datalen == champ2.datalen);
            std.debug.assert(champ1.nodelen == champ2.nodelen);
            const data1 = champ1.data();
            const data2 = champ2.data();
            for (0..2 * champ1.datalen + champ1.nodelen) |i| {
                if (!eql(data1[i], data2[i])) break :blk false;
            }
            break :blk true;
        },
        .primitive => obj1.?.as(.primitive).ptr == obj2.?.as(.primitive).ptr,
        .err => return false, // what is the desired behaviour?
        .symbol => blk: {
            const sym1 = obj1.?.as(.symbol);
            const sym2 = obj2.?.as(.symbol);
            if (sym1.len != sym2.len) break :blk false;
            break :blk std.mem.eql(
                u8,
                sym1.data()[0..sym1.len],
                sym2.data()[0..sym2.len],
            );
        },
        .special => obj1.?.as(.special).form == obj2.?.as(.special).form,
        ._true => true,
        ._false => true,
    };
}

pub fn print(obj: ?*Object, writer: anytype) anyerror!void {
    try _printImpl(obj, writer);
    try writer.print("\n", .{});
}

pub fn debugPrint(obj: ?*Object) void {
    const stderr = std.io.getStdErr().writer();
    print(obj, stderr) catch {};
}

fn _printImpl(_obj: ?*Object, writer: anytype) anyerror!void {
    const obj = _obj orelse return writer.print("nil", .{});
    switch (obj.kind) {
        .real => try writer.print("{d}", .{obj.as(.real).val}),
        .cons => {
            var cons = obj.as(.cons);
            try writer.print("(", .{});
            while (true) {
                try _printImpl(cons.car, writer);
                if (cons.cdr == null) {
                    break;
                } else if (cons.cdr.?.kind != .cons) {
                    try writer.print(" . ", .{});
                    try _printImpl(cons.cdr, writer);
                    break;
                }
                try writer.print(" ", .{});
                cons = cons.cdr.?.as(.cons);
            }
            try writer.print(")", .{});
        },
        .string => {
            const str = obj.as(.string);
            try writer.print("\"{s}\"", .{str.data()[0..str.len]});
        },
        .champ => {
            try writer.print("{{", .{});
            try _printChamp(obj, true, writer);
            try writer.print("}}", .{});
        },
        .primitive => try writer.print("<PRIMITIVE>", .{}),
        .err => {
            const err = obj.as(.err);
            try writer.print("<ERROR: {s}>", .{err.data()[0..err.len]});
        },
        .symbol => {
            const sym = obj.as(.symbol);
            try writer.print("{s}", .{sym.data()[0..sym.len]});
        },
        .special => {
            const special = obj.as(.special);
            switch (special.form) {
                ._if => try writer.print("<IF>", .{}),
                .def => try writer.print("<DEF>", .{}),
            }
        },
        ._true => try writer.print("<TRUE>", .{}),
        ._false => try writer.print("<FALSE>", .{}),
    }
}

fn _printChamp(obj: *Object, first: bool, writer: anytype) anyerror!void {
    const champ = obj.as(.champ);
    var not_first = false;
    for (0..champ.datalen) |i| {
        if (!first or i > 0) try writer.print(", ", .{});
        const key = champ.data()[2 * i];
        const val = champ.data()[2 * i + 1];
        try _printImpl(key, writer);
        try writer.print(" ", .{});
        try _printImpl(val, writer);
        not_first = true;
    }
    for (0..champ.nodelen) |i| {
        const child = champ.nodes()[i];
        try _printChamp(child, first and i == 0 and !not_first, writer);
    }
}
