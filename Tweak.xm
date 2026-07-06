#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

#define SHARED_STATE   @"/tmp/com.abdulilah.state.plist"

#define PRIMARY_COLOR    [UIColor colorWithRed:0.00 green:0.60 blue:1.00 alpha:1.0]
#define SUCCESS_COLOR    [UIColor colorWithRed:0.00 green:0.50 blue:1.00 alpha:1.0]
#define ERROR_COLOR      [UIColor colorWithRed:0.80 green:0.20 blue:0.30 alpha:1.0]
#define BG_DARK          [UIColor colorWithRed:0.05 green:0.05 blue:0.08 alpha:0.95]
#define BG_CARD          [UIColor colorWithRed:0.10 green:0.10 blue:0.15 alpha:0.90]
#define TEXT_PRIMARY     [UIColor whiteColor]
#define TEXT_SECONDARY   [UIColor colorWithRed:0.60 green:0.60 blue:0.70 alpha:1.0]

@interface AbdulilahOverlayWindow : UIWindow
@end
@implementation AbdulilahOverlayWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self) return nil;
    return hit;
}
@end

@interface AbdulilahManager : NSObject

@property (nonatomic, strong) UIView *mainPanel;
@property (nonatomic, strong) UIButton *floatButton;
@property (nonatomic, strong) UIButton *toggleBtn;
@property (nonatomic, strong) UISlider *speedSlider;
@property (nonatomic, strong) UILabel *speedLabel;
@property (nonatomic, assign) BOOL autoTapEnabled;
@property (nonatomic, assign) float currentSpeed;
@property (nonatomic, assign) BOOL isMenuVisible;
@property (nonatomic, assign) float transparencyValue;
@property (nonatomic, strong) NSTimer *uiGuardTimer;

@property (nonatomic, assign) UIBackgroundTaskIdentifier bgTask;
@property (nonatomic, strong) AVAudioPlayer *silentAudioPlayer;

@property (nonatomic, strong) UIView *tapMarker;
@property (nonatomic, assign) BOOL showMarker;

@property (nonatomic, strong) NSTimer *syncTimer;
@property (nonatomic, assign) dispatch_source_t fileMonitorSource;
@property (nonatomic, strong) AbdulilahOverlayWindow *overlayWindow;

@property (nonatomic, weak) UIView *cachedTapTarget;
@property (nonatomic, weak) UIWindow *cachedGameWindow;
@property (nonatomic, strong) NSSet *emptyTouches;
@property (nonatomic, strong) UIEvent *dummyEvent;
@property (nonatomic, assign) NSUInteger tapGeneration;

+ (instancetype)shared;
- (void)showFloatingButton;
- (void)toggleMenu;
- (void)saveInstanceState;
- (void)loadInstanceState;

@end

@implementation AbdulilahManager

+ (instancetype)shared {
    static AbdulilahManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AbdulilahManager alloc] init];
        instance.currentSpeed = 0.008f;
        instance.transparencyValue = 1.0;
        instance.showMarker = NO;
        [instance startUIGuard];
        instance.syncTimer = [NSTimer timerWithTimeInterval:0.05 target:instance selector:@selector(syncTimerFired) userInfo:nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:instance.syncTimer forMode:NSRunLoopCommonModes];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [instance showTapMarker];
            [instance startBackgroundKeepAlive];
        });
        [instance startFileMonitoring];
    });
    return instance;
}

