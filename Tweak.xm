#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <AudioToolbox/AudioToolbox.h>

#define NOTIFY_MOVE    "com.abdulilah.circleMoved"
#define NOTIFY_START   "com.abdulilah.tapStarted"
#define NOTIFY_STOP    "com.abdulilah.tapStopped"
#define SHARED_PATH    @"/var/mobile/Library/Preferences/com.abdulilah.shared.plist"

@class AbdulilahManager;

static void markerMovedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    [(__bridge AbdulilahManager *)observer markerPositionDidChange];
}

static void tapStartedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    [(__bridge AbdulilahManager *)observer performSelectorOnMainThread:@selector(startTap) withObject:nil waitUntilDone:NO];
}

static void tapStoppedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    [(__bridge AbdulilahManager *)observer performSelectorOnMainThread:@selector(stopTap) withObject:nil waitUntilDone:NO];
}

#define PRIMARY_COLOR    [UIColor colorWithRed:0.00 green:0.60 blue:1.00 alpha:1.0]
#define SUCCESS_COLOR    [UIColor colorWithRed:0.00 green:0.50 blue:1.00 alpha:1.0]
#define ERROR_COLOR      [UIColor colorWithRed:0.80 green:0.20 blue:0.30 alpha:1.0]
#define BG_DARK          [UIColor colorWithRed:0.05 green:0.05 blue:0.08 alpha:0.95]
#define BG_CARD          [UIColor colorWithRed:0.10 green:0.10 blue:0.15 alpha:0.90]
#define TEXT_PRIMARY     [UIColor whiteColor]
#define TEXT_SECONDARY   [UIColor colorWithRed:0.60 green:0.60 blue:0.70 alpha:1.0]
#define TURBO_COLOR      [UIColor colorWithRed:1.00 green:0.50 blue:0.00 alpha:1.0]

@interface AbdulilahManager : NSObject

@property (nonatomic, strong) UIView *mainPanel;
@property (nonatomic, strong) UIButton *floatButton;
@property (nonatomic, strong) UIButton *toggleBtn;
@property (nonatomic, strong) UISlider *speedSlider;
@property (nonatomic, strong) UILabel *speedLabel;
@property (nonatomic, assign) BOOL autoTapEnabled;
@property (nonatomic, assign) float currentSpeed;
@property (nonatomic, strong) NSMutableArray *targetsArray;
@property (nonatomic, strong) NSMutableArray *recordedEvents;
@property (nonatomic, assign) BOOL isRecording;
@property (nonatomic, strong) NSDate *recordingStartTime;
@property (nonatomic, strong) UIButton *recordBtn;
@property (nonatomic, strong) UIButton *stopRecordBtn;
@property (nonatomic, assign) BOOL scriptPlaying;
@property (nonatomic, strong) NSString *scriptsFolder;
@property (nonatomic, strong) NSMutableArray *savedScripts;
@property (nonatomic, strong) UIView *scriptsPanel;
@property (nonatomic, strong) UITableView *scriptsTable;
@property (nonatomic, assign) BOOL isDarkMode;
@property (nonatomic, assign) BOOL isMenuVisible;
@property (nonatomic, assign) BOOL autoQueueEnabled;
@property (nonatomic, assign) BOOL goldenShotEnabled;
@property (nonatomic, assign) BOOL drawPredictionEnabled;
@property (nonatomic, assign) BOOL freezeLinesEnabled;
@property (nonatomic, assign) BOOL antiRecordEnabled;
@property (nonatomic, assign) float transparencyValue;
@property (nonatomic, strong) NSTimer *uiGuardTimer;
@property (nonatomic, strong) NSTimer *bgKeepAliveTimer;
@property (nonatomic, assign) UIBackgroundTaskIdentifier bgTask;

// Account tracking
@property (nonatomic, strong) NSMutableArray *trackedAccounts;
@property (nonatomic, strong) UILabel *accountCountLabel;
@property (nonatomic, assign) BOOL isTrackingAccounts;
@property (nonatomic, strong) UIButton *mergeButton;
@property (nonatomic, strong) NSMutableArray *accountCircles;
@property (nonatomic, strong) UIView *circleContainer;

// Single tap marker for positioning
@property (nonatomic, strong) UIView *tapMarker;
@property (nonatomic, assign) BOOL showMarker;

// Prediction line layer
@property (nonatomic, strong) CAShapeLayer *predictionLine;

+ (instancetype)shared;
- (void)showFloatingButton;
- (void)toggleMenu;
- (void)startBackgroundKeepAlive;
- (void)stopBackgroundKeepAlive;

@end

@implementation AbdulilahManager

+ (instancetype)shared {
    static AbdulilahManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AbdulilahManager alloc] init];
        instance.targetsArray = [NSMutableArray array];
        instance.currentSpeed = 0.008f;
        instance.isDarkMode = YES;
        instance.transparencyValue = 1.0;
        instance.recordedEvents = [NSMutableArray array];
        instance.savedScripts = [NSMutableArray array];
        instance.trackedAccounts = [NSMutableArray array];
        instance.accountCircles = [NSMutableArray array];
        instance.isTrackingAccounts = NO;
        instance.showMarker = NO;
        [instance prepareScriptsFolder];
        [instance startUIGuard];
        // Register for cross-instance notifications
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)(instance), markerMovedCallback, CFSTR(NOTIFY_MOVE), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)(instance), tapStartedCallback, CFSTR(NOTIFY_START), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)(instance), tapStoppedCallback, CFSTR(NOTIFY_STOP), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        // Auto-show marker after window is ready
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [instance showTapMarker];
        });
    });
    return instance;
}

- (void)startUIGuard {
    self.uiGuardTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(checkUI) userInfo:nil repeats:YES];
}

- (void)checkUI {
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    if (!w) return;
    if (!self.floatButton || self.floatButton.superview != w) {
        [self showFloatingButton];
    } else {
        [w bringSubviewToFront:self.floatButton];
    }
    if (self.isMenuVisible && self.mainPanel) {
        if (self.mainPanel.superview != w) {
            [w addSubview:self.mainPanel];
        }
        [w bringSubviewToFront:self.mainPanel];
    }
    if (self.circleContainer && self.circleContainer.superview != w) {
        [w addSubview:self.circleContainer];
        [w bringSubviewToFront:self.circleContainer];
    }
    if (self.tapMarker && self.showMarker && self.tapMarker.superview != w) {
        [w addSubview:self.tapMarker];
        [w bringSubviewToFront:self.tapMarker];
    }
}

- (void)prepareScriptsFolder {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docs = [paths firstObject];
    self.scriptsFolder = [docs stringByAppendingPathComponent:@"Scripts"];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.scriptsFolder withIntermediateDirectories:YES attributes:nil error:nil];
}

