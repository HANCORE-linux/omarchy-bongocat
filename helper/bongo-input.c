#define _DEFAULT_SOURCE
#define _POSIX_C_SOURCE 200809L

#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <time.h>
#include <unistd.h>

#define MAX_DEVICES 64
#define MAX_BITMAP_WORDS 64
#define RESCAN_SECONDS 5

typedef struct {
  char path[512];
  char name[256];
  bool readable;
  int fd;
} keyboard_t;

static volatile sig_atomic_t running = 1;
static pid_t bound_parent_pid = -1;

static void handle_signal(int signal_number) {
  (void)signal_number;
  running = 0;
}

static bool enter_session_mode(void) {
  if (geteuid() == 0) {
    fputs("Session input helper must not run as root.\n", stderr);
    return false;
  }

  pid_t parent = getppid();
  if (parent <= 1 || prctl(PR_SET_PDEATHSIG, SIGTERM) != 0 || getppid() != parent ||
      prctl(PR_SET_DUMPABLE, 0) != 0 ||
      prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0 ||
      prctl(PR_SET_NAME, "bongo-input", 0, 0, 0) != 0) {
    fputs("Could not harden the session input helper.\n", stderr);
    return false;
  }
  bound_parent_pid = parent;
  return true;
}

static void trim_newline(char *text) {
  size_t length = strlen(text);
  while (length > 0 && (text[length - 1] == '\n' || text[length - 1] == '\r'))
    text[--length] = '\0';
}

static bool read_text_file(const char *path, char *buffer, size_t size) {
  FILE *file = fopen(path, "r");
  if (!file)
    return false;
  bool ok = fgets(buffer, (int)size, file) != NULL;
  fclose(file);
  if (ok)
    trim_newline(buffer);
  return ok;
}

/*
 * Linux exposes capability bitmaps as hexadecimal words, most-significant
 * word first. Input event key codes are counted from the least-significant
 * word, so index from the end of the token list.
 */
static bool bitmap_has_key(const char *bitmap, unsigned int keycode) {
  char copy[4096];
  char *words[MAX_BITMAP_WORDS];
  size_t count = 0;

  snprintf(copy, sizeof(copy), "%s", bitmap);
  char *save = NULL;
  for (char *word = strtok_r(copy, " \t", &save); word && count < MAX_BITMAP_WORDS;
       word = strtok_r(NULL, " \t", &save)) {
    words[count++] = word;
  }

  const unsigned int bits_per_word = 64;
  unsigned int word_from_right = keycode / bits_per_word;
  unsigned int bit = keycode % bits_per_word;
  if (word_from_right >= count)
    return false;

  const char *word = words[count - 1 - word_from_right];
  errno = 0;
  unsigned long long value = strtoull(word, NULL, 16);
  return errno == 0 && (value & (1ULL << bit)) != 0;
}

static bool is_typing_keyboard(const char *event) {
  char path[512];
  char bitmap[4096];
  snprintf(path, sizeof(path), "/sys/class/input/%s/device/capabilities/key", event);
  if (!read_text_file(path, bitmap, sizeof(bitmap)))
    return false;

  return bitmap_has_key(bitmap, KEY_A) && bitmap_has_key(bitmap, KEY_Z) &&
         bitmap_has_key(bitmap, KEY_ENTER) && bitmap_has_key(bitmap, KEY_SPACE);
}

static bool read_keyboard_name(const char *event, char *name, size_t size) {
  char path[512];
  snprintf(path, sizeof(path), "/sys/class/input/%s/device/name", event);
  return read_text_file(path, name, size);
}

static bool name_looks_like_pointer(const char *name) {
  char lower[256];
  size_t length = strlen(name);
  if (length >= sizeof(lower))
    length = sizeof(lower) - 1;
  for (size_t i = 0; i < length; ++i)
    lower[i] = (char)tolower((unsigned char)name[i]);
  lower[length] = '\0';

  static const char *markers[] = {
      "mouse", "touchpad", "trackball", "basilisk", "deathadder",
      "mx master", "mx anywhere", "magic trackpad",
  };
  for (size_t i = 0; i < sizeof(markers) / sizeof(markers[0]); ++i) {
    if (strstr(lower, markers[i]) != NULL)
      return true;
  }
  return false;
}