- (AbdulilahOverlayWindow *)overlayWindow {
    if (!_overlayWindow) {
        _overlayWindow = [[AbdulilahOverlayWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        _overlayWindow.windowLevel = UIWindowLevelAlert + 100.0;
        _overlayWindow.backgroundColor = [UIColor clearColor];
        _overlayWindow.userInteractionEnabled = YES;
        _overlayWindow.hidden = NO;
    }
    return _overlayWindow;
}

- (void)startUIGuard {
    self.uiGuardTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(checkUI) userInfo:nil repeats:YES];
}

- (void)checkUI {
    [self overlayWindow];
    self.overlayWindow.windowLevel = UIWindowLevelAlert + 100.0;
    if (!self.floatButton || self.floatButton.superview != self.overlayWindow) {
        [self showFloatingButton];
    } else {
        [self.overlayWindow bringSubviewToFront:self.floatButton];
    }
    if (self.isMenuVisible && self.mainPanel) {
        if (self.mainPanel.superview != self.overlayWindow) {
            [self.overlayWindow addSubview:self.mainPanel];
        }
        [self.overlayWindow bringSubviewToFront:self.mainPanel];
    }
    if (self.tapMarker && self.showMarker && self.tapMarker.superview != self.overlayWindow) {
        [self.overlayWindow addSubview:self.tapMarker];
        [self.overlayWindow bringSubviewToFront:self.tapMarker];
    }
    if (!self.silentAudioPlayer || !self.silentAudioPlayer.isPlaying) {
        [self startBackgroundKeepAlive];
    }
}

#pragma mark - File Monitor (Cross-Instance Sync)

- (void)startFileMonitoring {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (![[NSFileManager defaultManager] fileExistsAtPath:SHARED_STATE]) {
            [@{} writeToFile:SHARED_STATE atomically:YES];
        }
        int fd = open([SHARED_STATE UTF8String], O_EVTONLY);
        if (fd < 0) return;
        dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, fd,
            DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_DELETE,
            dispatch_get_main_queue());
        dispatch_source_set_event_handler(source, ^{
            [self loadInstanceState];
        });
        dispatch_source_set_cancel_handler(source, ^{
            close(fd);
        });
        dispatch_resume(source);
        self.fileMonitorSource = source;
    });
}

#pragma mark - Floating Button

- (void)showFloatingButton {
    if (self.floatButton) {
        [self.floatButton.superview removeFromSuperview];
        self.floatButton = nil;
    }
    UIWindow *w = self.overlayWindow;
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

#pragma mark - Tap Marker

- (void)showTapMarker {
    if (self.tapMarker) {
        [self.tapMarker removeFromSuperview];
        self.tapMarker = nil;
    }
    UIWindow *w = self.overlayWindow;
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

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapMarkerPan:)];
    [marker addGestureRecognizer:pan];

    [w addSubview:marker];
    self.tapMarker = marker;
    self.showMarker = YES;
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:SHARED_STATE];
    if (dict[@"cx"] && dict[@"cy"]) {
        CGFloat x = [dict[@"cx"] floatValue];
        CGFloat y = [dict[@"cy"] floatValue];
        if (x > 0 && y > 0) {
            marker.center = CGPointMake(x, y);
        }
    }
    [self loadInstanceState];

    marker.alpha = 0;
    marker.transform = CGAffineTransformMakeScale(0.5, 0.5);
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0.8 options:0 animations:^{
        marker.alpha = 1;
        marker.transform = CGAffineTransformIdentity;
    } completion:nil];
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
    self.cachedTapTarget = nil;
    self.cachedGameWindow = nil;
    if (p.state == UIGestureRecognizerStateEnded) {
        [self saveInstanceState];
    }
}

- (void)syncTimerFired {
    [self loadInstanceState];
}

- (void)saveInstanceState {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    if (self.tapMarker) {
        dict[@"cx"] = @(self.tapMarker.center.x);
        dict[@"cy"] = @(self.tapMarker.center.y);
    }
    dict[@"tapOn"] = @(self.autoTapEnabled);
    dict[@"speed"] = @(self.currentSpeed);
    [dict writeToFile:SHARED_STATE atomically:YES];
}

- (void)loadInstanceState {
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:SHARED_STATE];
    if (!dict) return;
    if (dict[@"cx"] && dict[@"cy"] && self.tapMarker) {
        CGFloat x = [dict[@"cx"] floatValue];
        CGFloat y = [dict[@"cy"] floatValue];
        if (x > 0 && y > 0) {
            self.tapMarker.center = CGPointMake(x, y);
            self.cachedTapTarget = nil;
            self.cachedGameWindow = nil;
        }
    }
    float spd = [dict[@"speed"] floatValue];
    if (spd > 0) {
        self.currentSpeed = spd;
        if (self.autoTapEnabled) {
            [self restartTapWithSpeed:spd];
        }
    }
    BOOL shouldTap = [dict[@"tapOn"] boolValue];
    if (shouldTap && !self.autoTapEnabled) {
        [self startTap];
    } else if (!shouldTap && self.autoTapEnabled) {
        [self stopTap];
    }
}

