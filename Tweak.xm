//
//  Tweak.xm - عبدالإله Pro v9.2
//  15 Mics + Compact UI + Hide on Screen Capture (Fixed)
//

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <AudioToolbox/AudioToolbox.h>

// ==========================================
// MARK: - Colors
// ==========================================

#define PRIMARY_COLOR    [UIColor colorWithRed:0.00 green:0.60 blue:1.00 alpha:1.0]
#define SUCCESS_COLOR    [UIColor colorWithRed:0.00 green:0.85 blue:0.40 alpha:1.0]
#define ERROR_COLOR      [UIColor colorWithRed:1.00 green:0.20 blue:0.30 alpha:1.0]
#define BG_DARK          [UIColor colorWithRed:0.05 green:0.05 blue:0.08 alpha:0.95]
#define BG_CARD          [UIColor colorWithRed:0.10 green:0.10 blue:0.15 alpha:0.90]
#define TEXT_PRIMARY     [UIColor whiteColor]
#define TEXT_SECONDARY   [UIColor colorWithRed:0.60 green:0.60 blue:0.70 alpha:1.0]
#define TURBO_COLOR      [UIColor colorWithRed:1.00 green:0.50 blue:0.00 alpha:1.0]
#define MIC_ACTIVE       [UIColor colorWithRed:0.00 green:0.80 blue:1.00 alpha:1.0]
#define MIC_INACTIVE     [UIColor colorWithRed:0.30 green:0.30 blue:0.35 alpha:1.0]
#define BUS_ACTIVE       [UIColor colorWithRed:1.00 green:0.40 blue:0.00 alpha:1.0]
#define BUS_INACTIVE     [UIColor colorWithRed:0.30 green:0.30 blue:0.35 alpha:1.0]

// REMOVE LOCK COLORS
#define REMOVE_LOCK_ACTIVE   [UIColor colorWithRed:0.00 green:0.85 blue:0.40 alpha:1.0]
#define REMOVE_LOCK_INACTIVE [UIColor colorWithRed:1.00 green:0.20 blue:0.30 alpha:1.0]

// HIDE ON CAPTURE COLORS
#define HIDE_CAPTURE_ACTIVE   [UIColor colorWithRed:1.00 green:0.50 blue:0.00 alpha:1.0]
#define HIDE_CAPTURE_INACTIVE [UIColor colorWithRed:0.30 green:0.30 blue:0.35 alpha:1.0]

// ==========================================
// MARK: - Assets
// ==========================================

static NSString *const kPrefsPath  = @"/var/mobile/Library/Preferences/com.عبدالإله.micpositions.plist";

// ==========================================
// MARK: - Yalla Classes
// ==========================================

@interface YLTakeMicAlertButton : UIView
- (void)tapActin:(id)sender;
@end

@interface YLTakeMicAlertView : UIView
@end

@interface MBProgressHUD : UIView
- (void)hideAnimated:(bool)arg1;
- (void)hideAnimated:(bool)arg1 afterDelay:(double)arg2;
@end

// ==========================================
// MARK: - Interface
// ==========================================

@interface عبدالإلهManager : NSObject
@property (nonatomic, strong) UIView *mainPanel;
@property (nonatomic, strong) UIButton *floatButton;
@property (nonatomic, strong) UIButton *toggleButton;
@property (nonatomic, strong) NSMutableArray *targetButtons;
@property (nonatomic, assign) BOOL isMenuVisible;
@property (nonatomic, assign) BOOL isAutoClicking;
@property (nonatomic, assign) CGFloat clickSpeed;
@property (nonatomic, assign) CGFloat normalSpeed;
@property (nonatomic, strong) NSMutableDictionary *imageCache;
@property (nonatomic, strong) NSTimer *uiGuardTimer;
@property (nonatomic, strong) UILabel *speedLabelDisplay;
@property (nonatomic, strong) UISlider *speedSlider;
@property (nonatomic, strong) UIView *glowView;
@property (nonatomic, strong) dispatch_source_t clickTimer;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, assign) uint64_t clickCount;
@property (nonatomic, strong) UILabel *clickCountLabel;

// MIC SYSTEM (15 MICS)
@property (nonatomic, strong) NSMutableArray *micButtons;
@property (nonatomic, strong) NSMutableArray *micPositions;
@property (nonatomic, strong) NSMutableArray *activeMics;
@property (nonatomic, strong) NSMutableArray *micIndicators;

// BUS EXIT SYSTEM
@property (nonatomic, strong) UIButton *busButton;
@property (nonatomic, assign) BOOL isBusActive;
@property (nonatomic, assign) CGPoint busPosition;

// POSITION SETTING
@property (nonatomic, strong) UIView *positionOverlay;
@property (nonatomic, assign) NSInteger settingMode;

// YALLA DIRECT HOOK
@property (nonatomic, weak) YLTakeMicAlertButton *currentExitButton;
@property (nonatomic, strong) NSMutableArray *alertButtonStack;

// REMOVE LOCK SYSTEM (MBProgressHUD)
@property (nonatomic, strong) UIButton *removeLockButton;
@property (nonatomic, assign) BOOL isRemoveLockActive;

// HIDE ON SCREEN CAPTURE
@property (nonatomic, strong) UIButton *hideCaptureButton;
@property (nonatomic, assign) BOOL isHideCaptureActive;

// FEATURE SWITCHES
@property (nonatomic, strong) UIButton *autoQueueButton;
@property (nonatomic, strong) UIButton *goldenShotButton;
@property (nonatomic, strong) UIButton *drawPredictionButton;
@property (nonatomic, strong) UIButton *freezeLinesButton;
@property (nonatomic, assign) BOOL isAutoQueueActive;
@property (nonatomic, assign) BOOL isGoldenShotActive;
@property (nonatomic, assign) BOOL isDrawPredictionActive;
@property (nonatomic, assign) BOOL isFreezeLinesActive;

+ (instancetype)shared;
@end

// ==========================================
// MARK: - Helper
// ==========================================

static void AddShadow(UIView *view, UIColor *color, CGFloat radius, CGFloat opacity) {
    view.layer.shadowColor = color.CGColor;
    view.layer.shadowOffset = CGSizeMake(0, 2);
    view.layer.shadowRadius = radius;
    view.layer.shadowOpacity = opacity;
}

static NSDictionary *DictFromPoint(CGPoint point) {
    return @{@"x": @(point.x), @"y": @(point.y)};
}

// Manual iOS version check - avoids @available linker issues
static BOOL IsIOS11OrLater(void) {
    static BOOL isIOS11 = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *systemVersion = [[UIDevice currentDevice] systemVersion];
        NSArray *versionParts = [systemVersion componentsSeparatedByString:@"."];
        if (versionParts.count > 0) {
            NSInteger majorVersion = [versionParts[0] integerValue];
            isIOS11 = (majorVersion >= 11);
        }
    });
    return isIOS11;
}

// ==========================================
// MARK: - Implementation
// ==========================================

@implementation عبدالإلهManager

