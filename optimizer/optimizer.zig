const std = @import("std");
const ir = @import("../ir.zig");
const lvn = @import("lvn.zig");
const cf = @import("constant_folding.zig");

const Function = ir.Function;

const Passes = .{
    cf.ConstantFolding,
    lvn.LocalValueNumbering,
};

pub const Optimizer = struct {
    function: *Function,

    pub fn init(function: *Function) @This() {
        return .{ .function = function };
    }

    pub fn run(self: *const @This()) !void {
        inline for (Passes) |Pass| {
            const pass = Pass.init(self.function);
            try pass.run();
        }
    }
};