- (CGPoint)tapMarkerPosition {
    if (!self.tapMarker || !self.showMarker) return CGPointZero;
    return self.tapMarker.center;
}

#pragma mark - Main Panel

- (void)buildMainPanel {
    if (self.mainPanel) return;
    UIWindow *w = self.overlayWindow;
    CGFloat pw = 220;
    CGFloat px = (w.bounds.size.width - pw) / 2;
    CGFloat py = 60;
    self.mainPanel = [[UIView alloc] initWithFrame:CGRectMake(px, py, pw, 190)];
    self.mainPanel.backgroundColor = BG_DARK;
    self.mainPanel.layer.cornerRadius = 20;
    self.mainPanel.clipsToBounds = YES;
    self.mainPanel.alpha = 0;
    self.mainPanel.hidden = YES;
    self.mainPanel.layer.borderWidth = 1;
    self.mainPanel.layer.borderColor = [PRIMARY_COLOR colorWithAlphaComponent:0.3].CGColor;
    [w addSubview:self.mainPanel];

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

    self.speedLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, y, pw - 24, 16)];
    self.speedLabel.text = [NSString stringWithFormat:@"السرعة: %.3f ث", self.currentSpeed];
    self.speedLabel.textColor = TEXT_PRIMARY;
    self.speedLabel.font = [UIFont systemFontOfSize:10];
    [self.mainPanel addSubview:self.speedLabel];
    y += 18;

    self.speedSlider = [[UISlider alloc] initWithFrame:CGRectMake(12, y, pw - 24, 20)];
    self.speedSlider.minimumValue = 0.001f;
    self.speedSlider.maximumValue = 0.1f;
    self.speedSlider.value = self.currentSpeed;
    self.speedSlider.tintColor = PRIMARY_COLOR;
    self.speedSlider.minimumTrackTintColor = PRIMARY_COLOR;
    self.speedSlider.maximumTrackTintColor = [UIColor colorWithWhite:0.3 alpha:1];
    [self.speedSlider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.mainPanel addSubview:self.speedSlider];
    y += 28;

    UIView *creditBox = [[UIView alloc] initWithFrame:CGRectMake(12, y, pw - 24, 28)];
    creditBox.backgroundColor = BG_CARD;
    creditBox.layer.cornerRadius = 14;
    [self.mainPanel addSubview:creditBox];

    UILabel *creditLbl = [[UILabel alloc] initWithFrame:CGRectMake(8, 0, pw - 40, 28)];
    creditLbl.text = @"حقوق البرمجة: عبدالإله";
    creditLbl.textColor = [PRIMARY_COLOR colorWithAlphaComponent:0.7];
    creditLbl.font = [UIFont boldSystemFontOfSize:9];
    creditLbl.textAlignment = NSTextAlignmentCenter;
    [creditBox addSubview:creditLbl];

    y += 34;

    CGRect f = self.mainPanel.frame;
    f.size.height = y + 8;
    self.mainPanel.frame = f;

    UIPanGestureRecognizer *panP = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.mainPanel addGestureRecognizer:panP];
}

#pragma mark - Background Keep Alive (Silent Audio)

- (NSData *)generateSilentWAV {
    int sampleRate = 44100;
    short numChannels = 1;
    short bitsPerSample = 16;
    int numSamples = sampleRate * 2;
    int dataSize = numSamples * (bitsPerSample / 8);
    int fileSize = 44 + dataSize;

    NSMutableData *wav = [NSMutableData dataWithLength:fileSize];
    unsigned char *bytes = (unsigned char *)[wav mutableBytes];
    int offset = 0;

    memcpy(bytes + offset, "RIFF", 4); offset += 4;
    uint32_t chunkSize = fileSize - 8;
    memcpy(bytes + offset, &chunkSize, 4); offset += 4;
    memcpy(bytes + offset, "WAVE", 4); offset += 4;

    memcpy(bytes + offset, "fmt ", 4); offset += 4;
    uint32_t subchunk1Size = 16;
    memcpy(bytes + offset, &subchunk1Size, 4); offset += 4;
    uint16_t audioFormat = 1;
    memcpy(bytes + offset, &audioFormat, 2); offset += 2;
    memcpy(bytes + offset, &numChannels, 2); offset += 2;
    memcpy(bytes + offset, &sampleRate, 4); offset += 4;
    uint32_t byteRate = sampleRate * numChannels * (bitsPerSample / 8);
    memcpy(bytes + offset, &byteRate, 4); offset += 4;
    uint16_t blockAlign = numChannels * (bitsPerSample / 8);
    memcpy(bytes + offset, &blockAlign, 2); offset += 2;
    memcpy(bytes + offset, &bitsPerSample, 2); offset += 2;

    memcpy(bytes + offset, "data", 4); offset += 4;
    memcpy(bytes + offset, &dataSize, 4); offset += 4;

    return wav;
}