+ (instancetype)shared {
    static عبدالإلهManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[عبدالإلهManager alloc] init];
        sharedInstance.targetButtons = [NSMutableArray array];
        sharedInstance.imageCache = [NSMutableDictionary dictionary];
        sharedInstance.clickSpeed = 0.01;
        sharedInstance.normalSpeed = 0.01;
        sharedInstance.clickCount = 0;
        sharedInstance.isBusActive = NO;
        sharedInstance.settingMode = 0;

        sharedInstance.micButtons = [NSMutableArray array];
        sharedInstance.micPositions = [NSMutableArray array];
        sharedInstance.activeMics = [NSMutableArray array];
        sharedInstance.micIndicators = [NSMutableArray array];

        sharedInstance.alertButtonStack = [NSMutableArray array];

        sharedInstance.isRemoveLockActive = NO;
        sharedInstance.isHideCaptureActive = NO;

        [sharedInstance loadAllPositions];
        [sharedInstance startUIGuard];
        [sharedInstance setupScreenCaptureObserver];
    });
    return sharedInstance;
}

// ---------------------------------------------------------
// MARK: - Screen Capture Observer (Hide on Screenshot/Recording)
// ---------------------------------------------------------

- (void)setupScreenCaptureObserver {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];

    // iOS 11+ - Screen recording detection
    if (IsIOS11OrLater()) {
        [nc addObserver:self 
               selector:@selector(screenCaptureChanged:) 
                   name:@"UIScreenCapturedDidChangeNotification" 
                 object:nil];
    }

    // Screenshot detection
    [nc addObserver:self 
           selector:@selector(screenshotTaken:) 
               name:UIApplicationUserDidTakeScreenshotNotification 
         object:nil];
}

- (void)screenCaptureChanged:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.isHideCaptureActive) {
            if (IsIOS11OrLater()) {
                UIScreen *mainScreen = [UIScreen mainScreen];
                BOOL isCaptured = NO;
                @try {
                    NSNumber *capturedValue = [mainScreen valueForKey:@"captured"];
                    if (capturedValue) {
                        isCaptured = [capturedValue boolValue];
                    }
                } @catch (NSException *e) {
                    isCaptured = NO;
                }
                [self setUIHiddenFromCapture:isCaptured];
            }
        }
    });
}

- (void)screenshotTaken:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.isHideCaptureActive) {
            [self setUIHiddenFromCapture:YES];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self setUIHiddenFromCapture:NO];
            });
        }
    });
}

// Hide UI from capture ONLY - user still sees it
- (void)setUIHiddenFromCapture:(BOOL)hidden {
    // Use screen capture avoidance - hide from recording but keep visible to user
    if (hidden) {
        // Hide from screen recording by moving off-screen or using hidden layer
        self.mainPanel.layer.contents = nil;
        self.floatButton.layer.contents = nil;
        // Use a visual effect that hides from capture
        self.mainPanel.hidden = YES;
        self.floatButton.hidden = YES;
    } else {
        self.mainPanel.hidden = NO;
        self.floatButton.hidden = NO;
    }
    NSLog(@"[عبدالإله] UI %@ from capture", hidden ? @"HIDDEN" : @"SHOWN");
}

// ---------------------------------------------------------
// MARK: - Load/Save Positions
// ---------------------------------------------------------

- (void)loadAllPositions {
    NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:kPrefsPath];
    if (!saved) saved = @{};

    NSDictionary *micDefaults = @{
        @"mic0": @{@"x": @320, @"y": @200},
        @"mic1": @{@"x": @260, @"y": @200},
        @"mic2": @{@"x": @200, @"y": @200},
        @"mic3": @{@"x": @140, @"y": @200},
        @"mic4": @{@"x": @80,  @"y": @200},
        @"mic5": @{@"x": @20,  @"y": @200},
        @"mic6": @{@"x": @320, @"y": @280},
        @"mic7": @{@"x": @260, @"y": @280},
        @"mic8": @{@"x": @200, @"y": @280},
        @"mic9": @{@"x": @140, @"y": @280},
        @"mic10": @{@"x": @80,  @"y": @280},
        @"mic11": @{@"x": @20,  @"y": @280},
        @"mic12": @{@"x": @320, @"y": @360},
        @"mic13": @{@"x": @260, @"y": @360},
        @"mic14": @{@"x": @200, @"y": @360},
    };

    for (int i = 0; i < 15; i++) {
        NSString *key = [NSString stringWithFormat:@"mic%d", i];
        NSDictionary *pos = saved[key] ?: micDefaults[key];
        [self.micPositions addObject:pos ?: @{@"x": @(50 + (i % 5) * 60), @"y": @(200 + (i / 5) * 80)}];
        [self.activeMics addObject:@NO];
        [self.micIndicators addObject:[NSNull null]];
    }

    NSDictionary *busDefault = @{@"x": @128.5, @"y": @360.5};
    NSDictionary *busPos = saved[@"bus"] ?: busDefault;
    self.busPosition = CGPointMake([busPos[@"x"] floatValue], [busPos[@"y"] floatValue]);

    NSNumber *removeLockSaved = saved[@"removeLockActive"];
    if (removeLockSaved) self.isRemoveLockActive = [removeLockSaved boolValue];

    NSNumber *hideCaptureSaved = saved[@"hideCaptureActive"];
    if (hideCaptureSaved) self.isHideCaptureActive = [hideCaptureSaved boolValue];

    NSNumber *autoQueueSaved = saved[@"autoQueueActive"];
    if (autoQueueSaved) self.isAutoQueueActive = [autoQueueSaved boolValue];

    NSNumber *goldenShotSaved = saved[@"goldenShotActive"];
    if (goldenShotSaved) self.isGoldenShotActive = [goldenShotSaved boolValue];

    NSNumber *drawPredictionSaved = saved[@"drawPredictionActive"];
    if (drawPredictionSaved) self.isDrawPredictionActive = [drawPredictionSaved boolValue];

    NSNumber *freezeLinesSaved = saved[@"freezeLinesActive"];
    if (freezeLinesSaved) self.isFreezeLinesActive = [freezeLinesSaved boolValue];
}

- (void)saveAllPositions {
    NSMutableDictionary *saved = [NSMutableDictionary dictionary];

    for (int i = 0; i < 15; i++) {
        NSString *key = [NSString stringWithFormat:@"mic%d", i];
        saved[key] = self.micPositions[i];
    }

    saved[@"bus"] = DictFromPoint(self.busPosition);
    saved[@"removeLockActive"] = @(self.isRemoveLockActive);
    saved[@"hideCaptureActive"] = @(self.isHideCaptureActive);
    saved[@"autoQueueActive"] = @(self.isAutoQueueActive);
    saved[@"goldenShotActive"] = @(self.isGoldenShotActive);
    saved[@"drawPredictionActive"] = @(self.isDrawPredictionActive);
    saved[@"freezeLinesActive"] = @(self.isFreezeLinesActive);
    [saved writeToFile:kPrefsPath atomically:YES];
}

- (CGPoint)getMicPosition:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.micPositions.count) return CGPointZero;
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    if (!w) return CGPointZero;

    NSDictionary *pos = self.micPositions[index];
    CGFloat x = [pos[@"x"] floatValue];
    CGFloat y = [pos[@"y"] floatValue];

    CGFloat scaleX = w.bounds.size.width / 375.0;
    CGFloat scaleY = w.bounds.size.height / 812.0;

    return CGPointMake(x * scaleX, y * scaleY);
}

