import std;
import os;
import dictionary;
import src.version;
import src.manifest;
import src.repository;

struct Node {
    egg: const u8[:], version: Version, manifest: i64, override: i64 = -1, first_request: i64 = 0,
    request_count: i64 = 0,
}

struct Request { from: i64, egg: const u8[:], wanted: Version, named: i64, chosen: i64 = -1 }

struct Build {
    project: Manifest, nodes: const Node[:], requests: const Request[:], used: const i64[:],
    overrides: const Override[:],
}

fn requests_of(b: Build, node: i64) -> const Request[:] {
    let n = b.nodes[node];
    return b.requests[n.first_request..n.first_request + n.request_count];
}

fn local_path(b: Build, node: i64) -> const u8[:] {
    let n = b.nodes[node];
    if n.override >= 0 && is_local(b.overrides[n.override]) { return b.overrides[n.override].path; }
    return n.egg[..0];
}

fn is_overridden(b: Build, node: i64) -> bool { b.nodes[node].override >= 0 }

fn lookup(d: dictionary<const u8[:], i64>&, key: const u8[:]) -> i64 {
    let v = d.get(key);
    if v { return v; }
    return -1;
}

fn resolve<F>(dir: const u8[:], repository: const u8[:]) -> u8[>..] {
    var text: u8[>..] = [];
    var names: u8[>..] = [];
    var dependencies: Dependency[>..] = [];
    var overrides: Override[>..] = [];
    var manifests: Manifest[>..] = [];
    var nodes: Node[>..] = [];
    var requests: Request[>..] = [];
    var keys: u8[>..] = [];
    var node_of_key = dictionary<const u8[:], i64> {};
    var newest_node = dictionary<const u8[:], i64> {};
    var override_node = dictionary<const u8[:], i64> {};

    fn fail(message: const u8[:]) { return str(message) from resolve; }

    fn load_file(path: const u8[:]) -> i64 {
        let start = text.len;
        guard read_file(path, text) else { fail(str("cannot read ", path)); }
        let m, error = parse_manifest(text[start..], dependencies, overrides, names);
        guard error.len == 0 else { fail(str(path, ": ", error)); }
        manifests.push(m);
        return manifests.len - 1;
    }

    fn load_egg(egg: const u8[:], v: Version) -> i64 {
        guard !wants_newest_snapshot(v) else { return -1; }
        let path = str(egg_dir(repository, egg, v), "/barn.pkg");
        guard file_exists(path) else { return -1; }
        let index = load_file(path);
        let found = manifests[index].egg;
        guard found.name == egg && found.version == release_of(v) else {
            fail(str(path, " says it is ", found, ", not ", egg, ":", v));
        }
        return index;
    }

    fn node(egg: const u8[:], v: Version, manifest: i64, override: i64) -> i64 {
        let separator = if override >= 0 && is_local(overrides[override]) { "=" } else { ":" };
        let key = str(egg, separator, v);
        let existing = lookup(node_of_key, key);
        guard existing < 0 else { return existing; }
        let loaded = if manifest >= 0 { manifest } else { load_egg(egg, v) };
        let start = keys.len;
        keys.append(key);
        node_of_key.insert(keys[start..], nodes.len);
        nodes.push(Node { egg: egg, version: v, manifest: loaded, override: override });
        return nodes.len - 1;
    }

    fn add_override(project: Manifest, index: i64) {
        let o = overrides[index];
        guard o.name != project.egg.name else {
            fail(str("barn.pkg overrides ", o.name, ", which is the project itself"));
        }
        guard is_local(o) else {
            override_node.insert(o.name, node(o.name, concrete_version(repository, o.name, o.version), -1, index));
            return;
        }
        let path = str(dir, "/", o.path, "/barn.pkg");
        guard file_exists(path) else { fail(str("override ", o.name, ": there is no barn.pkg in ", o.path)); }
        let loaded = load_file(path);
        let found = manifests[loaded].egg.name;
        guard found == o.name else { fail(str("override ", o.name, ": ", o.path, " holds ", found)); }
        override_node.insert(o.name, node(o.name, manifests[loaded].egg.version, loaded, index));
    }

    fn request(from: i64, d: Dependency) {
        var named = lookup(override_node, d.name);
        if named < 0 {
            named = node(d.name, concrete_version(repository, d.name, d.version), -1, -1);
            let newest = lookup(newest_node, d.name);
            let is_newest = newest < 0 || is_newer(nodes[named].version, nodes[newest].version);
            if is_newest { newest_node.insert(d.name, named); }
        }
        requests.push(Request { from: from, egg: d.name, wanted: d.version, named: named });
    }

    fn walk_graph(project: Manifest) {
        var next = 0;
        while next < nodes.len {
            let current = next;
            next++;
            nodes[current].first_request = requests.len;
            let index = nodes[current].manifest;
            if index >= 0 {
                let m = manifests[index];
                for i in m.first_dependency..dependencies_end(m) {
                    if dependencies[i].name != project.egg.name { request(current, dependencies[i]); }
                }
            }
            nodes[current].request_count = requests.len - nodes[current].first_request;
        }
    }

    fn chosen_node(egg: const u8[:]) -> i64 {
        let forced = lookup(override_node, egg);
        if forced >= 0 { return forced; }
        return lookup(newest_node, egg);
    }

    let root = load_file(str(dir, "/barn.pkg"));
    let project = manifests[root];
    node(project.egg.name, project.egg.version, root, -1);
    for i in project.first_override..overrides_end(project) { add_override(project, i); }
    walk_graph(project);
    for i in 0..requests.len { requests[i].chosen = chosen_node(requests[i].egg); }

    var is_used: bool[>..] = [];
    var used: i64[>..] = [];

    fn mark_used() {
        for _ in nodes.len { is_used.push(false); }
        used.push(0);
        is_used[0] = true;
        var next = 0;
        while next < used.len {
            let n = nodes[used[next]];
            next++;
            for i in n.first_request..n.first_request + n.request_count {
                let chosen = requests[i].chosen;
                if !is_used[chosen] { is_used[chosen] = true; used.push(chosen); }
            }
        }
    }

    mark_used();

    let b = Build { project: project, nodes: nodes[..], requests: requests[..], used: used[..],
                    overrides: overrides[..] };
    let problems = build_problems(b, is_used);
    guard problems.len == 0 else { return str("cannot resolve ", project.egg.name, ":", problems); }
    for i in project.first_override..overrides_end(project) {
        if !is_used[lookup(override_node, overrides[i].name)] {
            write_stderr(str("warning: unused override ", overrides[i].name, "\n"));
        }
    }
    F(b);
    return str("");
}

