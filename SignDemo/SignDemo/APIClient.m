//
//  APIClient.m
//  SignDemo
//

#import "APIClient.h"
#import "APIConfig.h"
#import "HMACSigner.h"
#import "PinningURLSessionDelegate.h"
#import "SecretStore.h"

@implementation APIResponse

- (NSString *)displayText {
    NSMutableString *text = [NSMutableString string];

    if ([self isLoopbackURL]) {
        [text appendString:@"警告：127.0.0.1 / localhost 在真机上指向 iPhone 自己，"
                           @"不是 Mac。请改成 Mac 局域网 IP，例如 https://192.168.1.8:5443\n\n"];
    }

    [text appendFormat:@"%@\n%@ %@",
     self.action ?: @"request",
     self.method ?: @"",
     self.URLString ?: @""];

    if (self.requestBody != nil) {
        [text appendFormat:@"\nRequest:\n%@", [self prettyJSON:self.requestBody]];
    }

    if (self.error != nil) {
        [text appendFormat:@"\n\n网络错误：%@", self.error.localizedDescription];
        return text;
    }

    [text appendFormat:@"\n\nHTTP %ld", (long)self.statusCode];
    if (self.JSONObject != nil) {
        [text appendFormat:@"\n%@", [self prettyJSON:self.JSONObject]];
    } else if (self.rawBody.length > 0) {
        [text appendFormat:@"\n%@", self.rawBody];
    } else {
        [text appendString:@"\n<empty response>"];
    }
    return text;
}

- (BOOL)isLoopbackURL {
    NSURL *url = [NSURL URLWithString:self.URLString ?: @""];
    NSString *host = url.host.lowercaseString;
    return [host isEqualToString:@"127.0.0.1"] || [host isEqualToString:@"localhost"];
}

- (NSString *)prettyJSON:(id)object {
    if (object == nil) {
        return @"";
    }
    NSJSONWritingOptions options = NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object
                                                   options:options
                                                     error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

@end

@interface APIClient ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) PinningURLSessionDelegate *pinningDelegate;
@property (nonatomic, strong) NSURLSessionWebSocketTask *webSocketTask;
@property (nonatomic, copy) APIClientWSHandler wsHandler;
@end

@implementation APIClient

- (instancetype)initWithBaseURLString:(NSString *)baseURLString
                               secret:(NSString *)secret {
    self = [super init];
    if (self) {
        _baseURLString = [baseURLString copy];
        _secret = [secret copy];
        _pinningEnabled = SignDemoPinningEnabled;
        _pinningDelegate = [[PinningURLSessionDelegate alloc] init];
        _pinningDelegate.pinningEnabled = _pinningEnabled;
        _session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration
                                                 delegate:_pinningDelegate
                                            delegateQueue:nil];
    }
    return self;
}

- (void)dealloc {
    [_webSocketTask cancel];
    [_session invalidateAndCancel];
}

- (BOOL)isEventsConnected {
    return self.webSocketTask != nil;
}

- (void)setPinningEnabled:(BOOL)pinningEnabled {
    _pinningEnabled = pinningEnabled;
    self.pinningDelegate.pinningEnabled = pinningEnabled;
}

- (void)healthWithCompletion:(APIClientCompletion)completion {
    [self sendMethod:@"GET"
                path:@"/api/health"
                body:nil
              action:@"Health"
          completion:completion];
}

- (void)loginWithUserID:(NSString *)userID
               password:(NSString *)password
             completion:(APIClientCompletion)completion {
    NSMutableDictionary *body = [[self signedBodyForAction:@"login"
                                                    userID:userID] mutableCopy];
    body[@"password"] = password ?: @"";
    [self sendMethod:@"POST"
                path:@"/api/login"
                body:body
              action:@"Login"
          completion:completion];
}

