#import "ViewController.h"
#import "Session.h"
#import <Security/Security.h>
#import <WebKit/WebKit.h>
#import <LocalAuthentication/LocalAuthentication.h>

static NSString * const kUsernameKey = @"username";
static NSString * const kPasswordKey = @"password";
static NSString * const kLoggedInKey = @"isLoggedIn";
@interface ViewController ()
@property (nonatomic, strong) UITextField *userField;
@property (nonatomic, strong) UITextField *passField;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *loginButton;
@property (nonatomic, strong) UIButton *logoutButton;
@property (nonatomic, strong) UIButton *bioButton;
@property (nonatomic, strong) WKWebView *webView;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.title = @"InsecureApp";
    [self removeLegacyInsecureDefaults];

    UILabel *hint = [[UILabel alloc] init];
    hint.translatesAutoresizingMaskIntoConstraints = NO;
    hint.numberOfLines = 0;
    hint.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    hint.textColor = UIColor.secondaryLabelColor;
    hint.text = @"W16 修复版：URL Scheme 与网页 Bridge 不再自动登录；Face ID 失败就是失败。虚构 demo / pass。";

    self.userField = [self fieldWithPlaceholder:@"username（虚构）"];
    self.userField.text = @"demo";
    self.passField = [self fieldWithPlaceholder:@"password（虚构）"];
    self.passField.text = @"pass";
    self.passField.secureTextEntry = YES;

    self.loginButton = [self buttonWithTitle:@"Login" action:@selector(loginTapped)];
    self.logoutButton = [self buttonWithTitle:@"Logout" action:@selector(logoutTapped)];
    self.bioButton = [self buttonWithTitle:@"Face ID 登录" action:@selector(biometricsTapped)];

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    self.webView.layer.borderWidth = 1;
    self.webView.layer.borderColor = UIColor.separatorColor.CGColor;
    NSString *html = @"<html><body style='font:16px -apple-system'>"
        @"<p>WebView（已去掉 nativeLogin Bridge）</p>"
        @"<p>网页不能再把 App 设为已登录。</p>"
        @"</body></html>";
    [self.webView loadHTMLString:html baseURL:nil];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        hint, self.userField, self.passField, self.loginButton, self.logoutButton,
        self.bioButton, self.webView, self.statusLabel
    ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    [self.view addSubview:stack];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [stack.topAnchor constraintEqualToAnchor:safe.topAnchor constant:12],
        [self.userField.heightAnchor constraintEqualToConstant:36],
        [self.passField.heightAnchor constraintEqualToConstant:36],
        [self.loginButton.heightAnchor constraintEqualToConstant:40],
        [self.logoutButton.heightAnchor constraintEqualToConstant:40],
        [self.bioButton.heightAnchor constraintEqualToConstant:40],
        [self.webView.heightAnchor constraintEqualToConstant:120]
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(refreshStatus)
                                                 name:InsecureAppSessionDidChangeNotification
                                               object:nil];
    [self refreshStatus];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)removeLegacyInsecureDefaults {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:kPasswordKey];
    [defaults removeObjectForKey:kLoggedInKey];
    [defaults synchronize];
}

- (UITextField *)fieldWithPlaceholder:(NSString *)placeholder {
    UITextField *field = [[UITextField alloc] init];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.borderStyle = UITextBorderStyleRoundedRect;
    field.placeholder = placeholder;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    return field;
}

- (UIButton *)buttonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    button.layer.borderWidth = 1;
    button.layer.borderColor = UIColor.systemBlueColor.CGColor;
    button.layer.cornerRadius = 8;
    return button;
}

- (void)loginTapped {
    NSString *user = self.userField.text ?: @"";
    NSString *pass = self.passField.text ?: @"";
    if (user.length == 0 || pass.length == 0) {
        self.statusLabel.text = @"请填写虚构用户名和密码";
        return;
    }
    NSLog(@"login ok");
    [[Session shared] loginWithSource:@"password"];
    [self savePasswordToKeychain:pass account:user];
}

- (void)logoutTapped {
    [[Session shared] logout];
}

- (void)biometricsTapped {
    LAContext *context = [[LAContext alloc] init];
    NSError *error = nil;
    if (![context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&error]) {
        self.statusLabel.text = [NSString stringWithFormat:@"设备不支持生物识别：%@", error.localizedDescription];
        return;
    }
    [context evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics
            localizedReason:@"InsecureApp 练习认证"
                      reply:^(BOOL success, NSError *evalError) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                [[Session shared] loginWithSource:@"biometrics"];
            } else {
                self.statusLabel.text = [NSString stringWithFormat:@"生物识别失败：%@", evalError.localizedDescription];
            }
        });
    }];
}

- (void)refreshStatus {
    Session *session = [Session shared];
    if (session.authenticated) {
        self.statusLabel.text = [NSString stringWithFormat:
                                 @"状态：已登录\n来源：%@\nScheme/WebView 不会自动登录。",
                                 session.source];
    } else {
        self.statusLabel.text = @"状态：未登录\nSafari 的 insecureapp://login 和网页按钮不应再登录。";
    }
}

- (void)savePasswordToKeychain:(NSString *)password account:(NSString *)account {
    NSData *data = [password dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: @"InsecureApp",
        (__bridge id)kSecAttrAccount: account
    };
    SecItemDelete((__bridge CFDictionaryRef)query);
    NSMutableDictionary *add = [query mutableCopy];
    add[(__bridge id)kSecValueData] = data;
    add[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly;
    SecItemAdd((__bridge CFDictionaryRef)add, NULL);
}

@end