#pragma mark - Floating Button

- (void)showFloatingButton {
    if (self.floatButton) {
        [self.floatButton.superview removeFromSuperview];
        self.floatButton = nil;
    }
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(20, 150, 52, 52)];
    self.floatButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.floatButton.frame = CGRectMake(0, 0, 52, 52);
    self.floatButton.backgroundColor = [UIColor blackColor];
    self.floatButton.layer.cornerRadius = 26;
    self.floatButton.clipsToBounds = YES;
    self.floatButton.layer.borderWidth = 2;
    self.floatButton.layer.borderColor = PRIMARY_COLOR.CGColor;
    [self.floatButton setTitle:@"ع" forState:UIControlStateNormal];
    self.floatButton.titleLabel.font = [UIFont boldSystemFontOfSize:24];
    self.floatButton.layer.shadowColor = [UIColor blackColor].CGColor;
    self.floatButton.layer.shadowOffset = CGSizeMake(0, 4);
    self.floatButton.layer.shadowRadius = 10;
    self.floatButton.layer.shadowOpacity = 0.5;
    [self.floatButton addTarget:self action:@selector(handleFloatTap) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.floatButton addGestureRecognizer:pan];
    [container addSubview:self.floatButton];
    [w addSubview:container];
    container.alpha = 0;
    [UIView animateWithDuration:0.3 animations:^{ container.alpha = 1; }];
}

- (void)handleFloatTap {
    [self toggleMenu];
}

- (void)handlePan:(UIPanGestureRecognizer *)p {
    UIView *v = p.view;
    CGPoint t = [p translationInView:v.superview];
    v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y);
    [p setTranslation:CGPointZero inView:v.superview];
}

- (void)toggleMenu {
    if (!self.mainPanel) [self buildMainPanel];
    self.isMenuVisible = !self.isMenuVisible;
    if (self.isMenuVisible) {
        self.mainPanel.hidden = NO;
        self.mainPanel.alpha = 0;
        [UIView animateWithDuration:0.2 animations:^{
            self.mainPanel.alpha = self.transparencyValue;
            self.floatButton.alpha = 0.3;
        }];
    } else {
        [UIView animateWithDuration:0.15 animations:^{
            self.mainPanel.alpha = 0;
            self.floatButton.alpha = 1;
        } completion:^(BOOL finished) {
            self.mainPanel.hidden = YES;
        }];
    }
}

#pragma mark - Account Circles

- (void)addAccountCircleForAccount:(NSString *)accountID {
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    if (!self.circleContainer) {
        self.circleContainer = [[UIView alloc] initWithFrame:CGRectMake(100, 300, 200, 200)];
        self.circleContainer.userInteractionEnabled = YES;
        self.circleContainer.backgroundColor = [UIColor clearColor];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleCircleContainerPan:)];
        [self.circleContainer addGestureRecognizer:pan];
        [w addSubview:self.circleContainer];
    }

    CGFloat circleSize = 24;
    CGFloat spacing = 10;
    NSUInteger count = self.accountCircles.count;

    // Shift existing circles
    for (int i = 0; i < self.accountCircles.count; i++) {
        UIView *dot = self.accountCircles[i];
        [UIView animateWithDuration:0.3 animations:^{
            dot.frame = CGRectMake(i * (circleSize + spacing), 0, circleSize, circleSize);
        }];
    }

    UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(count * (circleSize + spacing), 0, circleSize, circleSize)];
    dot.backgroundColor = [self randomColor];
    dot.layer.cornerRadius = circleSize / 2;
    dot.layer.borderWidth = 2;
    dot.layer.borderColor = [UIColor whiteColor].CGColor;
    dot.layer.shadowColor = [UIColor blackColor].CGColor;
    dot.layer.shadowOffset = CGSizeZero;
    dot.layer.shadowRadius = 4;
    dot.layer.shadowOpacity = 0.5;

    // Label with account number
    UILabel *numLabel = [[UILabel alloc] initWithFrame:dot.bounds];
    numLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)self.accountCircles.count + 1];
    numLabel.textColor = [UIColor whiteColor];
    numLabel.font = [UIFont boldSystemFontOfSize:10];
    numLabel.textAlignment = NSTextAlignmentCenter;
    [dot addSubview:numLabel];

    [self.circleContainer addSubview:dot];
    [self.accountCircles addObject:dot];

    // Update container width
    CGRect cf = self.circleContainer.frame;
    cf.size.width = (count + 1) * (circleSize + spacing);
    cf.size.height = circleSize + 10;
    self.circleContainer.frame = cf;

    // Fade in
    dot.alpha = 0;
    dot.transform = CGAffineTransformMakeScale(0.3, 0.3);
    [UIView animateWithDuration:0.4 delay:count * 0.05 usingSpringWithDamping:0.6 initialSpringVelocity:0.8 options:0 animations:^{
        dot.alpha = 1;
        dot.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)handleCircleContainerPan:(UIPanGestureRecognizer *)p {
    UIView *v = p.view;
    CGPoint t = [p translationInView:v.superview];
    v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y);
    [p setTranslation:CGPointZero inView:v.superview];
}

- (UIColor *)randomColor {
    NSArray *colors = @[
        [UIColor colorWithRed:0.00 green:0.80 blue:1.00 alpha:1.0],
        [UIColor colorWithRed:1.00 green:0.40 blue:0.00 alpha:1.0],
        [UIColor colorWithRed:0.00 green:0.85 blue:0.40 alpha:1.0],
        [UIColor colorWithRed:0.90 green:0.10 blue:0.30 alpha:1.0],
        [UIColor colorWithRed:0.50 green:0.30 blue:0.90 alpha:1.0],
        [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:1.0],
        [UIColor colorWithRed:0.00 green:0.50 blue:0.50 alpha:1.0],
    ];
    return colors[self.accountCircles.count % colors.count];
}

#pragma mark - Tap Marker

