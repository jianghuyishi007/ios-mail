// Objective-C API for talking to gitlab.com/ProtonMail/go-pm-crypto/crypto Go package.
//   gobind -lang=objc gitlab.com/ProtonMail/go-pm-crypto/crypto
//
// File is generated by gobind. Do not edit.

#ifndef __Crypto_H__
#define __Crypto_H__

@import Foundation;
#include "Universe.objc.h"

#include "Armor.objc.h"
#include "Models.objc.h"

@class CryptoAttachmentProcessor;
@class CryptoPmCrypto;
@class CryptoSignatureCollector;
@protocol CryptoMIMECallbacks;
@class CryptoMIMECallbacks;

@protocol CryptoMIMECallbacks <NSObject>
- (void)onAttachment:(NSString*)headers data:(NSData*)data;
- (void)onBody:(NSString*)body mimetype:(NSString*)mimetype;
- (void)onEncryptedHeaders:(NSString*)headers;
- (void)onError:(NSError*)err;
- (void)onVerified:(long)verified;
@end

/**
 * EncryptedSplit when encrypt attachment
 */
@interface CryptoAttachmentProcessor : NSObject <goSeqRefInterface> {
}
@property(strong, readonly) id _ref;

- (instancetype)initWithRef:(id)ref;
- (instancetype)init;
- (ModelsEncryptedSplit*)finish:(NSError**)error;
- (void)process:(NSData*)plainData;
@end

/**
 * PmCrypto structure to manage multiple address keys and user keys
Called PGP crypto because it cannot have the same name as the package by gomobile's ridiculous rules.
 */
@interface CryptoPmCrypto : NSObject <goSeqRefInterface> {
}
@property(strong, readonly) id _ref;

- (instancetype)initWithRef:(id)ref;
- (instancetype)init;
- (NSString*)checkKey:(NSString*)pubKey error:(NSError**)error;
- (NSData*)decryptAttachment:(NSData*)keyPacket dataPacket:(NSData*)dataPacket privateKey:(NSString*)privateKey passphrase:(NSString*)passphrase error:(NSError**)error;
- (NSData*)decryptAttachmentBinKey:(NSData*)keyPacket dataPacket:(NSData*)dataPacket privateKeys:(NSData*)privateKeys passphrase:(NSString*)passphrase error:(NSError**)error;
- (NSData*)decryptAttachmentWithPassword:(NSData*)keyPacket dataPacket:(NSData*)dataPacket password:(NSString*)password error:(NSError**)error;
- (void)decryptMIMEMessage:(NSString*)encryptedText verifierKey:(NSData*)verifierKey privateKeys:(NSData*)privateKeys passphrase:(NSString*)passphrase callbacks:(id<CryptoMIMECallbacks>)callbacks verifyTime:(int64_t)verifyTime;
- (NSString*)decryptMessage:(NSString*)encryptedText privateKey:(NSString*)privateKey passphrase:(NSString*)passphrase error:(NSError**)error;
- (NSString*)decryptMessageBinKey:(NSString*)encryptedText privateKey:(NSData*)privateKey passphrase:(NSString*)passphrase error:(NSError**)error;
- (ModelsDecryptSignedVerify*)decryptMessageVerify:(NSString*)encryptedText verifierKey:(NSString*)verifierKey privateKey:(NSString*)privateKey passphrase:(NSString*)passphrase verifyTime:(int64_t)verifyTime error:(NSError**)error;
- (ModelsDecryptSignedVerify*)decryptMessageVerifyBinKey:(NSString*)encryptedText verifierKey:(NSData*)verifierKey privateKey:(NSString*)privateKey passphrase:(NSString*)passphrase verifyTime:(int64_t)verifyTime error:(NSError**)error;
- (ModelsDecryptSignedVerify*)decryptMessageVerifyBinKeyPrivBinKeys:(NSString*)encryptedText verifierKey:(NSData*)verifierKey privateKeys:(NSData*)privateKeys passphrase:(NSString*)passphrase verifyTime:(int64_t)verifyTime error:(NSError**)error;
- (ModelsDecryptSignedVerify*)decryptMessageVerifyPrivBinKeys:(NSString*)encryptedText verifierKey:(NSString*)verifierKey privateKeys:(NSData*)privateKeys passphrase:(NSString*)passphrase verifyTime:(int64_t)verifyTime error:(NSError**)error;
- (NSString*)decryptMessageWithPassword:(NSString*)encrypted password:(NSString*)password error:(NSError**)error;
- (ModelsEncryptedSplit*)encryptAttachment:(NSData*)plainData fileName:(NSString*)fileName publicKey:(NSString*)publicKey error:(NSError**)error;
- (CryptoAttachmentProcessor*)encryptAttachmentLowMemory:(long)estimatedSize fileName:(NSString*)fileName publicKey:(NSString*)publicKey error:(NSError**)error;
- (NSString*)encryptAttachmentWithPassword:(NSData*)plainData password:(NSString*)password error:(NSError**)error;
- (NSString*)encryptMessage:(NSString*)plainText publicKey:(NSString*)publicKey privateKey:(NSString*)privateKey passphrase:(NSString*)passphrase trim:(BOOL)trim error:(NSError**)error;
- (NSString*)encryptMessageBinKey:(NSString*)plainText publicKey:(NSData*)publicKey privateKey:(NSString*)privateKey passphrase:(NSString*)passphrase trim:(BOOL)trim error:(NSError**)error;
- (NSString*)encryptMessageWithPassword:(NSString*)plainText password:(NSString*)password error:(NSError**)error;
- (NSString*)generateKey:(NSString*)userName domain:(NSString*)domain passphrase:(NSString*)passphrase keyType:(NSString*)keyType bits:(long)bits error:(NSError**)error;
- (NSString*)generateRSAKeyWithPrimes:(NSString*)userName domain:(NSString*)domain passphrase:(NSString*)passphrase bits:(long)bits primeone:(NSData*)primeone primetwo:(NSData*)primetwo primethree:(NSData*)primethree primefour:(NSData*)primefour error:(NSError**)error;
/**
 * GetSessionFromKeyPacket get session key no encoding in and out
 */