static int event_filter(const struct dirent *entry) {
  return strncmp(entry->d_name, "event", 5) == 0;
}

static int discover_keyboards(keyboard_t *devices, const char *selected_name,
                              bool keep_open) {
  struct dirent **entries = NULL;
  int entry_count = scandir("/dev/input", &entries, event_filter, alphasort);
  if (entry_count < 0)
    return 0;

  int count = 0;
  for (int i = 0; i < entry_count; ++i) {
    const char *event = entries[i]->d_name;
    if (count >= MAX_DEVICES) {
      free(entries[i]);
      continue;
    }
    if (!is_typing_keyboard(event)) {
      free(entries[i]);
      continue;
    }

    keyboard_t candidate = {.fd = -1};
    snprintf(candidate.path, sizeof(candidate.path), "/dev/input/%s", event);
    if (!read_keyboard_name(event, candidate.name, sizeof(candidate.name)) ||
        name_looks_like_pointer(candidate.name)) {
      free(entries[i]);
      continue;
    }
    if (selected_name && selected_name[0] != '\0' &&
        strcmp(candidate.name, selected_name) != 0) {
      free(entries[i]);
      continue;
    }

    candidate.fd = open(candidate.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    candidate.readable = candidate.fd >= 0;
    if (!keep_open && candidate.fd >= 0) {
      close(candidate.fd);
      candidate.fd = -1;
    }
    devices[count++] = candidate;
    free(entries[i]);
  }

  free(entries);
  return count;
}

static void json_string(const char *text) {
  putchar('"');
  for (const unsigned char *cursor = (const unsigned char *)text; *cursor; ++cursor) {
    switch (*cursor) {
    case '"': fputs("\\\"", stdout); break;
    case '\\': fputs("\\\\", stdout); break;
    case '\b': fputs("\\b", stdout); break;
    case '\f': fputs("\\f", stdout); break;
    case '\n': fputs("\\n", stdout); break;
    case '\r': fputs("\\r", stdout); break;
    case '\t': fputs("\\t", stdout); break;
    default:
      if (*cursor < 0x20)
        printf("\\u%04x", *cursor);
      else
        putchar(*cursor);
    }
  }
  putchar('"');
}

static int list_keyboards(void) {
  keyboard_t devices[MAX_DEVICES];
  int count = discover_keyboards(devices, NULL, false);
  putchar('[');
  for (int i = 0; i < count; ++i) {
    if (i > 0)
      putchar(',');
    fputs("{\"path\":", stdout);
    json_string(devices[i].path);
    fputs(",\"name\":", stdout);
    json_string(devices[i].name);
    printf(",\"readable\":%s}", devices[i].readable ? "true" : "false");
  }
  puts("]");
  return 0;
}

static char paw_for_key(unsigned short keycode) {
  static const unsigned short left_keys[] = {
      KEY_ESC, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_TAB,
      KEY_Q, KEY_W, KEY_E, KEY_R, KEY_T, KEY_LEFTCTRL, KEY_A, KEY_S,
      KEY_D, KEY_F, KEY_G, KEY_GRAVE, KEY_LEFTSHIFT, KEY_Z, KEY_X,
      KEY_C, KEY_V, KEY_B, KEY_LEFTALT, KEY_CAPSLOCK, KEY_LEFTMETA,
      KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5,
  };
  static const unsigned short right_keys[] = {
      KEY_7, KEY_8, KEY_9, KEY_0, KEY_MINUS, KEY_EQUAL, KEY_BACKSPACE,
      KEY_Y, KEY_U, KEY_I, KEY_O, KEY_P, KEY_LEFTBRACE, KEY_RIGHTBRACE,
      KEY_ENTER, KEY_H, KEY_J, KEY_K, KEY_L, KEY_SEMICOLON, KEY_APOSTROPHE,
      KEY_N, KEY_M, KEY_COMMA, KEY_DOT, KEY_SLASH, KEY_RIGHTSHIFT,
      KEY_KPASTERISK, KEY_SPACE, KEY_F6, KEY_F7, KEY_F8, KEY_F9, KEY_F10,
      KEY_NUMLOCK, KEY_SCROLLLOCK, KEY_KP7, KEY_KP8, KEY_KP9, KEY_KPMINUS,
      KEY_KP4, KEY_KP5, KEY_KP6, KEY_KPPLUS, KEY_KP1, KEY_KP2, KEY_KP3,
      KEY_KP0, KEY_KPDOT, KEY_102ND, KEY_F11, KEY_F12, KEY_KPENTER,
      KEY_RIGHTCTRL, KEY_KPSLASH, KEY_SYSRQ, KEY_RIGHTALT, KEY_HOME,
      KEY_UP, KEY_PAGEUP, KEY_LEFT, KEY_RIGHT, KEY_END, KEY_DOWN,
      KEY_PAGEDOWN, KEY_INSERT, KEY_DELETE, KEY_PAUSE, KEY_RIGHTMETA,
      KEY_COMPOSE,
  };
  for (size_t i = 0; i < sizeof(left_keys) / sizeof(left_keys[0]); ++i) {
    if (left_keys[i] == keycode)
      return 'L';
  }
  for (size_t i = 0; i < sizeof(right_keys) / sizeof(right_keys[0]); ++i) {
    if (right_keys[i] == keycode)
      return 'R';
  }
  return '\0';
}

static void close_keyboards(keyboard_t *devices, int count) {
  for (int i = 0; i < count; ++i) {
    if (devices[i].fd >= 0)
      close(devices[i].fd);
    devices[i].fd = -1;
  }
}

static long monotonic_seconds(void) {
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  return now.tv_sec;
}

static void emit_status(const char *state, int count, char *last_state,
                        size_t last_state_size, int *last_count) {
  if (strcmp(state, last_state) == 0 && count == *last_count)
    return;
  printf("STATUS\t%s\t%d\n", state, count);
  fflush(stdout);
  snprintf(last_state, last_state_size, "%s", state);
  *last_count = count;
}

static int watch_keyboards(const char *selected_name, const int *inherited_fds,
                           int inherited_count) {
  keyboard_t devices[MAX_DEVICES];
  int device_count = 0;
  long next_scan = 0;
  char last_state[32] = "";
  int last_count = -1;

  setvbuf(stdout, NULL, _IOLBF, 0);
  signal(SIGINT, handle_signal);
  signal(SIGTERM, handle_signal);

  bool session_scoped = inherited_count >= 0;
  if (session_scoped) {
    for (int i = 0; i < inherited_count && i < MAX_DEVICES; ++i) {
      if (inherited_fds[i] < 3 || fcntl(inherited_fds[i], F_GETFD) < 0)
        continue;
      devices[device_count] = (keyboard_t){.readable = true, .fd = inherited_fds[i]};
      snprintf(devices[device_count].path, sizeof(devices[device_count].path),
               "inherited:%d", inherited_fds[i]);
      ++device_count;
    }
    emit_status(device_count > 0 ? "ready" : "no-device", device_count,
                last_state, sizeof(last_state), &last_count);
  }

  while (running) {
    if (bound_parent_pid > 1 && getppid() != bound_parent_pid)
      break;
    long now = monotonic_seconds();
    if (!session_scoped && now >= next_scan) {
      close_keyboards(devices, device_count);
      device_count = discover_keyboards(devices, selected_name, true);
      int readable_count = 0;
      for (int i = 0; i < device_count; ++i)
        readable_count += devices[i].readable ? 1 : 0;

      if (device_count == 0)
        emit_status("no-device", 0, last_state, sizeof(last_state), &last_count);
      else if (readable_count == 0)
        emit_status("permission", device_count, last_state, sizeof(last_state), &last_count);
      else
        emit_status("ready", readable_count, last_state, sizeof(last_state), &last_count);
      next_scan = now + RESCAN_SECONDS;
    }

    struct pollfd poll_fds[MAX_DEVICES];
    int map[MAX_DEVICES];
    int poll_count = 0;
    for (int i = 0; i < device_count; ++i) {
      if (devices[i].fd < 0)
        continue;
      poll_fds[poll_count] = (struct pollfd){.fd = devices[i].fd, .events = POLLIN};
      map[poll_count++] = i;
    }

    int timeout_ms = 1000;
    if (!session_scoped) {
      timeout_ms = (int)((next_scan - monotonic_seconds()) * 1000);
      if (timeout_ms < 100)
        timeout_ms = 100;
      if (timeout_ms > 1000)
        timeout_ms = 1000;
    }

    int result = poll(poll_fds, (nfds_t)poll_count, timeout_ms);
    if (result <= 0)
      continue;

    for (int i = 0; i < poll_count; ++i) {
      if (!(poll_fds[i].revents & (POLLIN | POLLERR | POLLHUP | POLLNVAL)))
        continue;
      keyboard_t *device = &devices[map[i]];
      if (poll_fds[i].revents & (POLLERR | POLLHUP | POLLNVAL)) {
        close(device->fd);
        device->fd = -1;
        int remaining = 0;
        for (int index = 0; index < device_count; ++index)
          remaining += devices[index].fd >= 0 ? 1 : 0;
        emit_status(remaining > 0 ? "ready" : "no-device", remaining,
                    last_state, sizeof(last_state), &last_count);
        continue;
      }
      struct input_event events[32];
      ssize_t bytes = read(device->fd, events, sizeof(events));
      if (bytes <= 0)
        continue;
      size_t event_count = (size_t)bytes / sizeof(events[0]);
      for (size_t event_index = 0; event_index < event_count; ++event_index) {
        struct input_event *event = &events[event_index];
        if (event->type != EV_KEY || event->value != 1)
          continue;
        char paw = paw_for_key(event->code);
        if (paw != '\0')
          printf("%c\n", paw);
      }
    }
  }

  close_keyboards(devices, device_count);
  return 0;
}

static void usage(FILE *stream, const char *program) {
  fprintf(stream,
          "Usage: %s [--watch] [--name DEVICE_NAME]\n"
          "       %s --list\n\n"
          "Emits only L/R paw events; it never prints key codes or key text.\n",
          program, program);
}

int main(int argc, char **argv) {
  bool list = false;
  bool session_fds = false;
  int inherited_fds[MAX_DEVICES];
  int inherited_count = 0;
  int close_fd = -1;
  const char *selected_name = NULL;

  for (int i = 1; i < argc; ++i) {
    if (strcmp(argv[i], "--list") == 0) {
      list = true;
    } else if (strcmp(argv[i], "--watch") == 0) {
      continue;
    } else if (strcmp(argv[i], "--session-fds") == 0) {
      session_fds = true;
    } else if (strcmp(argv[i], "--fd") == 0 && i + 1 < argc) {
      char *end = NULL;
      errno = 0;
      long parsed_fd = strtol(argv[++i], &end, 10);
      if (errno != 0 || !end || *end != '\0' || parsed_fd < 3 ||
          inherited_count >= MAX_DEVICES) {
        fputs("Invalid inherited input descriptor.\n", stderr);
        return 2;
      }
      inherited_fds[inherited_count++] = (int)parsed_fd;
    } else if (strcmp(argv[i], "--close-fd") == 0 && i + 1 < argc) {
      char *end = NULL;
      errno = 0;
      long parsed_fd = strtol(argv[++i], &end, 10);
      if (errno != 0 || !end || *end != '\0' || parsed_fd < 3) {
        fputs("Invalid helper descriptor.\n", stderr);
        return 2;
      }
      close_fd = (int)parsed_fd;
    } else if (strcmp(argv[i], "--name") == 0 && i + 1 < argc) {
      selected_name = argv[++i];
    } else if (strcmp(argv[i], "--version") == 0) {
      puts("bongo-input 1.2.0");
      return 0;
    } else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
      usage(stdout, argv[0]);
      return 0;
    } else {
      usage(stderr, argv[0]);
      return 2;
    }
  }

  if (list && session_fds) {
    fputs("--session-fds cannot be combined with --list.\n", stderr);
    return 2;
  }
  if (!session_fds && inherited_count > 0) {
    fputs("--fd requires --session-fds.\n", stderr);
    return 2;
  }
  if (session_fds && !enter_session_mode())
    return 1;
  if (close_fd >= 0)
    close(close_fd);

  return list ? list_keyboards()
              : watch_keyboards(selected_name,
                                session_fds ? inherited_fds : NULL,
                                session_fds ? inherited_count : -1);
}
