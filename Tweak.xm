#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <sys/socket.h>
#import <sys/select.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <substrate.h>
#import <signal.h>
#import <dlfcn.h>
#import <pthread.h>
#import <sys/stat.h>
#import <errno.h>

#define SHARED_STATE @"/tmp/com.abdulilah.state.plist"

#define PRIMARY_COLOR    [UIColor colorWithRed:0.00 green:0.60 blue:1.00 alpha:1.0]
#define SUCCESS_COLOR    [UIColor colorWithRed:0.00 green:0.50 blue:1.00 alpha:1.0]
#define ERROR_COLOR      [UIColor colorWithRed:0.80 green:0.20 blue:0.30 alpha:1.0]
#define BG_DARK          [UIColor colorWithRed:0.05 green:0.05 blue:0.08 alpha:0.95]
#define BG_CARD          [UIColor colorWithRed:0.10 green:0.10 blue:0.15 alpha:0.90]
#define TEXT_PRIMARY     [UIColor whiteColor]
#define TEXT_SECONDARY   [UIColor colorWithRed:0.60 green:0.60 blue:0.70 alpha:1.0]

#define RGBA(r,g,b,a)    [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:a]

static NSArray<NSString *> *accountNames = @[
    @"عبدالإله", @"شارو", @"لحلوح", @"سعيد",
    @"ابومتعب", @"كنق الشرق", @"حاتم",
    @"الكايد", @"الشمامره", @"الهباس"
];

#define NUM_MICS 10

// Exact mic positions derived from AlDeebManager code (relative to 375x667 base)
static const CGFloat micPositions[NUM_MICS][2] = {
    {320.0/375.0, 200.0/667.0}, // mic 1
    {260.0/375.0, 200.0/667.0}, // mic 2
    {200.0/375.0, 200.0/667.0}, // mic 3
    {140.0/375.0, 200.0/667.0}, // mic 4
    {80.0/375.0,  200.0/667.0}, // mic 5
    {320.0/375.0, 280.0/667.0}, // mic 6
    {260.0/375.0, 280.0/667.0}, // mic 7
    {200.0/375.0, 280.0/667.0}, // mic 8
    {140.0/375.0, 280.0/667.0}, // mic 9
    {80.0/375.0,  280.0/667.0}, // mic 10
};

#pragma mark - UDP IPC

static int udpSock = -1;
static int myPort = 0;
#define UDP_MIN 51551
#define UDP_MAX 51560

static void udpInit(void);
static void udpSend(NSString *msg);
static void sendAll(NSString *msg);

#pragma mark - Anti-Termination Hooks

static void (*orig_exit)(int);
static void ylt_hook_exit(int code) {}

static void (*orig_abort)(void);
static void ylt_hook_abort(void) {}

static void (*orig__exit)(int);
static void ylt_hook__exit(int code) {}

static int (*orig_pthread_cancel)(pthread_t);
static int ylt_hook_pthread_cancel(pthread_t t) { return -1; }

static int (*orig_kill)(pid_t, int);
static int ylt_hook_kill(pid_t pid, int sig) {
    if (sig == SIGKILL && pid == getpid()) return 0;
    return orig_kill(pid, sig);
}

static int (*orig_raise)(int);
static int ylt_hook_raise(int sig) {
    if (sig == SIGKILL) return 0;
    return orig_raise(sig);
}

static void (*orig_objc_exception_throw)(id);
static void ylt_hook_objc_exception_throw(id exc) {}

static void (*orig_cxa_throw)(void *, void *, void (*)(void *));
static void ylt_hook_cxa_throw(void *thrown, void *type, void (*dest)(void *)) {}

static void (*orig_cxa_rethrow)(void);
static void ylt_hook_cxa_rethrow(void) {}

static int (*orig_access)(const char *, int);
static int ylt_hook_access(const char *path, int mode) {
    if (path && strstr(path, "YLTool")) return -1;
    return orig_access(path, mode);
}

static void *(*orig_dlopen)(const char *, int);
static void *ylt_hook_dlopen(const char *path, int mode) {
    if (path && strstr(path, "YLTool")) return NULL;
    if (path && strstr(path, "Substrate")) return NULL;
    if (path && strstr(path, "substrate")) return NULL;
    return orig_dlopen(path, mode);
}

static void *(*orig_dlsym)(void *, const char *);
static void *ylt_hook_dlsym(void *handle, const char *symbol) {
    if (symbol && (strstr(symbol, "MSHook") || strstr(symbol, "Substrate") || strstr(symbol, "substrate") || strstr(symbol, "YLTool")))
        return NULL;
    return orig_dlsym(handle, symbol);
}

static int (*orig_dladdr)(const void *, Dl_info *);
static int ylt_hook_dladdr(const void *addr, Dl_info *info) {
    int ret = orig_dladdr(addr, info);
    if (ret && info && info->dli_fname && strstr(info->dli_fname, "YLTool"))
        return 0;
    return ret;
}

static FILE *(*orig_fopen)(const char *, const char *);
static FILE *ylt_hook_fopen(const char *path, const char *mode) {
    if (path && strstr(path, "YLTool")) { errno = ENOENT; return NULL; }
    return orig_fopen(path, mode);
}

#pragma mark - NSFileManager Anti-Detection

#pragma mark - Alert Blocker (Kick/Ban) — handled via Logos hooks below

#pragma mark - Background Task

static UIBackgroundTaskIdentifier bgTask = UIBackgroundTaskInvalid;

static void startBgTask(void) {
    if (bgTask != UIBackgroundTaskInvalid) return;
    __block UIBackgroundTaskIdentifier task = [[UIApplication sharedApplication] beginBackgroundTaskWithName:@"AbdulilahBg" expirationHandler:^{
        [[UIApplication sharedApplication] endBackgroundTask:task];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (bgTask == task) bgTask = UIBackgroundTaskInvalid;
            startBgTask();
        });
    }];
    if (task != UIBackgroundTaskInvalid) {
        bgTask = task;
    } else {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            startBgTask();
        });
    }
}

static void startBgTaskRenewal(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_source_t t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), 10 * NSEC_PER_SEC, 2 * NSEC_PER_SEC);
        dispatch_source_set_event_handler(t, ^{
            if (bgTask != UIBackgroundTaskInvalid) {
                [[UIApplication sharedApplication] endBackgroundTask:bgTask];
                bgTask = UIBackgroundTaskInvalid;
            }
            startBgTask();
        });
        dispatch_resume(t);
    });
}

static BOOL ylt_hook_isBacEnabled(id self, SEL _cmd) { return NO; }
static NSInteger ylt_hook_appState(id self, SEL _cmd) { return 0; }
static void ylt_hook_terminate(id self, SEL _cmd) {}

static void startSilentAudio(void);