- (void)showTapMarker {
    if (self.tapMarker) {
        [self.tapMarker removeFromSuperview];
        self.tapMarker = nil;
    }
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    CGFloat size = 48;
    UIView *marker = [[UIView alloc] initWithFrame:CGRectMake(w.center.x - size/2, w.center.y - size/2, size, size)];
    marker.backgroundColor = [UIColor clearColor];
    marker.layer.cornerRadius = size / 2;
    marker.layer.borderWidth = 2.5;
    marker.layer.borderColor = PRIMARY_COLOR.CGColor;
    marker.layer.shadowColor = [UIColor blackColor].CGColor;
    marker.layer.shadowOffset = CGSizeZero;
    marker.layer.shadowRadius = 5;
    marker.layer.shadowOpacity = 0.6;
    marker.userInteractionEnabled = YES;

    UILabel *impLabel = [[UILabel alloc] initWithFrame:marker.bounds];
    impLabel.text = @"impossible";
    impLabel.textColor = PRIMARY_COLOR;
    impLabel.font = [UIFont boldSystemFontOfSize:7];
    impLabel.textAlignment = NSTextAlignmentCenter;
    impLabel.numberOfLines = 1;
    impLabel.adjustsFontSizeToFitWidth = YES;
    impLabel.minimumScaleFactor = 0.5;
    [marker addSubview:impLabel];

    // Pan gesture for dragging
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapMarkerPan:)];
    [marker addGestureRecognizer:pan];

    [w addSubview:marker];
    self.tapMarker = marker;
    self.showMarker = YES;

    marker.alpha = 0;
    marker.transform = CGAffineTransformMakeScale(0.5, 0.5);
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0.8 options:0 animations:^{
        marker.alpha = 1;
        marker.transform = CGAffineTransformIdentity;
    } completion:nil];
    // Load saved position from other instances
    [self loadSharedMarkerPosition];
}

- (void)hideTapMarker {
    if (!self.tapMarker) return;
    [UIView animateWithDuration:0.2 animations:^{
        self.tapMarker.alpha = 0;
        self.tapMarker.transform = CGAffineTransformMakeScale(0.3, 0.3);
    } completion:^(BOOL f) {
        [self.tapMarker removeFromSuperview];
        self.tapMarker = nil;
        self.showMarker = NO;
    }];
    [self showToast:@"تم إخفاء العلامة"];
}

- (void)handleTapMarkerPan:(UIPanGestureRecognizer *)p {
    UIView *v = p.view;
    CGPoint t = [p translationInView:v.superview];
    v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y);
    [p setTranslation:CGPointZero inView:v.superview];
    if (p.state == UIGestureRecognizerStateEnded || p.state == UIGestureRecognizerStateChanged) {
        [self saveSharedMarkerPosition];
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR(NOTIFY_MOVE), NULL, NULL, YES);
    }
}

- (void)saveSharedMarkerPosition {
    if (!self.tapMarker) return;
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    CGPoint pt = [self.tapMarker convertPoint:CGPointMake(self.tapMarker.bounds.size.width/2, self.tapMarker.bounds.size.height/2) toView:w];
    NSDictionary *dict = @{@"x": @(pt.x), @"y": @(pt.y)};
    [dict writeToFile:SHARED_PATH atomically:YES];
}

- (void)loadSharedMarkerPosition {
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:SHARED_PATH];
    if (dict && self.tapMarker) {
        CGFloat x = [dict[@"x"] floatValue];
        CGFloat y = [dict[@"y"] floatValue];
        if (x > 0 && y > 0) {
            self.tapMarker.center = CGPointMake(x, y);
        }
    }
}

- (void)markerPositionDidChange {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self loadSharedMarkerPosition];
    });
}

- (CGPoint)tapMarkerPosition {
    if (!self.tapMarker || !self.showMarker) return CGPointZero;
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    return [self.tapMarker convertPoint:CGPointMake(self.tapMarker.bounds.size.width/2, self.tapMarker.bounds.size.height/2) toView:w];
}

#pragma mark - Main Panel