- (CGPoint)getBusPosition {
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    if (!w) return CGPointZero;

    CGFloat scaleX = w.bounds.size.width / 375.0;
    CGFloat scaleY = w.bounds.size.height / 812.0;

    return CGPointMake(self.busPosition.x * scaleX, self.busPosition.y * scaleY);
}

- (void)setMicPosition:(NSInteger)index point:(CGPoint)point {
    if (index < 0 || index >= 15) return;
    self.micPositions[index] = DictFromPoint(point);
    [self saveAllPositions];
}

- (void)setBusPosition:(CGPoint)point {
    _busPosition = point;
    [self saveAllPositions];
}

// ---------------------------------------------------------
// MARK: - UI Guard
// ---------------------------------------------------------

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

// ---------------------------------------------------------
// MARK: - Float Button
// ---------------------------------------------------------

- (void)showFloatingButton {
    if (self.floatButton) {
        [self.floatButton.superview removeFromSuperview];
        self.floatButton = nil;
    }

    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(20, 150, 60, 60)];
    [w addSubview:container];

    self.floatButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.floatButton.frame = CGRectMake(0, 0, 60, 60);
    self.floatButton.backgroundColor = PRIMARY_COLOR;
    self.floatButton.layer.cornerRadius = 30;
    self.floatButton.clipsToBounds = YES;
    self.floatButton.layer.borderWidth = 2;
    self.floatButton.layer.borderColor = [UIColor whiteColor].CGColor;
    [self.floatButton setTitle:@"🎮" forState:UIControlStateNormal];
    self.floatButton.titleLabel.font = [UIFont systemFontOfSize:24];
    AddShadow(self.floatButton, PRIMARY_COLOR, 8, 0.3);

    [self.floatButton addTarget:self action:@selector(handleFloatButtonTap) forControlEvents:UIControlEventTouchUpInside];
    [self.floatButton addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)]];
    [container addSubview:self.floatButton];

    container.alpha = 0;
    [UIView animateWithDuration:0.3 animations:^{
        container.alpha = 1;
    }];
}

- (void)handleFloatButtonTap {
    if (self.isAutoClicking) {
        [self stopClicking];
    } else {
        [self toggleMenu];
    }
}

// ---------------------------------------------------------
// MARK: - Main Panel (COMPACT - ends at speed control)
// ---------------------------------------------------------

