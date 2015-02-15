//
//  RMStore.h
//  RMStore
//
//  Created by Hermes Pique on 12/6/09.
//  Copyright (c) 2013 Robot Media SL (http://www.robotmedia.net)
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "RMStore.h"

NSTimeInterval const RMStoreWatchdogMinimalAllowedTimeout = 5.0; // Average Internet latency for mobile users according to reports from http://www.akamai.com/stateoftheinternet/
NSTimeInterval const RMStoreRequestProductWatchdogDefaultTimeout = 10.0; // According to Jakob Nielsen it's about the limit for keeping the user's attention focused on the dialogue. http://www.nngroup.com/articles/response-times-3-important-limits/

NSString *const RMStoreErrorDomain = @"net.robotmedia.store";
NSInteger const RMStoreErrorCodeDownloadCanceled = 300;
NSInteger const RMStoreErrorCodeUnknownProductIdentifier = 100;
NSInteger const RMStoreErrorCodeUnableToCompleteVerification = 200;
NSInteger const RMStoreErrorCodeWatchdogTimerFired = 300;

NSString* const RMSKDownloadCanceled = @"RMSKDownloadCanceled";
NSString* const RMSKDownloadFailed = @"RMSKDownloadFailed";
NSString* const RMSKDownloadFinished = @"RMSKDownloadFinished";
NSString* const RMSKDownloadPaused = @"RMSKDownloadPaused";
NSString* const RMSKDownloadUpdated = @"RMSKDownloadUpdated";
NSString* const RMSKPaymentTransactionDeferred = @"RMSKPaymentTransactionDeferred";
NSString* const RMSKPaymentTransactionStarted = @"RMSKPaymentTransactionStarted";
NSString* const RMSKPaymentTransactionFailed = @"RMSKPaymentTransactionFailed";
NSString* const RMSKPaymentTransactionFinished = @"RMSKPaymentTransactionFinished";
NSString* const RMSKProductsRequestStarted = @"RMSKProductsRequestStarted";
NSString* const RMSKProductsRequestFailed = @"RMSKProductsRequestFailed";
NSString* const RMSKProductsRequestFinished = @"RMSKProductsRequestFinished";
NSString* const RMSKRefreshReceiptStarted = @"RMSKRefreshReceiptStarted";
NSString* const RMSKRefreshReceiptFailed = @"RMSKRefreshReceiptFailed";
NSString* const RMSKRefreshReceiptFinished = @"RMSKRefreshReceiptFinished";
NSString* const RMSKRestoreTransactionsStarted = @"RMSKRestoreTransactionsStarted";
NSString* const RMSKRestoreTransactionsFailed = @"RMSKRestoreTransactionsFailed";
NSString* const RMSKRestoreTransactionsFinished = @"RMSKRestoreTransactionsFinished";

NSString* const RMStoreNotificationInvalidProductIdentifiers = @"invalidProductIdentifiers";
NSString* const RMStoreNotificationDownloadProgress = @"downloadProgress";
NSString* const RMStoreNotificationProductIdentifier = @"productIdentifier";
NSString* const RMStoreNotificationProductsIdentifiers = @"productsIdentifiers";
NSString* const RMStoreNotificationUserIdentifier = @"userIdentifier";
NSString* const RMStoreNotificationProducts = @"products";
NSString* const RMStoreNotificationStoreDownload = @"storeDownload";
NSString* const RMStoreNotificationStoreError = @"storeError";
NSString* const RMStoreNotificationStoreReceipt = @"storeReceipt";
NSString* const RMStoreNotificationTransaction = @"transaction";
NSString* const RMStoreNotificationTransactions = @"transactions";

#if DEBUG
#define RMStoreLog(...) NSLog(@"RMStore: %@", [NSString stringWithFormat:__VA_ARGS__]);
#else
#define RMStoreLog(...)
#endif

typedef void (^RMSKPaymentTransactionFailureBlock)(SKPaymentTransaction *transaction, NSError *error);
typedef void (^RMSKPaymentTransactionSuccessBlock)(SKPaymentTransaction *transaction);
typedef void (^RMSKProductsRequestFailureBlock)(NSError *error);
typedef void (^RMSKProductsRequestSuccessBlock)(NSArray *products, NSArray *invalidIdentifiers);
typedef void (^RMStoreFailureBlock)(NSError *error);
typedef void (^RMStoreSuccessBlock)();

@implementation NSNotification(RMStore)

- (float)rm_downloadProgress
{
    return [self.userInfo[RMStoreNotificationDownloadProgress] floatValue];
}

- (NSArray*)rm_invalidProductIdentifiers
{
    return (self.userInfo)[RMStoreNotificationInvalidProductIdentifiers];
}

- (NSString*)rm_productIdentifier
{
    return (self.userInfo)[RMStoreNotificationProductIdentifier];
}

- (NSArray*)rm_products
{
    return (self.userInfo)[RMStoreNotificationProducts];
}

- (SKDownload*)rm_storeDownload
{
    return (self.userInfo)[RMStoreNotificationStoreDownload];
}

- (NSError*)rm_storeError
{
    return (self.userInfo)[RMStoreNotificationStoreError];
}

