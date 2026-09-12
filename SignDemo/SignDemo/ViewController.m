//
//  ViewController.m
//  SignDemo
//
//  Created by SignDemo on 2026/9/10.
//

#import "ViewController.h"
#import "APIClient.h"
#import "APIConfig.h"
#import "AntiDebug.h"
#import "JailbreakCheck.h"
#import "SecretStore.h"

static NSString * const kSignDemoBaseURLDefaultsKey = @"SignDemoBaseURL";
static NSString * const kSignDemoPinningDefaultsKey = @"SignDemoPinningEnabled";
static NSString * const kSignDemoAntiDebugDefaultsKey = @"SignDemoAntiDebugEnabled";
static NSString * const kSignDemoPlainSecretDefaultsKey = @"SignDemoUsePlainSecret";

@interface ViewController () <UITextFieldDelegate>

@property (nonatomic, strong) APIClient *client;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UITextField *baseURLField;
@property (nonatomic, strong) UITextField *userIDField;
@property (nonatomic, strong) UITextField *passwordField;
@property (nonatomic, strong) UISwitch *pinningSwitch;
@property (nonatomic, strong) UISwitch *antiDebugSwitch;
@property (nonatomic, strong) UISwitch *plainSecretSwitch;
@property (nonatomic, strong) NSTimer *antiDebugTimer;
@property (nonatomic, assign) BOOL didReportTrace;
@property (nonatomic, strong) UIButton *healthButton;
@property (nonatomic, strong) UIButton *loginButton;
@property (nonatomic, strong) UIButton *profileButton;
@property (nonatomic, strong) UIButton *orderButton;
@property (nonatomic, strong) UIButton *connectWSButton;
@property (nonatomic, strong) UIButton *disconnectWSButton;
@property (nonatomic, strong) UIButton *crashButton;
@property (nonatomic, strong) UIButton *jailbreakButton;
@property (nonatomic, strong) UITextView *outputView;
@property (nonatomic, copy) NSString *sessionToken;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"SignDemo";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.client = [[APIClient alloc] initWithBaseURLString:[self storedBaseURL]
                                                    secret:SignDemoSigningSecret];
    self.client.pinningEnabled = [self storedPinningEnabled];
    SignDemoPinningEnabled = self.client.pinningEnabled;
    SignDemoAntiDebugEnabled = [self storedAntiDebugEnabled];
    SignDemoUsePlainSecret = [self storedPlainSecretEnabled];

    [self buildInterface];
    [self registerKeyboardNotifications];
    if (SignDemoAntiDebugEnabled) {
        [self startAntiDebugTimer];
    }

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
                                   initWithTarget:self
                                   action:@selector(dismissKeyboard)];
    tap.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tap];
}