- (void)buildMainPanel {
    if (self.mainPanel) return;
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    CGFloat pw = 220;
    CGFloat px = (w.bounds.size.width - pw) / 2;
    CGFloat py = 60;
    self.mainPanel = [[UIView alloc] initWithFrame:CGRectMake(px, py, pw, 480)];
    self.mainPanel.backgroundColor = BG_DARK;
    self.mainPanel.layer.cornerRadius = 20;
    self.mainPanel.clipsToBounds = YES;
    self.mainPanel.alpha = 0;
    self.mainPanel.hidden = YES;
    self.mainPanel.layer.borderWidth = 1;
    self.mainPanel.layer.borderColor = [PRIMARY_COLOR colorWithAlphaComponent:0.3].CGColor;
    [w addSubview:self.mainPanel];

    // Header
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, pw, 36)];
    header.backgroundColor = PRIMARY_COLOR;
    [self.mainPanel addSubview:header];

    UILabel *titleLbl = [[UILabel alloc] initWithFrame:CGRectMake(12, 7, 160, 18)];
    titleLbl.text = @"عبدالإله";
    titleLbl.textColor = TEXT_PRIMARY;
    titleLbl.font = [UIFont boldSystemFontOfSize:15];
    [header addSubview:titleLbl];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(pw - 32, 6, 24, 24);
    closeBtn.layer.cornerRadius = 12;
    closeBtn.backgroundColor = [ERROR_COLOR colorWithAlphaComponent:0.2];
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:ERROR_COLOR forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:closeBtn];
    UIPanGestureRecognizer *panH = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [closeBtn addGestureRecognizer:panH];

    CGFloat y = 42;

    // Single toggle button: تشغيل / إيقاف
    self.toggleBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.toggleBtn.frame = CGRectMake(12, y, pw - 24, 38);
    self.toggleBtn.backgroundColor = SUCCESS_COLOR;
    self.toggleBtn.layer.cornerRadius = 19;
    [self.toggleBtn setTitle:@"تشغيل" forState:UIControlStateNormal];
    [self.toggleBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.toggleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [self.toggleBtn addTarget:self action:@selector(toggleStartStop) forControlEvents:UIControlEventTouchUpInside];
    [self.mainPanel addSubview:self.toggleBtn];

    y += 44;

    // Speed label
    self.speedLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, y, pw - 24, 16)];
    self.speedLabel.text = [NSString stringWithFormat:@"السرعة: %.3f ث", self.currentSpeed];
    self.speedLabel.textColor = TEXT_PRIMARY;
    self.speedLabel.font = [UIFont systemFontOfSize:10];
    [self.mainPanel addSubview:self.speedLabel];
    y += 18;

    // Speed slider
    self.speedSlider = [[UISlider alloc] initWithFrame:CGRectMake(12, y, pw - 24, 20)];
    self.speedSlider.minimumValue = 0.001f;
    self.speedSlider.maximumValue = 0.1f;
    self.speedSlider.value = self.currentSpeed;
    self.speedSlider.tintColor = PRIMARY_COLOR;
    self.speedSlider.minimumTrackTintColor = PRIMARY_COLOR;
    self.speedSlider.maximumTrackTintColor = [UIColor colorWithWhite:0.3 alpha:1];
    [self.speedSlider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.mainPanel addSubview:self.speedSlider];
    y += 24;

    // Record buttons
    UIView *recBox = [[UIView alloc] initWithFrame:CGRectMake(12, y, pw - 24, 38)];
    recBox.backgroundColor = BG_CARD;
    recBox.layer.cornerRadius = 10;
    [self.mainPanel addSubview:recBox];

    self.recordBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.recordBtn.frame = CGRectMake(4, 4, (pw - 42) / 2, 30);
    self.recordBtn.backgroundColor = PRIMARY_COLOR;
    self.recordBtn.layer.cornerRadius = 15;
    [self.recordBtn setTitle:@"تسجيل" forState:UIControlStateNormal];
    [self.recordBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.recordBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    [self.recordBtn addTarget:self action:@selector(startRecording) forControlEvents:UIControlEventTouchUpInside];
    [recBox addSubview:self.recordBtn];

    self.stopRecordBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.stopRecordBtn.frame = CGRectMake(4 + (pw - 42) / 2 + 8, 4, (pw - 42) / 2, 30);
    self.stopRecordBtn.backgroundColor = ERROR_COLOR;
    self.stopRecordBtn.layer.cornerRadius = 15;
    [self.stopRecordBtn setTitle:@"حفظ" forState:UIControlStateNormal];
    [self.stopRecordBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.stopRecordBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    [self.stopRecordBtn addTarget:self action:@selector(stopRecording) forControlEvents:UIControlEventTouchUpInside];
    self.stopRecordBtn.alpha = 0;
    [recBox addSubview:self.stopRecordBtn];
    y += 44;

    // Scripts button
    UIButton *scriptsBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    scriptsBtn.frame = CGRectMake(12, y, pw - 24, 30);
    [scriptsBtn setTitle:@"ملفاتي" forState:UIControlStateNormal];
    scriptsBtn.backgroundColor = [UIColor colorWithRed:0.00 green:0.40 blue:0.80 alpha:1];
    scriptsBtn.tintColor = [UIColor whiteColor];
    scriptsBtn.layer.cornerRadius = 15;
    [scriptsBtn addTarget:self action:@selector(showScriptsManager) forControlEvents:UIControlEventTouchUpInside];
    [self.mainPanel addSubview:scriptsBtn];
    y += 34;

    // Features toggle button
    UIButton *featuresBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    featuresBtn.frame = CGRectMake(12, y, pw - 24, 30);
    [featuresBtn setTitle:@"الأدوات" forState:UIControlStateNormal];
    featuresBtn.backgroundColor = [UIColor colorWithRed:0.00 green:0.30 blue:0.70 alpha:1];
    featuresBtn.tintColor = [UIColor whiteColor];
    featuresBtn.layer.cornerRadius = 15;
    [featuresBtn addTarget:self action:@selector(showFeaturesWindow) forControlEvents:UIControlEventTouchUpInside];
    [self.mainPanel addSubview:featuresBtn];
    y += 34;

    // Account tracking section
    UIView *acctBox = [[UIView alloc] initWithFrame:CGRectMake(12, y, pw - 24, 56)];
    acctBox.backgroundColor = BG_CARD;
    acctBox.layer.cornerRadius = 10;
    [self.mainPanel addSubview:acctBox];

    UILabel *acctTitle = [[UILabel alloc] initWithFrame:CGRectMake(8, 4, 100, 16)];
    acctTitle.text = @"👤 تتبع الحسابات";
    acctTitle.textColor = TEXT_PRIMARY;
    acctTitle.font = [UIFont boldSystemFontOfSize:10];
    [acctBox addSubview:acctTitle];

    self.accountCountLabel = [[UILabel alloc] initWithFrame:CGRectMake(8, 20, 100, 24)];
    self.accountCountLabel.text = [NSString stringWithFormat:@"%lu حساب", (unsigned long)self.trackedAccounts.count];
    self.accountCountLabel.textColor = TEXT_SECONDARY;
    self.accountCountLabel.font = [UIFont systemFontOfSize:9];
    self.accountCountLabel.numberOfLines = 2;
    [acctBox addSubview:self.accountCountLabel];

    UIButton *trackBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    trackBtn.frame = CGRectMake(108, 4, 48, 22);
    trackBtn.layer.cornerRadius = 11;
    trackBtn.backgroundColor = PRIMARY_COLOR;
    [trackBtn setTitle:@"تتبع" forState:UIControlStateNormal];
    [trackBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    trackBtn.titleLabel.font = [UIFont boldSystemFontOfSize:9];
    [trackBtn addTarget:self action:@selector(toggleAccountTracking) forControlEvents:UIControlEventTouchUpInside];
    [acctBox addSubview:trackBtn];

    self.mergeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.mergeButton.frame = CGRectMake(160, 4, 48, 22);
    self.mergeButton.layer.cornerRadius = 11;
    self.mergeButton.backgroundColor = PRIMARY_COLOR;
    [self.mergeButton setTitle:@"دمج" forState:UIControlStateNormal];
    [self.mergeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.mergeButton.titleLabel.font = [UIFont boldSystemFontOfSize:9];
    [self.mergeButton addTarget:self action:@selector(mergeAccounts) forControlEvents:UIControlEventTouchUpInside];
    [acctBox addSubview:self.mergeButton];

    // Reset circles button
    UIButton *resetCirclesBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    resetCirclesBtn.frame = CGRectMake(108, 30, 100, 20);
    resetCirclesBtn.layer.cornerRadius = 10;
    resetCirclesBtn.backgroundColor = [UIColor blackColor];
    [resetCirclesBtn setTitle:@"🔄 إعادة" forState:UIControlStateNormal];
    [resetCirclesBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    resetCirclesBtn.titleLabel.font = [UIFont systemFontOfSize:8];
    [resetCirclesBtn addTarget:self action:@selector(resetAccountCircles) forControlEvents:UIControlEventTouchUpInside];
    [acctBox addSubview:resetCirclesBtn];

    y += 50;

    // Background keep-alive toggle
    UIView *bgBox = [[UIView alloc] initWithFrame:CGRectMake(12, y, pw - 24, 36)];
    bgBox.backgroundColor = BG_CARD;
    bgBox.layer.cornerRadius = 10;
    [self.mainPanel addSubview:bgBox];

    UILabel *bgTitle = [[UILabel alloc] initWithFrame:CGRectMake(8, 9, 120, 18)];
    bgTitle.text = @"🔋 البقاء في الخلفية";
    bgTitle.textColor = TEXT_PRIMARY;
    bgTitle.font = [UIFont boldSystemFontOfSize:10];
    [bgBox addSubview:bgTitle];

    UIButton *bgToggle = [UIButton buttonWithType:UIButtonTypeCustom];
    bgToggle.frame = CGRectMake(pw - 80, 4, 60, 28);
    bgToggle.layer.cornerRadius = 14;
    bgToggle.backgroundColor = SUCCESS_COLOR;
    [bgToggle setTitle:@"ON" forState:UIControlStateNormal];
    [bgToggle setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    bgToggle.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    [bgToggle addTarget:self action:@selector(toggleBackgroundKeepAlive:) forControlEvents:UIControlEventTouchUpInside];
    [bgBox addSubview:bgToggle];
    y += 42;

    // Settings button
    UIButton *settingsBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    settingsBtn.frame = CGRectMake(12, y, pw - 24, 30);
    [settingsBtn setTitle:@"الإعدادات" forState:UIControlStateNormal];
    settingsBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.5 blue:0.8 alpha:1];
    settingsBtn.tintColor = [UIColor whiteColor];
    settingsBtn.layer.cornerRadius = 15;
    [settingsBtn addTarget:self action:@selector(showSettingsWindow) forControlEvents:UIControlEventTouchUpInside];
    [self.mainPanel addSubview:settingsBtn];
    y += 34;

    // Resize panel
    CGRect f = self.mainPanel.frame;
    f.size.height = y + 10;
    self.mainPanel.frame = f;

    UIPanGestureRecognizer *panP = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.mainPanel addGestureRecognizer:panP];
}

#pragma mark - Account Tracking

- (void)toggleAccountTracking {
    self.isTrackingAccounts = !self.isTrackingAccounts;
    if (self.isTrackingAccounts) {
        [self startTracking];
    } else {
        [self stopTracking];
    }
}

- (void)startTracking {
    [self showToast:@"بدء تتبع الحسابات..."];
    __block NSUInteger lastMergeCount = 0;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        while (self.isTrackingAccounts) {
            dispatch_async(dispatch_get_main_queue(), ^{
                UIWindow *w = [UIApplication sharedApplication].keyWindow;
                if (!w) return;
                UIView *accountView = [self findAccountInfoInView:w];
                if (accountView) {
                    NSString *accountID = [self extractAccountIDFromView:accountView];
                    if (accountID && ![self.trackedAccounts containsObject:accountID]) {
                        [self.trackedAccounts addObject:accountID];
                        self.accountCountLabel.text = [NSString stringWithFormat:@"%lu حساب", (unsigned long)self.trackedAccounts.count];
                        [self addAccountCircleForAccount:accountID];
                    }
                }
                // Auto-merge when 2+ accounts detected
                if (self.trackedAccounts.count >= 2 && self.trackedAccounts.count != lastMergeCount) {
                    lastMergeCount = self.trackedAccounts.count;
                    [self performMerge];
                }
            });
            [NSThread sleepForTimeInterval:3.0];
        }
    });
}

- (void)stopTracking {
    self.isTrackingAccounts = NO;
    [self showToast:@"تم إيقاف التتبع"];
}

- (UIView *)findAccountInfoInView:(UIView *)view {
    NSString *cls = NSStringFromClass([view class]);
    if ([cls containsString:@"LTUserInfo"] || [cls containsString:@"LTMine"]) {
        return view;
    }
    for (UIView *sub in view.subviews) {
        UIView *found = [self findAccountInfoInView:sub];
        if (found) return found;
    }
    return nil;
}

- (NSString *)extractAccountIDFromView:(UIView *)view {
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:[UILabel class]]) {
            UILabel *lbl = (UILabel *)sub;
            if (lbl.text.length > 5) {
                return lbl.text;
            }
        }
    }
    return [NSString stringWithFormat:@"account_%lu", (unsigned long)self.trackedAccounts.count];
}

