#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct { const uint8_t *data; int64_t len; } barn_bytes;

#ifdef _WIN32
#include <windows.h>

static void append_backslashes(wchar_t *out, size_t *at, size_t count) {
    for (size_t i = 0; i < count; i++) out[(*at)++] = L'\\';
}

static void append_quoted(wchar_t *out, size_t *at, const wchar_t *argument) {
    int needs_quotes = argument[0] == 0 || wcspbrk(argument, L" \t\"") != NULL;
    if (needs_quotes) out[(*at)++] = L'"';
    for (const wchar_t *p = argument;; p++) {
        size_t backslashes = 0;
        while (*p == L'\\') { backslashes++; p++; }
        if (*p == 0) {
            append_backslashes(out, at, needs_quotes ? backslashes * 2 : backslashes);
            break;
        }
        append_backslashes(out, at, *p == L'"' ? backslashes * 2 + 1 : backslashes);
        out[(*at)++] = *p;
    }
    if (needs_quotes) out[(*at)++] = L'"';
}

static wchar_t *wide_text(barn_bytes text) {
    int length = MultiByteToWideChar(CP_UTF8, 0, (const char *)text.data, (int)text.len, NULL, 0);
    wchar_t *wide = calloc((size_t)length + 1, sizeof(wchar_t));
    if (wide) MultiByteToWideChar(CP_UTF8, 0, (const char *)text.data, (int)text.len, wide, length);
    return wide;
}

static wchar_t *command_line(barn_bytes arguments) {
    wchar_t *wide = wide_text(arguments);
    int length = MultiByteToWideChar(CP_UTF8, 0, (const char *)arguments.data, (int)arguments.len, NULL, 0);
    wchar_t *line = calloc((size_t)length * 3 + 3, sizeof(wchar_t));
    if (!wide || !line) { free(wide); free(line); return NULL; }
    size_t at = 0;
    for (int i = 0; i < length; i += (int)wcslen(wide + i) + 1) {
        if (at > 0) line[at++] = L' ';
        append_quoted(line, &at, wide + i);
    }
    free(wide);
    return line;
}

static int64_t run_with(wchar_t *line, STARTUPINFOW *startup) {
    PROCESS_INFORMATION process;
    BOOL started = CreateProcessW(NULL, line, NULL, NULL, TRUE, 0, NULL, NULL, startup, &process);
    free(line);
    if (!started) return -1;
    WaitForSingleObject(process.hProcess, INFINITE);
    DWORD code = 1;
    GetExitCodeProcess(process.hProcess, &code);
    CloseHandle(process.hProcess);
    CloseHandle(process.hThread);
    return (int64_t)code;
}

int64_t barn_run_program(barn_bytes arguments) {
    wchar_t *line = command_line(arguments);
    if (!line) return -1;
    STARTUPINFOW startup = { sizeof startup };
    return run_with(line, &startup);
}

int64_t barn_run_program_into(barn_bytes arguments, barn_bytes output) {
    wchar_t *line = command_line(arguments);
    wchar_t *path = wide_text(output);
    if (!line || !path) { free(line); free(path); return -1; }
    SECURITY_ATTRIBUTES inherit = { sizeof inherit, NULL, TRUE };
    HANDLE out = CreateFileW(path, GENERIC_WRITE, 0, &inherit, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    HANDLE quiet = CreateFileW(L"NUL", GENERIC_WRITE, FILE_SHARE_WRITE, &inherit, OPEN_EXISTING, 0, NULL);
    free(path);
    if (out == INVALID_HANDLE_VALUE || quiet == INVALID_HANDLE_VALUE) {
        if (out != INVALID_HANDLE_VALUE) CloseHandle(out);
        if (quiet != INVALID_HANDLE_VALUE) CloseHandle(quiet);
        free(line);
        return -1;
    }
    STARTUPINFOW startup = { sizeof startup };
    startup.dwFlags = STARTF_USESTDHANDLES;
    startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    startup.hStdOutput = out;
    startup.hStdError = quiet;
    int64_t code = run_with(line, &startup);
    CloseHandle(out);
    CloseHandle(quiet);
    return code;
}

#else
#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <sys/wait.h>

extern char **environ;

static char *zero_terminated(barn_bytes text) {
    char *copy = malloc((size_t)text.len + 1);
    if (!copy) return NULL;
    memcpy(copy, text.data, (size_t)text.len);
    copy[text.len] = 0;
    return copy;
}

static int64_t spawn_and_wait(barn_bytes arguments, const posix_spawn_file_actions_t *actions) {
    int64_t count = 0;
    for (int64_t i = 0; i < arguments.len; i++) if (arguments.data[i] == 0) count++;
    char *text = zero_terminated(arguments);
    char **argv = calloc((size_t)count + 1, sizeof(char *));
    if (!text || !argv || count == 0) { free(text); free(argv); return -1; }
    for (int64_t i = 0, at = 0; i < count; i++) {
        argv[i] = text + at;
        at += (int64_t)strlen(text + at) + 1;
    }
    pid_t pid;
    int failed = posix_spawnp(&pid, argv[0], actions, NULL, argv, environ);
    free(argv);
    free(text);
    if (failed) return -1;
    int status;
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    return 128 + WTERMSIG(status);
}

int64_t barn_run_program(barn_bytes arguments) { return spawn_and_wait(arguments, NULL); }

int64_t barn_run_program_into(barn_bytes arguments, barn_bytes output) {
    char *path = zero_terminated(output);
    if (!path) return -1;
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, 1, path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0);
    int64_t code = spawn_and_wait(arguments, &actions);
    posix_spawn_file_actions_destroy(&actions);
    free(path);
    return code;
}
#endif