- (void)dealloc {
    [self.antiDebugTimer invalidate];
    [self.client disconnectEvents];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Interface

- (void)buildInterface {
    UILabel *titleLabel = [self labelWithText:@"SignDemo 本地协议实验"];
    titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];

    UILabel *hintLabel = [self labelWithText:
                          @"顺序：Health → Login → Profile → Order → Connect WS。真机用 https://192.168.1.8:5443，不要填 127.0.0.1。抓包时关掉 Pinning。"];
    hintLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    hintLabel.textColor = UIColor.secondaryLabelColor;
    hintLabel.numberOfLines = 0;

    self.baseURLField = [self textFieldWithPlaceholder:
                         @"后端地址，例如 https://192.168.1.8:5443"];
    self.baseURLField.text = [self storedBaseURL];
    self.baseURLField.keyboardType = UIKeyboardTypeURL;
    self.baseURLField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.baseURLField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.baseURLField.returnKeyType = UIReturnKeyDone;
    self.baseURLField.delegate = self;

    self.userIDField = [self textFieldWithPlaceholder:@"user_id"];
    self.userIDField.text = SignDemoDefaultUserID;
    self.userIDField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.userIDField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.userIDField.returnKeyType = UIReturnKeyNext;
    self.userIDField.delegate = self;

    self.passwordField = [self textFieldWithPlaceholder:@"password"];
    self.passwordField.text = SignDemoDefaultPassword;
    self.passwordField.secureTextEntry = YES;
    self.passwordField.returnKeyType = UIReturnKeyDone;
    self.passwordField.delegate = self;

    UILabel *pinningLabel = [self labelWithText:@"证书 Pinning"];
    self.pinningSwitch = [[UISwitch alloc] init];
    self.pinningSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    self.pinningSwitch.on = self.client.pinningEnabled;
    [self.pinningSwitch addTarget:self
                           action:@selector(pinningSwitchChanged:)
                 forControlEvents:UIControlEventValueChanged];
    UIStackView *pinningRow = [[UIStackView alloc] initWithArrangedSubviews:@[
        pinningLabel,
        self.pinningSwitch
    ]];
    pinningRow.translatesAutoresizingMaskIntoConstraints = NO;
    pinningRow.axis = UILayoutConstraintAxisHorizontal;
    pinningRow.alignment = UIStackViewAlignmentCenter;

    UILabel *antiDebugLabel = [self labelWithText:@"反调试（只提示）"];
    self.antiDebugSwitch = [[UISwitch alloc] init];
    self.antiDebugSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    self.antiDebugSwitch.on = SignDemoAntiDebugEnabled;
    [self.antiDebugSwitch addTarget:self
                             action:@selector(antiDebugSwitchChanged:)
                   forControlEvents:UIControlEventValueChanged];
    UIStackView *antiDebugRow = [[UIStackView alloc] initWithArrangedSubviews:@[
        antiDebugLabel,
        self.antiDebugSwitch
    ]];
    antiDebugRow.translatesAutoresizingMaskIntoConstraints = NO;
    antiDebugRow.axis = UILayoutConstraintAxisHorizontal;
    antiDebugRow.alignment = UIStackViewAlignmentCenter;

    UILabel *plainSecretLabel = [self labelWithText:@"明文 secret（对比）"];
    self.plainSecretSwitch = [[UISwitch alloc] init];
    self.plainSecretSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    self.plainSecretSwitch.on = SignDemoUsePlainSecret;
    [self.plainSecretSwitch addTarget:self
                               action:@selector(plainSecretSwitchChanged:)
                     forControlEvents:UIControlEventValueChanged];
    UIStackView *plainSecretRow = [[UIStackView alloc] initWithArrangedSubviews:@[
        plainSecretLabel,
        self.plainSecretSwitch
    ]];
    plainSecretRow.translatesAutoresizingMaskIntoConstraints = NO;
    plainSecretRow.axis = UILayoutConstraintAxisHorizontal;
    plainSecretRow.alignment = UIStackViewAlignmentCenter;

    self.healthButton = [self buttonWithTitle:@"Health"
                                       action:@selector(healthButtonTapped:)];
    self.loginButton = [self buttonWithTitle:@"Login"
                                      action:@selector(loginButtonTapped:)];
    self.profileButton = [self buttonWithTitle:@"Profile"
                                        action:@selector(profileButtonTapped:)];
    self.orderButton = [self buttonWithTitle:@"Create Test Order"
                                      action:@selector(orderButtonTapped:)];
    self.connectWSButton = [self buttonWithTitle:@"Connect WS"
                                          action:@selector(connectWSButtonTapped:)];
    self.disconnectWSButton = [self buttonWithTitle:@"Disconnect WS"
                                             action:@selector(disconnectWSButtonTapped:)];
    self.crashButton = [self buttonWithTitle:@"Crash (W13)"
                                      action:@selector(crashButtonTapped:)];
    self.crashButton.layer.borderColor = UIColor.systemRedColor.CGColor;
    [self.crashButton setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];
    self.jailbreakButton = [self buttonWithTitle:@"Jailbreak Check (W19)"
                                          action:@selector(jailbreakButtonTapped:)];

    UILabel *outputLabel = [self labelWithText:@"HTTP 状态码和响应正文"];
    outputLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];

    self.outputView = [[UITextView alloc] init];
    self.outputView.translatesAutoresizingMaskIntoConstraints = NO;
    self.outputView.editable = NO;
    self.outputView.font = [UIFont monospacedSystemFontOfSize:13.0
                                                       weight:UIFontWeightRegular];
    self.outputView.layer.borderWidth = 1.0;
    self.outputView.layer.borderColor = UIColor.separatorColor.CGColor;
    self.outputView.layer.cornerRadius = 8.0;
    self.outputView.text = @"等待请求...\nHealth → Login → Profile → Order → Connect WS。";

    UIStackView *buttonStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.healthButton,
        self.loginButton,
        self.profileButton
    ]];
    buttonStack.translatesAutoresizingMaskIntoConstraints = NO;
    buttonStack.axis = UILayoutConstraintAxisHorizontal;
    buttonStack.spacing = 8.0;
    buttonStack.distribution = UIStackViewDistributionFillEqually;

    UIStackView *wsButtonStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.orderButton,
        self.connectWSButton,
        self.disconnectWSButton,
        self.crashButton
    ]];
    wsButtonStack.translatesAutoresizingMaskIntoConstraints = NO;
    wsButtonStack.axis = UILayoutConstraintAxisHorizontal;
    wsButtonStack.spacing = 8.0;
    wsButtonStack.distribution = UIStackViewDistributionFillEqually;

    UIStackView *formStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        titleLabel,
        hintLabel,
        self.baseURLField,
        self.userIDField,
        self.passwordField,
        pinningRow,
        antiDebugRow,
        plainSecretRow,
        self.jailbreakButton,
        buttonStack,
        wsButtonStack,
        outputLabel,
        self.outputView
    ]];
    formStack.translatesAutoresizingMaskIntoConstraints = NO;
    formStack.axis = UILayoutConstraintAxisVertical;
    formStack.spacing = 12.0;

    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.scrollView addSubview:formStack];
    [self.view addSubview:self.scrollView];

    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor],
        [self.scrollView.topAnchor constraintEqualToAnchor:safeArea.topAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:safeArea.bottomAnchor],

        [formStack.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor
                                                constant:16.0],
        [formStack.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor
                                                 constant:-16.0],
        [formStack.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor
                                            constant:16.0],
        [formStack.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor
                                               constant:-16.0],
        [formStack.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor
                                              constant:-32.0],

        [self.baseURLField.heightAnchor constraintEqualToConstant:42.0],
        [self.userIDField.heightAnchor constraintEqualToConstant:42.0],
        [self.passwordField.heightAnchor constraintEqualToConstant:42.0],
        [buttonStack.heightAnchor constraintEqualToConstant:44.0],
        [wsButtonStack.heightAnchor constraintEqualToConstant:44.0],
        [self.outputView.heightAnchor constraintGreaterThanOrEqualToConstant:260.0]
    ]];
}

