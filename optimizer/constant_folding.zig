const std = @import("std");
const ir = @import("../ir.zig");

const Function = ir.Function;

pub const ConstantFolding = struct {
    function: *Function,

    pub fn init(function: *Function) @This() {
        return .{ .function = function };
    }

    // pub fn run(self: *const @This()) !void {}
};