static void ylt_installBgHook(void) {
    Class app = objc_getClass("UIApplication");
    Method m;
    m = class_getInstanceMethod(app, sel_registerName("_isBackgroundTaskExpirationEnabled"));
    if (m) method_setImplementation(m, (IMP)ylt_hook_isBacEnabled);
    m = class_getInstanceMethod(app, sel_registerName("applicationState"));
    if (m) method_setImplementation(m, (IMP)ylt_hook_appState);
    m = class_getInstanceMethod(app, sel_registerName("terminateWithSuccess"));
    if (m) method_setImplementation(m, (IMP)ylt_hook_terminate);
    m = class_getInstanceMethod(app, sel_registerName("terminate"));
    if (m) method_setImplementation(m, (IMP)ylt_hook_terminate);
    m = class_getInstanceMethod(app, sel_registerName("_isBackgrounded"));
    if (m) method_setImplementation(m, (IMP)ylt_hook_isBacEnabled);
    m = class_getInstanceMethod(app, sel_registerName("isBackground"));
    if (m) method_setImplementation(m, (IMP)ylt_hook_isBacEnabled);
    m = class_getInstanceMethod(app, sel_registerName("_suspend"));
    if (m) method_setImplementation(m, (IMP)ylt_hook_terminate);
    m = class_getInstanceMethod(app, sel_registerName("suspend"));
    if (m) method_setImplementation(m, (IMP)ylt_hook_terminate);
    // Block app from entering background entirely — this prevents
    // applicationDidEnterBackground: on the delegate AND prevents
    // UIApplicationDidEnterBackgroundNotification from posting.
    // The app will NEVER know it went to background.
    m = class_getInstanceMethod(app, sel_registerName("_handleApplicationEnterBackground"));
    if (m) method_setImplementation(m, (IMP)ylt_hook_terminate);
    m = class_getInstanceMethod(app, sel_registerName("_handleApplicationEnterBackground:"));
    if (m) method_setImplementation(m, (IMP)ylt_hook_terminate);
}

#pragma mark - Forward Declarations

@class AbdulilahManager;

#pragma mark - UDP Implementation

static void udpSend(NSString *m) {
    if (udpSock < 0) return;
    const char *c = m.UTF8String; size_t l = strlen(c);
    struct sockaddr_in sa;
    memset(&sa, 0, sizeof(sa));
    sa.sin_family = AF_INET;
    inet_aton("127.0.0.1", &sa.sin_addr);
    for (int p = UDP_MIN; p <= UDP_MAX; p++) {
        sa.sin_port = htons(p);
        sendto(udpSock, c, l, 0, (struct sockaddr *)&sa, sizeof(sa));
    }
}

static void sendAll(NSString *msg) {
    udpSend(msg);
}

#pragma mark - Silent Audio

static AVAudioPlayer *silentPlayer = nil;

static void startSilentAudio(void) {
    @try {
        if (silentPlayer && silentPlayer.isPlaying) return;
        AVAudioSession *session = [AVAudioSession sharedInstance];
        [session setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:nil];
        [session setActive:YES error:nil];
        int rate = 8000, dur = 60, ch = 1, bits = 16;
        int dataSz = rate * dur * ch * (bits / 8);
        int fileSz = 44 + dataSz;
        NSMutableData *d = [NSMutableData dataWithLength:fileSz];
        char *b = (char *)[d mutableBytes];
        memcpy(b, "RIFF", 4);
        uint32_t v = fileSz - 8; memcpy(b + 4, &v, 4);
        memcpy(b + 8, "WAVE", 4);
        memcpy(b + 12, "fmt ", 4); v = 16; memcpy(b + 16, &v, 4);
        uint16_t w = 1; memcpy(b + 20, &w, 2);
        w = ch; memcpy(b + 22, &w, 2);
        v = rate; memcpy(b + 24, &v, 4);
        w = ch * (bits / 8); v = rate * w; memcpy(b + 28, &v, 4); memcpy(b + 32, &w, 2);
        w = bits; memcpy(b + 34, &w, 2);
        memcpy(b + 36, "data", 4); v = dataSz; memcpy(b + 40, &v, 4);
        silentPlayer = [[AVAudioPlayer alloc] initWithData:d error:nil];
        if (!silentPlayer) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ startSilentAudio(); });
            return;
        }
        silentPlayer.numberOfLoops = -1;
        silentPlayer.volume = 0.0;
        [silentPlayer prepareToPlay];
        [silentPlayer play];
    } @catch (NSException *e) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ startSilentAudio(); });
    }
}

#pragma mark - Overlay Window

@interface AbdulilahOverlayWindow : UIWindow
@end
@implementation AbdulilahOverlayWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self) return nil;
    return hit;
}
@end

#pragma mark - AbdulilahManager

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

@property (nonatomic, assign) NSInteger selectedMicIndex;
@property (nonatomic, strong) UIView *tapDot;
@property (nonatomic, assign) BOOL isCaptureMode;
@property (nonatomic, strong) UIView *captureDot;
@property (nonatomic, strong) NSMutableDictionary *capturedPositions;

@property (nonatomic, strong) AbdulilahOverlayWindow *overlayWindow;

@property (nonatomic, weak) UIView *cachedTapTarget;
@property (nonatomic, weak) UIWindow *cachedGameWindow;
@property (nonatomic, assign) NSUInteger tapGeneration;
@property (nonatomic, strong) NSObject *tapTimerLock;
@property (nonatomic, assign) dispatch_source_t tapTimer;

@property (nonatomic, strong) CADisplayLink *fastTapLink;
@property (nonatomic, assign) CFTimeInterval fastTapAccumulator;
@property (nonatomic, strong) UITextField *micTextField;
@property (nonatomic, strong) UILabel *selectedNumberLabel;

+ (instancetype)shared;
- (void)showFloatingButton;
- (void)toggleMenu;
- (void)saveInstanceState;
- (void)loadInstanceState;
- (void)selectMicAtIndex:(NSInteger)index;
- (void)startTap;
- (void)stopTap;

@end

@implementation AbdulilahManager

+ (instancetype)shared {
    static AbdulilahManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AbdulilahManager alloc] init];
        instance.currentSpeed = 0.008f;
        instance.transparencyValue = 1.0;
        instance.selectedMicIndex = 0;
        instance.isCaptureMode = NO;
        instance.capturedPositions = [NSMutableDictionary dictionary];
        [instance startUIGuard];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [instance showTapDot];
        });
        [instance loadInstanceState];
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
    if (!self.tapDot || self.tapDot.superview != self.overlayWindow) {
        if (!self.isCaptureMode) [self showTapDot];
    } else {
        [self.overlayWindow bringSubviewToFront:self.tapDot];
    }
    if (self.isCaptureMode && (!self.captureDot || self.captureDot.superview != self.overlayWindow)) {
        [self showCaptureDot];
    }
    if (!silentPlayer || !silentPlayer.isPlaying) {
        startSilentAudio();
    }
    if (bgTask == UIBackgroundTaskInvalid) {
        startBgTask();
    }
}

