//
// OMERTA iOS — phase3 patched-ramdisk proof-of-concept.
//
// Replaces /usr/local/bin/restored_external (the real Apple restore
// protocol daemon) in a RestoreRamDisk. Deliberately minimal: prints a
// banner to console (the ramdisk's own com.apple.restored_external.plist
// already routes stdout/stderr to /dev/console, unmodified), then stays
// alive so the boot doesn't look crashed. Nothing else — no restore
// protocol, no filesystem writes, no persistence. Proves the actual
// mechanism (checkra1n -k -> modload KPF -> ramdisk -> bootx with
// rootdev=md0 -> our code runs instead of Apple's) works, before any
// real OMERTA recovery-environment functionality gets built on top.
//
// Plain C, no Objective-C/Foundation -- this ramdisk ships flat
// libSystem-family dylibs (libSystem.B.dylib, libdyld.dylib,
// libsystem_kernel.dylib, etc.) but no .framework bundles, so keeping
// this dependency-free avoids any risk of a missing framework at
// runtime.
//
#include <unistd.h>
#include <string.h>

int main(int argc, char *argv[]) {
    (void)argc;
    (void)argv;

    static const char banner[] =
        "\n"
        "  ============================================\n"
        "   OMERTA iOS -- phase3 patched ramdisk\n"
        "  ============================================\n"
        "   restored_external has been replaced.\n"
        "   This is NOT Apple's real restore protocol.\n"
        "  ============================================\n"
        "\n";

    write(STDOUT_FILENO, banner, strlen(banner));

    for (;;) {
        sleep(5);
    }
    return 0;
}