- (ModelsSessionSplit*)getSessionFromKeyPacket:(NSData*)keyPackage privateKey:(NSString*)privateKey passphrase:(NSString*)passphrase error:(NSError**)error;
/**
 * GetSessionFromKeyPacketBinkeys get session key no encoding in and out
 */
- (ModelsSessionSplit*)getSessionFromKeyPacketBinkeys:(NSData*)keyPackage privateKey:(NSData*)privateKey passphrase:(NSString*)passphrase error:(NSError**)error;
/**
 * GetSessionFromSymmetricPacket ...
 */
- (ModelsSessionSplit*)getSessionFromSymmetricPacket:(NSData*)keyPackage password:(NSString*)password error:(NSError**)error;
/**
 * GetTime get latest cached time
 */
- (int64_t)getTime;
- (BOOL)isKeyExpired:(NSString*)publicKey ret0_:(BOOL*)ret0_ error:(NSError**)error;
- (BOOL)isKeyExpiredBin:(NSData*)publicKey ret0_:(BOOL*)ret0_ error:(NSError**)error;
/**
 * KeyPacketWithPublicKey ...
 */
- (NSData*)keyPacketWithPublicKey:(ModelsSessionSplit*)sessionSplit publicKey:(NSString*)publicKey error:(NSError**)error;
/**
 * KeyPacketWithPublicKeyBin ...
 */
- (NSData*)keyPacketWithPublicKeyBin:(ModelsSessionSplit*)sessionSplit publicKey:(NSData*)publicKey error:(NSError**)error;
/**
 * RandomToken ...
 */
- (NSData*)randomToken:(NSError**)error;
/**
 * RandomTokenWith ...
 */
- (NSData*)randomTokenWith:(long)size error:(NSError**)error;
/**
 * SignBinDetached sign bin data
 */
- (NSString*)signBinDetached:(NSData*)plainData privateKey:(NSString*)privateKey passphrase:(NSString*)passphrase error:(NSError**)error;
/**
 * SignBinDetachedBinKey ...
 */
- (NSString*)signBinDetachedBinKey:(NSData*)plainData privateKey:(NSData*)privateKey passphrase:(NSString*)passphrase error:(NSError**)error;
/**
 * SignTextDetached sign detached text type
 */