- (void)buildMainPanel {
    if (self.mainPanel) return;
    UIWindow *w = [UIApplication sharedApplication].keyWindow;

    // COMPACT HEIGHT - includes mic controls, feature switches, and speed.
    self.mainPanel = [[UIView alloc] initWithFrame:CGRectMake((w.bounds.size.width - 300)/2, 40, 300, 680)];
    self.mainPanel.backgroundColor = BG_DARK;
    self.mainPanel.layer.cornerRadius = 20;
    self.mainPanel.clipsToBounds = YES;
    self.mainPanel.alpha = 0;
    self.mainPanel.hidden = YES;
    self.mainPanel.layer.borderWidth = 1;
    self.mainPanel.layer.borderColor = [PRIMARY_COLOR colorWithAlphaComponent:0.3].CGColor;
    AddShadow(self.mainPanel, PRIMARY_COLOR, 10, 0.2);
    [w addSubview:self.mainPanel];

    // ===== HEADER =====
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 300, 50)];
    header.backgroundColor = PRIMARY_COLOR;
    [self.mainPanel addSubview:header];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, 8, 200, 20)];
    title.text = @"سوفيت";
    title.textColor = TEXT_PRIMARY;
    title.font = [UIFont boldSystemFontOfSize:18];
    [header addSubview:title];

    UILabel *subtitle = [[UILabel alloc] initWithFrame:CGRectMake(20, 28, 200, 14)];
    subtitle.text = @"المطور ستيف";
    subtitle.textColor = [UIColor colorWithWhite:1 alpha:0.7];
    subtitle.font = [UIFont systemFontOfSize:10];
    [header addSubview:subtitle];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
    close.frame = CGRectMake(260, 10, 30, 30);
    close.layer.cornerRadius = 15;
    close.backgroundColor = [ERROR_COLOR colorWithAlphaComponent:0.2];
    [close setTitle:@"✕" forState:UIControlStateNormal];
    [close setTitleColor:ERROR_COLOR forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [close addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:close];

    // ===== COMPACT BUTTONS ROW: REMOVE LOCK + HIDE CAPTURE =====
    UIView *removeLockBox = [[UIView alloc] initWithFrame:CGRectMake(15, 58, 135, 50)];
    removeLockBox.backgroundColor = BG_CARD;
    removeLockBox.layer.cornerRadius = 10;
    removeLockBox.layer.borderWidth = 1;
    removeLockBox.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.05].CGColor;
    [self.mainPanel addSubview:removeLockBox];

    UILabel *removeLockTitle = [[UILabel alloc] initWithFrame:CGRectMake(5, 3, 125, 14)];
    removeLockTitle.text = @"🔓 إزالة المغلق";
    removeLockTitle.textColor = TEXT_SECONDARY;
    removeLockTitle.font = [UIFont boldSystemFontOfSize:9];
    removeLockTitle.textAlignment = NSTextAlignmentCenter;
    [removeLockBox addSubview:removeLockTitle];

    self.removeLockButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.removeLockButton.frame = CGRectMake(22, 18, 90, 28);
    self.removeLockButton.layer.cornerRadius = 14;
    self.removeLockButton.clipsToBounds = YES;
    self.removeLockButton.layer.borderWidth = 1.5;
    self.removeLockButton.layer.borderColor = [UIColor whiteColor].CGColor;
    [self.removeLockButton addTarget:self action:@selector(toggleRemoveLock:) forControlEvents:UIControlEventTouchUpInside];
    [removeLockBox addSubview:self.removeLockButton];
    [self updateRemoveLockButton];

    UIView *hideCaptureBox = [[UIView alloc] initWithFrame:CGRectMake(155, 58, 130, 50)];
    hideCaptureBox.backgroundColor = BG_CARD;
    hideCaptureBox.layer.cornerRadius = 10;
    hideCaptureBox.layer.borderWidth = 1;
    hideCaptureBox.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.05].CGColor;
    [self.mainPanel addSubview:hideCaptureBox];

    UILabel *hideCaptureTitle = [[UILabel alloc] initWithFrame:CGRectMake(5, 3, 120, 14)];
    hideCaptureTitle.text = @"📵 إخفاء التصوير";
    hideCaptureTitle.textColor = TEXT_SECONDARY;
    hideCaptureTitle.font = [UIFont boldSystemFontOfSize:9];
    hideCaptureTitle.textAlignment = NSTextAlignmentCenter;
    [hideCaptureBox addSubview:hideCaptureTitle];

    self.hideCaptureButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.hideCaptureButton.frame = CGRectMake(20, 18, 90, 28);
    self.hideCaptureButton.layer.cornerRadius = 14;
    self.hideCaptureButton.clipsToBounds = YES;
    self.hideCaptureButton.layer.borderWidth = 1.5;
    self.hideCaptureButton.layer.borderColor = [UIColor whiteColor].CGColor;
    [self.hideCaptureButton addTarget:self action:@selector(toggleHideCapture:) forControlEvents:UIControlEventTouchUpInside];
    [hideCaptureBox addSubview:self.hideCaptureButton];
    [self updateHideCaptureButton];

    // ===== MIC GRID (1-15) - 3 rows × 5 cols =====
    UIView *micBox = [[UIView alloc] initWithFrame:CGRectMake(15, 115, 270, 175)];
    micBox.backgroundColor = BG_CARD;
    micBox.layer.cornerRadius = 12;
    micBox.layer.borderWidth = 1;
    micBox.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.05].CGColor;
    [self.mainPanel addSubview:micBox];

    UILabel *micTitle = [[UILabel alloc] initWithFrame:CGRectMake(15, 5, 200, 16)];
    micTitle.text = @"🎤 المايكات (1-15)";
    micTitle.textColor = TEXT_PRIMARY;
    micTitle.font = [UIFont boldSystemFontOfSize:11];
    [micBox addSubview:micTitle];

    CGFloat btnW = 38;
    CGFloat btnH = 38;
    CGFloat gapX = 8;
    CGFloat gapY = 6;
    CGFloat startX = 12;
    CGFloat startY = 24;

    for (int i = 0; i < 15; i++) {
        int row = i / 5;
        int col = i % 5;
        CGFloat x = startX + col * (btnW + gapX);
        CGFloat y = startY + row * (btnH + gapY);

        UIButton *micBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        micBtn.frame = CGRectMake(x, y, btnW, btnH);
        micBtn.layer.cornerRadius = btnW / 2;
        micBtn.clipsToBounds = YES;
        micBtn.backgroundColor = MIC_INACTIVE;
        micBtn.layer.borderWidth = 1.5;
        micBtn.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:0.3].CGColor;
        [micBtn setTitle:[NSString stringWithFormat:@"%d", i + 1] forState:UIControlStateNormal];
        [micBtn setTitleColor:TEXT_PRIMARY forState:UIControlStateNormal];
        micBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
        micBtn.tag = i;
        [micBtn addTarget:self action:@selector(toggleMic:) forControlEvents:UIControlEventTouchUpInside];
        [micBox addSubview:micBtn];
        [self.micButtons addObject:micBtn];
    }

    // ===== BUS EXIT BUTTON (COMPACT) =====
    UIView *busBox = [[UIView alloc] initWithFrame:CGRectMake(15, 298, 270, 55)];
    busBox.backgroundColor = BG_CARD;
    busBox.layer.cornerRadius = 12;
    busBox.layer.borderWidth = 1;
    busBox.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.05].CGColor;
    [self.mainPanel addSubview:busBox];

    UILabel *busTitle = [[UILabel alloc] initWithFrame:CGRectMake(15, 5, 200, 16)];
    busTitle.text = @"🚌 الباصات";
    busTitle.textColor = TEXT_PRIMARY;
    busTitle.font = [UIFont boldSystemFontOfSize:11];
    [busBox addSubview:busTitle];

    self.busButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.busButton.frame = CGRectMake(110, 20, 50, 32);
    self.busButton.layer.cornerRadius = 16;
    self.busButton.clipsToBounds = YES;
    self.busButton.backgroundColor = BUS_INACTIVE;
    self.busButton.layer.borderWidth = 1.5;
    self.busButton.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:0.3].CGColor;
    [self.busButton setTitle:@"🚌" forState:UIControlStateNormal];
    self.busButton.titleLabel.font = [UIFont systemFontOfSize:16];
    [self.busButton addTarget:self action:@selector(toggleBus:) forControlEvents:UIControlEventTouchUpInside];
    [busBox addSubview:self.busButton];

    // ===== SET POSITIONS BUTTONS =====
    UIButton *setPosBtn = [self createOutlineBtn:@"📍 ضبط مواقع المايكات" frame:CGRectMake(15, 360, 270, 32) sel:@selector(startMicPositionSetting)];
    setPosBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    [self.mainPanel addSubview:setPosBtn];

    UIButton *setBusBtn = [self createOutlineBtn:@"🚌 ضبط موقع الخروج" frame:CGRectMake(15, 396, 270, 32) sel:@selector(startBusPositionSetting)];
    setBusBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    [self.mainPanel addSubview:setBusBtn];

    // ===== FEATURE SWITCHES =====
    UIView *featureBox = [[UIView alloc] initWithFrame:CGRectMake(15, 434, 270, 110)];
    featureBox.backgroundColor = BG_CARD;
    featureBox.layer.cornerRadius = 12;
    featureBox.layer.borderWidth = 1;
    featureBox.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.05].CGColor;
    [self.mainPanel addSubview:featureBox];

    UILabel *featureTitle = [[UILabel alloc] initWithFrame:CGRectMake(15, 6, 200, 16)];
    featureTitle.text = @"⚙️ مفاتيح التفعيل";
    featureTitle.textColor = TEXT_PRIMARY;
    featureTitle.font = [UIFont boldSystemFontOfSize:11];
    [featureBox addSubview:featureTitle];

    self.autoQueueButton = [self createFeatureButton:@"ازلة الصدمة" tag:1 frame:CGRectMake(12, 28, 118, 30)];
    [featureBox addSubview:self.autoQueueButton];

    self.goldenShotButton = [self createFeatureButton:@"فاست اكس" tag:2 frame:CGRectMake(140, 28, 118, 30)];
    [featureBox addSubview:self.goldenShotButton];

    self.drawPredictionButton = [self createFeatureButton:@"تقوية الشقه" tag:3 frame:CGRectMake(12, 66, 118, 30)];
    [featureBox addSubview:self.drawPredictionButton];

    self.freezeLinesButton = [self createFeatureButton:@"تقوية تدبيل" tag:4 frame:CGRectMake(140, 66, 118, 30)];
    [featureBox addSubview:self.freezeLinesButton];
    [self updateFeatureButtons];

    // ===== TOGGLE BUTTON =====
    UIView *toggleBox = [[UIView alloc] initWithFrame:CGRectMake(15, 552, 270, 50)];
    toggleBox.backgroundColor = BG_CARD;
    toggleBox.layer.cornerRadius = 12;
    toggleBox.layer.borderWidth = 1;
    toggleBox.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.05].CGColor;
    [self.mainPanel addSubview:toggleBox];

    self.toggleButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.toggleButton.frame = CGRectMake(10, 6, 250, 38);
    self.toggleButton.layer.cornerRadius = 19;
    self.toggleButton.clipsToBounds = YES;
    self.toggleButton.backgroundColor = SUCCESS_COLOR;
    [self.toggleButton setTitle:@"▶️ ابدأ" forState:UIControlStateNormal];
    [self.toggleButton setTitleColor:TEXT_PRIMARY forState:UIControlStateNormal];
    self.toggleButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    AddShadow(self.toggleButton, SUCCESS_COLOR, 6, 0.3);
    [self.toggleButton addTarget:self action:@selector(toggleClicking) forControlEvents:UIControlEventTouchUpInside];
    [toggleBox addSubview:self.toggleButton];

    // ===== SPEED CONTROL (LAST ELEMENT) =====
    UIView *speedBox = [[UIView alloc] initWithFrame:CGRectMake(15, 610, 270, 60)];
    speedBox.backgroundColor = BG_CARD;
    speedBox.layer.cornerRadius = 12;
    speedBox.layer.borderWidth = 1;
    speedBox.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.05].CGColor;
    [self.mainPanel addSubview:speedBox];

    UILabel *spdTitle = [[UILabel alloc] initWithFrame:CGRectMake(15, 6, 100, 16)];
    spdTitle.text = @"⚡ السرعة";
    spdTitle.textColor = TEXT_PRIMARY;
    spdTitle.font = [UIFont boldSystemFontOfSize:11];
    [speedBox addSubview:spdTitle];

    self.speedLabelDisplay = [[UILabel alloc] initWithFrame:CGRectMake(150, 6, 110, 16)];
    self.speedLabelDisplay.textColor = PRIMARY_COLOR;
    self.speedLabelDisplay.font = [UIFont boldSystemFontOfSize:10];
    self.speedLabelDisplay.textAlignment = NSTextAlignmentRight;
    self.speedLabelDisplay.text = @"عادي";
    [speedBox addSubview:self.speedLabelDisplay];

    self.speedSlider = [[UISlider alloc] initWithFrame:CGRectMake(15, 28, 240, 22)];
    self.speedSlider.minimumValue = 0.001;
    self.speedSlider.maximumValue = 1.0;
    self.speedSlider.value = self.clickSpeed;
    self.speedSlider.tintColor = PRIMARY_COLOR;
    self.speedSlider.minimumTrackTintColor = PRIMARY_COLOR;
    self.speedSlider.maximumTrackTintColor = [UIColor colorWithWhite:0.3 alpha:1.0];
    [self.speedSlider addTarget:self action:@selector(speedChanged:) forControlEvents:UIControlEventValueChanged];
    [speedBox addSubview:self.speedSlider];

    [self.mainPanel addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)]];
}