- (SKPaymentTransaction*)rm_transaction
{
    return (self.userInfo)[RMStoreNotificationTransaction];
}

- (NSArray*)rm_transactions {
    return (self.userInfo)[RMStoreNotificationTransactions];
}

@end

@interface RMProductsRequestDelegate : RMStoreWatchdoggedObject<SKProductsRequestDelegate>

@property (nonatomic, strong) RMSKProductsRequestSuccessBlock successBlock;
@property (nonatomic, strong) RMSKProductsRequestFailureBlock failureBlock;
@property (nonatomic, weak) RMStore *store;
@property (nonatomic, weak) SKProductsRequest * request;

@end

@interface RMAddPaymentParameters : NSObject

@property (nonatomic, strong) RMSKPaymentTransactionSuccessBlock successBlock;
@property (nonatomic, strong) RMSKPaymentTransactionFailureBlock failureBlock;

@end

@implementation RMAddPaymentParameters

@end

@interface RMStore() <SKRequestDelegate>

@end

@implementation RMStore {
    NSMutableDictionary *_addPaymentParameters; // HACK: We use a dictionary of product identifiers because the returned SKPayment is different from the one we add to the queue. Bad Apple.
    NSMutableDictionary *_products;
    NSMutableSet *_productsRequestDelegates;
    
    NSMutableArray *_restoredTransactions;
    
    NSInteger _pendingRestoredTransactionsCount;
    BOOL _restoredCompletedTransactionsFinished;
    
    SKReceiptRefreshRequest *_refreshReceiptRequest;
    void (^_refreshReceiptFailureBlock)(NSError* error);
    void (^_refreshReceiptSuccessBlock)();
    
    void (^_restoreTransactionsFailureBlock)(NSError* error);
    void (^_restoreTransactionsSuccessBlock)(NSArray* transactions);
}

- (id) init
{
    if (self = [super init])
    {
        _useRequestProductsWatchdogTimer = NO;
        
        _addPaymentParameters = [NSMutableDictionary dictionary];
        _products = [NSMutableDictionary dictionary];
        _productsRequestDelegates = [NSMutableSet set];
        _restoredTransactions = [NSMutableArray array];
        [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
    }
    return self;
}

- (void)dealloc
{
    [[SKPaymentQueue defaultQueue] removeTransactionObserver:self];
}

+ (RMStore *)defaultStore
{
    static RMStore *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[[self class] alloc] init];
    });
    return sharedInstance;
}

#pragma mark Watchdog timers

- (NSTimeInterval)requestProductTimeout
{
    if (_requestProductTimeout > RMStoreWatchdogMinimalAllowedTimeout) {
        return _requestProductTimeout;
    }
    return RMStoreWatchdogMinimalAllowedTimeout;
}

#pragma mark StoreKit wrapper

+ (BOOL)canMakePayments
{
    return [SKPaymentQueue canMakePayments];
}

- (void)addPayment:(NSString*)productIdentifier
{
    [self addPayment:productIdentifier success:nil failure:nil];
}

- (void)addPayment:(NSString*)productIdentifier
           success:(void (^)(SKPaymentTransaction *transaction))successBlock
           failure:(void (^)(SKPaymentTransaction *transaction, NSError *error))failureBlock
{
    [self addPayment:productIdentifier user:nil success:successBlock failure:failureBlock];
}

- (void)addPayment:(NSString*)productIdentifier
              user:(NSString*)userIdentifier
           success:(void (^)(SKPaymentTransaction *transaction))successBlock
           failure:(void (^)(SKPaymentTransaction *transaction, NSError *error))failureBlock
{
    SKProduct *product = [self productForIdentifier:productIdentifier];
    if (product == nil)
    {
        RMStoreLog(@"unknown product id %@", productIdentifier)
        if (failureBlock != nil)
        {
            NSError *error = [NSError errorWithDomain:RMStoreErrorDomain code:RMStoreErrorCodeUnknownProductIdentifier userInfo:@{NSLocalizedDescriptionKey: NSLocalizedStringFromTable(@"Unknown product identifier", @"RMStore", @"Error description")}];
            failureBlock(nil, error);
        }
        return;
    }
    SKMutablePayment *payment = [SKMutablePayment paymentWithProduct:product];
    if ([payment respondsToSelector:@selector(setApplicationUsername:)])
    {
        payment.applicationUsername = userIdentifier;
    }
    
    RMAddPaymentParameters *parameters = [[RMAddPaymentParameters alloc] init];
    parameters.successBlock = successBlock;
    parameters.failureBlock = failureBlock;
    _addPaymentParameters[productIdentifier] = parameters;
    
    [[SKPaymentQueue defaultQueue] addPayment:payment];
    
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    [userInfo setValue:productIdentifier forKey:RMStoreNotificationProductIdentifier];
    [userInfo setValue:userIdentifier forKey:RMStoreNotificationUserIdentifier];
    [[NSNotificationCenter defaultCenter] postNotificationName:RMSKPaymentTransactionStarted object:self userInfo:userInfo];
}

- (void)requestProducts:(NSSet*)identifiers
{
    [self requestProducts:identifiers success:nil failure:nil];
}

