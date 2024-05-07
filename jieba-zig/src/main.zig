const std = @import("std");
const Tokenizer = @import("root.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const dictionary = "../dict2.txt";

    var tokenizer = Tokenizer.init(allocator, dictionary);
    defer tokenizer.deinit();
    try tokenizer.gen_pfdict();
    tokenizer.print_pfdict();

    var words = try tokenizer.cut("我来到北京清华大学");
    defer words.deinit();

    while (words.next()) |word| {
        std.debug.print("word='{s}'\n", .{word});
    }
}
