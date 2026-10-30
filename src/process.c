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

static wchar_t *command_line(barn_bytes arguments) {
    int length = MultiByteToWideChar(CP_UTF8, 0, (const char *)arguments.data, (int)arguments.len, NULL, 0);
    wchar_t *wide = calloc((size_t)length + 1, sizeof(wchar_t));
    wchar_t *line = calloc((size_t)length * 3 + 3, sizeof(wchar_t));
    if (!wide || !line) { free(wide); free(line); return NULL; }
    MultiByteToWideChar(CP_UTF8, 0, (const char *)arguments.data, (int)arguments.len, wide, length);
    size_t at = 0;
    for (int i = 0; i < length; i += (int)wcslen(wide + i) + 1) {
        if (at > 0) line[at++] = L' ';
        append_quoted(line, &at, wide + i);
    }
    free(wide);
    return line;
}

int64_t barn_run_program(barn_bytes arguments) {
    wchar_t *line = command_line(arguments);
    if (!line) return -1;
    STARTUPINFOW startup = { sizeof startup };
    PROCESS_INFORMATION process;
    BOOL started = CreateProcessW(NULL, line, NULL, NULL, TRUE, 0, NULL, NULL, &startup, &process);
    free(line);
    if (!started) return -1;
    WaitForSingleObject(process.hProcess, INFINITE);
    DWORD code = 1;
    GetExitCodeProcess(process.hProcess, &code);
    CloseHandle(process.hProcess);
    CloseHandle(process.hThread);
    return (int64_t)code;
}

#else
#include <errno.h>
#include <spawn.h>
#include <sys/wait.h>

extern char **environ;

int64_t barn_run_program(barn_bytes arguments) {
    int64_t count = 0;
    for (int64_t i = 0; i < arguments.len; i++) if (arguments.data[i] == 0) count++;
    char *text = malloc((size_t)arguments.len + 1);
    char **argv = calloc((size_t)count + 1, sizeof(char *));
    if (!text || !argv || count == 0) { free(text); free(argv); return -1; }
    memcpy(text, arguments.data, (size_t)arguments.len);
    text[arguments.len] = 0;
    for (int64_t i = 0, at = 0; i < count; i++) {
        argv[i] = text + at;
        at += (int64_t)strlen(text + at) + 1;
    }
    pid_t pid;
    int failed = posix_spawnp(&pid, argv[0], NULL, NULL, argv, environ);
    free(argv);
    free(text);
    if (failed) return -1;
    int status;
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    return 128 + WTERMSIG(status);
}
#endif
