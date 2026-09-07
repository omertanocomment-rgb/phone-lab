#import "OMLockViewController.h"
#import "OwnerLock.h"

@interface OMLockViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *pinField;
@property (nonatomic, strong) UILabel *statusLabel;
@end

@implementation OMLockViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 120, self.view.bounds.size.width, 30)];
    title.text = @"Enter Passcode";
    title.textColor = [UIColor whiteColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:title];

    self.pinField = [[UITextField alloc] initWithFrame:CGRectMake(40, 170, self.view.bounds.size.width - 80, 44)];
    self.pinField.borderStyle = UITextBorderStyleRoundedRect;
    self.pinField.secureTextEntry = YES;
    self.pinField.keyboardType = UIKeyboardTypeNumberPad;
    self.pinField.textAlignment = NSTextAlignmentCenter;
    self.pinField.delegate = self;
    self.pinField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:self.pinField];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 224, self.view.bounds.size.width, 20)];
    self.statusLabel.textColor = [UIColor redColor];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont systemFontOfSize:12];
    self.statusLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:self.statusLabel];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.pinField becomeFirstResponder];
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    NSString *next = [textField.text stringByReplacingCharactersInRange:range withString:string];
    if (next.length >= 4) {
        // Defer so the field visually updates to the final character first.
        dispatch_async(dispatch_get_main_queue(), ^{
            [self attemptUnlockWithPin:next];
        });
    }
    return YES;
}

- (void)attemptUnlockWithPin:(NSString *)pin {
    if ([OMOwnerLock verifyOwnerPin:pin]) {
        UIWindow *window = self.view.window;
        [UIView animateWithDuration:0.2 animations:^{
            window.alpha = 0;
        } completion:^(BOOL finished) {
            window.hidden = YES;
            window.alpha = 1;
        }];
    } else {
        self.statusLabel.text = @"Incorrect passcode";
        self.pinField.text = @"";
    }
}

@end