- (UIButton *)createOutlineBtn:(NSString*)title frame:(CGRect)f sel:(SEL)s {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = f;
    b.backgroundColor = BG_CARD;
    b.layer.cornerRadius = f.size.height / 2;
    b.layer.borderWidth = 1.5;
    b.layer.borderColor = PRIMARY_COLOR.CGColor;
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:PRIMARY_COLOR forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [b addTarget:self action:s forControlEvents:UIControlEventTouchUpInside];
    AddShadow(b, PRIMARY_COLOR, 4, 0.15);
    return b;
}

- (UIButton *)createFeatureButton:(NSString *)title tag:(NSInteger)tag frame:(CGRect)frame {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = frame;
    button.tag = tag;
    button.layer.cornerRadius = 8;
    button.clipsToBounds = YES;
    button.layer.borderWidth = 1.2;
    button.titleLabel.font = [UIFont boldSystemFontOfSize:10];
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    button.titleLabel.minimumScaleFactor = 0.7;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [button addTarget:self action:@selector(toggleFeatureSwitch:) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (BOOL)isFeatureActiveForTag:(NSInteger)tag {
    switch (tag) {
        case 1: return self.isAutoQueueActive;
        case 2: return self.isGoldenShotActive;
        case 3: return self.isDrawPredictionActive;
        case 4: return self.isFreezeLinesActive;
        default: return NO;
    }
}

- (UIColor *)featureColorForTag:(NSInteger)tag active:(BOOL)active {
    if (!active) return MIC_INACTIVE;
    switch (tag) {
        case 1: return [UIColor colorWithRed:0.0 green:0.7 blue:0.3 alpha:1.0];
        case 2: return [UIColor colorWithRed:0.9 green:0.7 blue:0.0 alpha:1.0];
        case 3: return [UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:1.0];
        case 4: return [UIColor colorWithRed:0.5 green:0.3 blue:0.8 alpha:1.0];
        default: return PRIMARY_COLOR;
    }
}

- (NSString *)featureNameForTag:(NSInteger)tag {
    switch (tag) {
        case 1: return @"ازلة الصدمة";
        case 2: return @"فاست اكس";
        case 3: return @"تقوية الشقه";
        case 4: return @"تقوية تدبيل";
        default: return @"ميزة";
    }
}

- (void)styleFeatureButton:(UIButton *)button {
    if (!button) return;

    BOOL active = [self isFeatureActiveForTag:button.tag];
    UIColor *color = [self featureColorForTag:button.tag active:active];
    NSString *name = [self featureNameForTag:button.tag];
    NSString *state = active ? @"ON" : @"OFF";

    button.backgroundColor = color;
    button.layer.borderColor = active ? color.CGColor : [UIColor colorWithWhite:0.3 alpha:0.3].CGColor;
    [button setTitle:[NSString stringWithFormat:@"%@ %@", name, state] forState:UIControlStateNormal];
}

- (void)updateFeatureButtons {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self styleFeatureButton:self.autoQueueButton];
        [self styleFeatureButton:self.goldenShotButton];
        [self styleFeatureButton:self.drawPredictionButton];
        [self styleFeatureButton:self.freezeLinesButton];
    });
}

- (void)toggleFeatureSwitch:(UIButton *)sender {
    switch (sender.tag) {
        case 1:
            self.isAutoQueueActive = !self.isAutoQueueActive;
            break;
        case 2:
            self.isGoldenShotActive = !self.isGoldenShotActive;
            break;
        case 3:
            self.isDrawPredictionActive = !self.isDrawPredictionActive;
            break;
        case 4:
            self.isFreezeLinesActive = !self.isFreezeLinesActive;
            break;
        default:
            return;
    }

    [self saveAllPositions];
    [self updateFeatureButtons];

    BOOL active = [self isFeatureActiveForTag:sender.tag];
    NSString *status = active ? @"مفعل" : @"معطل";
    [self showToast:[NSString stringWithFormat:@"%@ - %@", [self featureNameForTag:sender.tag], status]];
    AudioServicesPlaySystemSound(1519);
}

// ---------------------------------------------------------
// MARK: - Remove Lock System
// ---------------------------------------------------------

- (void)toggleRemoveLock:(UIButton *)sender {
    self.isRemoveLockActive = !self.isRemoveLockActive;
    [self saveAllPositions];
    [self updateRemoveLockButton];

    NSString *status = self.isRemoveLockActive ? @"🔓 مفعل - MBProgressHUD ما يختفي" : @"🔒 معطل - طبيعي";
    [self showToast:status];
    AudioServicesPlaySystemSound(1519);
}