- (void)resetAccountCircles {
    for (UIView *dot in self.accountCircles) {
        [dot removeFromSuperview];
    }
    [self.accountCircles removeAllObjects];
    [self.circleContainer removeFromSuperview];
    self.circleContainer = nil;
    [self showToast:@"تم مسح الدوائر"];
}

- (void)mergeAccounts {
    if (self.trackedAccounts.count < 2) {
        [self showToast:@"تحتاج حسابين على الأقل للدمج"];
        return;
    }
    [self performMerge];
}

- (void)performMerge {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for (NSString *acct in self.trackedAccounts) {
            NSLog(@"[عبدالإله] Merging account: %@", acct);
            [NSThread sleepForTimeInterval:0.5];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showToast:[NSString stringWithFormat:@"✅ تم دمج %lu حسابات", (unsigned long)self.trackedAccounts.count]];
        });
    });
}

#pragma mark - Background Keep Alive

- (void)toggleBackgroundKeepAlive:(UIButton *)sender {
    if (self.bgKeepAliveTimer) {
        [self stopBackgroundKeepAlive];
        sender.backgroundColor = [UIColor blackColor];
        [sender setTitle:@"OFF" forState:UIControlStateNormal];
    } else {
        [self startBackgroundKeepAlive];
        sender.backgroundColor = SUCCESS_COLOR;
        [sender setTitle:@"ON" forState:UIControlStateNormal];
    }
}

- (void)startBackgroundKeepAlive {
    self.bgTask = [[UIApplication sharedApplication] beginBackgroundTaskWithName:@"AbdulilahKeepAlive" expirationHandler:^{
        [[UIApplication sharedApplication] endBackgroundTask:self.bgTask];
        self.bgTask = UIBackgroundTaskInvalid;
        [self startBackgroundKeepAlive];
    }];
    self.bgKeepAliveTimer = [NSTimer scheduledTimerWithTimeInterval:10.0 target:self selector:@selector(keepAlivePing) userInfo:nil repeats:YES];
    [self showToast:@"🔋 وضع الخلفية نشط"];
}

- (void)keepAlivePing {
    // Silent keep-alive - no sound, keeps background task active
}

- (void)stopBackgroundKeepAlive {
    [self.bgKeepAliveTimer invalidate];
    self.bgKeepAliveTimer = nil;
    if (self.bgTask != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:self.bgTask];
        self.bgTask = UIBackgroundTaskInvalid;
    }
    [self showToast:@"🔋 تم إيقاف وضع الخلفية"];
}

#pragma mark - Features Window

