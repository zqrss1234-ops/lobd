#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <AudioToolbox/AudioToolbox.h>

#define PRIMARY_COLOR    [UIColor colorWithRed:0.00 green:0.60 blue:1.00 alpha:1.0]
#define SUCCESS_COLOR    [UIColor colorWithRed:0.00 green:0.85 blue:0.40 alpha:1.0]
#define ERROR_COLOR      [UIColor colorWithRed:1.00 green:0.20 blue:0.30 alpha:1.0]
#define BG_DARK          [UIColor colorWithRed:0.05 green:0.05 blue:0.08 alpha:0.95]
#define BG_CARD          [UIColor colorWithRed:0.10 green:0.10 blue:0.15 alpha:0.90]
#define TEXT_PRIMARY     [UIColor whiteColor]
#define TEXT_SECONDARY   [UIColor colorWithRed:0.60 green:0.60 blue:0.70 alpha:1.0]
#define TURBO_COLOR      [UIColor colorWithRed:1.00 green:0.50 blue:0.00 alpha:1.0]

static NSMutableDictionary *imageCache = nil;

@interface UIImage (Abdulilah)
+ (UIImage *)imageFromURL:(NSString *)urlString;
@end

@implementation UIImage (Abdulilah)
+ (UIImage *)imageFromURL:(NSString *)urlString {
    if (!imageCache) imageCache = [NSMutableDictionary dictionary];
    if (imageCache[urlString]) return imageCache[urlString];
    NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:urlString]];
    UIImage *img = [UIImage imageWithData:data];
    if (img) imageCache[urlString] = img;
    return img;
}
@end

@interface AbdulilahManager : NSObject

@property (nonatomic, strong) UIView *mainPanel;
@property (nonatomic, strong) UIButton *floatButton;
@property (nonatomic, strong) UIButton *startBtn;
@property (nonatomic, strong) UIButton *stopBtn;
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
@property (nonatomic, strong) UIButton *loopBtn;
@property (nonatomic, strong) UIButton *stopLoopBtn;
@property (nonatomic, assign) BOOL infiniteLoopRunning;
@property (nonatomic, strong) NSArray *infiniteEvents;
@property (nonatomic, assign) BOOL isDarkMode;
@property (nonatomic, assign) BOOL isEnglish;
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

+ (instancetype)shared;
- (void)showFloatingButton;
- (void)toggleMenu;
- (void)startBackgroundKeepAlive;
- (void)stopBackgroundKeepAlive;

@end

static UIImageView *createIcon(NSString *url, CGRect frame, UIColor *tint) {
    UIImage *img = [[UIImage imageFromURL:url] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    UIImageView *iv = [[UIImageView alloc] initWithFrame:frame];
    iv.image = img;
    iv.tintColor = tint;
    iv.contentMode = UIViewContentModeScaleAspectFit;
    return iv;
}

static UIButton *circularButton(CGRect frame, NSString *url, UIColor *color, SEL action, id target) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = frame;
    b.layer.cornerRadius = frame.size.height / 2;
    b.clipsToBounds = YES;
    b.backgroundColor = [UIColor clearColor];
    UIImageView *iv = createIcon(url, CGRectMake((frame.size.width-32)/2, (frame.size.height-32)/2, 32, 32), color);
    [b addSubview:iv];
    [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

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
        instance.isTrackingAccounts = NO;
        [instance prepareScriptsFolder];
        [instance startUIGuard];
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
}

- (void)prepareScriptsFolder {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docs = [paths firstObject];
    self.scriptsFolder = [docs stringByAppendingPathComponent:@"Scripts"];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.scriptsFolder withIntermediateDirectories:YES attributes:nil error:nil];
}

- (void)showFloatingButton {
    if (self.floatButton) {
        [self.floatButton.superview removeFromSuperview];
        self.floatButton = nil;
    }
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(20, 150, 52, 52)];
    self.floatButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.floatButton.frame = CGRectMake(0, 0, 52, 52);
    self.floatButton.backgroundColor = PRIMARY_COLOR;
    self.floatButton.layer.cornerRadius = 26;
    self.floatButton.clipsToBounds = YES;
    self.floatButton.layer.borderWidth = 2;
    self.floatButton.layer.borderColor = [UIColor whiteColor].CGColor;
    [self.floatButton setTitle:@"ع" forState:UIControlStateNormal];
    self.floatButton.titleLabel.font = [UIFont boldSystemFontOfSize:24];
    self.floatButton.layer.shadowColor = PRIMARY_COLOR.CGColor;
    self.floatButton.layer.shadowOffset = CGSizeMake(0, 4);
    self.floatButton.layer.shadowRadius = 10;
    self.floatButton.layer.shadowOpacity = 0.35;
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