- (void)requestProducts:(NSSet*)identifiers
                success:(RMSKProductsRequestSuccessBlock)successBlock
                failure:(RMSKProductsRequestFailureBlock)failureBlock
{
    RMProductsRequestDelegate *delegate = [[RMProductsRequestDelegate alloc] init];
    delegate.store = self;
    delegate.successBlock = successBlock;
    delegate.failureBlock = failureBlock;
    [_productsRequestDelegates addObject:delegate];
 
    SKProductsRequest *productsRequest = [[SKProductsRequest alloc] initWithProductIdentifiers:identifiers];
	productsRequest.delegate = delegate;
    
    [productsRequest start];
    delegate.request = productsRequest;
    [delegate activateWatchdogTimerWithStore:self timeout:self.requestProductTimeout];
    
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    [userInfo setValue:identifiers forKey:RMStoreNotificationProductsIdentifiers];
    [[NSNotificationCenter defaultCenter] postNotificationName:RMSKProductsRequestStarted object:self userInfo:userInfo];
}

- (void)restoreTransactions
{
    [self restoreTransactionsOnSuccess:nil failure:nil];
}

- (void)restoreTransactionsOnSuccess:(void (^)(NSArray *transactions))successBlock
                             failure:(void (^)(NSError *error))failureBlock
{
    _restoredCompletedTransactionsFinished = NO;
    _pendingRestoredTransactionsCount = 0;
    _restoredTransactions = [NSMutableArray array];
    _restoreTransactionsSuccessBlock = successBlock;
    _restoreTransactionsFailureBlock = failureBlock;
    [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
    
    NSMutableDictionary *userInfo = nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:RMSKRestoreTransactionsStarted object:self userInfo:userInfo];
}

- (void)restoreTransactionsOfUser:(NSString*)userIdentifier
                        onSuccess:(void (^)(NSArray *transactions))successBlock
                          failure:(void (^)(NSError *error))failureBlock
{
    NSAssert([[SKPaymentQueue defaultQueue] respondsToSelector:@selector(restoreCompletedTransactionsWithApplicationUsername:)], @"restoreCompletedTransactionsWithApplicationUsername: not supported in this iOS version. Use restoreTransactionsOnSuccess:failure: instead.");
    _restoredCompletedTransactionsFinished = NO;
    _pendingRestoredTransactionsCount = 0;
    _restoreTransactionsSuccessBlock = successBlock;
    _restoreTransactionsFailureBlock = failureBlock;
    [[SKPaymentQueue defaultQueue] restoreCompletedTransactionsWithApplicationUsername:userIdentifier];
    
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    [userInfo setValue:userIdentifier forKey:RMStoreNotificationUserIdentifier];
    [[NSNotificationCenter defaultCenter] postNotificationName:RMSKRestoreTransactionsStarted object:self userInfo:userInfo];
}

#pragma mark Receipt

+ (NSURL*)receiptURL
{
    // The general best practice of weak linking using the respondsToSelector: method cannot be used here. Prior to iOS 7, the method was implemented as private API, but that implementation called the doesNotRecognizeSelector: method.
    NSAssert(floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_6_1, @"appStoreReceiptURL not supported in this iOS version.");
    NSURL *url = [[NSBundle mainBundle] appStoreReceiptURL];
    return url;
}

- (void)refreshReceipt
{
    [self refreshReceiptOnSuccess:nil failure:nil];
}

- (void)refreshReceiptOnSuccess:(RMStoreSuccessBlock)successBlock
                        failure:(RMStoreFailureBlock)failureBlock
{
    _refreshReceiptFailureBlock = failureBlock;
    _refreshReceiptSuccessBlock = successBlock;
    _refreshReceiptRequest = [[SKReceiptRefreshRequest alloc] initWithReceiptProperties:@{}];
    _refreshReceiptRequest.delegate = self;
    [_refreshReceiptRequest start];
    
    NSMutableDictionary *userInfo = nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:RMSKRefreshReceiptStarted object:self userInfo:userInfo];
}

#pragma mark Product management

- (SKProduct*)productForIdentifier:(NSString*)productIdentifier
{
    return _products[productIdentifier];
}

+ (NSString*)localizedPriceOfProduct:(SKProduct*)product
{
	NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
	numberFormatter.numberStyle = NSNumberFormatterCurrencyStyle;
	numberFormatter.locale = product.priceLocale;
	NSString *formattedString = [numberFormatter stringFromNumber:product.price];
	return formattedString;
}

#pragma mark Observers

