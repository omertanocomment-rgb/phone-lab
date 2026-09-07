//
// OMERTA iOS — phase3 persistence proof-of-concept
//
// A minimal LaunchDaemon, not a SpringBoard hook. Its whole job is to
// prove PLAN.md's phase3 claim for real: that OMERTA components can
// start automatically via launchd post-jailbreak, independent of
// SpringBoard's own process lifecycle, persistent across reboots for
// as long as the jailbreak stays applied (the normal checkra1n
// semi-tethered model — see phase1/toolchain/01-jailbreak-iphone6-checkra1n.md).
//
// It reuses OwnerLock.m/.h directly from phase1/OMERTAiOS-tweak (the
// same Keychain-backed PIN storage the tweak already uses, tested and
// confirmed working on real hardware) rather than duplicating or
// inventing new owner-lock logic — this is meant as a first real
// building block toward a background "hidden control hub" process
// (phase1/OMERTA-iOS-PLAN.md's own roadmap item 4), not that feature
// itself.
//
// What it actually does, honestly: runs once at launchd load
// (RunAtLoad), reads whether an owner PIN is set, appends one
// timestamped line to a log file, exits. Nothing more — no polling
// loop, no KeepAlive, no network, no control-hub UI. Confirming the
// daemon fires automatically (checked via that log file after a
// respring/reboot, not requiring any manual step) is the entire
// point of this phase3 slice.
//
#import <Foundation/Foundation.h>
#import "OwnerLock.h"

static NSString * const kLogPath = @"/var/mobile/omerta_persistd.log";

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss Z";
        NSString *timestamp = [fmt stringFromDate:[NSDate date]];

        BOOL hasPin = [OMOwnerLock hasOwnerPin];
        NSString *line = [NSString stringWithFormat:
            @"%@ omerta_persistd started via launchd (pid %d), hasOwnerPin=%@\n",
            timestamp, getpid(), hasPin ? @"YES" : @"NO"];

        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:kLogPath]) {
            [fm createFileAtPath:kLogPath contents:nil attributes:nil];
        }
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:kLogPath];
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
    return 0;
}
