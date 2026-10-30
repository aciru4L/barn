import std;
import os;
import src.manifest;

let LOCAL_MARK = "local";

struct Locked { coordinate: const u8[:], egg: const u8[:], name: const u8[:], hash: const u8[:] }

fn lock_path(dir: const u8[:]) -> u8[>..] { str(dir, "/barn.lock") }

fn parse_locked(entry: const u8[:]) -> Locked {
    let space = find(entry, " ");
    let coordinate = if space < 0 { entry } else { entry[..space] };
    let colon = find(coordinate, ":");
    let egg = if colon < 0 { coordinate } else { coordinate[..colon] };
    let hash = if space < 0 { entry[..0] } else { entry[space + 1..] };
    return Locked { coordinate: coordinate, egg: egg, name: short_name(egg), hash: hash };
}

fn read_lock(dir: const u8[:], text: u8[>..]&, entries: Locked[>..]&) -> bool {
    guard read_file(lock_path(dir), text) else { return false; }
    each_split(text, '\n') {
        let line = trim(it);
        if starts_with(line, "\"") {
            let end = find(line[1..], "\"");
            if end > 0 { entries.push(parse_locked(line[1..end + 1])); }
        }
    };
    return true;
}

fn find_locked(entries: const Locked[:], name: const u8[:]) -> i64 {
    for entry, i in entries { if entry.name == name { return i; } }
    return -1;
}

fn lock_text(lines: const u8[:], out: u8[>..]&) {
    out.append("locked = [\n");
    each_split(lines, '\n') { if it.len > 0 { format(out, "    \"", it, "\",\n"); } };
    out.append("];\n");
}
