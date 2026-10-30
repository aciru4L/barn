import std;
import os;
import src.files;
import src.manifest;
import src.project;

struct Use { name: const u8[:], line: i64 }

fn is_identifier_start(c: u8) -> bool { (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' }
fn is_identifier_part(c: u8) -> bool { is_identifier_start(c) || (c >= '0' && c <= '9') }

fn find_uses(text: const u8[:], names: const u8[:][:], uses: Use[>..]&) {
    let n = text.len;
    var i = 0;
    var line = 1;
    var after_import = false;

    fn at(k: i64, s: const u8[:]) -> bool { k + s.len <= n && text[k..k + s.len] == s }

    fn skip_line_comment() { while i < n && text[i] != '\n' { i++; } }

    fn skip_block_comment() {
        var depth = 0;
        while i < n {
            if at(i, "/*") { depth++; i += 2; }
            else if at(i, "*/") { depth--; i += 2; if depth == 0 { return; } }
            else { if text[i] == '\n' { line++; } i++; }
        }
    }

    fn skip_raw_string() {
        i += 3;
        while i < n && !at(i, "\"\"\"") { if text[i] == '\n' { line++; } i++; }
        i += 3;
    }

    fn skip_quoted(quote: u8) {
        i++;
        while i < n && text[i] != quote && text[i] != '\n' {
            if text[i] == '\\' { i++; }
            i++;
        }
        i++;
    }

    fn is_module_import(end: i64) -> bool {
        var k = end;
        while k < n && (text[k] == ' ' || text[k] == '\t') { k++; }
        return !(at(k, "from") && (k + 4 >= n || !is_identifier_part(text[k + 4])));
    }

    fn is_qualifier(start: i64, end: i64) -> bool {
        at(end, "::") && !(start >= 2 && text[start - 2] == ':' && text[start - 1] == ':')
    }

    fn record(name: const u8[:]) {
        guard contains(names, name) else { return; }
        for u in uses { if u.name == name { return; } }
        uses.push(Use { name: name, line: line });
    }

    fn take_identifier() {
        let start = i;
        while i < n && is_identifier_part(text[i]) { i++; }
        let name = text[start..i];
        let used = if after_import { is_module_import(i) } else { is_qualifier(start, i) };
        if used { record(name); }
        after_import = name == "import";
    }

    while i < n {
        let c = text[i];
        if c == '\n' { line++; i++; continue; }
        if c == ' ' || c == '\t' || c == '\r' { i++; continue; }
        if at(i, "//") { skip_line_comment(); continue; }
        if is_identifier_start(c) { take_identifier(); continue; }
        after_import = false;
        if at(i, "/*") { skip_block_comment(); }
        else if at(i, "\"\"\"") { skip_raw_string(); }
        else if c == '"' || c == '\'' { skip_quoted(c); }
        else if c >= '0' && c <= '9' { while i < n && is_identifier_part(text[i]) { i++; } }
        else { i++; }
    }
}

fn is_inside(file: const u8[:], folders: const u8[:][:]) -> bool {
    for folder in folders { if starts_with(file, str(folder, "/")) { return true; } }
    return false;
}

fn uses_of(dir: const u8[:], names: const u8[:][:], skipped_folders: const u8[:][:], out: u8[>..]&) -> i64 {
    guard names.len > 0 else { return 0; }
    var count = 0;
    walk(dir, false) { file, is_folder =>
        if !is_folder && ends_with(file, ".goose") && !is_inside(file, skipped_folders) {
            var text: u8[>..] = [];
            read_file(str(dir, "/", file), text);
            var uses: Use[>..] = [];
            find_uses(text, names, uses);
            for u in uses { format(out, "\n  ", file, ":", u.line, " uses ", u.name); }
            count += uses.len;
        }
    };
    return count;
}

fn local_folders(p: Project, out: (const u8[:])[>..]&) {
    for o in p.overrides {
        if is_local(o) && !starts_with(o.path, "../") {
            out.push(if starts_with(o.path, "./") { o.path[2..] } else { o.path });
        }
    }
}
