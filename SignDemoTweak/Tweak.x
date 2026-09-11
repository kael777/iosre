#import <UIKit/UIKit.h>

%hook ViewController

- (void)viewDidLoad {
	NSLog(@"[SignDemoTweak] viewDidLoad self=%@", self);
	%orig;
}

- (void)loginButtonTapped:(id)sender {
	NSLog(@"[SignDemoTweak] loginButtonTapped: sender=%@", sender);
	%orig;
}

%end