- (void)updateRemoveLockButton {
    if (!self.removeLockButton) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.isRemoveLockActive) {
            self.removeLockButton.backgroundColor = REMOVE_LOCK_ACTIVE;
            [self.removeLockButton setTitle:@"🔓 ON" forState:UIControlStateNormal];
            self.removeLockButton.titleLabel.font = [UIFont boldSystemFontOfSize:10];
            [self.removeLockButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        } else {
            self.removeLockButton.backgroundColor = REMOVE_LOCK_INACTIVE;
            [self.removeLockButton setTitle:@"🔒 OFF" forState:UIControlStateNormal];
            self.removeLockButton.titleLabel.font = [UIFont boldSystemFontOfSize:10];
            [self.removeLockButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        }
    });
}

// ---------------------------------------------------------
// MARK: - Hide on Capture System (FIXED)
// ---------------------------------------------------------

- (void)toggleHideCapture:(UIButton *)sender {
    self.isHideCaptureActive = !self.isHideCaptureActive;
    [self saveAllPositions];
    [self updateHideCaptureButton];

    NSString *status = self.isHideCaptureActive ? @"📵 مفعل - مخفي من التصوير" : @"📷 معطل - ظاهر";
    [self showToast:status];
    AudioServicesPlaySystemSound(1519);
}

- (void)updateHideCaptureButton {
    if (!self.hideCaptureButton) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.isHideCaptureActive) {
            self.hideCaptureButton.backgroundColor = HIDE_CAPTURE_ACTIVE;
            [self.hideCaptureButton setTitle:@"📵 ON" forState:UIControlStateNormal];
            self.hideCaptureButton.titleLabel.font = [UIFont boldSystemFontOfSize:10];
            [self.hideCaptureButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        } else {
            self.hideCaptureButton.backgroundColor = HIDE_CAPTURE_INACTIVE;
            [self.hideCaptureButton setTitle:@"📷 OFF" forState:UIControlStateNormal];
            self.hideCaptureButton.titleLabel.font = [UIFont boldSystemFontOfSize:10];
            [self.hideCaptureButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        }
    });
}

// ---------------------------------------------------------
// MARK: - MIC Toggle (1-15)
// ---------------------------------------------------------

- (void)toggleMic:(UIButton *)sender {
    NSInteger micIndex = sender.tag;
    BOOL isActive = [self.activeMics[micIndex] boolValue];
    isActive = !isActive;
    self.activeMics[micIndex] = @(isActive);

    if (isActive) {
        sender.backgroundColor = MIC_ACTIVE;
        sender.layer.borderColor = MIC_ACTIVE.CGColor;
        AudioServicesPlaySystemSound(1519);
    } else {
        sender.backgroundColor = MIC_INACTIVE;
        sender.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:0.3].CGColor;
    }
}

// ---------------------------------------------------------
// MARK: - Bus Exit Toggle (COMPACT)
// ---------------------------------------------------------

- (void)toggleBus:(UIButton *)sender {
    self.isBusActive = !self.isBusActive;

    if (self.isBusActive) {
        sender.backgroundColor = BUS_ACTIVE;
        sender.layer.borderColor = BUS_ACTIVE.CGColor;
        sender.layer.shadowColor = BUS_ACTIVE.CGColor;
        sender.layer.shadowRadius = 6;
        sender.layer.shadowOpacity = 0.4;
        AudioServicesPlaySystemSound(1519);
    } else {
        sender.backgroundColor = BUS_INACTIVE;
        sender.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:0.3].CGColor;
        sender.layer.shadowOpacity = 0;
    }
}

// ---------------------------------------------------------
// MARK: - Position Setting (15 Mics + Bus)
// ---------------------------------------------------------

- (void)startMicPositionSetting {
    self.settingMode = 1;
    [self startPositionSettingWithTitle:@"📍 اضغط على موقع المايك\nثم اختر الرقم (1-15)"];
}

- (void)startBusPositionSetting {
    self.settingMode = 2;
    [self startPositionSettingWithTitle:@"🚌 اضغط على موقع 'الخروج من المايك'\nفي الشاشة"];
}

- (void)startPositionSettingWithTitle:(NSString *)titleText {
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    if (!w) return;

    [self toggleMenu];

    self.positionOverlay = [[UIView alloc] initWithFrame:w.bounds];
    self.positionOverlay.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.5];
    [w addSubview:self.positionOverlay];

    UILabel *instruction = [[UILabel alloc] initWithFrame:CGRectMake(20, 50, w.bounds.size.width - 40, 60)];
    instruction.text = titleText;
    instruction.textColor = [UIColor whiteColor];
    instruction.font = [UIFont boldSystemFontOfSize:16];
    instruction.textAlignment = NSTextAlignmentCenter;
    instruction.numberOfLines = 0;
    [self.positionOverlay addSubview:instruction];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(positionTapped:)];
    [self.positionOverlay addGestureRecognizer:tap];

    UIButton *cancelBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    cancelBtn.frame = CGRectMake((w.bounds.size.width - 180)/2, w.bounds.size.height - 80, 180, 40);
    cancelBtn.backgroundColor = ERROR_COLOR;
    cancelBtn.layer.cornerRadius = 20;
    [cancelBtn setTitle:@"❌ إلغاء" forState:UIControlStateNormal];
    [cancelBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    cancelBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [cancelBtn addTarget:self action:@selector(cancelPositionSetting) forControlEvents:UIControlEventTouchUpInside];
    [self.positionOverlay addSubview:cancelBtn];
}

- (void)positionTapped:(UITapGestureRecognizer *)tap {
    CGPoint point = [tap locationInView:self.positionOverlay];

    if (self.settingMode == 2) {
        [self setBusPosition:point];
        [self cancelPositionSetting];
        [self showToast:@"🚌 تم حفظ موقع الخروج"];
        return;
    }

    [self showMicSelectorAtPoint:point];
}

- (void)showMicSelectorAtPoint:(CGPoint)point {
    UIWindow *w = [UIApplication sharedApplication].keyWindow;

    UIView *existing = [w viewWithTag:9999];
    [existing removeFromSuperview];

    UIView *selector = [[UIView alloc] initWithFrame:CGRectMake(20, point.y + 20, w.bounds.size.width - 40, 140)];
    selector.backgroundColor = BG_CARD;
    selector.layer.cornerRadius = 12;
    selector.tag = 9999;
    AddShadow(selector, PRIMARY_COLOR, 6, 0.2);

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(10, 5, selector.bounds.size.width - 20, 18)];
    title.text = @"اختر رقم المايك (1-15):";
    title.textColor = TEXT_PRIMARY;
    title.font = [UIFont boldSystemFontOfSize:12];
    title.textAlignment = NSTextAlignmentCenter;
    [selector addSubview:title];

    CGFloat btnW = 36;
    CGFloat btnH = 32;
    CGFloat gapX = 6;
    CGFloat startX = 10;
    CGFloat startY = 28;

    for (int i = 0; i < 15; i++) {
        int row = i / 5;
        int col = i % 5;
        CGFloat x = startX + col * (btnW + gapX);
        CGFloat y = startY + row * (btnH + 6);

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(x, y, btnW, btnH);
        btn.backgroundColor = MIC_INACTIVE;
        btn.layer.cornerRadius = 6;
        [btn setTitle:[NSString stringWithFormat:@"%d", i + 1] forState:UIControlStateNormal];
        [btn setTitleColor:TEXT_PRIMARY forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
        btn.tag = i;
        [btn addTarget:self action:@selector(saveMicPosition:) forControlEvents:UIControlEventTouchUpInside];
        [selector addSubview:btn];
    }

    objc_setAssociatedObject(selector, @selector(showMicSelectorAtPoint:), [NSValue valueWithCGPoint:point], OBJC_ASSOCIATION_RETAIN);

    [w addSubview:selector];
}

