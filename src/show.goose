import std;
import src.version;
import src.manifest;
import src.resolve;

fn describe_origin(b: Build, node: i64, out: u8[>..]&) {
    guard is_overridden(b, node) else { return; }
    let path = local_path(b, node);
    if path.len > 0 { format(out, "  (", path, ")"); }
    else { out.append("  (override)"); }
}

fn print_list(b: Build) {
    for node in b.used[1..] {
        var line = str(b.nodes[node].egg, ":", b.nodes[node].version);
        describe_origin(b, node, line);
        print(line);
    }
}

fn print_tree(b: Build) {
    var shown: bool[>..] = [];
    for _ in b.nodes.len { shown.push(false); }

    fn print_branch(r: Request, depth: i64, last_at_depth: i64, is_last: bool, repeated: bool) {
        var line: u8[>..] = [];
        for d in depth { line.append(if (last_at_depth >> d) & 1 == 1 { "   " } else { "|  " }); }
        format(line, if is_last { "\\- " } else { "+- " }, r.egg, ":", r.wanted);
        let chosen = b.nodes[r.chosen];
        if chosen.version != r.wanted { format(line, " -> ", chosen.version); }
        describe_origin(b, r.chosen, line);
        if repeated { line.append(" (*)"); }
        print(line);
    }

    recursive fn print_requests(node: i64, depth: i64, last_at_depth: i64) {
        shown[node] = true;
        let rs = requests_of(b, node);
        for r, i in rs {
            let is_last = i == rs.len - 1;
            let has_children = b.nodes[r.chosen].request_count > 0;
            let expand = has_children && !shown[r.chosen];
            print_branch(r, depth, last_at_depth, is_last, has_children && !expand);
            if expand && depth < 62 {
                print_requests(r.chosen, depth + 1, last_at_depth | ((if is_last { 1 } else { 0 }) << depth));
            }
        }
    }

    print(b.nodes[0].egg, ":", b.nodes[0].version);
    print_requests(0, 0, 0);
}