- (CGPoint)selectedMicPosition {
    return [self positionForMic:self.selectedMicIndex];
}

#pragma mark - Floating Button

- (void)showFloatingButton {
    if (self.floatButton) {
        [self.floatButton.superview removeFromSuperview];
        self.floatButton = nil;
    }
    UIWindow *w = self.overlayWindow;
    CGFloat fbSize = 40;
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(20, 150, fbSize, fbSize)];
    self.floatButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.floatButton.frame = CGRectMake(0, 0, fbSize, fbSize);
    self.floatButton.backgroundColor = [UIColor blackColor];
    self.floatButton.layer.cornerRadius = fbSize / 2;
    self.floatButton.clipsToBounds = YES;
    self.floatButton.layer.borderWidth = 2;
    self.floatButton.layer.borderColor = PRIMARY_COLOR.CGColor;
    [self.floatButton setTitle:@"ع" forState:UIControlStateNormal];
    self.floatButton.titleLabel.font = [UIFont boldSystemFontOfSize:18];
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

#pragma mark - Tap Dot & Mic Selection

- (CGPoint)positionForMic:(NSInteger)index {
    // Check calibrated position first
    NSValue *val = self.capturedPositions[@(index)];
    if (val) return [val CGPointValue];
    // Fall back to default percentage-based position
    CGSize sz = [UIScreen mainScreen].bounds.size;
    CGFloat x = sz.width * micPositions[index][0];
    CGFloat y = sz.height * micPositions[index][1];
    return CGPointMake(x, y);
}

- (void)showTapDot {
    if (self.tapDot) {
        [self.tapDot removeFromSuperview];
        self.tapDot = nil;
    }
    UIWindow *w = self.overlayWindow;
    CGPoint pos = [self positionForMic:self.selectedMicIndex];
    CGFloat ds = 10;
    UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(pos.x - ds/2, pos.y - ds/2, ds, ds)];
    dot.backgroundColor = PRIMARY_COLOR;
    dot.layer.cornerRadius = ds / 2;
    dot.layer.borderWidth = 1;
    dot.layer.borderColor = [UIColor whiteColor].CGColor;
    dot.userInteractionEnabled = NO;
    [w addSubview:dot];
    self.tapDot = dot;
}

- (void)updateTapDotPosition {
    if (!self.tapDot) { [self showTapDot]; return; }
    CGPoint pos = [self positionForMic:self.selectedMicIndex];
    self.tapDot.center = pos;
}

#pragma mark - Capture Mode

- (void)showCaptureDot {
    UIWindow *w = self.overlayWindow;
    if (self.captureDot) {
        [self.captureDot removeFromSuperview];
        self.captureDot = nil;
    }
    CGPoint pos = [self positionForMic:self.selectedMicIndex];
    CGFloat cs = 36;
    UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(pos.x - cs/2, pos.y - cs/2, cs, cs)];
    dot.backgroundColor = [UIColor clearColor];
    dot.layer.cornerRadius = cs / 2;
    dot.layer.borderWidth = 2.5;
    dot.layer.borderColor = [UIColor yellowColor].CGColor;
    dot.userInteractionEnabled = YES;

    UILabel *cross = [[UILabel alloc] initWithFrame:dot.bounds];
    cross.text = @"+";
    cross.textColor = [UIColor yellowColor];
    cross.font = [UIFont boldSystemFontOfSize:20];
    cross.textAlignment = NSTextAlignmentCenter;
    [dot addSubview:cross];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleCaptureDotPan:)];
    [dot addGestureRecognizer:pan];

    [w addSubview:dot];
    self.captureDot = dot;
    [self showToast:@"اسحب النقطة على المايك واضغط رقمه"];
}

- (void)hideCaptureDot {
    if (self.captureDot) {
        [self.captureDot removeFromSuperview];
        self.captureDot = nil;
    }
}

- (void)handleCaptureDotPan:(UIPanGestureRecognizer *)p {
    UIView *v = p.view;
    CGPoint t = [p translationInView:v.superview];
    v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y);
    [p setTranslation:CGPointZero inView:v.superview];
    if (p.state == UIGestureRecognizerStateEnded) {
        self.cachedTapTarget = nil;
        self.cachedGameWindow = nil;
    }
}

- (void)toggleCaptureMode {
    self.isCaptureMode = !self.isCaptureMode;
    if (self.isCaptureMode) {
        if (self.tapDot) { self.tapDot.hidden = YES; }
        [self showCaptureDot];
    } else {
        [self hideCaptureDot];
        if (self.tapDot) { self.tapDot.hidden = NO; }
        [self updateTapDotPosition];
        [self saveInstanceState];
    }
    [self updatePanelMicDisplay];
}

#pragma mark - Selection & Activation

- (void)selectMicAtIndex:(NSInteger)index {
    if (index < 0 || index >= NUM_MICS) return;
    self.selectedMicIndex = index;
    [self updateTapDotPosition];
    sendAll([NSString stringWithFormat:@"MIC:%ld", (long)index]);
    self.cachedTapTarget = nil;
    self.cachedGameWindow = nil;
    [self updatePanelMicDisplay];
    [self saveInstanceState];
}

- (void)confirmAndTapMic:(NSInteger)index {
    [self selectMicAtIndex:index];
    if (self.tapDot) {
        BOOL wasOn = self.autoTapEnabled;
        self.autoTapEnabled = YES;
        [self tapRealTarget];
        self.autoTapEnabled = wasOn;
    }
    NSString *name = (index < (NSInteger)accountNames.count) ? accountNames[index] : @"";
    [self showToast:[NSString stringWithFormat:@"مايك %ld | %@", (long)(index + 1), name]];
}

#pragma mark - Persistence

- (void)saveInstanceState {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"micIdx"] = @(self.selectedMicIndex);
    dict[@"tapOn"] = @(self.autoTapEnabled);
    dict[@"speed"] = @(self.currentSpeed);
    // Save calibrated positions
    if (self.capturedPositions.count > 0) {
        NSMutableDictionary *posDict = [NSMutableDictionary dictionary];
        for (NSNumber *key in self.capturedPositions) {
            CGPoint pt = [self.capturedPositions[key] CGPointValue];
            posDict[[key stringValue]] = @[@(pt.x), @(pt.y)];
        }
        dict[@"calibrated"] = posDict;
    }
    [dict writeToFile:SHARED_STATE atomically:YES];
}