- (void)profileWithUserID:(NSString *)userID
               completion:(APIClientCompletion)completion {
    NSCharacterSet *allowed = [NSCharacterSet URLPathAllowedCharacterSet];
    NSString *encoded = [userID stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
    NSString *path = [NSString stringWithFormat:@"/api/profile/%@", encoded];
    [self sendMethod:@"GET"
                path:path
                body:nil
              action:@"Profile"
          completion:completion];
}

- (void)createTestOrderWithUserID:(NSString *)userID
                       completion:(APIClientCompletion)completion {
    NSMutableDictionary *body = [[self signedBodyForAction:@"order"
                                                    userID:userID] mutableCopy];
    body[@"order_id"] = SignDemoDefaultOrderID;
    body[@"amount"] = @(SignDemoDefaultOrderAmount);
    [self sendMethod:@"POST"
                path:@"/api/order"
                body:body
              action:@"Create Test Order"
          completion:completion];
}

- (NSDictionary *)signedBodyForAction:(NSString *)action
                               userID:(NSString *)userID {
    long long timestamp = (long long)[NSDate date].timeIntervalSince1970;
    NSString *nonce = [HMACSigner newNonce];
    NSString *sign = [HMACSigner signWithUserID:userID
                                      timestamp:timestamp
                                          nonce:nonce
                                         action:action
                                         secret:[SecretStore currentSecret]];
    return @{
        @"user_id": userID ?: @"",
        @"timestamp": @(timestamp),
        @"nonce": nonce,
        @"sign": sign
    };
}

- (void)sendMethod:(NSString *)method
              path:(NSString *)path
              body:(NSDictionary *)body
            action:(NSString *)action
        completion:(APIClientCompletion)completion {
    APIResponse *response = [[APIResponse alloc] init];
    response.action = action;
    response.method = method;
    response.requestBody = body;

    NSString *base = [self.baseURLString
                      stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([base hasSuffix:@"/"]) {
        base = [base substringToIndex:base.length - 1];
    }

    if (base.length == 0) {
        response.error = [NSError errorWithDomain:@"SignDemo"
                                             code:-1
                                         userInfo:@{
            NSLocalizedDescriptionKey: @"请填写后端地址"
        }];
        [self finish:response completion:completion];
        return;
    }

    NSString *urlString = [base stringByAppendingString:path];
    response.URLString = urlString;
    NSURL *url = [NSURL URLWithString:urlString];
    if (url == nil) {
        response.error = [NSError errorWithDomain:@"SignDemo"
                                             code:-1
                                         userInfo:@{
            NSLocalizedDescriptionKey: @"后端地址格式不正确"
        }];
        [self finish:response completion:completion];
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = method;
    request.timeoutInterval = 10.0;
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    if (body != nil) {
        NSError *serializationError = nil;
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body
                                                           options:0
                                                             error:&serializationError];
        if (serializationError != nil) {
            response.error = serializationError;
            [self finish:response completion:completion];
            return;
        }
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    }

    self.pinningDelegate.lastFailureReason = nil;

    NSURLSessionDataTask *task =
        [self.session dataTaskWithRequest:request
                        completionHandler:
         ^(NSData *data, NSURLResponse *urlResponse, NSError *error) {
             if (self.pinningDelegate.lastFailureReason.length > 0) {
                 NSMutableDictionary *info = [NSMutableDictionary dictionary];
                 info[NSLocalizedDescriptionKey] = self.pinningDelegate.lastFailureReason;
                 if (error != nil) {
                     info[NSUnderlyingErrorKey] = error;
                 }
                 response.error = [NSError errorWithDomain:@"SignDemo.Pinning"
                                                      code:-1202
                                                  userInfo:info];
             } else {
                 response.error = error;
             }
             if ([urlResponse isKindOfClass:[NSHTTPURLResponse class]]) {
                 response.statusCode = [(NSHTTPURLResponse *)urlResponse statusCode];
             }
             if (data.length > 0) {
                 response.rawBody = [[NSString alloc] initWithData:data
                                                          encoding:NSUTF8StringEncoding];
                 response.JSONObject = [NSJSONSerialization JSONObjectWithData:data
                                                                       options:0
                                                                         error:nil];
             }
             [self finish:response completion:completion];
         }];
    [task resume];
}

- (NSString *)trimmedBaseURL {
    NSString *base = [self.baseURLString
                      stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([base hasSuffix:@"/"]) {
        base = [base substringToIndex:base.length - 1];
    }
    return base ?: @"";
}

- (NSString *)eventsURLStringWithToken:(NSString *)token {
    NSString *base = [self trimmedBaseURL];
    if ([base.lowercaseString hasPrefix:@"https://"]) {
        base = [@"wss://" stringByAppendingString:[base substringFromIndex:8]];
    } else if ([base.lowercaseString hasPrefix:@"http://"]) {
        base = [@"ws://" stringByAppendingString:[base substringFromIndex:7]];
    }
    NSCharacterSet *allowed = [NSCharacterSet URLQueryAllowedCharacterSet];
    NSString *encoded = [token stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
    return [NSString stringWithFormat:@"%@/ws/events?token=%@", base, encoded];
}

- (BOOL)connectEventsWithToken:(NSString *)token
                       handler:(APIClientWSHandler)handler
                         error:(NSError * _Nullable * _Nullable)error {
    if (token.length == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"SignDemo"
                                         code:-1
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"请先 Login，拿到 token 后再连 WebSocket"
            }];
        }
        return NO;
    }

    NSString *urlString = [self eventsURLStringWithToken:token];
    NSURL *url = [NSURL URLWithString:urlString];
    if (url == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"SignDemo"
                                         code:-1
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"WebSocket 地址格式不正确"
            }];
        }
        return NO;
    }

    [self disconnectEvents];
    self.wsHandler = handler;
    self.pinningDelegate.lastFailureReason = nil;
    self.webSocketTask = [self.session webSocketTaskWithURL:url];
    [self emitWS:[NSString stringWithFormat:@"WS 连接中\n%@", urlString]];
    [self.webSocketTask resume];
    [self listenForMessages];
    return YES;
}

