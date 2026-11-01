import std;

extern "barn_run_program" fn run_program(arguments: const u8[:]) -> i64;
extern "barn_run_program_into" fn run_program_into(arguments: const u8[:], output: const u8[:]) -> i64;

fn joined_arguments(arguments: const u8[:][:]) -> u8[>..] {
    var joined: u8[>..] = [];
    for a in arguments { format(joined, a, "\0"); }
    return joined;
}

fn run_program(arguments: const u8[:][:]) -> i64 { run_program(joined_arguments(arguments)) }

fn run_program_into(arguments: const u8[:][:], output: const u8[:]) -> i64 {
    run_program_into(joined_arguments(arguments), output)
}

extern "barn_make_writable" fn make_writable(path: const u8[:]) -> i64;
