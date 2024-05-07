const std = @import("std");

const Tokenizer = @This();

allocator: std.mem.Allocator,
freq: std.StringHashMap(usize),
total: usize = 0,
dictionary: []const u8,
initialized: bool = false,

pub fn initialize(self: *Tokenizer) !void {
    try self.gen_pfdict();
    self.initialized = true;
}

pub fn check_initialized(self: *Tokenizer) !void {
    if (!self.initialized) {
        try self.initialize();
    }
}

pub fn init(allocator: std.mem.Allocator, dictionary: []const u8) Tokenizer {
    return .{
        .allocator = allocator,
        .dictionary = dictionary,
        .freq = std.StringHashMap(usize).init(allocator),
    };
}

pub fn deinit(self: *Tokenizer) void {
    var it = self.freq.iterator();
    while (it.next()) |entry| {
        self.allocator.free(entry.key_ptr.*);
    }
    self.freq.deinit();
}

pub fn print_pfdict(self: Tokenizer) void {
    var it = self.freq.iterator();
    while (it.next()) |entry| {
        std.debug.print("word='{s}' freq={}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }
    std.debug.print("total={}\n", .{self.total});
}

pub fn gen_pfdict(self: *Tokenizer) !void {
    const file = try std.fs.cwd().openFile(self.dictionary, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    const reader = buf_reader.reader();

    var line = std.ArrayList(u8).init(self.allocator);
    defer line.deinit();

    const writer = line.writer();
    var line_no: usize = 1;

    while (reader.streamUntilDelimiter(writer, '\n', null)) : (line_no += 1) {
        defer line.clearRetainingCapacity();

        var it = std.mem.splitScalar(u8, line.items, ' ');
        const word_origin = it.next();
        const freq_string = it.next();

        if (word_origin == null or freq_string == null) {
            continue;
        }

        if (self.freq.contains(word_origin.?)) {
            continue;
        }

        const freq = try std.fmt.parseInt(usize, freq_string.?, 10);
        const word = try self.allocator.alloc(u8, word_origin.?.len);
        @memcpy(word, word_origin.?);

        try self.freq.put(word, freq);
        self.total += freq;

        var utf8 = (try std.unicode.Utf8View.init(word)).iterator();
        while (utf8.nextCodepointSlice()) |codepoint| {
            _ = codepoint;
            const wfrag = word[0..utf8.i];
            if (!self.freq.contains(wfrag)) {
                const word_fragment = try self.allocator.alloc(u8, wfrag.len);
                @memcpy(word_fragment, wfrag);
                try self.freq.put(word_fragment, 0);
            }
        }
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => return err,
    }
}

const DAG = struct {
    allocator: std.mem.Allocator,
    data: std.AutoHashMap(usize, []usize),

    pub fn init(allocator: std.mem.Allocator) DAG {
        return .{
            .allocator = allocator,
            .data = std.AutoHashMap(usize, []usize).init(allocator),
        };
    }

    pub fn deinit(self: *DAG) void {
        var it = self.data.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.data.deinit();
    }

    pub fn put(self: *DAG, key: usize, value: []usize) !void {
        try self.data.put(key, value);
    }

    pub fn print(self: *DAG) void {
        var it = self.data.iterator();
        while (it.next()) |entry| {
            std.debug.print("key={any} value={any}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
    }

    pub fn get(self: DAG, key: usize) ?[]usize {
        return self.data.get(key);
    }
};

const Runes = struct {
    sentence: []const u8,
    N: usize,
    ilist: std.ArrayList(usize),

    pub fn init(allocator: std.mem.Allocator, sentence: []const u8) !Runes {
        const N = try std.unicode.utf8CountCodepoints(sentence);
        var ilist = try std.ArrayList(usize).initCapacity(allocator, N);
        var utf8 = (try std.unicode.Utf8View.init(sentence)).iterator();
        try ilist.append(0);
        while (utf8.nextCodepointSlice()) |codepoint| {
            _ = codepoint;
            try ilist.append(utf8.i);
        }
        return .{
            .sentence = sentence,
            .N = N,
            .ilist = ilist,
        };
    }

    pub fn deinit(self: *Runes) void {
        self.ilist.deinit();
    }

    pub fn slice(self: Runes, from: usize, to: usize) []const u8 {
        const start = self.ilist.items[from];
        const end = self.ilist.items[to];
        const frag = self.sentence[start..end];
        return frag;
    }

    pub fn print(self: Runes) void {
        std.debug.print("N={} ilist={any}\n", .{ self.N, self.ilist.items });
    }
};

const Route = std.AutoHashMap(usize, struct { f64, usize });

pub fn print_route(self: Route) void {
    var it = self.iterator();
    while (it.next()) |entry| {
        std.debug.print("key={any} value={any}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }
}

const RouteValue = struct { f64, usize };

fn compare(_: void, a: RouteValue, b: RouteValue) bool {
    return b[0] > a[0] or b[1] > a[1];
}

fn log(num: usize) f64 {
    return @log(@as(f64, @floatFromInt(num)));
}

fn calc(self: *Tokenizer, runes: Runes, dag: DAG) !Route {
    const N = runes.N;
    var route = Route.init(self.allocator);
    try route.put(N, .{ 0, 0 });
    const logtotal: f64 = log(self.total);

    var ps = std.ArrayList(RouteValue).init(self.allocator);
    defer ps.deinit();

    var idx: isize = @intCast(N - 1);
    while (idx > -1) : (idx -= 1) {
        const i: usize = @intCast(idx);
        defer ps.clearRetainingCapacity();
        for (dag.get(i).?) |x| {
            const word = runes.slice(i, x + 1);
            const freq = if (self.freq.get(word)) |freq| freq else 1;
            const logword: f64 = log(freq);
            const f = logword - logtotal + route.get(x + 1).?[0];
            try ps.append(.{ f, x });
        }
        const value = std.sort.max(RouteValue, ps.items, {}, compare);
        try route.put(i, value.?);
    }
    return route;
}

fn get_DAG(self: *Tokenizer, runes: Runes) !DAG {
    try self.check_initialized();
    var dag = DAG.init(self.allocator);
    const N = runes.N;
    for (0..N) |k| {
        var tmplist = std.ArrayList(usize).init(self.allocator);
        var i: usize = k;
        while (i < N) : (i += 1) {
            const frag = runes.slice(k, i + 1);
            if (self.freq.get(frag)) |freq| {
                if (freq > 0) {
                    try tmplist.append(i);
                }
            } else {
                break;
            }
        }
        if (tmplist.items.len == 0) {
            try tmplist.append(k);
        }
        const value = try tmplist.toOwnedSlice();
        try dag.put(k, value);
    }
    return dag;
}

const Words = struct {
    route: Route,
    runes: Runes,
    x: usize = 0,

    pub fn next(self: *Words) ?[]const u8 {
        if (self.x >= self.runes.N) {
            return null;
        }
        const y = self.route.get(self.x).?[1] + 1;
        const word = self.runes.slice(self.x, y);
        self.x = y;
        return word;
    }

    pub fn deinit(self: *Words) void {
        self.route.deinit();
        self.runes.deinit();
    }
};

pub fn cut(self: *Tokenizer, sentence: []const u8) !Words {
    const runes = try Runes.init(self.allocator, sentence);
    var dag = try self.get_DAG(runes);
    defer dag.deinit();
    const route = try self.calc(runes, dag);

    return .{
        .route = route,
        .runes = runes,
    };
}
