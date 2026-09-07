//
// OMERTA iOS — phase2 pongoOS module
//
// This is a loadable pongoOS module built against the real upstream module
// ABI (verified against checkra1n/PongoOS: example/testmodule/main.c,
// example/include/pongo.h, src/shell/command.c). It is NOT compiled into
// PongoConsolidated.bin — it's a separate Mach-O that gets pushed over USB
// after Pongo is already running and loaded with the `modload` shell
// command (see ../../tools/omerta_load.py).
//
// What it does, honestly:
//   - Registers an `omerta` shell command that prints an OMERTA status
//     banner (device info pulled from pongoOS globals: boot args, device
//     tree machine type).
//   - Hooks preboot_hook so the banner also prints automatically, once,
//     right before Pongo hands off to iOS/XNU (i.e. on `bootx`), while
//     chaining to whatever hook was already installed (so we don't stomp
//     on KPF or anything else that registered first).
//   - Nothing here is persistent or graphical yet — see phase2/README.md
//     "What this is not (yet)".
//
#include <pongo.h>

// ---------------------------------------------------------------------
// preboot hook chaining
// ---------------------------------------------------------------------

static void (*omerta_existing_preboot_hook)();
static char omerta_banner_shown;

static void omerta_print_banner(void)
{
    puts("");
    puts("  ============================================");
    puts("   OMERTA iOS -- phase2 pongoOS boot environment");
    puts("  ============================================");

    if (gDevType)
        iprintf("   device      : %s\n", gDevType);
    if (gBootArgs)
        iprintf("   boot_args   : rev %u ver %u, memSize 0x%llx\n",
                 gBootArgs->Revision, gBootArgs->Version,
                 (unsigned long long)gBootArgs->memSize);
    iprintf("   ticks       : %llu\n", (unsigned long long)get_ticks());
    puts("   status      : module loaded, preboot hook armed");
    puts("  ============================================");
    puts("");
}

static void omerta_preboot_hook(void)
{
    if (!omerta_banner_shown) {
        omerta_banner_shown = 1;
        omerta_print_banner();
    }
    // Always chain to whatever was registered before us (KPF, other
    // modules). Never swallow the existing hook.
    if (omerta_existing_preboot_hook != NULL)
        omerta_existing_preboot_hook();
}

// ---------------------------------------------------------------------
// `omerta` shell command — manual trigger, works even if bootx is never
// called (e.g. testing with `checkra1n -k Pongo.bin` and no ramdisk).
// ---------------------------------------------------------------------

static void omerta_cmd(const char* cmd, char* args)
{
    (void)cmd;
    (void)args;
    omerta_print_banner();
}

// ---------------------------------------------------------------------
// module entry point — called once when pongoOS finishes loading this
// Mach-O via `modload`.
// ---------------------------------------------------------------------

void module_entry(void)
{
    omerta_existing_preboot_hook = preboot_hook;
    preboot_hook = omerta_preboot_hook;
    command_register("omerta", "show the OMERTA iOS boot status banner", omerta_cmd);
}

char* module_name = "omerta_boot";

// No symbols exported for other modules to link against (yet). If a
// later phase2 module needs to call into this one, add entries here —
// see pongoOS's own checkra1n-kpf-pongo module for the pattern.
struct pongo_exports exported_symbols[] = {
    {.name = 0, .value = 0}
};
