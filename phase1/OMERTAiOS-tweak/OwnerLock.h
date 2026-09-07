#import <Foundation/Foundation.h>

// Owner-lock credential storage, mirroring OwnerLockManager.java on the
// Android side: PBKDF2-SHA256, salted, 120,000 iterations, 256-bit output.
// Storage backend is the iOS Keychain instead of AndroidKeyStore-encrypted
// SharedPreferences, restricted to kSecAttrAccessibleWhenUnlockedThisDeviceOnly
// so the credential never leaves this device and is unreadable while locked.
@interface OMOwnerLock : NSObject

+ (BOOL)hasOwnerPin;
+ (void)setOwnerPin:(NSString *)pin;
+ (BOOL)verifyOwnerPin:(NSString *)pin;
+ (void)clearOwnerPin;

@end