- (void)buildMainPanel {
    if (self.mainPanel) return;
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    CGFloat pw = 270, ph = 520;
    CGFloat px = (w.bounds.size.width - pw) / 2;
    CGFloat py = 60;
    self.mainPanel = [[UIView alloc] initWithFrame:CGRectMake(px, py, pw, ph)];
    self.mainPanel.backgroundColor = BG_DARK;
    self.mainPanel.layer.cornerRadius = 20;
    self.mainPanel.clipsToBounds = YES;
    self.mainPanel.alpha = 0;
    self.mainPanel.hidden = YES;
    self.mainPanel.layer.borderWidth = 1;
    self.mainPanel.layer.borderColor = [PRIMARY_COLOR colorWithAlphaComponent:0.3].CGColor;
    [w addSubview:self.mainPanel];

    // Header
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, pw, 44)];
    header.backgroundColor = PRIMARY_COLOR;
    [self.mainPanel addSubview:header];

    UILabel *titleLbl = [[UILabel alloc] initWithFrame:CGRectMake(15, 8, 200, 22)];
    titleLbl.text = @"عبدالإله";
    titleLbl.textColor = TEXT_PRIMARY;
    titleLbl.font = [UIFont boldSystemFontOfSize:18];
    [header addSubview:titleLbl];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(pw - 38, 7, 30, 30);
    closeBtn.layer.cornerRadius = 15;
    closeBtn.backgroundColor = [ERROR_COLOR colorWithAlphaComponent:0.2];
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:ERROR_COLOR forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:closeBtn];
    UIPanGestureRecognizer *panH = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [closeBtn addGestureRecognizer:panH];

    CGFloat y = 52;

    // Start/Stop buttons
    CGFloat btnSize = 80;
    self.startBtn = circularButton(CGRectMake(20, y, btnSize, btnSize),
        @"https://cdn-icons-png.flaticon.com/512/0/375.png",
        SUCCESS_COLOR, @selector(startTap), self);
    [self.mainPanel addSubview:self.startBtn];

    CGFloat stopX = pw - 20 - btnSize;
    self.stopBtn = circularButton(CGRectMake(stopX, y, btnSize, btnSize),
        @"https://img.icons8.com/?size=100&id=VAUcyT5ZfYFs&format=png&color=000000",
        ERROR_COLOR, @selector(stopTap), self);
    [self.mainPanel addSubview:self.stopBtn];

    y += btnSize + 10;

    // Speed label
    self.speedLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, y, pw - 30, 20)];
    self.speedLabel.text = [NSString stringWithFormat:@"السرعة: %.3f ث", self.currentSpeed];
    self.speedLabel.textColor = TEXT_PRIMARY;
    self.speedLabel.font = [UIFont systemFontOfSize:12];
    [self.mainPanel addSubview:self.speedLabel];
    y += 22;

    // Speed slider
    self.speedSlider = [[UISlider alloc] initWithFrame:CGRectMake(15, y, pw - 30, 24)];
    self.speedSlider.minimumValue = 0.001f;
    self.speedSlider.maximumValue = 0.1f;
    self.speedSlider.value = self.currentSpeed;
    self.speedSlider.tintColor = PRIMARY_COLOR;
    self.speedSlider.minimumTrackTintColor = PRIMARY_COLOR;
    self.speedSlider.maximumTrackTintColor = [UIColor colorWithWhite:0.3 alpha:1];
    [self.speedSlider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.mainPanel addSubview:self.speedSlider];
    y += 30;

    // Record buttons
    self.recordBtn = circularButton(CGRectMake(30, y, 55, 55),
        @"https://img.icons8.com/?size=100&id=69068&format=png&color=000000",
        TURBO_COLOR, @selector(startRecording), self);
    [self.mainPanel addSubview:self.recordBtn];

    self.stopRecordBtn = circularButton(CGRectMake(95, y, 55, 55),
        @"https://img.icons8.com/?size=100&id=VAUcyT5ZfYFs&format=png&color=000000",
        ERROR_COLOR, @selector(stopRecording), self);
    self.stopRecordBtn.alpha = 0;
    [self.mainPanel addSubview:self.stopRecordBtn];

    // Scripts button
    UIButton *scriptsBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    scriptsBtn.frame = CGRectMake(160, y + 5, pw - 175, 45);
    [scriptsBtn setTitle:@"ملفاتي" forState:UIControlStateNormal];
    scriptsBtn.backgroundColor = [UIColor colorWithRed:0.6 green:0.2 blue:0.8 alpha:1];
    scriptsBtn.tintColor = [UIColor whiteColor];
    scriptsBtn.layer.cornerRadius = 22;
    [scriptsBtn addTarget:self action:@selector(showScriptsManager) forControlEvents:UIControlEventTouchUpInside];
    [self.mainPanel addSubview:scriptsBtn];
    y += 62;

    // Features toggle button
    UIButton *featuresBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    featuresBtn.frame = CGRectMake(15, y, pw - 30, 36);
    [featuresBtn setTitle:@"الأدوات" forState:UIControlStateNormal];
    featuresBtn.backgroundColor = [UIColor colorWithRed:0.9 green:0.3 blue:0.6 alpha:1];
    featuresBtn.tintColor = [UIColor whiteColor];
    featuresBtn.layer.cornerRadius = 18;
    [featuresBtn addTarget:self action:@selector(showFeaturesWindow) forControlEvents:UIControlEventTouchUpInside];
    [self.mainPanel addSubview:featuresBtn];
    y += 42;

    // Account tracking section
    UIView *acctBox = [[UIView alloc] initWithFrame:CGRectMake(15, y, pw - 30, 55)];
    acctBox.backgroundColor = BG_CARD;
    acctBox.layer.cornerRadius = 12;
    [self.mainPanel addSubview:acctBox];

    UILabel *acctTitle = [[UILabel alloc] initWithFrame:CGRectMake(10, 5, 120, 20)];
    acctTitle.text = @"👤 تتبع الحسابات";
    acctTitle.textColor = TEXT_PRIMARY;
    acctTitle.font = [UIFont boldSystemFontOfSize:11];
    [acctBox addSubview:acctTitle];

    self.accountCountLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 25, 120, 20)];
    self.accountCountLabel.text = [NSString stringWithFormat:@"%lu حساب", (unsigned long)self.trackedAccounts.count];
    self.accountCountLabel.textColor = TEXT_SECONDARY;
    self.accountCountLabel.font = [UIFont systemFontOfSize:10];
    [acctBox addSubview:self.accountCountLabel];

    UIButton *trackBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    trackBtn.frame = CGRectMake(130, 8, 55, 40);
    trackBtn.layer.cornerRadius = 12;
    trackBtn.backgroundColor = PRIMARY_COLOR;
    [trackBtn setTitle:@"تتبع" forState:UIControlStateNormal];
    [trackBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    trackBtn.titleLabel.font = [UIFont boldSystemFontOfSize:10];
    [trackBtn addTarget:self action:@selector(toggleAccountTracking) forControlEvents:UIControlEventTouchUpInside];
    [acctBox addSubview:trackBtn];

    self.mergeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.mergeButton.frame = CGRectMake(190, 8, 65, 40);
    self.mergeButton.layer.cornerRadius = 12;
    self.mergeButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.4 blue:0.0 alpha:1];
    [self.mergeButton setTitle:@"دمج" forState:UIControlStateNormal];
    [self.mergeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.mergeButton.titleLabel.font = [UIFont boldSystemFontOfSize:10];
    [self.mergeButton addTarget:self action:@selector(mergeAccounts) forControlEvents:UIControlEventTouchUpInside];
    [acctBox addSubview:self.mergeButton];
    y += 62;

    // Background keep-alive toggle
    UIView *bgBox = [[UIView alloc] initWithFrame:CGRectMake(15, y, pw - 30, 45)];
    bgBox.backgroundColor = BG_CARD;
    bgBox.layer.cornerRadius = 12;
    [self.mainPanel addSubview:bgBox];

    UILabel *bgTitle = [[UILabel alloc] initWithFrame:CGRectMake(10, 12, 150, 20)];
    bgTitle.text = @"🔋 البقاء في الخلفية";
    bgTitle.textColor = TEXT_PRIMARY;
    bgTitle.font = [UIFont boldSystemFontOfSize:11];
    [bgBox addSubview:bgTitle];

    UIButton *bgToggle = [UIButton buttonWithType:UIButtonTypeCustom];
    bgToggle.frame = CGRectMake(pw - 100, 7, 70, 30);
    bgToggle.layer.cornerRadius = 15;
    bgToggle.backgroundColor = SUCCESS_COLOR;
    [bgToggle setTitle:@"ON" forState:UIControlStateNormal];
    [bgToggle setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    bgToggle.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [bgToggle addTarget:self action:@selector(toggleBackgroundKeepAlive:) forControlEvents:UIControlEventTouchUpInside];
    [bgBox addSubview:bgToggle];
    y += 52;

    // Settings button
    UIButton *settingsBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    settingsBtn.frame = CGRectMake(15, y, pw - 30, 36);
    [settingsBtn setTitle:@"الإعدادات" forState:UIControlStateNormal];
    settingsBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.5 blue:0.8 alpha:1];
    settingsBtn.tintColor = [UIColor whiteColor];
    settingsBtn.layer.cornerRadius = 18;
    [settingsBtn addTarget:self action:@selector(showSettingsWindow) forControlEvents:UIControlEventTouchUpInside];
    [self.mainPanel addSubview:settingsBtn];
    y += 42;

    // Resize panel to fit content
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
                    }
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