- (void)loadInstanceState {
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:SHARED_STATE];
    if (!dict) return;
    NSNumber *mi = dict[@"micIdx"];
    if (mi) {
        NSInteger idx = [mi integerValue];
        if (idx >= 0 && idx < NUM_MICS) {
            self.selectedMicIndex = idx;
        }
    }
    // Load calibrated positions
    NSDictionary *cal = dict[@"calibrated"];
    if (cal) {
        [self.capturedPositions removeAllObjects];
        for (NSString *key in cal) {
            NSArray *arr = cal[key];
            if (arr.count == 2) {
                CGPoint pt = CGPointMake([arr[0] floatValue], [arr[1] floatValue]);
                self.capturedPositions[@([key integerValue])] = [NSValue valueWithCGPoint:pt];
            }
        }
    }
    float spd = [dict[@"speed"] floatValue];
    if (spd > 0) {
        self.currentSpeed = spd;
    }
    BOOL shouldTap = [dict[@"tapOn"] boolValue];
    if (shouldTap && !self.autoTapEnabled) {
        [self startTap];
    } else if (!shouldTap && self.autoTapEnabled) {
        [self stopTap];
    }
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
    CGFloat mx = 12;
    CGFloat cw = pw - 24;

    // Toggle button
    self.toggleBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.toggleBtn.frame = CGRectMake(mx, y, cw, 38);
    self.toggleBtn.backgroundColor = SUCCESS_COLOR;
    self.toggleBtn.layer.cornerRadius = 19;
    [self.toggleBtn setTitle:@"تشغيل" forState:UIControlStateNormal];
    [self.toggleBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.toggleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [self.toggleBtn addTarget:self action:@selector(toggleStartStop) forControlEvents:UIControlEventTouchUpInside];
    [self.mainPanel addSubview:self.toggleBtn];
    y += 44;

    // Speed label
    self.speedLabel = [[UILabel alloc] initWithFrame:CGRectMake(mx, y, cw, 16)];
    self.speedLabel.textColor = TEXT_PRIMARY;
    self.speedLabel.font = [UIFont systemFontOfSize:10];
    [self.mainPanel addSubview:self.speedLabel];
    [self updateSpeedLabelDisplay];
    y += 18;

    // Speed slider
    self.speedSlider = [[UISlider alloc] initWithFrame:CGRectMake(mx, y, cw, 20)];
    self.speedSlider.minimumValue = 0.001f;
    self.speedSlider.maximumValue = 0.1f;
    self.speedSlider.value = self.currentSpeed;
    self.speedSlider.tintColor = PRIMARY_COLOR;
    self.speedSlider.minimumTrackTintColor = PRIMARY_COLOR;
    self.speedSlider.maximumTrackTintColor = [UIColor colorWithWhite:0.3 alpha:1];
    [self.speedSlider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.mainPanel addSubview:self.speedSlider];
    y += 24;

    // Speed preset buttons
    CGFloat btnW = (cw - 20) / 5;
    NSString *presetLabels[5] = {@"1", @"5", @"10", @"25", @"50"};
    for (int i = 0; i < 5; i++) {
        UIButton *pb = [UIButton buttonWithType:UIButtonTypeCustom];
        pb.frame = CGRectMake(mx + (btnW + 5) * i, y, btnW, 20);
        pb.backgroundColor = BG_CARD;
        pb.layer.cornerRadius = 6;
        pb.titleLabel.font = [UIFont systemFontOfSize:9];
        [pb setTitle:presetLabels[i] forState:UIControlStateNormal];
        [pb setTitleColor:PRIMARY_COLOR forState:UIControlStateNormal];
        pb.tag = i;
        [pb addTarget:self action:@selector(speedPresetTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.mainPanel addSubview:pb];
    }
    y += 26;

    // Mic selection
    // Row: label + selected number display + text field + small activate
    UILabel *micSelectLabel = [[UILabel alloc] initWithFrame:CGRectMake(mx, y + 4, 48, 20)];
    micSelectLabel.text = @"المايك:";
    micSelectLabel.textColor = TEXT_PRIMARY;
    micSelectLabel.font = [UIFont systemFontOfSize:11];
    micSelectLabel.textAlignment = NSTextAlignmentRight;
    [self.mainPanel addSubview:micSelectLabel];

    self.selectedNumberLabel = [[UILabel alloc] initWithFrame:CGRectMake(mx + 48, y + 2, 22, 24)];
    self.selectedNumberLabel.text = [NSString stringWithFormat:@"%ld", (long)(self.selectedMicIndex + 1)];
    self.selectedNumberLabel.textColor = PRIMARY_COLOR;
    self.selectedNumberLabel.font = [UIFont boldSystemFontOfSize:14];
    self.selectedNumberLabel.textAlignment = NSTextAlignmentCenter;
    self.selectedNumberLabel.backgroundColor = BG_CARD;
    self.selectedNumberLabel.layer.cornerRadius = 6;
    self.selectedNumberLabel.clipsToBounds = YES;
    [self.mainPanel addSubview:self.selectedNumberLabel];

    UITextField *micField = [[UITextField alloc] initWithFrame:CGRectMake(mx + 76, y + 2, 42, 24)];
    micField.backgroundColor = BG_CARD;
    micField.textColor = TEXT_PRIMARY;
    micField.font = [UIFont systemFontOfSize:11];
    micField.textAlignment = NSTextAlignmentCenter;
    micField.layer.cornerRadius = 6;
    micField.layer.borderWidth = 0.5;
    micField.layer.borderColor = PRIMARY_COLOR.CGColor;
    micField.keyboardType = UIKeyboardTypeNumberPad;
    micField.text = [NSString stringWithFormat:@"%ld", (long)(self.selectedMicIndex + 1)];
    self.micTextField = micField;
    [self.mainPanel addSubview:micField];

    UIButton *smallActBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    smallActBtn.frame = CGRectMake(mx + 122, y, cw - 122, 28);
    smallActBtn.backgroundColor = PRIMARY_COLOR;
    smallActBtn.layer.cornerRadius = 14;
    [smallActBtn setTitle:@"تفعيل" forState:UIControlStateNormal];
    [smallActBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    smallActBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    [smallActBtn addTarget:self action:@selector(activateMicFromField) forControlEvents:UIControlEventTouchUpInside];
    [self.mainPanel addSubview:smallActBtn];
    y += 34;

    // Number grid: 2 rows of 5 - tap to SELECT then press big تفعيل below
    CGFloat gBtnW = (cw - 16) / 5;
    for (int i = 0; i < NUM_MICS; i++) {
        int col = i % 5;
        int row = i / 5;
        UIButton *nb = [UIButton buttonWithType:UIButtonTypeCustom];
        nb.frame = CGRectMake(mx + (gBtnW + 4) * col, y + (24 + 4) * row, gBtnW, 24);
        nb.backgroundColor = (i == self.selectedMicIndex) ? PRIMARY_COLOR : BG_CARD;
        nb.layer.cornerRadius = 6;
        nb.titleLabel.font = [UIFont boldSystemFontOfSize:11];
        [nb setTitle:[NSString stringWithFormat:@"%d", i + 1] forState:UIControlStateNormal];
        [nb setTitleColor:(i == self.selectedMicIndex) ? [UIColor whiteColor] : PRIMARY_COLOR forState:UIControlStateNormal];
        nb.tag = i + 100;
        [nb addTarget:self action:@selector(micNumberTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.mainPanel addSubview:nb];
    }
    y += 56;

    // Big activate button for grid selection
    UIButton *bigActBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    bigActBtn.frame = CGRectMake(mx, y, cw, 32);
    bigActBtn.backgroundColor = PRIMARY_COLOR;
    bigActBtn.layer.cornerRadius = 16;
    [bigActBtn setTitle:@"🔹 تفعيل" forState:UIControlStateNormal];
    [bigActBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    bigActBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [bigActBtn addTarget:self action:@selector(activateSelectedMic) forControlEvents:UIControlEventTouchUpInside];
    [self.mainPanel addSubview:bigActBtn];
    y += 38;

    // Capture mode toggle
    UIButton *captBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    captBtn.frame = CGRectMake(mx, y, cw, 28);
    captBtn.backgroundColor = self.isCaptureMode ? [UIColor orangeColor] : BG_CARD;
    captBtn.layer.cornerRadius = 14;
    [captBtn setTitle:@"📍 تصوير الموقع" forState:UIControlStateNormal];
    [captBtn setTitleColor:self.isCaptureMode ? [UIColor whiteColor] : [UIColor orangeColor] forState:UIControlStateNormal];
    captBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    captBtn.tag = 200;
    [captBtn addTarget:self action:@selector(toggleCaptureMode) forControlEvents:UIControlEventTouchUpInside];
    [self.mainPanel addSubview:captBtn];
    y += 34;

    // Merge label
    UILabel *mergeLabel = [[UILabel alloc] initWithFrame:CGRectMake(mx, y, cw, 14)];
    mergeLabel.text = @"تم ربط الحسابات تلقائياً";
    mergeLabel.textColor = [UIColor greenColor];
    mergeLabel.font = [UIFont systemFontOfSize:9];
    mergeLabel.textAlignment = NSTextAlignmentCenter;
    [self.mainPanel addSubview:mergeLabel];
    y += 18;

    // Credit
    UIView *creditBox = [[UIView alloc] initWithFrame:CGRectMake(mx, y, cw, 24)];
    creditBox.backgroundColor = BG_CARD;
    creditBox.layer.cornerRadius = 12;
    [self.mainPanel addSubview:creditBox];
    UILabel *creditLbl = [[UILabel alloc] initWithFrame:CGRectMake(8, 0, cw - 16, 24)];
    creditLbl.text = @"حقوق عبدالإله فقط.";
    creditLbl.textColor = [PRIMARY_COLOR colorWithAlphaComponent:0.7];
    creditLbl.font = [UIFont boldSystemFontOfSize:8];
    creditLbl.textAlignment = NSTextAlignmentCenter;
    [creditBox addSubview:creditLbl];
    y += 30;

    CGRect f = self.mainPanel.frame;
    f.size.height = y + 8;
    self.mainPanel.frame = f;

    UIPanGestureRecognizer *panP = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.mainPanel addGestureRecognizer:panP];
}

#pragma mark - Tap Engine

- (void)sliderChanged:(UISlider *)sender {
    CGFloat val = sender.value;
    if (val < 0.001f) val = 0.001f;
    self.currentSpeed = val;
    [self updateSpeedLabelDisplay];
    if (self.autoTapEnabled) [self restartTapWithSpeed:self.currentSpeed];
    [self saveInstanceState];
}

- (void)speedPresetTapped:(UIButton *)sender {
    CGFloat presetVals[5] = {0.001, 0.005, 0.010, 0.025, 0.050};
    int idx = (int)sender.tag;
    if (idx < 0 || idx > 4) return;
    self.currentSpeed = presetVals[idx];
    self.speedSlider.value = self.currentSpeed;
    [self updateSpeedLabelDisplay];
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
            sendAll(@"STOP");
            [self stopTap];
        } else {
            sendAll(@"RUN");
            [self startTapInternal];
            [self saveInstanceState];
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
    [self stopTapTimer];
    [self stopFastTapLink];
    self.tapGeneration++;
    // Use CADisplayLink for speeds >= 8ms (matches display refresh well)
    if (speed >= 0.008f) {
        [self startFastTapLinkWithSpeed:speed];
        return;
    }
    __weak typeof(self) weakSelf = self;
    NSUInteger myGen = self.tapGeneration;
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, speed * NSEC_PER_SEC, 0);
    dispatch_source_set_event_handler(timer, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.autoTapEnabled || strongSelf.tapGeneration != myGen) {
            dispatch_source_cancel(timer);
            return;
        }
        [strongSelf tapRealTarget];
    });
    dispatch_resume(timer);
    self.tapTimer = timer;
}

