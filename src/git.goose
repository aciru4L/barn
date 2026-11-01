import std;
import os;
import src.process;
import src.files;

fn run_git_reporting(dir: const u8[:], scratch: const u8[:], command: const u8[:][:], out: u8[>..]&,
                     errors: u8[>..]&) -> i64 {
    let output = scratch_path(scratch, "git");
    let error_output = str(output, "-errors");
    var arguments: (const u8[:])[>..] = ["git", "-c", "core.longpaths=true", "-C", dir];
    for a in command { arguments.push(a); }
    let status = run_program_into(arguments[..], output, error_output);
    read_file(output, out);
    read_file(error_output, errors);
    delete_file(output);
    delete_file(error_output);
    return status;
}

fn run_git(dir: const u8[:], scratch: const u8[:], command: const u8[:][:], out: u8[>..]&) -> i64 {
    var errors: u8[>..] = [];
    return run_git_reporting(dir, scratch, command, out, errors);
}

fn git_succeeds(dir: const u8[:], scratch: const u8[:], command: const u8[:][:]) -> bool {
    var out: u8[>..] = [];
    return run_git(dir, scratch, command, out) == 0;
}

fn is_git_complaint(line: const u8[:]) -> bool { starts_with(line, "fatal: ") || starts_with(line, "error: ") }

fn git_reason(errors: const u8[:]) -> u8[>..] {
    var reason: u8[>..] = [];
    var found = false;
    each_split(errors, '\n') { raw =>
        let line = trim(raw);
        if !found && is_git_complaint(line) {
            reason.clear();
            reason.append(line[7..]);
            found = true;
        } else if !found && line.len > 0 {
            reason.clear();
            reason.append(line);
        }
    };
    guard reason.len > 0 else { return reason; }
    return str(" (git: ", reason, ")");
}