- (UILabel *)labelWithText:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = text;
    return label;
}

- (UITextField *)textFieldWithPlaceholder:(NSString *)placeholder {
    UITextField *field = [[UITextField alloc] init];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.placeholder = placeholder;
    field.borderStyle = UITextBorderStyleRoundedRect;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    return field;
}

- (UIButton *)buttonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    [button addTarget:self
               action:action
     forControlEvents:UIControlEventTouchUpInside];
    button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    button.titleLabel.minimumScaleFactor = 0.7;
    button.layer.borderWidth = 1.0;
    button.layer.borderColor = UIColor.systemBlueColor.CGColor;
    button.layer.cornerRadius = 8.0;
    return button;
}

#pragma mark - Actions

- (void)pinningSwitchChanged:(UISwitch *)sender {
    self.client.pinningEnabled = sender.isOn;
    SignDemoPinningEnabled = sender.isOn;
    [[NSUserDefaults standardUserDefaults] setBool:sender.isOn
                                            forKey:kSignDemoPinningDefaultsKey];
    self.outputView.text = sender.isOn
        ? @"Pinning 已打开：只接受练习服务器证书指纹。"
        : @"Pinning 已关闭：走系统 CA 信任，mitmproxy 可以解密。";
}

- (void)antiDebugSwitchChanged:(UISwitch *)sender {
    SignDemoAntiDebugEnabled = sender.isOn;
    [[NSUserDefaults standardUserDefaults] setBool:sender.isOn
                                            forKey:kSignDemoAntiDebugDefaultsKey];
    if (sender.isOn) {
        self.didReportTrace = NO;
        [self startAntiDebugTimer];
        [self appendOutput:[NSString stringWithFormat:
                            @"反调试已打开（不退出进程）。%@",
                            [AntiDebug statusSummary]]];
        [self checkAntiDebug];
    } else {
        [self.antiDebugTimer invalidate];
        self.antiDebugTimer = nil;
        [self appendOutput:@"反调试已关闭。"];
    }
}

- (void)startAntiDebugTimer {
    [self.antiDebugTimer invalidate];
    self.antiDebugTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                           target:self
                                                         selector:@selector(checkAntiDebug)
                                                         userInfo:nil
                                                          repeats:YES];
}