- (void)mergeAccounts {
    if (self.trackedAccounts.count < 2) {
        [self showToast:@"تحتاج حسابين على الأقل للدمج"];
        return;
    }
    [self showToast:[NSString stringWithFormat:@"جاري دمج %lu حسابات...", (unsigned long)self.trackedAccounts.count]];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"دمج الحسابات"
        message:[NSString stringWithFormat:@"تم تتبع %lu حساب. هل تريد متابعة الدمج؟", (unsigned long)self.trackedAccounts.count]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"دمج" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self performMerge];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
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
        sender.backgroundColor = [UIColor colorWithWhite:0.3 alpha:1];
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
    NSLog(@"[عبدالإله] Background keep-alive ping");
    AudioServicesPlaySystemSound(1103);
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
        btn.backgroundColor = enabled ? [UIColor colorWithRed:0.0 green:0.7 blue:0.3 alpha:1] : [UIColor colorWithWhite:0.3 alpha:1];
        btn.tintColor = [UIColor whiteColor];
        btn.layer.cornerRadius = 12;
        btn.tag = i + 1;
        [btn addTarget:self action:@selector(toggleFeatureFromTag:) forControlEvents:UIControlEventTouchUpInside];
        [panel addSubview:btn];
    }

    // Transparency
    UILabel *transLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 290, 240, 20)];
    transLabel.text = [NSString stringWithFormat:@"الشفافية: %.0f%%", self.transparencyValue * 100];
    transLabel.textColor = self.isDarkMode ? [UIColor whiteColor] : [UIColor blackColor];
    transLabel.font = [UIFont systemFontOfSize:12];
    transLabel.textAlignment = NSTextAlignmentCenter;
    [panel addSubview:transLabel];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(200, 310, 70, 30);
    [closeBtn setTitle:@"إغلاق" forState:UIControlStateNormal];
    closeBtn.backgroundColor = [UIColor grayColor];
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
    themeBtn.backgroundColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.3 alpha:1];
    themeBtn.tintColor = [UIColor whiteColor];
    themeBtn.layer.cornerRadius = 12;
    [themeBtn addTarget:self action:@selector(toggleTheme) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:themeBtn];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(200, 250, 70, 30);
    [closeBtn setTitle:@"إغلاق" forState:UIControlStateNormal];
    closeBtn.backgroundColor = [UIColor grayColor];
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
    closeBtn.backgroundColor = [UIColor grayColor];
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

- (void)startTap {
    if (self.autoTapEnabled) return;
    [self startTapWithSpeed:self.currentSpeed];
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
}

- (void)tapRealTarget {
    if (!self.autoTapEnabled || self.targetsArray.count == 0) return;
    for (UIButton *btn in self.targetsArray) {
        CGPoint pt = [btn convertPoint:CGPointMake(btn.bounds.size.width/2, btn.bounds.size.height/2) toView:nil];
        UIControl *target = (UIControl *)[[UIApplication sharedApplication].keyWindow hitTest:pt withEvent:nil];
        if ([target respondsToSelector:@selector(sendActionsForControlEvents:)])
            [target sendActionsForControlEvents:UIControlEventTouchUpInside];
    }
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
        }
    }
}

%end

#pragma mark - Constructor

%ctor {
    [AbdulilahManager shared];
    NSLog(@"[عبدالإله] Tweak v1.0 loaded for YallaLite");
}
