import std;
import os;
import src.project;
import src.resolve;
import src.copies;
import src.process;

fn check_build(p: Project, b: Build, eggs: const u8[:]) -> u8[>..] {
    var check = check_copies(b, p.dir, eggs);
    return copy_problems(check);
}

fn goose_arguments(command: const u8[:], root: const u8[:], passed: const u8[:][:]) -> (const u8[:])[>..] {
    let goose_command: const u8[:] = if command == "build" { "build" } else { "run" };
    var arguments: (const u8[:])[>..] = ["goose", goose_command, root];
    if goose_command == "run" && passed.len > 0 { arguments.push("--"); }
    for a in passed { arguments.push(a); }
    return arguments;
}

fn run_goose(command: const u8[:], dir: const u8[:], eggs: const u8[:], passed: const u8[:][:]) -> u8[>..] {
    return with_project(dir) { p =>
        let file = if command == "test" { test_file(p) } else { main_file(p) };
        let root: u8[>..] = if dir == "." { str(file) } else { str(dir, "/", file) };
        guard file_exists(root) else { return str("no ", root); }
        return resolve(dir, eggs) { b =>
            let problem = check_build(p, b, eggs);
            guard problem.len == 0 else { return problem; }
            let status = run_program(goose_arguments(command, root, passed)[..]);
            guard status >= 0 else { return str("cannot start goose"); }
            if status != 0 { exit(status); }
            return str("");
        };
    };
}