fn requester(b: Build, node: i64) -> u8[>..] {
    if node == 0 { return str("the project"); }
    return str(b.nodes[node].egg, ":", b.nodes[node].version);
}

fn describe_missing(b: Build, node: i64, is_used: const bool[:], out: u8[>..]&) {
    let n = b.nodes[node];
    if wants_newest_snapshot(n.version) { format(out, "\n  no snapshot of ", n.egg, ":", release_of(n.version)); }
    else { format(out, "\n  ", n.egg, ":", n.version, " not found"); }
    guard n.override < 0 else { out.append(" (override)"); return; }
    out.append(" (wanted by ");
    var first = true;
    for r in b.requests {
        if is_used[r.from] && r.egg == n.egg {
            format(out, if first { "" } else { ", " }, requester(b, r.from));
            first = false;
        }
    }
    out.append(")");
}

fn describe_incompatible(b: Build, node: i64, is_used: const bool[:], out: u8[>..]&) {
    let n = b.nodes[node];
    var incompatible = false;
    for r in b.requests {
        let is_relevant = is_used[r.from] && r.egg == n.egg;
        if is_relevant && !compatible(b.nodes[r.named].version, n.version) { incompatible = true; }
    }
    guard incompatible else { return; }
    format(out, "\n  ", n.egg, ": incompatible versions");
    for r in b.requests {
        if is_used[r.from] && r.egg == n.egg { format(out, "\n    ", requester(b, r.from), " wants ", r.wanted); }
    }
}

fn build_problems(b: Build, is_used: const bool[:]) -> u8[>..] {
    var problems: u8[>..] = [];
    var node_of_name = dictionary<const u8[:], i64> {};
    for node in b.used[1..] {
        let n = b.nodes[node];
        let clash = lookup(node_of_name, short_name(n.egg));
        if clash >= 0 {
            format(problems, "\n  ", b.nodes[clash].egg, " and ", n.egg, " are both imported as '",
                   short_name(n.egg), "'");
        }
        node_of_name.insert(short_name(n.egg), node);
        if n.manifest < 0 { describe_missing(b, node, is_used, problems); }
        else if n.override < 0 { describe_incompatible(b, node, is_used, problems); }
    }
    return problems;
}
