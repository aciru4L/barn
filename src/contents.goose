import std;
import os;
import src.manifest;
import src.project;
import src.checksum;
import src.files;
import src.git;

let LEFT_OUT_FOLDERS: const u8[:][5] = ["test", "tests", "examples", "bench", "docs"];
let ALWAYS_SHIPPED: const u8[:][2] = ["LICENSE", "README"];

fn source_dir(p: Project) -> u8[>..] {
    let source = source_of(p.manifest);
    if source == "." { return str(p.dir); }
    return str(p.dir, "/", source);
}

fn entry_path(p: Project) -> u8[>..] {
    let source = source_of(p.manifest);
    let file = str(p.manifest.name, ".goose");
    if source == "." { return file; }
    return str(source, "/", file);
}

fn inside_source(p: Project, path: const u8[:]) -> const u8[:] {
    let source = source_of(p.manifest);
    guard source != "." else { return path; }
    guard starts_with(path, str(source, "/")) else { return path[..0]; }
    return path[source.len + 1..];
}

fn first_segment(path: const u8[:]) -> const u8[:] {
    let slash = find(path, "/");
    if slash < 0 { return path; }
    return path[..slash];
}

fn is_always_shipped(name: const u8[:]) -> bool {
    for prefix in ALWAYS_SHIPPED { if starts_with(name, prefix) { return true; } }
    return false;
}

fn is_excluded(p: Project, path: const u8[:]) -> bool {
    for e in p.excludes { if path == e || starts_with(path, str(e, "/")) { return true; } }
    return false;
}

fn is_shipped(p: Project, path: const u8[:]) -> bool {
    guard !(source_of(p.manifest) == "." && find(path, "/") < 0 && is_always_shipped(path)) else { return true; }
    guard !contains(LEFT_OUT_FOLDERS[..], first_segment(path)) else { return false; }
    guard path != "barn.json" && path != SUM_FILE && path != RECORD_FILE && path != ORIGIN_FILE else { return false; }
    guard path != inside_source(p, main_file(p)) && path != inside_source(p, test_file(p)) else { return false; }
    return !is_excluded(p, path);
}

fn each_root_extra<F>(p: Project) {
    guard source_of(p.manifest) != "." else { return; }
    var listing: u8[>..] = [];
    list_dir(p.dir, listing);
    each_split(listing, '\n') { name =>
        let path = str(p.dir, "/", name);
        let shadowed = file_exists(str(source_dir(p), "/", name));
        if name.len > 0 && is_always_shipped(name) && !is_dir(path) && !shadowed { F(path[..], name); }
    };
}

fn has_left_out_part(path: const u8[:]) -> bool {
    var left = false;
    each_split(path, '/') { if it.len > 0 && left_out(it) { left = true; } };
    return left;
}

fn git_listing(p: Project, listing: u8[>..]&) -> bool {
    let command: const u8[:][5] = ["ls-files", "--cached", "--others", "--exclude-standard", "-z"];
    return run_git(source_dir(p), p.dir, command[..], listing) == 0;
}

fn each_listed_file<F>(p: Project, listing: const u8[:]) {
    let from = source_dir(p);
    each_split(listing, '\0') { path =>
        let full = str(from, "/", path);
        if path.len > 0 && !has_left_out_part(path) && is_shipped(p, path) && file_exists(full) && !is_dir(full) {
            F(full[..], path);
        }
    };
}

fn each_egg_file<F>(p: Project) -> bool {
    let from = source_dir(p);
    var listing: u8[>..] = [];
    var listed = true;
    if git_listing(p, listing) { each_listed_file(p, listing) { full, path => F(full, path); }; }
    else {
        listed = walk(from, false) { path, is_folder =>
            if !is_folder && is_shipped(p, path) {
                let full = str(from, "/", path);
                F(full[..], path);
            }
        };
    }
    guard listed else { return false; }
    each_root_extra(p) { path, name => F(path, name); };
    return true;
}

fn parent_of(path: const u8[:]) -> const u8[:] {
    var i = path.len - 1;
    while i >= 0 && path[i] != '/' { i--; }
    return path[..max(i, 0)];
}

fn copy_egg_files(p: Project, to: const u8[:]) -> bool {
    guard make_dirs(to) || is_dir(to) else { return false; }
    var copied = true;
    let listed = each_egg_file(p) { from, path =>
        let target = str(to, "/", path);
        let parent = parent_of(target);
        var data: u8[>..] = [];
        let ready = is_dir(parent) || make_dirs(parent);
        if !ready || !read_file(from, data) || !write_file(target, data) { copied = false; }
    };
    return listed && copied;
}