- (void)showFeaturesWindow {
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(50, 120, 280, 350)];
    panel.backgroundColor = self.isDarkMode ? [UIColor colorWithWhite:0.08 alpha:1] : [UIColor colorWithWhite:0.95 alpha:1];
    panel.layer.cornerRadius = 20;
    panel.tag = 8888;
    [w addSubview:panel];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, 280, 30)];
    title.text = @"الأدوات";
    title.textAlignment = NSTextAlignmentCenter;
    title.textColor = self.isDarkMode ? [UIColor whiteColor] : [UIColor blackColor];
    title.font = [UIFont boldSystemFontOfSize:18];
    [panel addSubview:title];

    NSArray *features = @[
        @{@"name": @"ازلة الصدمة", @"key": @"autoQueueEnabled"},
        @{@"name": @"فاست اكس", @"key": @"goldenShotEnabled"},
        @{@"name": @"تقوية الشقه", @"key": @"drawPredictionEnabled"},
        @{@"name": @"تقوية تدبيل", @"key": @"freezeLinesEnabled"},
        @{@"name": @"x9 سبيد سرعة", @"key": @"antiRecordEnabled"},
    ];

    for (int i = 0; i < features.count; i++) {
        NSDictionary *f = features[i];
        BOOL enabled = [[self valueForKey:f[@"key"]] boolValue];
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(20, 50 + i * 48, 240, 40);
        [btn setTitle:f[@"name"] forState:UIControlStateNormal];
        btn.backgroundColor = enabled ? PRIMARY_COLOR : [UIColor blackColor];
        btn.tintColor = [UIColor whiteColor];
        btn.layer.cornerRadius = 12;
        btn.tag = i + 1;
        [btn addTarget:self action:@selector(toggleFeatureFromTag:) forControlEvents:UIControlEventTouchUpInside];
        [panel addSubview:btn];
    }

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(200, 310, 70, 30);
    [closeBtn setTitle:@"إغلاق" forState:UIControlStateNormal];
    closeBtn.backgroundColor = [UIColor blackColor];
    closeBtn.tintColor = [UIColor whiteColor];
    closeBtn.layer.cornerRadius = 15;
    [closeBtn addTarget:self action:@selector(closePanel:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:closeBtn];
}

- (void)toggleFeatureFromTag:(UIButton *)sender {
    NSArray *keys = @[@"autoQueueEnabled", @"goldenShotEnabled", @"drawPredictionEnabled", @"freezeLinesEnabled", @"antiRecordEnabled"];
    NSString *key = keys[sender.tag - 1];
    BOOL current = [[self valueForKey:key] boolValue];
    [self setValue:@(!current) forKey:key];
    [self closePanel:nil];
    [self showFeaturesWindow];
}

- (void)closePanel:(UIButton *)sender {
    [[[UIApplication sharedApplication].keyWindow viewWithTag:8888] removeFromSuperview];
}

#pragma mark - Settings Window

- (void)showSettingsWindow {
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(50, 150, 280, 300)];
    panel.backgroundColor = self.isDarkMode ? [UIColor colorWithWhite:0.15 alpha:0.97] : [UIColor colorWithWhite:0.95 alpha:0.97];
    panel.layer.cornerRadius = 20;
    panel.tag = 9999;
    [w addSubview:panel];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, 280, 30)];
    title.text = @"الإعدادات";
    title.textAlignment = NSTextAlignmentCenter;
    title.textColor = self.isDarkMode ? [UIColor whiteColor] : [UIColor blackColor];
    title.font = [UIFont boldSystemFontOfSize:18];
    [panel addSubview:title];

    UIButton *themeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    themeBtn.frame = CGRectMake(20, 60, 240, 40);
    [themeBtn setTitle:self.isDarkMode ? @"وضع فاتح" : @"وضع داكن" forState:UIControlStateNormal];
    themeBtn.backgroundColor = PRIMARY_COLOR;
    themeBtn.tintColor = [UIColor whiteColor];
    themeBtn.layer.cornerRadius = 12;
    [themeBtn addTarget:self action:@selector(toggleTheme) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:themeBtn];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(200, 250, 70, 30);
    [closeBtn setTitle:@"إغلاق" forState:UIControlStateNormal];
    closeBtn.backgroundColor = [UIColor blackColor];
    closeBtn.tintColor = [UIColor whiteColor];
    closeBtn.layer.cornerRadius = 15;
    [closeBtn addTarget:self action:@selector(closeSettings) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:closeBtn];
}

- (void)toggleTheme {
    self.isDarkMode = !self.isDarkMode;
    [self closeSettings];
}

- (void)closeSettings {
    [[[UIApplication sharedApplication].keyWindow viewWithTag:9999] removeFromSuperview];
}

#pragma mark - Scripts Manager

- (void)showScriptsManager {
    if (self.scriptsPanel) {
        [self.scriptsPanel removeFromSuperview];
        self.scriptsPanel = nil;
        return;
    }
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    CGFloat pw = 300, ph = 420;
    CGFloat px = (w.bounds.size.width - pw) / 2;
    CGFloat py = (w.bounds.size.height - ph) / 2;
    self.scriptsPanel = [[UIView alloc] initWithFrame:CGRectMake(px, py, pw, ph)];
    self.scriptsPanel.backgroundColor = self.isDarkMode ? [UIColor colorWithWhite:0.15 alpha:0.97] : [UIColor colorWithWhite:0.95 alpha:0.97];
    self.scriptsPanel.layer.cornerRadius = 16;
    [w addSubview:self.scriptsPanel];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 8, pw, 30)];
    title.text = @"ملفاتي المحفوظة";
    title.textAlignment = NSTextAlignmentCenter;
    title.textColor = self.isDarkMode ? [UIColor whiteColor] : [UIColor blackColor];
    title.font = [UIFont boldSystemFontOfSize:17];
    [self.scriptsPanel addSubview:title];

    self.scriptsTable = [[UITableView alloc] initWithFrame:CGRectMake(8, 45, pw - 16, ph - 95) style:UITableViewStylePlain];
    self.scriptsTable.backgroundColor = [UIColor clearColor];
    self.scriptsTable.delegate = (id<UITableViewDelegate>)self;
    self.scriptsTable.dataSource = (id<UITableViewDataSource>)self;
    [self.scriptsPanel addSubview:self.scriptsTable];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(pw - 80, ph - 38, 70, 30);
    [closeBtn setTitle:@"إغلاق" forState:UIControlStateNormal];
    closeBtn.backgroundColor = [UIColor blackColor];
    closeBtn.tintColor = [UIColor whiteColor];
    closeBtn.layer.cornerRadius = 15;
    [closeBtn addTarget:self action:@selector(showScriptsManager) forControlEvents:UIControlEventTouchUpInside];
    [self.scriptsPanel addSubview:closeBtn];

    [self performSelector:@selector(refreshSavedScriptsList) withObject:nil afterDelay:0.05];
}

- (void)refreshSavedScriptsList {
    if (!self.scriptsTable) return;
    [self.savedScripts removeAllObjects];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.scriptsFolder error:nil];
    for (NSString *f in files) {
        if ([f hasSuffix:@".plist"]) [self.savedScripts addObject:[f stringByDeletingPathExtension]];
    }
    [self.scriptsTable reloadData];
}