- (void)stopTapTimer {
    if (self.tapTimer) {
        dispatch_source_cancel(self.tapTimer);
        self.tapTimer = NULL;
    }
    [self stopFastTapLink];
}

#pragma mark - CADisplayLink Fast Engine

- (void)startFastTapLinkWithSpeed:(float)speed {
    [self stopFastTapLink];
    self.fastTapAccumulator = 0;
    CADisplayLink *link = [CADisplayLink displayLinkWithTarget:self selector:@selector(fastTapLinkCallback:)];
    if (@available(iOS 10.3, *)) {
        link.preferredFramesPerSecond = 120;
    }
    [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    self.fastTapLink = link;
}

- (void)stopFastTapLink {
    if (self.fastTapLink) {
        [self.fastTapLink invalidate];
        self.fastTapLink = nil;
    }
    self.fastTapAccumulator = 0;
}

- (void)fastTapLinkCallback:(CADisplayLink *)link {
    if (!self.autoTapEnabled) { [self stopFastTapLink]; return; }
    self.fastTapAccumulator += link.duration;
    while (self.fastTapAccumulator >= self.currentSpeed) {
        self.fastTapAccumulator -= self.currentSpeed;
        [self tapRealTarget];
        if (!self.autoTapEnabled) break;
    }
}

#pragma mark - Speed Text Helper

- (NSString *)speedTextForValue:(float)speed {
    if (speed <= 0.005) return @"سريع جداً";
    if (speed <= 0.015) return @"سريع";
    if (speed <= 0.040) return @"عادي";
    return @"بطيء";
}

- (void)updatePanelMicDisplay {
    if (self.selectedNumberLabel) {
        self.selectedNumberLabel.text = [NSString stringWithFormat:@"%ld", (long)(self.selectedMicIndex + 1)];
    }
    if (self.micTextField) {
        self.micTextField.text = [NSString stringWithFormat:@"%ld", (long)(self.selectedMicIndex + 1)];
    }
    // Update number grid buttons in panel (tags 100-109)
    if (self.mainPanel) {
        for (UIView *sub in self.mainPanel.subviews) {
            if ([sub isKindOfClass:[UIButton class]] && sub.tag >= 100) {
                UIButton *btn = (UIButton *)sub;
                NSInteger idx = btn.tag - 100;
                if (idx >= 0 && idx < NUM_MICS) {
                    BOOL active = (idx == self.selectedMicIndex);
                    btn.backgroundColor = active ? PRIMARY_COLOR : BG_CARD;
                    [btn setTitleColor:active ? [UIColor whiteColor] : PRIMARY_COLOR forState:UIControlStateNormal];
                }
            }
            // Update capture button (tag 200)
            if ([sub isKindOfClass:[UIButton class]] && sub.tag == 200) {
                UIButton *cb = (UIButton *)sub;
                cb.backgroundColor = self.isCaptureMode ? [UIColor orangeColor] : BG_CARD;
                [cb setTitleColor:self.isCaptureMode ? [UIColor whiteColor] : [UIColor orangeColor] forState:UIControlStateNormal];
                [cb setTitle:self.isCaptureMode ? @"📍 تصوير الموقع" : @"📍 تصوير الموقع" forState:UIControlStateNormal];
            }
        }
    }
}

- (void)updateSpeedLabelDisplay {
    NSString *quality = [self speedTextForValue:self.currentSpeed];
    self.speedLabel.text = [NSString stringWithFormat:@"السرعة: %.0f مللي | %@", self.currentSpeed * 1000, quality];
    [self updatePanelMicDisplay];
}

- (void)activateMicFromField {
    NSString *text = self.micTextField.text;
    NSInteger num = [text integerValue];
    if (num < 1) num = 1;
    if (num > NUM_MICS) num = NUM_MICS;
    self.micTextField.text = [NSString stringWithFormat:@"%ld", (long)num];
    [self.micTextField resignFirstResponder];
    [self confirmAndTapMic:num - 1];
}

- (void)micNumberTapped:(UIButton *)sender {
    NSInteger idx = sender.tag - 100;
    if (idx < 0 || idx >= NUM_MICS) return;
    if (self.isCaptureMode && self.captureDot) {
        // Save capture dot position to this mic number
        self.capturedPositions[@(idx)] = [NSValue valueWithCGPoint:self.captureDot.center];
        [self showToast:[NSString stringWithFormat:@"حُفظت مايك %ld ✅", (long)(idx + 1)]];
        [self saveInstanceState];
        return;
    }
    self.selectedMicIndex = idx;
    [self updatePanelMicDisplay];
    [self updateTapDotPosition];
    [self showToast:[NSString stringWithFormat:@"اختير مايك %ld", (long)(idx + 1)]];
}

- (void)activateSelectedMic {
    [self confirmAndTapMic:self.selectedMicIndex];
}

- (void)stopTap {
    @try {
        self.autoTapEnabled = NO;
        [self stopTapTimer];
        [self stopFastTapLink];
        [self saveInstanceState];
        if (self.toggleBtn) {
            [self.toggleBtn setTitle:@"تشغيل" forState:UIControlStateNormal];
            self.toggleBtn.backgroundColor = SUCCESS_COLOR;
        }
    } @catch (NSException *e) {
        NSLog(@"[عبدالإله] stopTap exception: %@", e);
    }
}

- (void)tapRealTarget {
    @try {
        if (!self.autoTapEnabled) return;
        CGPoint tapPt = [self selectedMicPosition];
        if (tapPt.x <= 0 && tapPt.y <= 0) return;

        // Random jitter +/- 4px to avoid anti-cheat detection
        tapPt.x += (CGFloat)((int)arc4random_uniform(9) - 4);
        tapPt.y += (CGFloat)((int)arc4random_uniform(9) - 4);

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

        [self performGSTapAtPoint:tapPt];
        [self performHIDTapAtPoint:tapPt];
        // Also send UIControl actions as fallback for buttons
        if (targetView) {
            [self performRealTapOnView:targetView atPoint:tapPt];
        }
    } @catch (NSException *e) {
        NSLog(@"[عبدالإله] tapRealTarget exception: %@", e);
    }
}

- (void)performRealTapOnView:(UIView *)targetView atPoint:(CGPoint)pt {
    // Visual tap flash on dot
    if (self.tapDot) {
        self.tapDot.transform = CGAffineTransformMakeScale(2.0, 2.0);
        self.tapDot.alpha = 0.4;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.04 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.08 animations:^{
                self.tapDot.transform = CGAffineTransformIdentity;
                self.tapDot.alpha = 1.0;
            }];
        });
    }
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
}

