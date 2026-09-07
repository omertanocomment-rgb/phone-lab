#import <UIKit/UIKit.h>
#import "OwnerLock.h"
#import "OMLockViewController.h"

@interface SpringBoard : UIApplication
@end

static UIWindow *gOMLockWindow;

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    NSLog(@"[OMERTA] applicationDidFinishLaunching fired");
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    NSLog(@"[OMERTA] idleTimerDisabled set to YES");
    BOOL hasPin = [OMOwnerLock hasOwnerPin];
    NSLog(@"[OMERTA] hasOwnerPin = %d", hasPin);
    if (hasPin) {
        NSLog(@"[OMERTA] creating lock window");
        gOMLockWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        gOMLockWindow.windowLevel = CGFLOAT_MAX;
        gOMLockWindow.rootViewController = [[OMLockViewController alloc] init];
        [gOMLockWindow makeKeyAndVisible];
        NSLog(@"[OMERTA] lock window made key and visible, frame=%@", NSStringFromCGRect(gOMLockWindow.frame));
    }
}

%end

%ctor {
    NSLog(@"[OMERTA] ctor firing, setting PIN");
    [OMOwnerLock setOwnerPin:@"1234"];
    NSLog(@"[OMERTA] ctor done");
}