- (NSString*)signTextDetached:(NSString*)plainText privateKey:(NSString*)privateKey passphrase:(NSString*)passphrase trim:(BOOL)trim error:(NSError**)error;
/**
 * SignTextDetachedBinKey ...
 */
- (NSString*)signTextDetachedBinKey:(NSString*)plainText privateKey:(NSData*)privateKey passphrase:(NSString*)passphrase trim:(BOOL)trim error:(NSError**)error;
/**
 * SymmetricKeyPacketWithPassword ...
 */
- (NSData*)symmetricKeyPacketWithPassword:(ModelsSessionSplit*)sessionSplit password:(NSString*)password error:(NSError**)error;
- (NSString*)updatePrivateKeyPassphrase:(NSString*)privateKey oldPassphrase:(NSString*)oldPassphrase newPassphrase:(NSString*)newPassphrase error:(NSError**)error;
/**
 * UpdateTime update cached time
 */
- (void)updateTime:(int64_t)newTime;
/**
 * VerifyBinSignDetached ...
 */
- (BOOL)verifyBinSignDetached:(NSString*)signature plainData:(NSData*)plainData publicKey:(NSString*)publicKey verifyTime:(int64_t)verifyTime ret0_:(BOOL*)ret0_ error:(NSError**)error;
/**
 * VerifyBinSignDetachedBinKey ...
 */
- (BOOL)verifyBinSignDetachedBinKey:(NSString*)signature plainData:(NSData*)plainData publicKey:(NSData*)publicKey verifyTime:(int64_t)verifyTime ret0_:(BOOL*)ret0_ error:(NSError**)error;
/**
 * VerifyTextSignDetached ...
 */
- (BOOL)verifyTextSignDetached:(NSString*)signature plainText:(NSString*)plainText publicKey:(NSString*)publicKey verifyTime:(int64_t)verifyTime ret0_:(BOOL*)ret0_ error:(NSError**)error;
/**
 * VerifyTextSignDetachedBinKey ...
 */
- (BOOL)verifyTextSignDetachedBinKey:(NSString*)signature plainText:(NSString*)plainText publicKey:(NSData*)publicKey verifyTime:(int64_t)verifyTime ret0_:(BOOL*)ret0_ error:(NSError**)error;
@end

@interface CryptoSignatureCollector : NSObject <goSeqRefInterface> {
}
@property(strong, readonly) id _ref;

- (instancetype)initWithRef:(id)ref;
- (instancetype)init;
// skipped method SignatureCollector.Accept with unsupported parameter or return types

- (NSString*)getSignature;
@end

/**
 * DecryptWithoutIntegrity decrypts data encrypted with AES-CTR.
 */
FOUNDATION_EXPORT NSData* CryptoDecryptWithoutIntegrity(NSData* key, NSData* input, NSData* iv, NSError** error);

/**
 * DeriveKey derives a key from a password using scrypt. N should be set to the highest power of 2 you can derive within 100 milliseconds.
 */
FOUNDATION_EXPORT NSData* CryptoDeriveKey(NSString* password, NSData* salt, long N, NSError** error);

/**
 * EncryptWithoutIntegrity encrypts data with AES-CTR. Note: this encryption mode is not secure when stored/sent on an untrusted medium.
 */
FOUNDATION_EXPORT NSData* CryptoEncryptWithoutIntegrity(NSData* key, NSData* input, NSData* iv, NSError** error);

@class CryptoMIMECallbacks;

/**
 * define call back interface
 */
@interface CryptoMIMECallbacks : NSObject <goSeqRefInterface, CryptoMIMECallbacks> {
}
@property(strong, readonly) id _ref;

- (instancetype)initWithRef:(id)ref;
- (void)onAttachment:(NSString*)headers data:(NSData*)data;
- (void)onBody:(NSString*)body mimetype:(NSString*)mimetype;
/**
 * Encrypted headers can be an attachment and thus be placed at the end of the mime structure
 */
- (void)onEncryptedHeaders:(NSString*)headers;
- (void)onError:(NSError*)err;
- (void)onVerified:(long)verified;
@end

#endif