#pragma mark - GSEvent Tap (System-level touch)

typedef struct __GSEvent *GSEventRef;
static GSEventRef (*gs_CreateWithType)(int);
static void (*gs_SetLocationInWindow)(GSEventRef, CGPoint);
static void (*gs_PostEvent)(GSEventRef);

static dispatch_once_t gs_once;
#define GS_DOWN 1007
#define GS_UP 1009

static void gs_init(void) {
    dispatch_once(&gs_once, ^{
        void *h = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_LAZY);
        if (h) {
            *(void **)&gs_CreateWithType = dlsym(h, "GSEventCreateWithType");
            *(void **)&gs_SetLocationInWindow = dlsym(h, "GSEventSetLocationInWindow");
            *(void **)&gs_PostEvent = dlsym(h, "GSEventPostEvent");
        }
    });
}

static void gs_tap(CGPoint pt) {
    if (!gs_CreateWithType || !gs_SetLocationInWindow || !gs_PostEvent) return;
    GSEventRef down = gs_CreateWithType(GS_DOWN);
    if (down) {
        gs_SetLocationInWindow(down, pt);
        gs_PostEvent(down);
    }
    GSEventRef up = gs_CreateWithType(GS_UP);
    if (up) {
        gs_SetLocationInWindow(up, pt);
        gs_PostEvent(up);
    }
}

- (void)performGSTapAtPoint:(CGPoint)pt {
    @try {
        gs_init();
        gs_tap(pt);
    } @catch (NSException *e) {
        NSLog(@"[عبدالإله] GSTap exception: %@", e);
    }
}

