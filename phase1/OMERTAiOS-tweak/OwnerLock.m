#import "OwnerLock.h"
#import <Security/Security.h>
#import <CommonCrypto/CommonKeyDerivation.h>
#import <CommonCrypto/CommonRandom.h>

static NSString * const kOMService = @"com.omerta.iosui.ownerlock";
static NSString * const kOMAccountSalt = @"owner_salt";
static NSString * const kOMAccountHash = @"owner_hash";
static const uint32_t kOMIterations = 120000;
static const size_t kOMKeyLength = 32; // 256-bit, matches the Android side.
static const size_t kOMSaltLength = 16;

@implementation OMOwnerLock

+ (NSData *)keychainGet:(NSString *)account {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kOMService,
        (__bridge id)kSecAttrAccount: account,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne
    };
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess || result == NULL) {
        return nil;
    }
    return (__bridge_transfer NSData *)result;
}

+ (void)keychainSet:(NSData *)data account:(NSString *)account {
    NSDictionary *matchQuery = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kOMService,
        (__bridge id)kSecAttrAccount: account
    };
    SecItemDelete((__bridge CFDictionaryRef)matchQuery);

    NSMutableDictionary *insert = [matchQuery mutableCopy];
    insert[(__bridge id)kSecValueData] = data;
    insert[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly;
    SecItemAdd((__bridge CFDictionaryRef)insert, NULL);
}

+ (void)keychainDelete:(NSString *)account {
    NSDictionary *matchQuery = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kOMService,
        (__bridge id)kSecAttrAccount: account
    };
    SecItemDelete((__bridge CFDictionaryRef)matchQuery);
}

+ (NSData *)randomSalt {
    uint8_t bytes[kOMSaltLength];
    CCRandomGenerateBytes(bytes, sizeof(bytes));
    return [NSData dataWithBytes:bytes length:sizeof(bytes)];
}

+ (NSData *)derive:(NSString *)pin salt:(NSData *)salt {
    NSData *pinData = [pin dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t derived[kOMKeyLength];
    CCKeyDerivationPBKDF(kCCPBKDF2,
                          pinData.bytes, pinData.length,
                          salt.bytes, salt.length,
                          kCCPRFHmacAlgSHA256,
                          kOMIterations,
                          derived, kOMKeyLength);
    return [NSData dataWithBytes:derived length:kOMKeyLength];
}

+ (BOOL)hasOwnerPin {
    return [self keychainGet:kOMAccountHash] != nil;
}

+ (void)setOwnerPin:(NSString *)pin {
    if (pin.length < 4) {
        return;
    }
    NSData *salt = [self randomSalt];
    NSData *hash = [self derive:pin salt:salt];
    [self keychainSet:salt account:kOMAccountSalt];
    [self keychainSet:hash account:kOMAccountHash];
}

+ (BOOL)verifyOwnerPin:(NSString *)pin {
    NSData *salt = [self keychainGet:kOMAccountSalt];
    NSData *storedHash = [self keychainGet:kOMAccountHash];
    if (!salt || !storedHash) {
        return NO;
    }
    NSData *candidate = [self derive:pin salt:salt];
    return [candidate isEqualToData:storedHash];
}

+ (void)clearOwnerPin {
    [self keychainDelete:kOMAccountSalt];
    [self keychainDelete:kOMAccountHash];
}

@end