- (void)checkAntiDebug {
    if (!SignDemoAntiDebugEnabled) {
        return;
    }
    NSString *summary = [AntiDebug statusSummary];
    if (![AntiDebug isBeingTraced]) {
        return;
    }
    if (self.didReportTrace) {
        return;
    }
    self.didReportTrace = YES;
    [self appendOutput:[NSString stringWithFormat:
                        @"检测到调试/跟踪，进程不退出。%@", summary]];
}

- (void)plainSecretSwitchChanged:(UISwitch *)sender {
    SignDemoUsePlainSecret = sender.isOn;
    [[NSUserDefaults standardUserDefaults] setBool:sender.isOn
                                            forKey:kSignDemoPlainSecretDefaultsKey];
    self.client.secret = [SecretStore currentSecret];
    [self appendOutput:sender.isOn
        ? @"明文 secret 已打开：使用字面量 local-demo-secret-v1。"
        : @"明文 secret 已关闭：使用 XOR 0x5A 还原。"];
}

- (void)healthButtonTapped:(UIButton *)sender {
    if (![self prepareClient]) {
        return;
    }
    [self setLoading:YES action:@"Health"];
    __weak typeof(self) weakSelf = self;
    [self.client healthWithCompletion:^(APIResponse *response) {
        [weakSelf showResponse:response];
    }];
}

- (void)loginButtonTapped:(UIButton *)sender {
    if (![self prepareClient]) {
        return;
    }

    NSString *userID = [self trimmedText:self.userIDField];
    NSString *password = self.passwordField.text ?: @"";
    if (userID.length == 0 || password.length == 0) {
        self.outputView.text = @"请填写 user_id 和 password";
        return;
    }

    [self setLoading:YES action:@"Login"];
    __weak typeof(self) weakSelf = self;
    [self.client loginWithUserID:userID
                        password:password
                      completion:^(APIResponse *response) {
        NSString *token = nil;
        id json = response.JSONObject;
        id value = [json isKindOfClass:[NSDictionary class]] ? json[@"token"] : nil;
        if ([value isKindOfClass:[NSString class]]) {
            token = value;
        }
        weakSelf.sessionToken = token;
        [weakSelf showResponse:response];
        if (token.length > 0) {
            [weakSelf appendOutput:@"已保存 token，可以点 Connect WS。抓包请先关掉 Pinning。"];
        }
    }];
}

- (void)profileButtonTapped:(UIButton *)sender {
    if (![self prepareClient]) {
        return;
    }

    NSString *userID = [self trimmedText:self.userIDField];
    if (userID.length == 0) {
        self.outputView.text = @"请填写 user_id";
        return;
    }

    [self setLoading:YES action:@"Profile"];
    __weak typeof(self) weakSelf = self;
    [self.client profileWithUserID:userID
                        completion:^(APIResponse *response) {
        [weakSelf showResponse:response];
    }];
}

- (void)connectWSButtonTapped:(UIButton *)sender {
    if (![self prepareClient]) {
        return;
    }
    if (self.sessionToken.length == 0) {
        self.outputView.text = @"请先 Login，拿到 token 后再连 WebSocket";
        return;
    }

    NSError *error = nil;
    __weak typeof(self) weakSelf = self;
    BOOL started = [self.client connectEventsWithToken:self.sessionToken
                                               handler:^(NSString *line) {
        [weakSelf appendOutput:line];
    }
                                                 error:&error];
    if (!started) {
        self.outputView.text = error.localizedDescription ?: @"无法连接 WebSocket";
    }
}

- (void)disconnectWSButtonTapped:(UIButton *)sender {
    [self.client disconnectEvents];
}

- (void)crashButtonTapped:(UIButton *)sender {
    @throw [NSException exceptionWithName:@"SignDemoLab"
                                   reason:@"intentional crash for W13"
                                 userInfo:nil];
}

- (void)jailbreakButtonTapped:(UIButton *)sender {
    [self appendOutput:[NSString stringWithFormat:
                        @"JailbreakCheck（只记录，不退出）\n%@",
                        [JailbreakCheck statusSummary]]];
}

- (void)orderButtonTapped:(UIButton *)sender {
    if (![self prepareClient]) {
        return;
    }

    NSString *userID = [self trimmedText:self.userIDField];
    if (userID.length == 0) {
        self.outputView.text = @"请填写 user_id";
        return;
    }

    [self setLoading:YES action:@"Create Test Order"];
    __weak typeof(self) weakSelf = self;
    [self.client createTestOrderWithUserID:userID
                                completion:^(APIResponse *response) {
        [weakSelf showResponse:response];
    }];
}