- (void)addStoreObserver:(id<RMStoreObserver>)observer
{
    [self addStoreObserver:observer selector:@selector(storeDownloadCanceled:) notificationName:RMSKDownloadCanceled];
    [self addStoreObserver:observer selector:@selector(storeDownloadFailed:) notificationName:RMSKDownloadFailed];
    [self addStoreObserver:observer selector:@selector(storeDownloadFinished:) notificationName:RMSKDownloadFinished];
    [self addStoreObserver:observer selector:@selector(storeDownloadPaused:) notificationName:RMSKDownloadPaused];
    [self addStoreObserver:observer selector:@selector(storeDownloadUpdated:) notificationName:RMSKDownloadUpdated];
    [self addStoreObserver:observer selector:@selector(storeProductsRequestStarted:) notificationName:RMSKProductsRequestStarted];
    [self addStoreObserver:observer selector:@selector(storeProductsRequestFailed:) notificationName:RMSKProductsRequestFailed];
    [self addStoreObserver:observer selector:@selector(storeProductsRequestFinished:) notificationName:RMSKProductsRequestFinished];
    [self addStoreObserver:observer selector:@selector(storePaymentTransactionDeferred:) notificationName:RMSKPaymentTransactionDeferred];
    [self addStoreObserver:observer selector:@selector(storePaymentTransactionStarted:) notificationName:RMSKPaymentTransactionStarted];
    [self addStoreObserver:observer selector:@selector(storePaymentTransactionFailed:) notificationName:RMSKPaymentTransactionFailed];
    [self addStoreObserver:observer selector:@selector(storePaymentTransactionFinished:) notificationName:RMSKPaymentTransactionFinished];
    [self addStoreObserver:observer selector:@selector(storeRefreshReceiptStarted:) notificationName:RMSKRefreshReceiptStarted];
    [self addStoreObserver:observer selector:@selector(storeRefreshReceiptFailed:) notificationName:RMSKRefreshReceiptFailed];
    [self addStoreObserver:observer selector:@selector(storeRefreshReceiptFinished:) notificationName:RMSKRefreshReceiptFinished];
    [self addStoreObserver:observer selector:@selector(storeRestoreTransactionsStarted:) notificationName:RMSKRestoreTransactionsStarted];
    [self addStoreObserver:observer selector:@selector(storeRestoreTransactionsFailed:) notificationName:RMSKRestoreTransactionsFailed];
    [self addStoreObserver:observer selector:@selector(storeRestoreTransactionsFinished:) notificationName:RMSKRestoreTransactionsFinished];
}

- (void)removeStoreObserver:(id<RMStoreObserver>)observer
{
    [[NSNotificationCenter defaultCenter] removeObserver:observer name:RMSKDownloadCanceled object:self];
    [[NSNotificationCenter defaultCenter] removeObserver:observer name:RMSKDownloadFailed object:self];
    [[NSNotificationCenter defaultCenter] removeObserver:observer name:RMSKDownloadFinished object:self];
    [[NSNotificationCenter defaultCenter] removeObserver:observer name:RMSKDownloadPaused object:self];
    [[NSNotificationCenter defaultCenter] removeObserver:observer name:RMSKDownloadUpdated object:self];
    [[NSNotificationCenter defaultCenter] removeObserver:observer name:RMSKProductsRequestStarted object:self];
    [[NSNotificationCenter defaultCenter] removeObserver:observer name:RMSKProductsRequestFailed object:self];
    [[NSNotificationCenter defaultCenter] removeObserver:observer name:RMSKProductsRequestFinished object:self];
    [[NSNotificationCenter defaultCenter] removeObserver:observer name:RMSKPaymentTransactionDeferred object:self];
    [[NSNotificationCenter defaultCenter] removeObserver:observer name:RMSKPaymentTransactionStarted object:self];
    [[NSNotificationCenter defaultCenter] removeObserver:observer name:RMSKPaymentTransactionFailed object:self];
    [[NSNotificationCenter defaultCenter] removeObserver:observer name:RMSKPaymentTransactionFinished object:self];
    [[NSNotificationCenter defaultCenter] removeObserver:observer name:RMSKRefreshReceiptStarted object:self];
    [[NSNotificationCenter defaultCenter] removeObserver:observer name:RMSKRefreshReceiptFailed object:self];
    [[NSNotificationCenter defaultCenter] removeObserver:observer name:RMSKRefreshReceiptFinished object:self];
    [[NSNotificationCenter defaultCenter] removeObserver:observer name:RMSKRestoreTransactionsStarted object:self];
    [[NSNotificationCenter defaultCenter] removeObserver:observer name:RMSKRestoreTransactionsFailed object:self];
    [[NSNotificationCenter defaultCenter] removeObserver:observer name:RMSKRestoreTransactionsFinished object:self];
}

// Private

- (void)addStoreObserver:(id<RMStoreObserver>)observer selector:(SEL)aSelector notificationName:(NSString*)notificationName
{
    if ([observer respondsToSelector:aSelector])
    {
        [[NSNotificationCenter defaultCenter] addObserver:observer selector:aSelector name:notificationName object:self];
    }
}

#pragma mark SKPaymentTransactionObserver

- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray *)transactions
{
    for (SKPaymentTransaction *transaction in transactions)
    {
        switch (transaction.transactionState)
        {
            case SKPaymentTransactionStatePurchased:
                [self didPurchaseTransaction:transaction queue:queue];
                break;
            case SKPaymentTransactionStateFailed:
                [self didFailTransaction:transaction queue:queue error:transaction.error];
                break;
            case SKPaymentTransactionStateRestored:
                [self didRestoreTransaction:transaction queue:queue];
                break;
            case SKPaymentTransactionStateDeferred:
                [self didDeferTransaction:transaction];
                break;
            default:
                break;
        }
    }
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue
{
    RMStoreLog(@"restore transactions finished");
    _restoredCompletedTransactionsFinished = YES;
    
    [self notifyRestoreTransactionFinishedIfApplicableAfterTransaction:nil];
}

- (void)paymentQueue:(SKPaymentQueue *)queue restoreCompletedTransactionsFailedWithError:(NSError *)error
{
    RMStoreLog(@"restored transactions failed with error %@", error.debugDescription);
    if (_restoreTransactionsFailureBlock != nil)
    {
        _restoreTransactionsFailureBlock(error);
        _restoreTransactionsFailureBlock = nil;
    }
    NSDictionary *userInfo = nil;
    if (error)
    { // error might be nil (e.g., on airplane mode)
        userInfo = @{RMStoreNotificationStoreError: error};
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:RMSKRestoreTransactionsFailed object:self userInfo:userInfo];
}

- (void)paymentQueue:(SKPaymentQueue *)queue updatedDownloads:(NSArray *)downloads
{
    for (SKDownload *download in downloads)
    {
        switch (download.downloadState)
        {
            case SKDownloadStateActive:
                [self didUpdateDownload:download queue:queue];
                break;
            case SKDownloadStateCancelled:
                [self didCancelDownload:download queue:queue];
                break;
            case SKDownloadStateFailed:
                [self didFailDownload:download queue:queue];
                break;
            case SKDownloadStateFinished:
                [self didFinishDownload:download queue:queue];
                break;
            case SKDownloadStatePaused:
                [self didPauseDownload:download queue:queue];
                break;
            case SKDownloadStateWaiting:
                // Do nothing
                break;
        }
    }
}

#pragma mark Download State

- (void)didCancelDownload:(SKDownload*)download queue:(SKPaymentQueue*)queue
{
    SKPaymentTransaction *transaction = download.transaction;
    RMStoreLog(@"download %@ for product %@ canceled", download.contentIdentifier, download.transaction.payment.productIdentifier);

    [self postNotificationWithName:RMSKDownloadCanceled download:download userInfoExtras:nil];

    NSError *error = [NSError errorWithDomain:RMStoreErrorDomain code:RMStoreErrorCodeDownloadCanceled userInfo:@{NSLocalizedDescriptionKey: NSLocalizedStringFromTable(@"Download canceled", @"RMStore", @"Error description")}];

    const BOOL hasPendingDownloads = [self.class hasPendingDownloadsInTransaction:transaction];
    if (!hasPendingDownloads)
    {
        [self didFailTransaction:transaction queue:queue error:error];
    }
}

- (void)didFailDownload:(SKDownload*)download queue:(SKPaymentQueue*)queue
{
    NSError *error = download.error;
    SKPaymentTransaction *transaction = download.transaction;
    RMStoreLog(@"download %@ for product %@ failed with error %@", download.contentIdentifier, transaction.payment.productIdentifier, error.debugDescription);

    NSDictionary *extras = error ? @{RMStoreNotificationStoreError : error} : nil;
    [self postNotificationWithName:RMSKDownloadFailed download:download userInfoExtras:extras];

    const BOOL hasPendingDownloads = [self.class hasPendingDownloadsInTransaction:transaction];
    if (!hasPendingDownloads)
    {
        [self didFailTransaction:transaction queue:queue error:error];
    }
}

- (void)didFinishDownload:(SKDownload*)download queue:(SKPaymentQueue*)queue
{
    SKPaymentTransaction *transaction = download.transaction;
    RMStoreLog(@"download %@ for product %@ finished", download.contentIdentifier, transaction.payment.productIdentifier);
    
    [self postNotificationWithName:RMSKDownloadFinished download:download userInfoExtras:nil];

    const BOOL hasPendingDownloads = [self.class hasPendingDownloadsInTransaction:transaction];
    if (!hasPendingDownloads)
    {
        [self finishTransaction:download.transaction queue:queue];
    }
}

- (void)didPauseDownload:(SKDownload*)download queue:(SKPaymentQueue*)queue
{
    RMStoreLog(@"download %@ for product %@ paused", download.contentIdentifier, download.transaction.payment.productIdentifier);
    [self postNotificationWithName:RMSKDownloadPaused download:download userInfoExtras:nil];
}

- (void)didUpdateDownload:(SKDownload*)download queue:(SKPaymentQueue*)queue
{
    RMStoreLog(@"download %@ for product %@ updated", download.contentIdentifier, download.transaction.payment.productIdentifier);
    NSDictionary *extras = @{RMStoreNotificationDownloadProgress : @(download.progress)};
    [self postNotificationWithName:RMSKDownloadUpdated download:download userInfoExtras:extras];
}

+ (BOOL)hasPendingDownloadsInTransaction:(SKPaymentTransaction*)transaction
{
    for (SKDownload *download in transaction.downloads)
    {
        switch (download.downloadState)
        {
            case SKDownloadStateActive:
            case SKDownloadStatePaused:
            case SKDownloadStateWaiting:
                return YES;
            case SKDownloadStateCancelled:
            case SKDownloadStateFailed:
            case SKDownloadStateFinished:
                continue;
        }
    }
    return NO;
}

#pragma mark Transaction State

- (void)didPurchaseTransaction:(SKPaymentTransaction *)transaction queue:(SKPaymentQueue*)queue
{
    RMStoreLog(@"transaction purchased with product %@", transaction.payment.productIdentifier);
    
    if (self.receiptVerificator != nil)
    {
        [self.receiptVerificator verifyTransaction:transaction success:^{
            [self didVerifyTransaction:transaction queue:queue];
        } failure:^(NSError *error) {
            [self didFailTransaction:transaction queue:queue error:error];
        }];
    }
    else
    {
        RMStoreLog(@"WARNING: no receipt verification");
        [self didVerifyTransaction:transaction queue:queue];
    }
}

- (void)didFailTransaction:(SKPaymentTransaction *)transaction queue:(SKPaymentQueue*)queue error:(NSError*)error
{
    SKPayment *payment = transaction.payment;
	NSString* productIdentifier = payment.productIdentifier;
    RMStoreLog(@"transaction failed with product %@ and error %@", productIdentifier, error.debugDescription);
    
    if (error.code != RMStoreErrorCodeUnableToCompleteVerification)
    { // If we were unable to complete the verification we want StoreKit to keep reminding us of the transaction
        [queue finishTransaction:transaction];
    }
    
    RMAddPaymentParameters *parameters = [self popAddPaymentParametersForIdentifier:productIdentifier];
    if (parameters.failureBlock != nil)
    {
        parameters.failureBlock(transaction, error);
    }
    
    NSDictionary *extras = error ? @{RMStoreNotificationStoreError : error} : nil;
    [self postNotificationWithName:RMSKPaymentTransactionFailed transaction:transaction userInfoExtras:extras];
    
    if (transaction.transactionState == SKPaymentTransactionStateRestored)
    {
        [self notifyRestoreTransactionFinishedIfApplicableAfterTransaction:transaction];
    }
}

- (void)didRestoreTransaction:(SKPaymentTransaction *)transaction queue:(SKPaymentQueue*)queue
{
    RMStoreLog(@"transaction restored with product %@", transaction.originalTransaction.payment.productIdentifier);
    
    _pendingRestoredTransactionsCount++;
    if (self.receiptVerificator != nil)
    {
        [self.receiptVerificator verifyTransaction:transaction success:^{
            [self didVerifyTransaction:transaction queue:queue];
        } failure:^(NSError *error) {
            [self didFailTransaction:transaction queue:queue error:error];
        }];
    }
    else
    {
        RMStoreLog(@"WARNING: no receipt verification");
        [self didVerifyTransaction:transaction queue:queue];
    }
}

- (void)didDeferTransaction:(SKPaymentTransaction *)transaction
{
    [self postNotificationWithName:RMSKPaymentTransactionDeferred transaction:transaction userInfoExtras:nil];
}

- (void)didVerifyTransaction:(SKPaymentTransaction *)transaction queue:(SKPaymentQueue*)queue
{
    if (self.contentDownloader != nil)
    {
        [self.contentDownloader downloadContentForTransaction:transaction success:^{
            [self postNotificationWithName:RMSKDownloadFinished transaction:transaction userInfoExtras:nil];
            [self didDownloadSelfHostedContentForTransaction:transaction queue:queue];
        } progress:^(float progress) {
            NSDictionary *extras = @{RMStoreNotificationDownloadProgress : @(progress)};
            [self postNotificationWithName:RMSKDownloadUpdated transaction:transaction userInfoExtras:extras];
        } failure:^(NSError *error) {
            NSDictionary *extras = error ? @{RMStoreNotificationStoreError : error} : nil;
            [self postNotificationWithName:RMSKDownloadFailed transaction:transaction userInfoExtras:extras];
            [self didFailTransaction:transaction queue:queue error:error];
        }];
    }
    else
    {
        [self didDownloadSelfHostedContentForTransaction:transaction queue:queue];
    }
}

- (void)didDownloadSelfHostedContentForTransaction:(SKPaymentTransaction *)transaction queue:(SKPaymentQueue*)queue
{
    NSArray *downloads = [transaction respondsToSelector:@selector(downloads)] ? transaction.downloads : @[];
    if (downloads.count > 0)
    {
        RMStoreLog(@"starting downloads for product %@ started", transaction.payment.productIdentifier);
        [queue startDownloads:downloads];
    }
    else
    {
        [self finishTransaction:transaction queue:queue];
    }
}

- (void)finishTransaction:(SKPaymentTransaction *)transaction queue:(SKPaymentQueue*)queue
{
    SKPayment *payment = transaction.payment;
	NSString* productIdentifier = payment.productIdentifier;
    [queue finishTransaction:transaction];
    [self.transactionPersistor persistTransaction:transaction];
    
    RMAddPaymentParameters *wrapper = [self popAddPaymentParametersForIdentifier:productIdentifier];
    if (wrapper.successBlock != nil)
    {
        wrapper.successBlock(transaction);
    }
    
    [self postNotificationWithName:RMSKPaymentTransactionFinished transaction:transaction userInfoExtras:nil];
    
    if (transaction.transactionState == SKPaymentTransactionStateRestored)
    {
        [self notifyRestoreTransactionFinishedIfApplicableAfterTransaction:transaction];
    }
}

- (void)notifyRestoreTransactionFinishedIfApplicableAfterTransaction:(SKPaymentTransaction*)transaction
{
    if (transaction != nil)
    {
        [_restoredTransactions addObject:transaction];
        _pendingRestoredTransactionsCount--;
    }
    if (_restoredCompletedTransactionsFinished && _pendingRestoredTransactionsCount == 0)
    { // Wait until all restored transations have been verified
        NSArray *restoredTransactions = [_restoredTransactions copy];
        if (_restoreTransactionsSuccessBlock != nil)
        {
            _restoreTransactionsSuccessBlock(restoredTransactions);
            _restoreTransactionsSuccessBlock = nil;
        }
        NSDictionary *userInfo = @{ RMStoreNotificationTransactions : restoredTransactions };
        [[NSNotificationCenter defaultCenter] postNotificationName:RMSKRestoreTransactionsFinished object:self userInfo:userInfo];
    }
}

- (RMAddPaymentParameters*)popAddPaymentParametersForIdentifier:(NSString*)identifier
{
    if (!identifier) {
        return nil;
    }
    RMAddPaymentParameters *parameters = _addPaymentParameters[identifier];
    [_addPaymentParameters removeObjectForKey:identifier];
    return parameters;
}

#pragma mark SKRequestDelegate

- (void)requestDidFinish:(SKRequest *)request
{
    RMStoreLog(@"refresh receipt finished");
    _refreshReceiptRequest = nil;
    if (_refreshReceiptSuccessBlock)
    {
        _refreshReceiptSuccessBlock();
        _refreshReceiptSuccessBlock = nil;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:RMSKRefreshReceiptFinished object:self];
}

- (void)request:(SKRequest *)request didFailWithError:(NSError *)error
{
    RMStoreLog(@"refresh receipt failed with error %@", error.debugDescription);
    _refreshReceiptRequest = nil;
    if (_refreshReceiptFailureBlock)
    {
        _refreshReceiptFailureBlock(error);
        _refreshReceiptFailureBlock = nil;
    }
    NSDictionary *userInfo = nil;
    if (error)
    { // error might be nil (e.g., on airplane mode)
        userInfo = @{RMStoreNotificationStoreError: error};
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:RMSKRefreshReceiptFailed object:self userInfo:userInfo];
}

#pragma mark Private

- (void)addProduct:(SKProduct*)product
{
    if (product) {
        _products[product.productIdentifier] = product;
    }
}

- (void)postNotificationWithName:(NSString*)notificationName download:(SKDownload*)download userInfoExtras:(NSDictionary*)extras
{
    NSMutableDictionary *mutableExtras = extras ? [NSMutableDictionary dictionaryWithDictionary:extras] : [NSMutableDictionary dictionary];
    mutableExtras[RMStoreNotificationStoreDownload] = download;
    [self postNotificationWithName:notificationName transaction:download.transaction userInfoExtras:mutableExtras];
}

- (void)postNotificationWithName:(NSString*)notificationName transaction:(SKPaymentTransaction*)transaction userInfoExtras:(NSDictionary*)extras
{
    NSString *productIdentifier = transaction.payment.productIdentifier;
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    userInfo[RMStoreNotificationTransaction] = transaction;
    userInfo[RMStoreNotificationProductIdentifier] = productIdentifier;
    if (extras)
    {
        [userInfo addEntriesFromDictionary:extras];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:notificationName object:self userInfo:userInfo];
}

- (void)removeProductsRequestDelegate:(RMProductsRequestDelegate*)delegate
{
    [_productsRequestDelegates removeObject:delegate];
}

@end

@implementation RMProductsRequestDelegate

- (void)watchdogTimerFiredAction
{
    [self.request cancel];
    [self request:self.request didFailWithError:[RMStoreWatchdoggedObject watchdogTimeoutError]];
}

- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response
{
    [self ifNotWatchdogTimerIsFiredResetItAndRun:^{
        RMStoreLog(@"products request received response");
        NSArray *products = [NSArray arrayWithArray:response.products];
        NSArray *invalidProductIdentifiers = [NSArray arrayWithArray:response.invalidProductIdentifiers];
        
        for (SKProduct *product in products)
        {
            RMStoreLog(@"received product with id %@", product.productIdentifier);
            [self.store addProduct:product];
        }
        
        for (NSString *invalid in invalidProductIdentifiers)
        {
            RMStoreLog(@"invalid product with id %@", invalid);
        }
        
        if (self.successBlock)
        {
            self.successBlock(products, invalidProductIdentifiers);
        }
        NSDictionary *userInfo = @{RMStoreNotificationProducts: products, RMStoreNotificationInvalidProductIdentifiers: invalidProductIdentifiers};
        [[NSNotificationCenter defaultCenter] postNotificationName:RMSKProductsRequestFinished object:self.store userInfo:userInfo];
    }];
}

- (void)requestDidFinish:(SKRequest *)request
{
    [self disableWatchdogTimerAndComplete:^{
        [self.store removeProductsRequestDelegate:self];
    }];
}

- (void)request:(SKRequest *)request didFailWithError:(NSError *)error
{
    [self disableWatchdogTimerAndComplete:^{
        RMStoreLog(@"products request failed with error %@", error.debugDescription);
        if (self.failureBlock)
        {
            self.failureBlock(error);
        }
        NSDictionary *userInfo = nil;
        if (error)
        { // error might be nil (e.g., on airplane mode)
            userInfo = @{RMStoreNotificationStoreError: error};
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:RMSKProductsRequestFailed object:self.store userInfo:userInfo];
        [self.store removeProductsRequestDelegate:self];
    }];
}

@end

// Don't know how to implement network lags for unit testing of RMStoreWatchdoggedObject. Was tested manually by blocking access to Apple's itunes CDN on router (target host names contains keywords 'itunes' and 'akamaiedge').
@interface RMStoreWatchdoggedObject () {
    BOOL _isWatchdogTimerFired;
    NSTimer * _watchdogTimer;
    NSTimeInterval _timeout;
}
@property (nonatomic, weak) RMStore * storeUsingWatchedTimers;
@property (nonatomic, assign) BOOL isWatchdogTimerDisabled;
@end
#define RMWatchdogTimerInvalidate(TIMER) do { [TIMER invalidate]; TIMER = nil; } while(0)

@implementation RMStoreWatchdoggedObject

+ (NSError *)watchdogTimeoutError
{
    NSError *error = [NSError errorWithDomain:RMStoreErrorDomain code:RMStoreErrorCodeWatchdogTimerFired userInfo:@{NSLocalizedDescriptionKey:NSLocalizedString(@"Request is timed out because of network bottelneck.", @"Timeout error message")}];
    return error;
}

- (void)dealloc
{
    RMWatchdogTimerInvalidate(_watchdogTimer);
}

- (void)scheduleTimer
{
    if (self.storeUsingWatchedTimers && self.storeUsingWatchedTimers.useRequestProductsWatchdogTimer &&
        !_isWatchdogTimerFired && !_isWatchdogTimerDisabled) {
        RMWatchdogTimerInvalidate(_watchdogTimer);
        NSTimeInterval timeout = _timeout;
        if (timeout > RMStoreWatchdogMinimalAllowedTimeout) {
            NSLog(@"ATTENTION: watchdog timeout (%.2f) is less then recommended %.2f", timeout, RMStoreWatchdogMinimalAllowedTimeout);
        }
        _watchdogTimer = [NSTimer
                          scheduledTimerWithTimeInterval:timeout
                          target:self
                          selector:@selector(watchdogTimerFired:)
                          userInfo:nil
                          repeats:NO];
        RMStoreLog(@"Watcdog timer is scheduled with timeout: %.2f for: %@", timeout, self);
    }
}

- (void)watchdogTimerFired:(NSTimer *)timer
{
    @synchronized(self) {
        if (_isWatchdogTimerFired || _isWatchdogTimerDisabled || timer != _watchdogTimer) {
            return;
        }
        RMStoreLog(@"Watchdog timer is fired for: %@", self);
        [self watchdogTimerFiredAction];
        _isWatchdogTimerFired = YES;
    }
}

- (void)setIsWatchdogTimerDisabled:(BOOL)isWatchdogTimerDisabled
{
    _isWatchdogTimerDisabled = isWatchdogTimerDisabled;
    if (_isWatchdogTimerDisabled) {
        RMWatchdogTimerInvalidate(_watchdogTimer);
        RMStoreLog(@"Watchdog timer is invalidated and disabled for: %@.", self);
    }
}

#pragma mark For use in subclass
- (void)activateWatchdogTimerWithStore:(RMStore __weak *)store timeout:(NSTimeInterval)timeout
{
    @synchronized(self) {
        self.storeUsingWatchedTimers = store;
        _timeout = timeout;
        [self scheduleTimer];
    }
}

- (void)watchdogTimerFiredAction
{
    // Overload this in subclass.
}

- (void)ifNotWatchdogTimerIsFiredResetItAndRun:(void (^)())block
{
    @synchronized(self) {
        if (!self.storeUsingWatchedTimers.useRequestProductsWatchdogTimer) { // bypass when timers are disabled or store is inaccessible
            if (block) {
                block();
            }
        } else { // handle with timer
            if (_isWatchdogTimerFired) {
                return;
            }
            RMWatchdogTimerInvalidate(_watchdogTimer);
            if (block) {
                block();
            }
            [self scheduleTimer];
        }
    }
}

- (void)disableWatchdogTimerAndComplete:(void (^)())completion
{
    @synchronized(self) {
        if (!self.storeUsingWatchedTimers.useRequestProductsWatchdogTimer) { // bypass when timers are disabled or store is inaccessible
            if (completion) {
                completion();
            }
        } else { // handle with timer
            self.isWatchdogTimerDisabled = YES;
            if (_isWatchdogTimerFired) {
                return;
            }
            if (completion) {
                completion();
            }
        }
    }
}

@end
