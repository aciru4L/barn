import std;
import os;
import src.project;
import src.resolve;
import src.lock;
import src.install;
import src.process;

fn locked_key(entry: Locked) -> u8[>..] {
    return str(entry.coordinate, if entry.hash == LOCAL_MARK { " (local)" } else { "" });
}

fn resolved_key(b: Build, node: i64) -> u8[>..] {
    let n = b.nodes[node];
    return str(n.egg, ":", n.version, if local_path(b, node).len > 0 { " (local)" } else { "" });
}

fn has_line(lines: const u8[:], line: const u8[:]) -> bool { find(str("\n", lines), str("\n", line, "\n")) >= 0 }

fn describe_stale_lock(b: Build, entries: const Locked[:], out: u8[>..]&) {
    var resolved: u8[>..] = [];
    var locked: u8[>..] = [];
    for node in b.used[1..] { format(resolved, resolved_key(b, node), "\n"); }
    for entry in entries { format(locked, locked_key(entry), "\n"); }
    each_split(resolved, '\n') {
        if it.len > 0 && !has_line(locked, it) { format(out, "\n  ", it, " is not in barn.lock"); }
    };
    each_split(locked, '\n') {
        if it.len > 0 && !has_line(resolved, it) { format(out, "\n  ", it, " is no longer used"); }
    };
}

fn check_build(p: Project, b: Build, repository: const u8[:]) -> u8[>..] {
    var lock_source: u8[>..] = [];
    var entries: Locked[>..] = [];
    let has_lock = read_lock(p.dir, lock_source, entries);
    guard has_lock || b.used.len == 1 else { return str("no barn.lock in ", p.dir, "\nbarn install writes it"); }
    var stale: u8[>..] = [];
    describe_stale_lock(b, entries, stale);
    guard stale.len == 0 else { return str("barn.lock does not match barn.pkg:", stale, "\nbarn install updates it"); }
    var edited: u8[>..] = [];
    check_copies(p.dir, repository, entries, edited);
    guard edited.len == 0 else {
        return str(".barn/ differs from barn.lock:", edited, "\nbarn install --force restores it");
    }
    return str("");
}

fn goose_arguments(command: const u8[:], main: const u8[:], passed: const u8[:][:]) -> (const u8[:])[>..] {
    var arguments: (const u8[:])[>..] = ["goose", command, main];
    if command == "run" && passed.len > 0 { arguments.push("--"); }
    for a in passed { arguments.push(a); }
    return arguments;
}

fn run_goose(command: const u8[:], dir: const u8[:], repository: const u8[:], passed: const u8[:][:]) -> u8[>..] {
    return with_project(dir) { p =>
        return resolve(dir, repository) { b =>
            let problem = check_build(p, b, repository);
            guard problem.len == 0 else { return problem; }
            let main: u8[>..] = if dir == "." { str(main_file(p)) } else { str(dir, "/", main_file(p)) };
            let status = run_program(goose_arguments(command, main, passed)[..]);
            guard status >= 0 else { return str("cannot start goose"); }
            if status != 0 { exit(status); }
            return str("");
        };
    };
}
