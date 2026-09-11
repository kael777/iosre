//
//  APIClient.h
//  SignDemo
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface APIResponse : NSObject

@property (nonatomic, copy) NSString *action;
@property (nonatomic, copy) NSString *method;
@property (nonatomic, copy, nullable) NSString *URLString;
@property (nonatomic, copy, nullable) NSDictionary *requestBody;
@property (nonatomic, assign) NSInteger statusCode;
@property (nonatomic, strong, nullable) id JSONObject;
@property (nonatomic, copy, nullable) NSString *rawBody;
@property (nonatomic, strong, nullable) NSError *error;

- (NSString *)displayText;

@end

typedef void (^APIClientCompletion)(APIResponse *response);
typedef void (^APIClientWSHandler)(NSString *line);

@interface APIClient : NSObject

@property (nonatomic, copy) NSString *baseURLString;
@property (nonatomic, copy) NSString *secret;
@property (nonatomic, assign) BOOL pinningEnabled;
@property (nonatomic, readonly, getter=isEventsConnected) BOOL eventsConnected;

- (instancetype)initWithBaseURLString:(NSString *)baseURLString
                               secret:(NSString *)secret;

- (void)healthWithCompletion:(APIClientCompletion)completion;
- (void)loginWithUserID:(NSString *)userID
               password:(NSString *)password
             completion:(APIClientCompletion)completion;
- (void)profileWithUserID:(NSString *)userID
               completion:(APIClientCompletion)completion;
- (void)createTestOrderWithUserID:(NSString *)userID
                       completion:(APIClientCompletion)completion;

- (BOOL)connectEventsWithToken:(NSString *)token
                       handler:(APIClientWSHandler)handler
                         error:(NSError * _Nullable * _Nullable)error;
- (void)disconnectEvents;

@end

NS_ASSUME_NONNULL_END
