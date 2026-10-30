import std;
import src.manifest;
import src.project;

fn is_blank(c: u8) -> bool { c == ' ' || c == '\t' || c == '\r' }

fn line_start(text: const u8[:], at: i64) -> i64 {
    var start = at;
    while start > 0 && text[start - 1] != '\n' { start--; }
    return start;
}

fn line_end(text: const u8[:], at: i64) -> i64 {
    var end = at;
    while end < text.len && text[end] != '\n' { end++; }
    return end;
}

fn skip_blanks(text: const u8[:], at: i64) -> i64 {
    var i = at;
    while i < text.len && is_blank(text[i]) { i++; }
    return i;
}

fn all_blank(text: const u8[:]) -> bool {
    for c in text { if !is_blank(c) { return false; } }
    return true;
}

fn leading_blanks(text: const u8[:], at: i64) -> u8[>..] {
    var blanks: u8[>..] = [];
    for c in text[line_start(text, at)..at] { if is_blank(c) { blanks.push(c); } }
    return blanks;
}

fn replace_dependency(p: Project, d: Dependency, entry: const u8[:]) -> u8[>..] {
    str(p.text[..d.at], entry, p.text[d.end..])
}

fn append_dependency_list(text: const u8[:], entry: const u8[:]) -> u8[>..] {
    let newline = if text.len > 0 && text[text.len - 1] != '\n' { "\n" } else { "" };
    return str(text, newline, "\ndependencies = [\n    \"", entry, "\",\n];\n");
}

fn insert_dependency(p: Project, entry: const u8[:]) -> u8[>..] {
    let text = p.text;
    let m = p.manifest;
    guard m.dependencies_open >= 0 else { return append_dependency_list(text, entry); }
    let close_line = line_start(text, m.dependencies_close);
    let one_per_line = all_blank(text[close_line..m.dependencies_close]) &&
                       find(text[m.dependencies_open..m.dependencies_close], "\n") >= 0;
    guard p.dependencies.len > 0 else {
        if one_per_line { return str(text[..close_line], "    \"", entry, "\",\n", text[close_line..]); }
        return str(text[..m.dependencies_open + 1], "\"", entry, "\"", text[m.dependencies_open + 1..]);
    }
    let last = p.dependencies[p.dependencies.len - 1];
    let after_last = last.end + 1;
    guard one_per_line else { return str(text[..after_last], ", \"", entry, "\"", text[after_last..]); }
    let next = skip_blanks(text, after_last);
    let comma = if next < text.len && text[next] == ',' { "" } else { "," };
    let indent = leading_blanks(text, last.at - 1);
    let new_line = str(indent, "\"", entry, "\",\n");
    return str(text[..after_last], comma, text[after_last..close_line], new_line, text[close_line..]);
}

fn remove_dependency(p: Project, d: Dependency) -> u8[>..] {
    let text = p.text;
    let open_quote = d.at - 1;
    let after_quote = d.end + 1;
    let start = line_start(text, open_quote);
    let end = line_end(text, after_quote);
    var rest = trim(text[after_quote..end]);
    if starts_with(rest, ",") { rest = trim(rest[1..]); }
    if all_blank(text[start..open_quote]) && (rest.len == 0 || starts_with(rest, "//")) {
        return str(text[..start], text[if end < text.len { end + 1 } else { end }..]);
    }
    let next = skip_blanks(text, after_quote);
    if next < text.len && text[next] == ',' { return str(text[..open_quote], text[skip_blanks(text, next + 1)..]); }
    var before = open_quote;
    while before > 0 && is_blank(text[before - 1]) { before--; }
    if before > 0 && text[before - 1] == ',' { before--; }
    return str(text[..before], text[after_quote..]);
}
