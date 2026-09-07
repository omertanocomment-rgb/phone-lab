#import <UIKit/UIKit.h>

// Full-screen PIN-entry screen presented above SpringBoard by Tweak.xm.
// Phase 1 only checks the real owner PIN; duress/Safe Mode routing is a
// later phase (see OMERTA-iOS-PLAN.md) and must NOT be added here until
// this phase has been built and tested on the actual device.
@interface OMLockViewController : UIViewController
@end