#pragma mark - IOHIDEvent Tap (Kernel-level touch)

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef uint32_t IOHIDDigitizerTransducerType;
typedef uint32_t IOHIDEventField;
typedef double IOHIDFloat;

static IOHIDEventRef (*hid_CreateDigitizerEvent)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, IOHIDFloat, IOHIDFloat, IOHIDFloat, IOHIDFloat, IOHIDFloat, Boolean, Boolean, uint32_t);
static IOHIDEventRef (*hid_CreateFingerEvent)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, IOHIDFloat, IOHIDFloat, IOHIDFloat, IOHIDFloat, IOHIDFloat, IOHIDFloat, IOHIDFloat, IOHIDFloat, IOHIDFloat, IOHIDFloat, Boolean, Boolean, uint32_t);
static void (*hid_AppendEvent)(IOHIDEventRef, IOHIDEventRef);
static void (*hid_SetIntegerValue)(IOHIDEventRef, uint32_t, int);
static void (*hid_PostEvent)(IOHIDEventRef);

static dispatch_once_t hid_once;

static void hid_init(void) {
    dispatch_once(&hid_once, ^{
        void *h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
        if (!h) h = dlopen("/System/Library/PrivateFrameworks/IOMobileFramebuffer.framework/IOMobileFramebuffer", RTLD_LAZY);
        if (h) {
            *(void **)&hid_CreateDigitizerEvent = dlsym(h, "IOHIDEventCreateDigitizerEvent");
            *(void **)&hid_CreateFingerEvent = dlsym(h, "IOHIDEventCreateDigitizerFingerEventWithQuality");
            *(void **)&hid_AppendEvent = dlsym(h, "IOHIDEventAppendEvent");
            *(void **)&hid_SetIntegerValue = dlsym(h, "IOHIDEventSetIntegerValue");
            *(void **)&hid_PostEvent = dlsym(h, "IOHIDEventPostEvent");
        }
    });
}

static void hid_tap(CGPoint pt) {
    if (!hid_CreateDigitizerEvent || !hid_CreateFingerEvent || !hid_AppendEvent || !hid_SetIntegerValue || !hid_PostEvent)
        return;
    uint64_t now = mach_absolute_time();
    // Create hand event
    IOHIDEventRef hand = hid_CreateDigitizerEvent(kCFAllocatorDefault, now, 3, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 0);
    if (!hand) return;
    hid_SetIntegerValue(hand, 0x00E0001, 1);
    // Create finger down
    IOHIDEventRef down = hid_CreateFingerEvent(kCFAllocatorDefault, now, 1, 2, 3, (IOHIDFloat)pt.x, (IOHIDFloat)pt.y, 0, 0, 0, 5, 5, 1, 1, 1, 1, 1, 0);
    if (down) {
        hid_SetIntegerValue(down, 0x00E0001, 1);
        hid_AppendEvent(hand, down);
        hid_PostEvent(hand);
        CFRelease(down);
    }
    CFRelease(hand);
    // Create finger up
    hand = hid_CreateDigitizerEvent(kCFAllocatorDefault, now, 3, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 0);
    if (!hand) return;
    hid_SetIntegerValue(hand, 0x00E0001, 1);
    IOHIDEventRef up = hid_CreateFingerEvent(kCFAllocatorDefault, now, 1, 2, 2, (IOHIDFloat)pt.x, (IOHIDFloat)pt.y, 0, 0, 0, 5, 5, 1, 1, 1, 0, 0, 0);
    if (up) {
        hid_SetIntegerValue(up, 0x00E0001, 1);
        hid_AppendEvent(hand, up);
        hid_PostEvent(hand);
        CFRelease(up);
    }
    CFRelease(hand);
}

- (void)performHIDTapAtPoint:(CGPoint)pt {
    @try {
        hid_init();
        hid_tap(pt);
    } @catch (NSException *e) {
        NSLog(@"[عبدالإله] HIDTap exception: %@", e);
    }
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

#pragma mark - UDP Init (must be after AbdulilahManager for class visibility)

static void udpInit(void) {
    udpSock = socket(AF_INET, SOCK_DGRAM, 0);
    if (udpSock < 0) return;
    int opt = 1;
    setsockopt(udpSock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    for (int p = UDP_MIN; p <= UDP_MAX; p++) {
        struct sockaddr_in a;
        memset(&a, 0, sizeof(a));
        a.sin_family = AF_INET;
        a.sin_port = htons(p);
        a.sin_addr.s_addr = INADDR_ANY;
        if (bind(udpSock, (struct sockaddr *)&a, sizeof(a)) == 0) { myPort = p; break; }
    }
    if (myPort == 0) { close(udpSock); udpSock = -1; return; }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        char buf[256];
        fd_set fds;
        struct timeval tv;
        while (1) {
            @autoreleasepool {
                FD_ZERO(&fds);
                FD_SET(udpSock, &fds);
                tv.tv_sec = 0; tv.tv_usec = 5000;
                if (select(udpSock+1, &fds, NULL, NULL, &tv) <= 0) continue;
                struct sockaddr_in from;
                socklen_t flen = sizeof(from);
                ssize_t n = recvfrom(udpSock, buf, sizeof(buf)-1, 0, (struct sockaddr *)&from, &flen);
                if (n <= 0) continue;
                buf[n] = 0;
                NSString *m = [NSString stringWithUTF8String:buf];
                dispatch_async(dispatch_get_main_queue(), ^{
                    AbdulilahManager *mgr = [AbdulilahManager shared];
                    if ([m hasPrefix:@"MIC:"]) {
                        NSInteger idx = [[m substringFromIndex:4] integerValue];
                        [mgr selectMicAtIndex:idx];
                    } else if ([m isEqualToString:@"RUN"]) {
                        [mgr startTap];
                    } else if ([m isEqualToString:@"STOP"]) {
                        [mgr stopTap];
                    }
                });
            }
        }
    });
}

#pragma mark - NSFileManager Anti-Detection Hooks

%hook NSFileManager

- (BOOL)fileExistsAtPath:(NSString *)path {
    if (path && [path containsString:@"YLTool"]) return NO;
    if ([path hasPrefix:@"/Applications/Cydia.app"] ||
        [path hasPrefix:@"/Library/MobileSubstrate"] ||
        [path hasPrefix:@"/usr/sbin/sshd"] ||
        [path hasPrefix:@"/etc/apt"] ||
        [path hasPrefix:@"/usr/bin/ssh"])
        return NO;
    return %orig;
}

- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDir {
    if (path && [path containsString:@"YLTool"]) return NO;
    if ([path hasPrefix:@"/Applications/Cydia.app"] ||
        [path hasPrefix:@"/Library/MobileSubstrate"] ||
        [path hasPrefix:@"/usr/sbin/sshd"] ||
        [path hasPrefix:@"/etc/apt"] ||
        [path hasPrefix:@"/usr/bin/ssh"]) {
        if (isDir) *isDir = NO;
        return NO;
    }
    return %orig;
}