- (void)startBackgroundKeepAlive {
    @try {
        [self.silentAudioPlayer stop];
        self.silentAudioPlayer = nil;

        self.bgTask = [[UIApplication sharedApplication] beginBackgroundTaskWithName:@"AbdulilahKeepAlive" expirationHandler:^{
            [self stopBackgroundKeepAlive];
            [self startBackgroundKeepAlive];
        }];

        NSError *err = nil;
        AVAudioSession *session = [AVAudioSession sharedInstance];
        [session setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:&err];
        [session setActive:YES error:&err];

        NSData *wavData = [self generateSilentWAV];
        self.silentAudioPlayer = [[AVAudioPlayer alloc] initWithData:wavData error:&err];
        self.silentAudioPlayer.numberOfLoops = -1;
        self.silentAudioPlayer.volume = 0.0;
        [self.silentAudioPlayer prepareToPlay];
        [self.silentAudioPlayer play];
    } @catch (NSException *e) {
        NSLog(@"[عبدالإله] startBackgroundKeepAlive exception: %@", e);
    }
}

- (void)stopBackgroundKeepAlive {
    @try {
        [self.silentAudioPlayer stop];
        self.silentAudioPlayer = nil;

        AVAudioSession *session = [AVAudioSession sharedInstance];
        [session setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];

        if (self.bgTask != UIBackgroundTaskInvalid) {
            [[UIApplication sharedApplication] endBackgroundTask:self.bgTask];
            self.bgTask = UIBackgroundTaskInvalid;
        }
    } @catch (NSException *e) {
        NSLog(@"[عبدالإله] stopBackgroundKeepAlive exception: %@", e);
    }
}

#pragma mark - Tap Engine

- (void)sliderChanged:(UISlider *)sender {
    CGFloat val = sender.value;
    if (val < 0.001f) val = 0.001f;
    self.currentSpeed = val;
    self.speedLabel.text = [NSString stringWithFormat:@"السرعة: %.3f ث", self.currentSpeed];
    if (self.autoTapEnabled) [self restartTapWithSpeed:self.currentSpeed];
    [self saveInstanceState];
}

- (void)restartTapWithSpeed:(float)speed {
    self.tapGeneration++;
    [self startTapWithSpeed:speed];
}

- (void)toggleStartStop {
    @try {
        if (self.autoTapEnabled) {
            NSMutableDictionary *dict = [NSMutableDictionary dictionary];
            dict[@"tapOn"] = @(NO);
            if (self.tapMarker) {
                dict[@"cx"] = @(self.tapMarker.center.x);
                dict[@"cy"] = @(self.tapMarker.center.y);
            }
            dict[@"speed"] = @(self.currentSpeed);
            [dict writeToFile:SHARED_STATE atomically:YES];
            [self stopTap];
        } else {
            NSMutableDictionary *dict = [NSMutableDictionary dictionary];
            dict[@"tapOn"] = @(YES);
            if (self.tapMarker) {
                dict[@"cx"] = @(self.tapMarker.center.x);
                dict[@"cy"] = @(self.tapMarker.center.y);
            }
            dict[@"speed"] = @(self.currentSpeed);
            [dict writeToFile:SHARED_STATE atomically:YES];
            [self startTap];
        }
    } @catch (NSException *e) {
        NSLog(@"[عبدالإله] toggleStartStop exception: %@", e);
    }
}

- (void)startTap {
    @try {
        if (self.autoTapEnabled) return;
        [self startTapInternal];
        [self saveInstanceState];
    } @catch (NSException *e) {
        NSLog(@"[عبدالإله] startTap exception: %@", e);
    }
}

