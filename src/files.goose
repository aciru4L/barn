import std;
import os;
import src.process;

fn left_out(name: const u8[:]) -> bool {
    name[0] == '.' || ends_with(name, ".exe") || ends_with(name, ".pdb") || ends_with(name, ".ilk") ||
        ends_with(name, ".obj")
}

fn walk<F>(root: const u8[:], include_left_out: bool) -> bool {
    var folders: u8[>..] = [];
    var folder_ends: i64[>..] = [];
    var next = 0;
    var here: u8[>..] = [];
    loop {
        var listing: u8[>..] = [];
        let folder: u8[>..] = if here.len == 0 { str(root) } else { str(root, "/", here) };
        guard list_dir(folder, listing) else { return false; }
        each_split(listing, '\n') { name =>
            if name.len > 0 && (include_left_out || !left_out(name)) {
                let path: u8[>..] = if here.len == 0 { str(name) } else { str(here, "/", name) };
                let is_folder = is_dir(str(root, "/", path));
                if is_folder { folders.append(path); folder_ends.push(folders.len); }
                F(path[..], is_folder);
            }
        };
        guard next < folder_ends.len else { return true; }
        let start = if next == 0 { 0 } else { folder_ends[next - 1] };
        here.clear();
        here.append(folders[start..folder_ends[next]]);
        next++;
    }
}

fn make_dirs(path: const u8[:]) -> bool {
    for i in 1..path.len {
        if (path[i] == '/' || path[i] == '\\') && path[i - 1] != ':' { make_dir(path[..i]); }
    }
    return make_dir(path);
}

fn copy_tree(from: const u8[:], to: const u8[:]) -> bool {
    guard make_dirs(to) else { return false; }
    var copied = true;
    let listed = walk(from, false) { path, is_folder =>
        if is_folder { if !make_dir(str(to, "/", path)) { copied = false; } }
        else {
            var data: u8[>..] = [];
            if !read_file(str(from, "/", path), data) || !write_file(str(to, "/", path), data) { copied = false; }
        }
    };
    return listed && copied;
}

fn remove_file(path: const u8[:]) -> bool { delete_file(path) || (make_writable(path) != 0 && delete_file(path)) }

fn delete_tree(path: const u8[:]) -> bool {
    guard is_dir(path) else { return !file_exists(path) || remove_file(path); }
    var folders: u8[>..] = [];
    var folder_ends: i64[>..] = [];
    let listed = walk(path, true) { inner, is_folder =>
        if is_folder { folders.append(inner); folder_ends.push(folders.len); }
        else { remove_file(str(path, "/", inner)); }
    };
    guard listed else { return false; }
    var i = folder_ends.len - 1;
    while i >= 0 {
        let start = if i == 0 { 0 } else { folder_ends[i - 1] };
        delete_dir(str(path, "/", folders[start..folder_ends[i]]));
        i--;
    }
    return delete_dir(path);
}