%end

#pragma mark - UIViewController Hooks

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [[AbdulilahManager shared] checkUI];
}

- (void)presentViewController:(UIViewController *)vc animated:(BOOL)animated completion:(void (^)(void))completion {
    if ([vc isKindOfClass:[UIAlertController class]]) {
        NSString *title = [vc title];
        if (title) {
            NSString *lower = [title lowercaseString];
            if ([lower containsString:@"kick"] || [lower containsString:@"out"] ||
                [lower containsString:@"طرد"] || [lower containsString:@"كيك"] ||
                [lower containsString:@"logout"] || [lower containsString:@"ban"] ||
                [lower containsString:@"حظر"]) {
                return;
            }
        }
    }
    %orig;
}

%end

#pragma mark - Constructor

static void ym_uncaughtExceptionHandler(NSException *exception) {
    NSLog(@"[عبدالإله] Uncaught exception=%@ reason=%@ stack=%@", exception.name, exception.reason, exception.callStackSymbols);
}

static void ym_signalHandler(int sig) {
    NSLog(@"[عبدالإله] Caught signal=%d", sig);
}

%ctor {
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
    if (!bid || ![bid hasPrefix:@"com.yalla.yallalite"]) return;

    NSSetUncaughtExceptionHandler(&ym_uncaughtExceptionHandler);
    signal(SIGSEGV, ym_signalHandler);
    signal(SIGBUS, ym_signalHandler);
    signal(SIGFPE, ym_signalHandler);
    signal(SIGTRAP, ym_signalHandler);
    signal(SIGTERM, SIG_IGN);
    signal(SIGABRT, SIG_IGN);
    signal(SIGINT, SIG_IGN);
    signal(SIGQUIT, SIG_IGN);
    signal(SIGILL, SIG_IGN);
    signal(SIGHUP, SIG_IGN);
    signal(SIGPIPE, SIG_IGN);
    signal(SIGABRT, SIG_IGN);
    signal(SIGINT, SIG_IGN);
    signal(SIGQUIT, SIG_IGN);
    signal(SIGILL, SIG_IGN);
    signal(SIGHUP, SIG_IGN);
    signal(SIGPIPE, SIG_IGN);

    MSHookFunction((void *)&exit, (void *)ylt_hook_exit, (void **)&orig_exit);
    MSHookFunction((void *)&_exit, (void *)ylt_hook__exit, (void **)&orig__exit);
    MSHookFunction((void *)&pthread_cancel, (void *)ylt_hook_pthread_cancel, (void **)&orig_pthread_cancel);
    MSHookFunction((void *)&access, (void *)ylt_hook_access, (void **)&orig_access);
    MSHookFunction((void *)&dlopen, (void *)ylt_hook_dlopen, (void **)&orig_dlopen);
    MSHookFunction((void *)&dlsym, (void *)ylt_hook_dlsym, (void **)&orig_dlsym);
    MSHookFunction((void *)&dladdr, (void *)ylt_hook_dladdr, (void **)&orig_dladdr);
    MSHookFunction((void *)&fopen, (void *)ylt_hook_fopen, (void **)&orig_fopen);

    void *cxa = dlsym(RTLD_DEFAULT, "__cxa_throw");
    if (cxa) MSHookFunction(cxa, (void *)ylt_hook_cxa_throw, (void **)&orig_cxa_throw);
    cxa = dlsym(RTLD_DEFAULT, "__cxa_rethrow");
    if (cxa) MSHookFunction(cxa, (void *)ylt_hook_cxa_rethrow, (void **)&orig_cxa_rethrow);

    MSHookFunction((void *)&abort, (void *)ylt_hook_abort, (void **)&orig_abort);
    MSHookFunction((void *)&kill, (void *)ylt_hook_kill, (void **)&orig_kill);
    MSHookFunction((void *)&raise, (void *)ylt_hook_raise, (void **)&orig_raise);

    void *exc_ptr = dlsym(RTLD_DEFAULT, "objc_exception_throw");
    if (exc_ptr)
        MSHookFunction(exc_ptr, (void *)ylt_hook_objc_exception_throw, (void **)&orig_objc_exception_throw);

    ylt_installBgHook();
    udpInit();

    dispatch_async(dispatch_get_main_queue(), ^{
        startSilentAudio();
        startBgTaskRenewal();
        startBgTask();
        [AbdulilahManager shared];

        // Hook the app delegate's applicationDidEnterBackground: to no-op
        @try {
            id appDelegate = [[UIApplication sharedApplication] delegate];
            if (appDelegate) {
                Class delClass = [appDelegate class];
                SEL bgSel = @selector(applicationDidEnterBackground:);
                Method bgM = class_getInstanceMethod(delClass, bgSel);
                if (bgM) method_setImplementation(bgM, (IMP)ylt_hook_terminate);
                SEL resignSel = @selector(applicationWillResignActive:);
                Method resignM = class_getInstanceMethod(delClass, resignSel);
                if (resignM) method_setImplementation(resignM, (IMP)ylt_hook_terminate);
            }
        } @catch (NSException *e) {
            NSLog(@"[عبدالإله] delegate hook failed: %@", e);
        }

        // Background watchdog: check every 2s that audio + bg task are alive, restart if dead
        dispatch_source_t watchdog = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(watchdog, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), 2 * NSEC_PER_SEC, 1 * NSEC_PER_SEC);
        dispatch_source_set_event_handler(watchdog, ^{
            if (!silentPlayer || !silentPlayer.isPlaying) {
                silentPlayer = nil;
                startSilentAudio();
            }
            if (bgTask == UIBackgroundTaskInvalid) {
                startBgTask();
            }
            // Keep audio session active
            [[AVAudioSession sharedInstance] setActive:YES error:nil];
        });
        dispatch_resume(watchdog);

        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            AbdulilahManager *m = [AbdulilahManager shared];
            if (m.mainPanel) { [m.mainPanel removeFromSuperview]; m.mainPanel = nil; }
            if (!m.tapDot) { [m showTapDot]; }
            if (m.isCaptureMode && !m.captureDot) { [m showCaptureDot]; }
        }];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            if (bgTask != UIBackgroundTaskInvalid) {
                [[UIApplication sharedApplication] endBackgroundTask:bgTask];
                bgTask = UIBackgroundTaskInvalid;
            }
            startSilentAudio();
            startBgTask();
        }];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            startSilentAudio();
            startBgTask();
        }];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            startSilentAudio();
            startBgTask();
        }];
    });

    NSLog(@"[عبدالإله] Tweak v3.0 loaded for YallaLite — UDP IPC + anti-kick");
}
