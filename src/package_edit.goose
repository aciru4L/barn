import std;
import json;
import src.version;
import src.manifest;
import src.project;

fn format_field(out: u8[>..]&, key: const u8[:], value: const u8[:]) {
    out.append("  ");
    json::format_key(out, key);
    out.push(' ');
    json::format_string(out, value);
    out.append(",\n");
}

fn format_entry(out: u8[>..]&, key: const u8[:], value: const u8[:], is_last: bool) {
    out.append("    ");
    json::format_key(out, key);
    out.push(' ');
    json::format_string(out, value);
    out.append(if is_last { "\n" } else { ",\n" });
}

fn format_excludes(out: u8[>..]&, excludes: (const u8[:])[:]) {
    guard excludes.len > 0 else { return; }
    out.append("  \"exclude\": [");
    for e, i in excludes {
        if i > 0 { out.append(", "); }
        json::format_string(out, e);
    }
    out.append("],\n");
}

fn format_dependencies(out: u8[>..]&, dependencies: const Dependency[:]) {
    guard dependencies.len > 0 else { out.append("  \"dependencies\": {}"); return; }
    out.append("  \"dependencies\": {\n");
    for d, i in dependencies { format_entry(out, d.name, str(d.version), i == dependencies.len - 1); }
    out.append("  }");
}

fn format_overrides(out: u8[>..]&, overrides: const Override[:]) {
    guard overrides.len > 0 else { return; }
    out.append(",\n  \"overrides\": {\n");
    for o, i in overrides {
        let value: u8[>..] = if is_local(o) { str(o.path) } else { str(o.version) };
        format_entry(out, o.name, value, i == overrides.len - 1);
    }
    out.append("  }");
}

fn package_text(m: Manifest, dependencies: const Dependency[:], overrides: const Override[:],
                excludes: (const u8[:])[:]) -> u8[>..] {
    let slash = find(m.egg.name, "/");
    var out = str("{\n");
    format_field(out, "owner", m.egg.name[..slash]);
    format_field(out, "name", m.egg.name[slash + 1..]);
    format_field(out, "version", str(m.egg.version));
    if m.main.len > 0 { format_field(out, "main", m.main); }
    if m.test.len > 0 { format_field(out, "test", m.test); }
    if m.source.len > 0 { format_field(out, "source", m.source); }
    format_excludes(out, excludes);
    format_dependencies(out, dependencies);
    format_overrides(out, overrides);
    out.append("\n}\n");
    return out;
}

fn with_dependencies(p: Project, dependencies: const Dependency[:]) -> u8[>..] {
    package_text(p.manifest, dependencies, p.overrides, p.excludes)
}

fn replace_dependency(p: Project, d: Dependency, v: Version) -> u8[>..] {
    var dependencies: Dependency[>..] = [];
    for e in p.dependencies {
        dependencies.push(if e.name == d.name { Dependency { name: e.name, version: v } } else { e });
    }
    return with_dependencies(p, dependencies[..]);
}

fn insert_dependency(p: Project, d: Dependency) -> u8[>..] {
    var dependencies: Dependency[>..] = [];
    for e in p.dependencies { dependencies.push(e); }
    dependencies.push(d);
    return with_dependencies(p, dependencies[..]);
}

fn remove_dependency(p: Project, d: Dependency) -> u8[>..] {
    var dependencies: Dependency[>..] = [];
    for e in p.dependencies { if e.name != d.name { dependencies.push(e); } }
    return with_dependencies(p, dependencies[..]);
}