- (void)startTapInternal {
    @try {
        if (self.autoTapEnabled) return;
        self.autoTapEnabled = YES;
        self.cachedTapTarget = nil;
        self.cachedGameWindow = nil;
        [self startTapWithSpeed:self.currentSpeed];
        if (self.toggleBtn) {
            [self.toggleBtn setTitle:@"إيقاف" forState:UIControlStateNormal];
            self.toggleBtn.backgroundColor = ERROR_COLOR;
        }
    } @catch (NSException *e) {
        NSLog(@"[عبدالإله] startTapInternal exception: %@", e);
    }
}

- (void)startTapWithSpeed:(float)speed {
    if (speed < 0.001f) speed = 0.001f;
    self.tapGeneration++;
    NSUInteger myGen = self.tapGeneration;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            while (self.autoTapEnabled && self.tapGeneration == myGen) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self tapRealTarget];
                });
                [NSThread sleepForTimeInterval:speed];
            }
        }
    });
}

- (void)stopTap {
    @try {
        [self stopTapInternal];
        [self saveInstanceState];
    } @catch (NSException *e) {
        NSLog(@"[عبدالإله] stopTap exception: %@", e);
    }
}

- (void)stopTapInternal {
    self.autoTapEnabled = NO;
    if (self.toggleBtn) {
        [self.toggleBtn setTitle:@"تشغيل" forState:UIControlStateNormal];
        self.toggleBtn.backgroundColor = SUCCESS_COLOR;
    }
}

- (void)tapRealTarget {
    @try {
        if (!self.autoTapEnabled) return;
        CGPoint tapPt = [self tapMarkerPosition];
        if (tapPt.x <= 0 && tapPt.y <= 0) return;

        UIView *targetView = self.cachedTapTarget;
        UIWindow *gameWindow = self.cachedGameWindow;

        if (!targetView || targetView.hidden || !targetView.userInteractionEnabled || !gameWindow) {
            for (UIWindow *window in [[UIApplication sharedApplication] windows]) {
                if (window == self.overlayWindow || window.hidden) continue;
                if (window.windowLevel < UIWindowLevelNormal) continue;
                UIView *hit = [window hitTest:tapPt withEvent:nil];
                if (hit && hit != window && !hit.hidden && hit.userInteractionEnabled) {
                    targetView = hit;
                    gameWindow = window;
                    break;
                }
            }
            if (!targetView) {
                UIWindow *w = [UIApplication sharedApplication].keyWindow;
                targetView = [w hitTest:tapPt withEvent:nil];
                gameWindow = w;
            }
            if (!targetView || targetView == gameWindow) return;
            self.cachedTapTarget = targetView;
            self.cachedGameWindow = gameWindow;
        }

        if (!self.emptyTouches) self.emptyTouches = [NSSet set];
        if (!self.dummyEvent) self.dummyEvent = [[UIEvent alloc] init];

        [self performRealTapOnView:targetView inWindow:gameWindow atPoint:tapPt];
    } @catch (NSException *e) {
        NSLog(@"[عبدالإله] tapRealTarget exception: %@", e);
    }
}

- (void)performRealTapOnView:(UIView *)targetView inWindow:(UIWindow *)gameWindow atPoint:(CGPoint)pt {
    UIView *responder = targetView;
    while (responder) {
        if ([responder isKindOfClass:[UIControl class]]) {
            UIControl *ctrl = (UIControl *)responder;
            [ctrl sendActionsForControlEvents:UIControlEventTouchDown];
            [ctrl sendActionsForControlEvents:UIControlEventTouchUpInside];
            break;
        }
        responder = (UIView *)[responder nextResponder];
    }
    [targetView touchesBegan:self.emptyTouches withEvent:self.dummyEvent];
    [targetView touchesEnded:self.emptyTouches withEvent:self.dummyEvent];
}

#pragma mark - Toast

- (void)showToast:(NSString *)message {
    UIWindow *w = self.overlayWindow;
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

#pragma mark - YallaLite Specific Hook

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [[AbdulilahManager shared] checkUI];
}

%end

%ctor {
    [AbdulilahManager shared];
    NSLog(@"[عبدالإله] Tweak v2.0 loaded for YallaLite");
}
