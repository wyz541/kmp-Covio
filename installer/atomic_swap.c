#include <errno.h>
#include <fcntl.h>
#include <libgen.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int fsync_parent(const char *path) {
    char copy[PATH_MAX];
    if (strlen(path) >= sizeof(copy)) {
        errno = ENAMETOOLONG;
        return -1;
    }
    strcpy(copy, path);
    const int descriptor = open(dirname(copy), O_RDONLY | O_DIRECTORY);
    if (descriptor < 0) {
        return -1;
    }
    const int result = fsync(descriptor);
    close(descriptor);
    return result;
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <path-a> <path-b>\n", argv[0]);
        return 2;
    }
    if (renamex_np(argv[1], argv[2], RENAME_SWAP) != 0) {
        fprintf(stderr, "renamex_np(%s, %s): %s\n", argv[1], argv[2], strerror(errno));
        return 1;
    }
    if (fsync_parent(argv[1]) != 0 || fsync_parent(argv[2]) != 0) {
        fprintf(stderr, "fsync parent directory: %s\n", strerror(errno));
        return 1;
    }
    return 0;
}