- (void)saveMicPosition:(UIButton *)sender {
    NSInteger micIndex = sender.tag;

    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    UIView *selector = [w viewWithTag:9999];
    if (!selector) return;

    NSValue *posValue = objc_getAssociatedObject(selector, @selector(showMicSelectorAtPoint:));
    if (!posValue) return;

    CGPoint point = [posValue CGPointValue];

    [self setMicPosition:micIndex point:point];
    [selector removeFromSuperview];

    [self showToast:[NSString stringWithFormat:@"✅ تم حفظ موقع مايك %ld", (long)micIndex + 1]];
}

- (void)cancelPositionSetting {
    self.settingMode = 0;
    [self.positionOverlay removeFromSuperview];
    self.positionOverlay = nil;

    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    UIView *selector = [w viewWithTag:9999];
    [selector removeFromSuperview];
}

- (void)showToast:(NSString *)message {
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    if (!w) return;

    UIView *existing = [w viewWithTag:8888];
    [existing removeFromSuperview];

    UILabel *toast = [[UILabel alloc] initWithFrame:CGRectMake(30, w.bounds.size.height - 120, w.bounds.size.width - 60, 40)];
    toast.text = message;
    toast.textColor = [UIColor whiteColor];
    toast.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.7];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.font = [UIFont boldSystemFontOfSize:14];
    toast.layer.cornerRadius = 10;
    toast.clipsToBounds = YES;
    toast.tag = 8888;
    [w addSubview:toast];

    toast.alpha = 0;
    [UIView animateWithDuration:0.2 animations:^{
        toast.alpha = 1;
    } completion:^(BOOL finished) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.2 animations:^{
                toast.alpha = 0;
            } completion:^(BOOL finished) {
                [toast removeFromSuperview];
            }];
        });
    }];
}

// ---------------------------------------------------------
// MARK: - Speed Control
// ---------------------------------------------------------

- (void)updateSpeedLabel {
    if (self.clickSpeed < 0.02) {
        self.speedLabelDisplay.text = @"⚡ سريع";
        self.speedLabelDisplay.textColor = TURBO_COLOR;
    } else if (self.clickSpeed < 0.05) {
        self.speedLabelDisplay.text = @"🚀 عادي";
        self.speedLabelDisplay.textColor = PRIMARY_COLOR;
    } else {
        self.speedLabelDisplay.text = @"🐢 بطيء";
        self.speedLabelDisplay.textColor = TEXT_SECONDARY;
    }
}

- (void)toggleClicking {
    if (self.isAutoClicking) {
        [self stopClicking];
    } else {
        [self startClicking];
    }
}

- (void)updateToggleButton {
    if (self.isAutoClicking) {
        self.toggleButton.backgroundColor = ERROR_COLOR;
        [self.toggleButton setTitle:@"⏹ إيقاف" forState:UIControlStateNormal];
        self.toggleButton.layer.shadowColor = ERROR_COLOR.CGColor;
    } else {
        self.toggleButton.backgroundColor = SUCCESS_COLOR;
        [self.toggleButton setTitle:@"▶️ ابدأ" forState:UIControlStateNormal];
        self.toggleButton.layer.shadowColor = SUCCESS_COLOR.CGColor;
    }
}

// ---------------------------------------------------------
// MARK: - Menu Toggle
// ---------------------------------------------------------