#pragma mark - Request helpers

- (BOOL)prepareClient {
    [self dismissKeyboard];
    NSString *baseURL = [self trimmedText:self.baseURLField];
    if (baseURL.length == 0) {
        self.outputView.text = @"请填写后端地址，例如 https://192.168.1.8:5443";
        return NO;
    }

    self.client.baseURLString = baseURL;
    self.client.pinningEnabled = self.pinningSwitch.isOn;
    SignDemoPinningEnabled = self.pinningSwitch.isOn;
    [[NSUserDefaults standardUserDefaults] setObject:baseURL
                                              forKey:kSignDemoBaseURLDefaultsKey];
    return YES;
}

- (void)showResponse:(APIResponse *)response {
    [self setLoading:NO action:nil];
    self.outputView.text = [response displayText];
}

- (void)appendOutput:(NSString *)line {
    NSString *existing = self.outputView.text ?: @"";
    NSString *next = existing.length > 0
        ? [existing stringByAppendingFormat:@"\n%@", line]
        : line;
    if (next.length > 8000) {
        next = [next substringFromIndex:next.length - 6000];
    }
    self.outputView.text = next;
    NSRange bottom = NSMakeRange(next.length, 0);
    [self.outputView scrollRangeToVisible:bottom];
}

- (void)setLoading:(BOOL)loading action:(NSString *)action {
    self.healthButton.enabled = !loading;
    self.loginButton.enabled = !loading;
    self.profileButton.enabled = !loading;
    self.orderButton.enabled = !loading;
    if (loading) {
        self.outputView.text = [NSString stringWithFormat:@"%@ 请求中...", action];
    }
}

- (NSString *)storedBaseURL {
    NSString *saved = [[NSUserDefaults standardUserDefaults]
                       stringForKey:kSignDemoBaseURLDefaultsKey];
    if (saved.length == 0) {
        return SignDemoDefaultBaseURL;
    }

    NSURL *url = [NSURL URLWithString:saved];
    NSString *host = url.host.lowercaseString;
    NSNumber *port = url.port;
    BOOL loopback = [host isEqualToString:@"127.0.0.1"] || [host isEqualToString:@"localhost"];
    BOOL oldHTTP = [[url.scheme lowercaseString] isEqualToString:@"http"]
        && (port == nil || port.integerValue == 5000);
    if (loopback || oldHTTP) {
        return SignDemoDefaultBaseURL;
    }
    return saved;
}

- (BOOL)storedPlainSecretEnabled {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:kSignDemoPlainSecretDefaultsKey] == nil) {
        return NO;
    }
    return [defaults boolForKey:kSignDemoPlainSecretDefaultsKey];
}

- (BOOL)storedAntiDebugEnabled {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:kSignDemoAntiDebugDefaultsKey] == nil) {
        return NO;
    }
    return [defaults boolForKey:kSignDemoAntiDebugDefaultsKey];
}

- (BOOL)storedPinningEnabled {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:kSignDemoPinningDefaultsKey] == nil) {
        return SignDemoPinningEnabled;
    }
    return [defaults boolForKey:kSignDemoPinningDefaultsKey];
}

- (NSString *)trimmedText:(UITextField *)field {
    return [field.text stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

#pragma mark - Keyboard

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.userIDField) {
        [self.passwordField becomeFirstResponder];
    } else {
        [textField resignFirstResponder];
    }
    return YES;
}

- (void)registerKeyboardNotifications {
    [[NSNotificationCenter defaultCenter]
     addObserver:self
        selector:@selector(keyboardWillChange:)
            name:UIKeyboardWillChangeFrameNotification
          object:nil];
}

- (void)keyboardWillChange:(NSNotification *)notification {
    NSValue *frameValue = notification.userInfo[UIKeyboardFrameEndUserInfoKey];
    CGRect keyboardFrame = [self.view convertRect:frameValue.CGRectValue fromView:nil];
    CGFloat overlap = CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(keyboardFrame);
    UIEdgeInsets inset = self.scrollView.contentInset;
    inset.bottom = MAX(overlap, 0.0);
    self.scrollView.contentInset = inset;
    self.scrollView.scrollIndicatorInsets = inset;
}

@end
