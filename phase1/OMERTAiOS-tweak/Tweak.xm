#import <UIKit/UIKit.h>
#import "OwnerLock.h"
#import "OMLockViewController.h"

@interface SpringBoard : UIApplication
@end

static UIWindow *gOMLockWindow;

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    // Set NSLog(@"[OMERTA] ...") checkpoints back in here (and tail syslog
    // with `idevicesyslog | grep -i omerta` from the host) if this needs
    // debugging again on a device with no working screen -- that's how
    // Phase 1's logic was confirmed working end-to-end even before it was
    // ever seen rendered. See toolchain/03-odyssey-bootstrap-and-headless-debug.md.
    if ([OMOwnerLock hasOwnerPin]) {
        gOMLockWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        gOMLockWindow.windowLevel = CGFLOAT_MAX;
        gOMLockWindow.rootViewController = [[OMLockViewController alloc] init];
        [gOMLockWindow makeKeyAndVisible];
    }
}

%end
