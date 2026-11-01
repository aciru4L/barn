import std;
import os;
import src.sha256;
import src.files;

let SUM_FILE = "barn.sha256";
let RECORD_FILE = "barn.egg";
let ORIGIN_FILE = "barn.origin";
let HASH_PREFIX = "sha256:";

fn file_sums(dir: const u8[:], out: u8[>..]&) -> bool {
    return walk(dir, false) { path, is_folder =>
        if !is_folder && path != SUM_FILE && path != RECORD_FILE && path != ORIGIN_FILE {
            var data: u8[>..] = [];
            read_file(str(dir, "/", path), data);
            var digest = sha256();
            update(digest, data);
            finish(digest, out);
            format(out, "  ", path, "\n");
        }
    };
}

fn sums_hash(sums: const u8[:]) -> u8[>..] {
    var digest = sha256();
    update(digest, sums);
    var out = str(HASH_PREFIX);
    finish(digest, out);
    return out;
}

fn egg_hash(dir: const u8[:]) -> u8[>..] {
    var sums: u8[>..] = [];
    file_sums(dir, sums);
    return sums_hash(sums);
}

fn is_hash(text: const u8[:]) -> bool { starts_with(text, HASH_PREFIX) }

fn read_sums(dir: const u8[:], sums: u8[>..]&) -> bool { read_file(str(dir, "/", SUM_FILE), sums) }

fn sum_of(sums: const u8[:], path: const u8[:]) -> u8[>..], bool {
    var sum: u8[>..] = [];
    var found = false;
    each_split(sums, '\n') {
        let gap = find(it, "  ");
        if !found && gap > 0 && it[gap + 2..] == path { sum.append(it[..gap]); found = true; }
    };
    return sum, found;
}

fn each_sum<F>(sums: const u8[:]) {
    each_split(sums, '\n') {
        let gap = find(it, "  ");
        if gap > 0 { F(it[..gap], it[gap + 2..]); }
    };
}

fn describe_changes(was: const u8[:], now: const u8[:], prefix: const u8[:], out: u8[>..]&) {
    each_sum(was) { sum, path =>
        let current, present = sum_of(now, path);
        if !present { format(out, "\n    ", prefix, path, " is gone"); }
        else if current != sum { format(out, "\n    ", prefix, path, " was edited"); }
    };
    each_sum(now) { sum, path =>
        let _, present = sum_of(was, path);
        if !present { format(out, "\n    ", prefix, path, " was added"); }
    };
}

fn describe_changes_since(was: const u8[:], hash: const u8[:], now: const u8[:], prefix: const u8[:], out: u8[>..]&) {
    if was.len > 0 && sums_hash(was) == hash { describe_changes(was, now, prefix, out); }
}