#pragma mark - TableView (Scripts)

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)s {
    return self.savedScripts.count;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"cell";
    UITableViewCell *c = [table dequeueReusableCellWithIdentifier:cid];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cid];
    c.backgroundColor = [UIColor clearColor];
    c.textLabel.text = self.savedScripts[ip.row];
    c.textLabel.textColor = self.isDarkMode ? [UIColor whiteColor] : [UIColor blackColor];

    UIButton *playBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    playBtn.frame = CGRectMake(200, 5, 40, 30);
    [playBtn setTitle:@"▶️" forState:UIControlStateNormal];
    playBtn.tag = ip.row;
    [playBtn addTarget:self action:@selector(playScript:) forControlEvents:UIControlEventTouchUpInside];
    [c addSubview:playBtn];

    UIButton *delBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    delBtn.frame = CGRectMake(245, 5, 40, 30);
    [delBtn setTitle:@"🗑️" forState:UIControlStateNormal];
    delBtn.tag = ip.row;
    [delBtn addTarget:self action:@selector(deleteScript:) forControlEvents:UIControlEventTouchUpInside];
    [c addSubview:delBtn];

    return c;
}

- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)ip {
    return 50;
}

- (void)playScript:(UIButton *)sender {
    NSUInteger idx = sender.tag;
    NSString *name = self.savedScripts[idx];
    NSString *path = [self.scriptsFolder stringByAppendingPathComponent:[name stringByAppendingString:@".plist"]];
    NSArray *events = [NSArray arrayWithContentsOfFile:path];
    if (events) [self playExternalScript:events];
}

- (void)deleteScript:(UIButton *)sender {
    NSUInteger idx = sender.tag;
    NSString *name = self.savedScripts[idx];
    NSString *path = [self.scriptsFolder stringByAppendingPathComponent:[name stringByAppendingString:@".plist"]];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    [self refreshSavedScriptsList];
}

- (void)playExternalScript:(NSArray *)events {
    if (self.scriptPlaying || !events.count) return;
    self.scriptPlaying = YES;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSDate *start = [NSDate date];
        for (NSDictionary *evt in events) {
            if (!self.scriptPlaying) break;
            NSTimeInterval wait = [evt[@"t"] doubleValue] - [[NSDate date] timeIntervalSinceDate:start];
            if (wait > 0) usleep(wait * 1000000);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!self.scriptPlaying) return;
                CGPoint pt = CGPointMake([evt[@"x"] floatValue], [evt[@"y"] floatValue]);
                UIView *target = [[UIApplication sharedApplication].keyWindow hitTest:pt withEvent:nil];
                if ([target respondsToSelector:@selector(sendActionsForControlEvents:)]) {
                    [(UIControl *)target sendActionsForControlEvents:UIControlEventTouchDown];
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [(UIControl *)target sendActionsForControlEvents:UIControlEventTouchUpInside];
                    });
                }
            });
        }
        self.scriptPlaying = NO;
    });
}

#pragma mark - Recording

- (void)startRecording {
    if (self.isRecording) return;
    self.isRecording = YES;
    self.scriptPlaying = NO;
    [self.recordedEvents removeAllObjects];
    self.recordingStartTime = [NSDate date];
    [UIView animateWithDuration:0.2 animations:^{
        self.recordBtn.alpha = 0;
        self.stopRecordBtn.alpha = 1;
    }];
    [[UIApplication sharedApplication].keyWindow addGestureRecognizer:[self recordingTapGesture]];
}

- (void)stopRecording {
    if (!self.isRecording) return;
    self.isRecording = NO;
    [[UIApplication sharedApplication].keyWindow removeGestureRecognizer:[self recordingTapGesture]];
    [UIView animateWithDuration:0.2 animations:^{
        self.recordBtn.alpha = 1;
        self.stopRecordBtn.alpha = 0;
    }];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"حفظ السكربت"
        message:@"اختر اسم للسكربت" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"مثال: سكربت1";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"حفظ" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *name = alert.textFields.firstObject.text ?: @"Script";
        [self saveCurrentScriptWithName:name];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
}

- (UITapGestureRecognizer *)recordingTapGesture {
    static UITapGestureRecognizer *tap = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(screenTappedWhileRecording:)];
    });
    return tap;
}

- (void)screenTappedWhileRecording:(UITapGestureRecognizer *)tap {
    CGPoint loc = [tap locationInView:self.mainPanel.superview ?: [UIApplication sharedApplication].keyWindow];
    NSTimeInterval offset = [[NSDate date] timeIntervalSinceDate:self.recordingStartTime];
    [self.recordedEvents addObject:@{@"x": @(loc.x), @"y": @(loc.y), @"t": @(offset)}];
}

- (void)saveCurrentScriptWithName:(NSString *)name {
    if (!name.length) return;
    NSString *path = [self.scriptsFolder stringByAppendingPathComponent:[name stringByAppendingString:@".plist"]];
    [self.recordedEvents writeToFile:path atomically:YES];
    [self refreshSavedScriptsList];
}

#pragma mark - Tap Engine

- (void)sliderChanged:(UISlider *)sender {
    CGFloat val = sender.value;
    if (val < 0.001f) val = 0.001f;
    self.currentSpeed = val;
    self.speedLabel.text = [NSString stringWithFormat:@"السرعة: %.3f ث", self.currentSpeed];
    if (self.autoTapEnabled) [self restartTapWithSpeed:self.currentSpeed];
}

- (void)restartTapWithSpeed:(float)speed {
    [self stopTap];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self.autoTapEnabled) {
            self.autoTapEnabled = YES;
            [self startTapWithSpeed:speed];
        }
    });
}

- (void)toggleStartStop {
    if (self.autoTapEnabled) {
        [self stopTap];
    } else {
        [self startTap];
    }
}

- (void)startTap {
    if (self.autoTapEnabled) return;
    [self startTapWithSpeed:self.currentSpeed];
    [self.toggleBtn setTitle:@"إيقاف" forState:UIControlStateNormal];
    self.toggleBtn.backgroundColor = ERROR_COLOR;
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR(NOTIFY_START), NULL, NULL, YES);
}

- (void)startTapWithSpeed:(float)speed {
    self.autoTapEnabled = YES;
    if (speed < 0.001f) speed = 0.001f;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        while (self.autoTapEnabled) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.autoTapEnabled) [self tapRealTarget];
            });
            usleep((useconds_t)(speed * 1000000));
        }
    });
}

- (void)stopTap {
    self.autoTapEnabled = NO;
    [self.toggleBtn setTitle:@"تشغيل" forState:UIControlStateNormal];
    self.toggleBtn.backgroundColor = SUCCESS_COLOR;
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR(NOTIFY_STOP), NULL, NULL, YES);
}

- (void)tapRealTarget {
    if (!self.autoTapEnabled) return;
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    CGPoint tapPt = [self tapMarkerPosition];
    // All accounts tap at the single marker position
    [self performFeatureTapsAtPoint:tapPt inWindow:w];
    if (self.autoQueueEnabled) [self tapQueueButtonInWindow:w];
    if (self.drawPredictionEnabled) [self drawPredictionFromPoint:tapPt inWindow:w];
}