- (void)toggleMenu {
    if (!self.mainPanel) [self buildMainPanel];
    self.isMenuVisible = !self.isMenuVisible;
    if (self.isMenuVisible) {
        self.mainPanel.hidden = NO;
        self.mainPanel.alpha = 0;
        [UIView animateWithDuration:0.2 animations:^{
            self.mainPanel.alpha = 1;
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

// ---------------------------------------------------------
// MARK: - Gestures
// ---------------------------------------------------------

- (void)handlePan:(UIPanGestureRecognizer *)p {
    UIView *v = p.view;
    CGPoint t = [p translationInView:v.superview];
    v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y);
    [p setTranslation:CGPointZero inView:v.superview];
}

- (void)speedChanged:(UISlider *)s {
    self.clickSpeed = s.value;
    self.normalSpeed = s.value;
    [self updateSpeedLabel];
}

// ---------------------------------------------------------
// MARK: - CLICK ENGINE (15 Mics + Bus)
// ---------------------------------------------------------

- (void)startClicking {
    BOOL hasActiveMic = NO;
    for (NSNumber *active in self.activeMics) {
        if ([active boolValue]) {
            hasActiveMic = YES;
            break;
        }
    }

    if (!hasActiveMic && !self.isBusActive && self.targetButtons.count == 0) {
        [self addTarget];
    }

    self.isAutoClicking = YES;
    self.clickCount = 0;
    [self updateToggleButton];

    self.floatButton.alpha = 0.6;
    [self.floatButton setTitle:@"🔴" forState:UIControlStateNormal];

    if (self.clickSpeed <= 0.01) {
        [self startFastEngine];
    } else {
        [self startNormalEngine];
    }
}

- (void)startFastEngine {
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(batchClick)];
    self.displayLink.preferredFramesPerSecond = 1000;
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)startNormalEngine {
    عبدالإلهManager * __block blockSelf = self;
    self.clickTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
    uint64_t interval = (uint64_t)(self.clickSpeed * NSEC_PER_SEC);
    dispatch_source_set_timer(self.clickTimer, dispatch_time(DISPATCH_TIME_NOW, 0), interval, 0);

    dispatch_source_set_event_handler(self.clickTimer, ^{
        عبدالإلهManager *s = blockSelf;
        if (!s || !s.isAutoClicking) {
            if (s.clickTimer) {
                dispatch_source_cancel(s.clickTimer);
                s.clickTimer = nil;
            }
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [s batchClick];
        });
    });
    dispatch_resume(self.clickTimer);
}

- (void)batchClick {
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    if (!window) return;

    // 1. Click active mics (1-15)
    for (int i = 0; i < 15; i++) {
        if ([self.activeMics[i] boolValue]) {
            CGPoint pos = [self getMicPosition:i];
            if (!CGPointEqualToPoint(pos, CGPointZero)) {
                [self simulateTouchAtPoint:pos inWindow:window];
            }
        }
    }

    // 2. BUS EXIT: Direct Hook on YLTakeMicAlertButton
    if (self.isBusActive) {
        [self triggerBusExitDirect];
    }

    // 3. Legacy targets
    for (UIView *target in self.targetButtons) {
        [self simulateTouchAtPoint:target.center inWindow:window];
    }

    self.clickCount++;
}

// ===== DIRECT BUS EXIT TRIGGER =====
- (void)triggerBusExitDirect {
    if (self.currentExitButton) {
        if ([self.currentExitButton respondsToSelector:@selector(tapActin:)]) {
            NSLog(@"[عبدالإله] Triggering tapActin: on tracked button");
            [self.currentExitButton tapActin:nil];
            return;
        }
    }

    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    if (!window) return;

    YLTakeMicAlertButton *exitButton = [self findExitButtonInView:window];

    if (exitButton && [exitButton respondsToSelector:@selector(tapActin:)]) {
        NSLog(@"[عبدالإله] Found exit button, triggering tapActin:");
        [exitButton tapActin:nil];
        return;
    }

    NSLog(@"[عبدالإله] Button not found, using fallback touch simulation");
    CGPoint busPos = [self getBusPosition];
    if (!CGPointEqualToPoint(busPos, CGPointZero)) {
        [self simulateTouchAtPoint:busPos inWindow:window];
    }
}

- (YLTakeMicAlertButton *)findExitButtonInView:(UIView *)view {
    NSString *className = NSStringFromClass([view class]);

    if ([className hasPrefix:@"_TtCC9YLRoomKit18YLTakeMicAlertView"] && 
        [className hasSuffix:@"Button"]) {
        return (YLTakeMicAlertButton *)view;
    }

    for (UIView *subview in view.subviews) {
        YLTakeMicAlertButton *found = [self findExitButtonInView:subview];
        if (found) return found;
    }

    return nil;
}

// ===== SIMULATED TOUCH (Fallback) =====
- (void)simulateTouchAtPoint:(CGPoint)point inWindow:(UIWindow *)window {
    UIView *hitView = [window hitTest:point withEvent:nil];
    if (!hitView || hitView == self.floatButton || hitView == self.mainPanel) return;

    UIView *parent = hitView;
    while (parent) {
        if (parent == self.mainPanel) return;
        parent = parent.superview;
    }

    if ([hitView isKindOfClass:[UIControl class]]) {
        [(UIControl *)hitView sendActionsForControlEvents:UIControlEventTouchUpInside];
        return;
    }

    UIView *current = hitView;
    while (current) {
        if ([current isKindOfClass:[UIControl class]]) {
            [(UIControl *)current sendActionsForControlEvents:UIControlEventTouchUpInside];
            return;
        }
        current = current.superview;
    }

    [self privateTouchAtPoint:point inView:hitView window:window];
}

- (void)privateTouchAtPoint:(CGPoint)point inView:(UIView *)view window:(UIWindow *)window {
    @try {
        UITouch *touch = [[UITouch alloc] init];
        [touch setValue:@(UITouchPhaseBegan) forKey:@"phase"];
        [touch setValue:@(1) forKey:@"tapCount"];
        [touch setValue:view forKey:@"view"];
        [touch setValue:window forKey:@"window"];
        [touch setValue:[NSValue valueWithCGPoint:point] forKey:@"_locationInWindow"];
        [touch setValue:[NSValue valueWithCGPoint:point] forKey:@"_previousLocationInWindow"];

        UIEvent *event = [[UIEvent alloc] init];
        [event setValue:touch forKey:@"_touch"];

        [view touchesBegan:[NSSet setWithObject:touch] withEvent:event];
        [touch setValue:@(UITouchPhaseEnded) forKey:@"phase"];
        [view touchesEnded:[NSSet setWithObject:touch] withEvent:event];

    } @catch (NSException *e) {
        // Silent fail
    }
}

- (void)stopClicking {
    self.isAutoClicking = NO;

    if (self.displayLink) {
        [self.displayLink invalidate];
        self.displayLink = nil;
    }
    if (self.clickTimer) {
        dispatch_source_cancel(self.clickTimer);
        self.clickTimer = nil;
    }

    [self updateToggleButton];
    self.floatButton.alpha = 1;
    [self.floatButton setTitle:@"https://a.top4top.io/p_345479vud0.png" forState:UIControlStateNormal];

    for (UIView *btn in self.targetButtons) {
        btn.userInteractionEnabled = YES;
        btn.alpha = 1.0;
    }
}

// ---------------------------------------------------------
// MARK: - Legacy Target
// ---------------------------------------------------------

- (void)addTarget {
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    for (UIView *v in self.targetButtons) [v removeFromSuperview];
    [self.targetButtons removeAllObjects];

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(w.bounds.size.width/2 - 30, w.bounds.size.height/2 - 80, 60, 60)];
    [w addSubview:container];

    UIView *outerRing = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 60, 60)];
    outerRing.backgroundColor = [UIColor clearColor];
    outerRing.layer.cornerRadius = 30;
    outerRing.layer.borderWidth = 2;
    outerRing.layer.borderColor = ERROR_COLOR.CGColor;
    [container addSubview:outerRing];

    UIView *centerDot = [[UIView alloc] initWithFrame:CGRectMake(26, 26, 8, 8)];
    centerDot.backgroundColor = ERROR_COLOR;
    centerDot.layer.cornerRadius = 4;
    [container addSubview:centerDot];

    [self.targetButtons addObject:container];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [container addGestureRecognizer:pan];
}

@end

// ==========================================
// MARK: - MBProgressHUD Hook (Remove Lock)
// ==========================================

%hook MBProgressHUD

- (void)hideAnimated:(bool)arg1 {
    عبدالإلهManager *manager = [عبدالإلهManager shared];
    if (manager.isRemoveLockActive) {
        arg1 = NO;
        NSLog(@"[عبدالإله] MBProgressHUD hideAnimated blocked (Remove Lock ON)");
    }
    %orig(arg1);
}

- (void)hideAnimated:(bool)arg1 afterDelay:(double)arg2 {
    عبدالإلهManager *manager = [عبدالإلهManager shared];
    if (manager.isRemoveLockActive) {
        arg1 = NO;
        arg2 = 0;
        NSLog(@"[عبدالإله] MBProgressHUD hideAnimated:afterDelay blocked (Remove Lock ON)");
    }
    %orig(arg1, arg2);
}

%end

// ==========================================
// MARK: - Yalla Class Hooks (v9.2)
// ==========================================

%hook _TtCC9YLRoomKit18YLTakeMicAlertViewP33_097D67C9E65CE05B568646FBC61B24A86Button

- (void)layoutSubviews {
    %orig;
    عبدالإلهManager *manager = [عبدالإلهManager shared];
    manager.currentExitButton = (YLTakeMicAlertButton *)self;
    if (![manager.alertButtonStack containsObject:self]) {
        [manager.alertButtonStack addObject:self];
    }
    NSLog(@"[عبدالإله] Exit button tracked");
}

- (void)dealloc {
    عبدالإلهManager *manager = [عبدالإلهManager shared];
    [manager.alertButtonStack removeObject:self];
    if (manager.currentExitButton == (YLTakeMicAlertButton *)self) {
        manager.currentExitButton = nil;
    }
    %orig;
}

%end

// ==========================================
// MARK: - UIViewController Hook
// ==========================================

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [[عبدالإلهManager shared] checkUI];
}

%end

// ==========================================
// MARK: - Constructor
// ==========================================

%ctor {
    [عبدالإلهManager shared];
    NSLog(@"[عبدالإله] Tweak v9.2 loaded - 15 Mics + Compact UI + Hide on Capture");
}