- (void)disconnectEvents {
    NSURLSessionWebSocketTask *task = self.webSocketTask;
    self.webSocketTask = nil;
    if (task != nil) {
        [task cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure
                           reason:nil];
        [self emitWS:@"WS 已主动断开"];
    }
}

- (void)listenForMessages {
    NSURLSessionWebSocketTask *task = self.webSocketTask;
    if (task == nil) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    [task receiveMessageWithCompletionHandler:
     ^(NSURLSessionWebSocketMessage *message, NSError *error) {
         __strong typeof(weakSelf) strongSelf = weakSelf;
         if (strongSelf == nil || strongSelf.webSocketTask != task) {
             return;
         }
         if (error != nil) {
             NSString *reason = strongSelf.pinningDelegate.lastFailureReason;
             if (reason.length > 0) {
                 [strongSelf emitWS:[NSString stringWithFormat:@"WS 断开：%@", reason]];
             } else {
                 [strongSelf emitWS:[NSString stringWithFormat:@"WS 断开：%@",
                                     error.localizedDescription]];
             }
             strongSelf.webSocketTask = nil;
             return;
         }

         if (message.type == NSURLSessionWebSocketMessageTypeString) {
             [strongSelf emitWS:[NSString stringWithFormat:@"WS 帧：%@", message.string]];
         } else {
             [strongSelf emitWS:[NSString stringWithFormat:@"WS 二进制 %lu bytes",
                                 (unsigned long)message.data.length]];
         }
         [strongSelf listenForMessages];
     }];
}

- (void)emitWS:(NSString *)line {
    APIClientWSHandler handler = self.wsHandler;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (handler != nil) {
            handler(line);
        }
    });
}

- (void)finish:(APIResponse *)response completion:(APIClientCompletion)completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion != nil) {
            completion(response);
        }
    });
}

@end