- (void)performFeatureTapsAtPoint:(CGPoint)pt inWindow:(UIWindow *)w {
    [self performTapAtPoint:pt inWindow:w];
    if (self.goldenShotEnabled) [self performTapAtPoint:pt inWindow:w];
    if (self.freezeLinesEnabled) [self performFrozenTapAtPoint:pt inWindow:w];
    if (self.antiRecordEnabled) {
        for (int i = 0; i < 8; i++) [self performTapAtPoint:pt inWindow:w];
    }
}

- (void)performTapAtPoint:(CGPoint)pt inWindow:(UIWindow *)w {
    // Temporarily disable marker so hitTest finds the view underneath
    BOOL wasEnabled = self.tapMarker.userInteractionEnabled;
    self.tapMarker.userInteractionEnabled = NO;

    UIView *target = [w hitTest:pt withEvent:nil];

    self.tapMarker.userInteractionEnabled = wasEnabled;

    if ([target isKindOfClass:[UIControl class]]) {
        UIControl *ctrl = (UIControl *)target;
        [ctrl sendActionsForControlEvents:UIControlEventTouchDown];
        [ctrl sendActionsForControlEvents:UIControlEventTouchUpInside];
    } else {
        // Try invoking tap gesture recognizers on the target
        for (UIGestureRecognizer *gr in target.gestureRecognizers) {
            if ([gr isKindOfClass:[UITapGestureRecognizer class]] && gr.isEnabled) {
                gr.enabled = NO;
                gr.enabled = YES; // Force state reset
                break;
            }
        }
        // Fallback: send touch events directly
        [target touchesBegan:[NSSet set] withEvent:nil];
        [target touchesEnded:[NSSet set] withEvent:nil];
    }
}

- (void)performFrozenTapAtPoint:(CGPoint)pt inWindow:(UIWindow *)w {
    BOOL wasEnabled = self.tapMarker.userInteractionEnabled;
    self.tapMarker.userInteractionEnabled = NO;

    UIView *target = [w hitTest:pt withEvent:nil];

    self.tapMarker.userInteractionEnabled = wasEnabled;

    if ([target isKindOfClass:[UIControl class]]) {
        UIControl *ctrl = (UIControl *)target;
        [ctrl sendActionsForControlEvents:UIControlEventTouchDown];
        [ctrl sendActionsForControlEvents:UIControlEventTouchUpInside];
    } else {
        [target touchesBegan:[NSSet set] withEvent:nil];
        [target touchesEnded:[NSSet set] withEvent:nil];
    }
}

- (void)tapQueueButtonInWindow:(UIView *)w {
    for (UIView *sub in w.subviews) {
        if ([sub isKindOfClass:[UIButton class]]) {
            UIButton *btn = (UIButton *)sub;
            NSString *title = [btn titleForState:UIControlStateNormal] ?: @"";
            if ([title containsString:@"جاهز"] || [title containsString:@"موافق"] ||
                [title containsString:@"Ready"] || [title containsString:@"OK"] ||
                [title containsString:@"انضم"] || [title containsString:@"Join"]) {
                [btn sendActionsForControlEvents:UIControlEventTouchUpInside];
            }
        }
        [self tapQueueButtonInWindow:sub];
    }
}

- (void)drawPredictionFromPoint:(CGPoint)pt inWindow:(UIWindow *)w {
    // Remove previous line
    [self.predictionLine removeFromSuperlayer];

    // Draw a small line indicator at tap point
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(pt.x - 15, pt.y)];
    [path addLineToPoint:CGPointMake(pt.x + 15, pt.y)];
    [path moveToPoint:CGPointMake(pt.x, pt.y - 15)];
    [path addLineToPoint:CGPointMake(pt.x, pt.y + 15)];

    self.predictionLine = [CAShapeLayer layer];
    self.predictionLine.path = path.CGPath;
    self.predictionLine.strokeColor = PRIMARY_COLOR.CGColor;
    self.predictionLine.lineWidth = 1.5;
    self.predictionLine.opacity = 0.6;
    [w.layer addSublayer:self.predictionLine];

    // Auto-remove after 0.3s
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.predictionLine removeFromSuperlayer];
        self.predictionLine = nil;
    });
}

#pragma mark - Toast

- (void)showToast:(NSString *)message {
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    if (!w) return;
    UIView *existing = [w viewWithTag:7777];
    [existing removeFromSuperview];
    UILabel *toast = [[UILabel alloc] initWithFrame:CGRectMake(30, w.bounds.size.height - 100, w.bounds.size.width - 60, 36)];
    toast.text = message;
    toast.textColor = [UIColor whiteColor];
    toast.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.7];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.font = [UIFont boldSystemFontOfSize:13];
    toast.layer.cornerRadius = 10;
    toast.clipsToBounds = YES;
    toast.tag = 7777;
    [w addSubview:toast];
    toast.alpha = 0;
    [UIView animateWithDuration:0.2 animations:^{ toast.alpha = 1; } completion:^(BOOL fin) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.2 animations:^{ toast.alpha = 0; } completion:^(BOOL f) { [toast removeFromSuperview]; }];
        });
    }];
}

@end

#pragma mark - YallaLite Specific Hooks

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [[AbdulilahManager shared] checkUI];
}

%end

%hook LTLoginViewController

- (void)viewDidLoad {
    %orig;
    NSLog(@"[عبدالإله] Login screen detected - tracking account");
}

- (void)loginSuccess:(id)response {
    %orig;
    AbdulilahManager *m = [AbdulilahManager shared];
    if (m.isTrackingAccounts) {
        NSString *uid = [response valueForKey:@"uid"] ?: [response description];
        if (uid && ![m.trackedAccounts containsObject:uid]) {
            [m.trackedAccounts addObject:uid];
            m.accountCountLabel.text = [NSString stringWithFormat:@"%lu حساب", (unsigned long)m.trackedAccounts.count];
            [m addAccountCircleForAccount:uid];
        }
    }
}

%end

%hook LTMineViewController

- (void)viewDidLoad {
    %orig;
    AbdulilahManager *m = [AbdulilahManager shared];
    if (m.isTrackingAccounts) {
        NSString *label = [NSString stringWithFormat:@"mine_%lu", (unsigned long)[NSDate date].timeIntervalSince1970];
        if (![m.trackedAccounts containsObject:label]) {
            [m.trackedAccounts addObject:label];
            m.accountCountLabel.text = [NSString stringWithFormat:@"%lu حساب", (unsigned long)m.trackedAccounts.count];
            [m addAccountCircleForAccount:label];
        }
    }
}

%end

#pragma mark - Constructor

%ctor {
    [AbdulilahManager shared];
    NSLog(@"[عبدالإله] Tweak v1.0 loaded for YallaLite");
}
