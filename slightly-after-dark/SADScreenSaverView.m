#import "SADScreenSaverView.h"

#import <AppKit/AppKit.h>
#import <math.h>
#import <WebKit/WebKit.h>

static NSString * const SADSelectedSaverDefaultsKey = @"ScreenSaver";
static NSString * const SADFrameRateDefaultsKey = @"FrameRate";
static NSString * const SADObjectScaleDefaultsKey = @"ObjectScalePercent";
static NSString * const SADPlaybackSpeedDefaultsKey = @"PlaybackSpeedPercent";
static NSString * const SADAssetDirectoryName = @"after-dark-css";
static NSString * const SADSaverPopUpIdentifier = @"SADSaverPopUp";
static NSString * const SADFrameRateSliderIdentifier = @"SADFrameRateSlider";
static NSString * const SADObjectScaleSliderIdentifier = @"SADObjectScaleSlider";
static NSString * const SADPlaybackSpeedSliderIdentifier = @"SADPlaybackSpeedSlider";
static NSString * const SADCancelButtonIdentifier = @"SADCancelButton";
static NSString * const SADDoneButtonIdentifier = @"SADDoneButton";
static const NSTimeInterval SADLegacyPosterTimeMilliseconds = 2000.0;
static const NSInteger SADDefaultFrameRate = 30;
static const NSInteger SADMinimumFrameRate = 15;
static const NSInteger SADMaximumFrameRate = 60;
static const NSInteger SADDefaultObjectScalePercent = 100;
static const NSInteger SADMinimumObjectScalePercent = 50;
static const NSInteger SADMaximumObjectScalePercent = 200;
static const NSInteger SADDefaultPlaybackSpeedPercent = 100;
static const NSInteger SADMinimumPlaybackSpeedPercent = 50;
static const NSInteger SADMaximumPlaybackSpeedPercent = 200;

static BOOL SADShouldUseLegacyWebView(void)
{
    NSString *rendererOverride = NSProcessInfo.processInfo.environment[@"SAD_WEB_RENDERER"];
    if (rendererOverride != nil) {
        if ([rendererOverride caseInsensitiveCompare:@"legacy"] == NSOrderedSame) {
            return YES;
        }
        if ([rendererOverride caseInsensitiveCompare:@"modern"] == NSOrderedSame) {
            return NO;
        }
    }

    // WKWebView content in a legacy ScreenSaver hierarchy disappears after a few
    // seconds on macOS 26.4 and later. Keep this compatibility path isolated so
    // newer macOS releases automatically return to WKWebView.
    NSOperatingSystemVersion version = NSProcessInfo.processInfo.operatingSystemVersion;
    return version.majorVersion == 26 && version.minorVersion >= 4;
}

@interface SADScreenSaverView () <WKNavigationDelegate>

@property (nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *savers;
@property (nonatomic) NSInteger selectedSaverIndex;
@property (nonatomic) NSInteger frameRate;
@property (nonatomic) NSInteger objectScalePercent;
@property (nonatomic) NSInteger playbackSpeedPercent;
@property (nonatomic, strong, nullable) NSView *rendererView;
@property (nonatomic, strong, nullable) WKWebView *modernWebView;
@property (nonatomic, strong, nullable) id legacyWebView;
@property (nonatomic, strong, nullable) NSURL *legacyPageURL;
@property (nonatomic) BOOL retriedModernRenderer;
@property (nonatomic) BOOL legacyDocumentReady;
@property (nonatomic) BOOL legacyAnimationsPrepared;
@property (nonatomic) BOOL legacyHasAnimations;
@property (nonatomic) NSTimeInterval legacyAnimationEpoch;
@property (nonatomic) NSTimeInterval legacyAnimationOffsetMilliseconds;
@property (nonatomic) NSSize presentationSettingsViewportSize;

@property (nonatomic, strong, nullable) NSPanel *configurationPanel;
@property (nonatomic, strong, nullable) NSPopUpButton *saverPopUpButton;
@property (nonatomic, strong, nullable) NSSlider *frameRateSlider;
@property (nonatomic, strong, nullable) NSSlider *objectScaleSlider;
@property (nonatomic, strong, nullable) NSSlider *playbackSpeedSlider;
@property (nonatomic, strong, nullable) NSTextField *frameRateValueLabel;
@property (nonatomic, strong, nullable) NSTextField *objectScaleValueLabel;
@property (nonatomic, strong, nullable) NSTextField *playbackSpeedValueLabel;
@property (nonatomic) NSInteger configurationOriginalSaverIndex;
@property (nonatomic) NSInteger configurationOriginalFrameRate;
@property (nonatomic) NSInteger configurationOriginalObjectScalePercent;
@property (nonatomic) NSInteger configurationOriginalPlaybackSpeedPercent;

@end

@implementation SADScreenSaverView

- (nullable instancetype)initWithFrame:(NSRect)frame isPreview:(BOOL)isPreview
{
    // macOS 26 can ask a legacy module for its preview using NSZeroRect and
    // never resize the module itself, even though its remote container has a
    // valid size. Give only that preview host a nominal canvas it can scale.
    NSRect initialFrame = frame;
    if (isPreview && NSIsEmptyRect(frame)) {
        initialFrame.size = NSMakeSize(800.0, 600.0);
    }
    self = [super initWithFrame:initialFrame isPreview:isPreview];
    if (self == nil) {
        return nil;
    }

    self.wantsLayer = YES;
    self.layer.backgroundColor = NSColor.blackColor.CGColor;

    self.savers = [self.class availableSavers];
    self.selectedSaverIndex = [self savedSaverIndex];
    self.frameRate = [self savedIntegerForKey:SADFrameRateDefaultsKey
                                 defaultValue:SADDefaultFrameRate
                                      minimum:SADMinimumFrameRate
                                      maximum:SADMaximumFrameRate];
    self.objectScalePercent = [self savedIntegerForKey:SADObjectScaleDefaultsKey
                                               defaultValue:SADDefaultObjectScalePercent
                                                    minimum:SADMinimumObjectScalePercent
                                                    maximum:SADMaximumObjectScalePercent];
    self.playbackSpeedPercent = [self savedIntegerForKey:SADPlaybackSpeedDefaultsKey
                                                 defaultValue:SADDefaultPlaybackSpeedPercent
                                                      minimum:SADMinimumPlaybackSpeedPercent
                                                      maximum:SADMaximumPlaybackSpeedPercent];
    [self updateAnimationTimeInterval];

    // The modern Screen Saver host may create a preview at zero size and may
    // not start its animation until after the view is onscreen. Load an initial
    // frame now so the host always has content to display; startAnimation will
    // reload it to restart the CSS animations.
    [self loadSelectedSaver];

    return self;
}

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)availableSavers
{
    return @[
        @{ @"title": @"Flying Toasters", @"filename": @"flying-toasters" },
        @{ @"title": @"Fish", @"filename": @"fish" },
        @{ @"title": @"Globe", @"filename": @"globe" },
        @{ @"title": @"Hard Rain", @"filename": @"hard-rain" },
        @{ @"title": @"Bouncing Ball", @"filename": @"bouncing-ball" },
        @{ @"title": @"Warp", @"filename": @"warp" },
        @{ @"title": @"Messages", @"filename": @"messages" },
        @{ @"title": @"Messages 2", @"filename": @"messages2" },
        @{ @"title": @"Fade Out", @"filename": @"fade-out" },
        @{ @"title": @"Logo", @"filename": @"logo" },
        @{ @"title": @"Rainstorm", @"filename": @"rainstorm" },
        @{ @"title": @"Spotlight", @"filename": @"spotlight" },
    ];
}

- (nullable ScreenSaverDefaults *)screenSaverDefaults
{
    NSString *moduleName = NSProcessInfo.processInfo.environment[@"SAD_DEFAULTS_MODULE"];
    if (moduleName.length == 0) {
        moduleName = [NSBundle bundleForClass:self.class].bundleIdentifier;
    }
    if (moduleName.length == 0) {
        return nil;
    }
    ScreenSaverDefaults *defaults = [ScreenSaverDefaults defaultsForModuleWithName:moduleName];
    [defaults registerDefaults:@{
        SADSelectedSaverDefaultsKey: @0,
        SADFrameRateDefaultsKey: @(SADDefaultFrameRate),
        SADObjectScaleDefaultsKey: @(SADDefaultObjectScalePercent),
        SADPlaybackSpeedDefaultsKey: @(SADDefaultPlaybackSpeedPercent),
    }];
    return defaults;
}

- (NSInteger)savedSaverIndex
{
    ScreenSaverDefaults *defaults = [self screenSaverDefaults];
    NSInteger index = [defaults integerForKey:SADSelectedSaverDefaultsKey];
    if (index < 0 || index >= (NSInteger)self.savers.count) {
        return 0;
    }
    return index;
}

- (NSInteger)savedIntegerForKey:(NSString *)key
                   defaultValue:(NSInteger)defaultValue
                        minimum:(NSInteger)minimum
                        maximum:(NSInteger)maximum
{
    NSInteger value = [[self screenSaverDefaults] integerForKey:key];
    return value >= minimum && value <= maximum ? value : defaultValue;
}

- (void)updateAnimationTimeInterval
{
    // WKWebView follows the display refresh rate itself. The compatibility
    // renderer needs ScreenSaverView's timer to drive its frozen CSS timeline.
    BOOL usesCompatibilityTimer = self.legacyWebView != nil
        || (self.legacyWebView == nil && self.modernWebView == nil
            && SADShouldUseLegacyWebView());
    self.animationTimeInterval = usesCompatibilityTimer
        ? 1.0 / (NSTimeInterval)self.frameRate
        : 1.0;
}

- (void)installModernRenderer
{
    [self removeRenderer];

    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.websiteDataStore = WKWebsiteDataStore.nonPersistentDataStore;
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = NO;
    configuration.suppressesIncrementalRendering = YES;
    if (@available(macOS 11.0, *)) {
        configuration.defaultWebpagePreferences.allowsContentJavaScript = NO;
    }

    WKWebView *webView = [[WKWebView alloc] initWithFrame:self.bounds configuration:configuration];
    webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    webView.navigationDelegate = self;
    webView.allowsMagnification = NO;
    if (@available(macOS 12.0, *)) {
        webView.underPageBackgroundColor = NSColor.blackColor;
    }

    self.modernWebView = webView;
    self.rendererView = webView;
    [self addSubview:webView];
    [self updateAnimationTimeInterval];
}

- (BOOL)installLegacyRenderer
{
    Class legacyWebViewClass = NSClassFromString(@"WebView");
    if (legacyWebViewClass == Nil || ![legacyWebViewClass isSubclassOfClass:NSView.class]) {
        return NO;
    }

    [self removeRenderer];

    NSView *webView = [(NSView *)[legacyWebViewClass alloc] initWithFrame:self.bounds];
    webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    if ([webView respondsToSelector:NSSelectorFromString(@"setDrawsBackground:")]) {
        [webView setValue:@NO forKey:@"drawsBackground"];
    }
    if ([webView respondsToSelector:NSSelectorFromString(@"setFrameLoadDelegate:")]) {
        [webView setValue:self forKey:@"frameLoadDelegate"];
    }

    self.legacyWebView = webView;
    self.rendererView = webView;
    [self addSubview:webView];
    [self updateAnimationTimeInterval];
    return YES;
}

- (void)installPreferredRenderer
{
    if (SADShouldUseLegacyWebView() && [self installLegacyRenderer]) {
        return;
    }
    [self installModernRenderer];
}

- (void)removeRenderer
{
    self.modernWebView.navigationDelegate = nil;
    [self.modernWebView stopLoading];
    if ([self.legacyWebView respondsToSelector:NSSelectorFromString(@"setFrameLoadDelegate:")]) {
        [self.legacyWebView setValue:nil forKey:@"frameLoadDelegate"];
    }
    [self.rendererView removeFromSuperview];
    self.modernWebView = nil;
    self.legacyWebView = nil;
    self.legacyPageURL = nil;
    self.rendererView = nil;
    self.presentationSettingsViewportSize = NSZeroSize;
    self.legacyDocumentReady = NO;
    self.legacyAnimationsPrepared = NO;
    self.legacyHasAnimations = NO;
}

- (void)loadSelectedSaver
{
    if (self.selectedSaverIndex < 0 || self.selectedSaverIndex >= (NSInteger)self.savers.count) {
        self.selectedSaverIndex = 0;
    }

    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    NSURL *assetRootURL = [bundle.resourceURL URLByAppendingPathComponent:SADAssetDirectoryName
                                                               isDirectory:YES];
    NSString *filename = self.savers[(NSUInteger)self.selectedSaverIndex][@"filename"];
    NSURL *pageURL = [[assetRootURL URLByAppendingPathComponent:@"all" isDirectory:YES]
                      URLByAppendingPathComponent:[filename stringByAppendingPathExtension:@"html"]];

    if (![NSFileManager.defaultManager fileExistsAtPath:pageURL.path]) {
        [self showErrorMessage:@"The bundled screen saver assets are missing. Rebuild after initializing the after-dark-css submodule."];
        return;
    }

    if (self.modernWebView == nil && self.legacyWebView == nil) {
        [self installPreferredRenderer];
    }

    if (self.modernWebView != nil) {
        [self.modernWebView loadFileURL:pageURL allowingReadAccessToURL:assetRootURL];
        return;
    }

    [self loadLegacyPageURL:pageURL];
}

- (void)loadLegacyPageURL:(NSURL *)pageURL
{
    self.legacyDocumentReady = NO;
    self.legacyAnimationsPrepared = NO;
    self.legacyHasAnimations = NO;
    self.legacyAnimationOffsetMilliseconds = [pageURL.lastPathComponent isEqualToString:@"flying-toasters.html"]
        ? SADLegacyPosterTimeMilliseconds
        : 0.0;
    self.legacyAnimationEpoch = NSProcessInfo.processInfo.systemUptime;
    self.legacyPageURL = pageURL;

    id mainFrame = [self.legacyWebView valueForKey:@"mainFrame"];
    SEL loadRequestSelector = NSSelectorFromString(@"loadRequest:");
    if (![mainFrame respondsToSelector:loadRequestSelector]) {
        [self showErrorMessage:@"The compatibility web renderer is unavailable."];
        return;
    }

    IMP implementation = [mainFrame methodForSelector:loadRequestSelector];
    void (*loadRequest)(id, SEL, NSURLRequest *) = (void *)implementation;
    loadRequest(mainFrame, loadRequestSelector, [NSURLRequest requestWithURL:pageURL]);
}

- (nullable NSString *)evaluateLegacyJavaScript:(NSString *)script
{
    SEL selector = NSSelectorFromString(@"stringByEvaluatingJavaScriptFromString:");
    if (![self.legacyWebView respondsToSelector:selector]) {
        return nil;
    }

    IMP implementation = [self.legacyWebView methodForSelector:selector];
    id (*evaluate)(id, SEL, NSString *) = (void *)implementation;
    id result = evaluate(self.legacyWebView, selector, script);
    return [result isKindOfClass:NSString.class] ? result : nil;
}

- (NSString *)pagePresentationSettingsScriptControllingAnimationSpeed:(BOOL)controlsAnimationSpeed
{
    return [NSString stringWithFormat:
        @"(function (scalePercent, speedPercent, controlsSpeed) {"
         "var animations = document.getAnimations ? document.getAnimations() : [];"
         "var scaleTargets = window.__sadScaleTargets;"
         "if (!scaleTargets && innerWidth > 0 && innerHeight > 0) {"
         "var seen = [];"
         "scaleTargets = [];"
         "animations.forEach(function (animation) {"
         "var target = animation.effect && animation.effect.target;"
         "if (!target || !target.style || seen.indexOf(target) >= 0) return;"
         "seen.push(target);"
         "var forcedForeground = target.matches && target.matches("
         "'.toaster, .toast, .fish, .bubbles, .r, .message');"
         "var fullScreenEffect = target === document.body || target === document.documentElement"
         "|| (target.matches && target.matches('.stars, .rain, .dim, .spotlight'))"
         "|| (target.offsetWidth >= innerWidth * 0.9"
         "&& target.offsetHeight >= innerHeight * 0.9);"
         "if (forcedForeground || !fullScreenEffect) scaleTargets.push(target);"
         "});"
         "window.__sadScaleTargets = scaleTargets;"
         "}"
         "if (!scaleTargets) scaleTargets = [];"
         "var scale = scalePercent / 100;"
         "var supportsIndependentScale = window.CSS && CSS.supports && CSS.supports('scale', '1.25');"
         "scaleTargets.forEach(function (target) {"
         "target.style.setProperty('transform-origin', 'center center', 'important');"
         "target.style.setProperty('image-rendering', 'pixelated', 'important');"
         "if (supportsIndependentScale) {"
         "target.style.removeProperty('zoom');"
         "target.style.setProperty('scale', String(scale), 'important');"
         "} else {"
         "target.style.removeProperty('scale');"
         "target.style.setProperty('zoom', String(scale), 'important');"
         "}"
         "});"
         "var speed = speedPercent / 100;"
         "if (controlsSpeed) {"
         "var timedAnimations = document.getAnimations ? document.getAnimations() : animations;"
         "timedAnimations.forEach(function (animation) {"
         "var currentTime = animation.currentTime;"
         "if (animation.startTime !== null && currentTime !== null"
         "&& !animation.pending && animation.updatePlaybackRate) {"
         "animation.updatePlaybackRate(speed);"
         "} else {"
         "animation.playbackRate = speed;"
         "if (currentTime !== null) animation.currentTime = currentTime;"
         "}"
         "});"
         "}"
         "document.documentElement.dataset.sadObjectScale = String(scalePercent);"
         "document.documentElement.dataset.sadPlaybackSpeed = String(speedPercent);"
         "document.documentElement.dataset.sadScaleTargetCount = String(scaleTargets.length);"
         "return JSON.stringify({scale: scalePercent, speed: speedPercent,"
         "targets: scaleTargets.length});"
         "})(%ld, %ld, %@)",
        (long)self.objectScalePercent,
        (long)self.playbackSpeedPercent,
        controlsAnimationSpeed ? @"true" : @"false"];
}

- (void)applyPagePresentationSettings
{
    if (self.modernWebView != nil) {
        NSString *script = [self pagePresentationSettingsScriptControllingAnimationSpeed:YES];
        [self.modernWebView evaluateJavaScript:script completionHandler:nil];
        return;
    }

    if (self.legacyWebView != nil && self.legacyDocumentReady) {
        [self evaluateLegacyJavaScript:
            [self pagePresentationSettingsScriptControllingAnimationSpeed:NO]];
    }
}

- (void)pauseModernAnimationsIfStopped
{
    if (self.modernWebView == nil || self.isAnimating) {
        return;
    }
    [self.modernWebView evaluateJavaScript:
        @"if (document.getAnimations) {"
         "document.getAnimations().forEach(function (animation) { animation.pause(); });"
         "}"
                               completionHandler:nil];
}

- (BOOL)legacyRendererIsShowingExpectedPage
{
    if (self.legacyWebView == nil || self.legacyPageURL == nil) {
        return NO;
    }

    id URLString = [self.legacyWebView valueForKey:@"mainFrameURL"];
    if (![URLString isKindOfClass:NSString.class]) {
        return NO;
    }

    NSURL *currentURL = [NSURL URLWithString:URLString];
    return currentURL.isFileURL
        && [currentURL.path.stringByStandardizingPath
            isEqualToString:self.legacyPageURL.path.stringByStandardizingPath];
}

- (void)prepareLegacyAnimationsIfNeeded
{
    if (!self.legacyDocumentReady || self.legacyAnimationsPrepared
        || ![self legacyRendererIsShowingExpectedPage]) {
        return;
    }

    NSString *result = [self evaluateLegacyJavaScript:
        @"(function () {"
         "if (document.readyState !== 'complete' || !document.getAnimations) return '';"
         "window.__sadAnimations = document.getAnimations();"
         "window.__sadAnimations.forEach(function (animation) { animation.pause(); });"
         "return String(window.__sadAnimations.length);"
         "})()"];
    if (result.length == 0) {
        return;
    }

    self.legacyAnimationsPrepared = YES;
    self.legacyHasAnimations = result.integerValue > 0;
}

- (void)advanceLegacyAnimationsToMilliseconds:(NSTimeInterval)milliseconds
{
    [self prepareLegacyAnimationsIfNeeded];
    if (!self.legacyHasAnimations) {
        return;
    }

    NSString *time = @((NSInteger)llround(MAX(0.0, milliseconds))).stringValue;
    NSString *script = [NSString stringWithFormat:
        @"(function (time) {"
         "window.__sadAnimations.forEach(function (animation) {"
         "try { animation.currentTime = time; } catch (error) {}"
         "});"
         "void document.documentElement.offsetWidth;"
         "})(%@)", time];
    [self evaluateLegacyJavaScript:script];
    [(NSView *)self.legacyWebView setNeedsDisplay:YES];
}

- (NSTimeInterval)currentLegacyAnimationTimeMilliseconds
{
    if (!self.isAnimating) {
        return self.legacyAnimationOffsetMilliseconds;
    }

    NSTimeInterval elapsed = NSProcessInfo.processInfo.systemUptime - self.legacyAnimationEpoch;
    return self.legacyAnimationOffsetMilliseconds
        + elapsed * 1000.0 * (NSTimeInterval)self.playbackSpeedPercent / 100.0;
}

- (void)setPlaybackSpeedPercentPreservingPhase:(NSInteger)playbackSpeedPercent
{
    NSTimeInterval currentTime = [self currentLegacyAnimationTimeMilliseconds];
    self.playbackSpeedPercent = playbackSpeedPercent;
    self.legacyAnimationOffsetMilliseconds = currentTime;
    self.legacyAnimationEpoch = NSProcessInfo.processInfo.systemUptime;

    if (self.legacyDocumentReady) {
        [self advanceLegacyAnimationsToMilliseconds:currentTime];
    }
}

// WebKitLegacy frame-load delegate callback, kept dynamically typed so the
// bundle does not gain a hard link to the deprecated WebView class.
- (void)webView:(id)webView didFinishLoadForFrame:(id)frame
{
    if (webView != self.legacyWebView || frame != [webView valueForKey:@"mainFrame"]
        || ![self legacyRendererIsShowingExpectedPage]) {
        return;
    }

    // A timer tick can arrive while a same-URL reload still displays its old
    // document. Bind the cached animation array only after the requested main
    // frame finishes, and always replace any cache from the outgoing page.
    self.legacyDocumentReady = YES;
    self.legacyAnimationsPrepared = NO;
    self.legacyHasAnimations = NO;
    [self applyPagePresentationSettings];
    NSTimeInterval milliseconds = [self currentLegacyAnimationTimeMilliseconds];
    if (!self.isAnimating) {
        milliseconds = SADLegacyPosterTimeMilliseconds;
        self.legacyAnimationOffsetMilliseconds = milliseconds;
        self.legacyAnimationEpoch = NSProcessInfo.processInfo.systemUptime;
    }
    [self advanceLegacyAnimationsToMilliseconds:milliseconds];
    [(NSView *)self.legacyWebView displayIfNeeded];
}

- (void)showErrorMessage:(NSString *)message
{
    [self removeRenderer];

    NSTextField *label = [NSTextField wrappingLabelWithString:message];
    label.alignment = NSTextAlignmentCenter;
    label.textColor = NSColor.whiteColor;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:label];
    self.rendererView = label;

    [NSLayoutConstraint activateConstraints:@[
        [label.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [label.widthAnchor constraintLessThanOrEqualToAnchor:self.widthAnchor multiplier:0.8],
    ]];
}

#pragma mark - ScreenSaverView lifecycle

- (void)layout
{
    [super layout];

    // Some macOS hosts initialize legacy modules with an empty frame and size
    // them only after attaching the remote view. Do not rely solely on the
    // autoresizing-mask calculation from a zero-sized starting frame.
    if (self.modernWebView != nil) {
        self.modernWebView.frame = self.bounds;
    } else if ([self.legacyWebView isKindOfClass:NSView.class]) {
        ((NSView *)self.legacyWebView).frame = self.bounds;
    }

    NSSize viewportSize = self.bounds.size;
    if (viewportSize.width > 0.0 && viewportSize.height > 0.0
        && !NSEqualSizes(viewportSize, self.presentationSettingsViewportSize)) {
        self.presentationSettingsViewportSize = viewportSize;
        [self applyPagePresentationSettings];
    }
}

- (void)startAnimation
{
    [self updateAnimationTimeInterval];
    [super startAnimation];
    [self loadSelectedSaver];
}

- (void)stopAnimation
{
    if (self.legacyWebView != nil && self.isAnimating) {
        self.legacyAnimationOffsetMilliseconds = [self currentLegacyAnimationTimeMilliseconds];
        self.legacyAnimationEpoch = NSProcessInfo.processInfo.systemUptime;
    }
    [super stopAnimation];
    [self pauseModernAnimationsIfStopped];

    // Keep the last rendered frame attached. System Settings stops preview
    // animations while their remote views remain visible; removing the web
    // view here exposes only the host's empty grey placeholder. The renderer is
    // reloaded on the next start and released when this view is deallocated.
}

- (void)animateOneFrame
{
    if (self.legacyWebView == nil) {
        return;
    }

    [self advanceLegacyAnimationsToMilliseconds:[self currentLegacyAnimationTimeMilliseconds]];
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView
    decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
    NSURL *URL = navigationAction.request.URL;
    decisionHandler(URL.isFileURL ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}

- (void)webView:(WKWebView *)webView
    didFailNavigation:(WKNavigation *)navigation
    withError:(NSError *)error
{
    if (webView != self.modernWebView) {
        return;
    }
    [self recoverFromModernRendererFailure:error];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation
{
    if (webView != self.modernWebView) {
        return;
    }
    self.retriedModernRenderer = NO;
    [self applyPagePresentationSettings];
    [self pauseModernAnimationsIfStopped];
}

- (void)webView:(WKWebView *)webView
    didFailProvisionalNavigation:(WKNavigation *)navigation
    withError:(NSError *)error
{
    if (webView != self.modernWebView) {
        return;
    }
    [self recoverFromModernRendererFailure:error];
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView
{
    if (webView != self.modernWebView) {
        return;
    }
    NSError *error = [NSError errorWithDomain:@"SADWebRenderer"
                                         code:1
                                     userInfo:@{ NSLocalizedDescriptionKey: @"The WebKit content process terminated." }];
    [self recoverFromModernRendererFailure:error];
}

- (void)recoverFromModernRendererFailure:(NSError *)error
{
    if (self.modernWebView == nil) {
        return;
    }
    if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) {
        return;
    }

    if (SADShouldUseLegacyWebView() && [self installLegacyRenderer]) {
        if (self.isAnimating) {
            [super stopAnimation];
            [super startAnimation];
        }
        NSLog(@"Slightly After Dark: WKWebView failed (%@); using compatibility renderer.", error.localizedDescription);
        [self loadSelectedSaver];
        return;
    }

    if (!self.retriedModernRenderer) {
        self.retriedModernRenderer = YES;
        [self loadSelectedSaver];
        return;
    }

    NSLog(@"Slightly After Dark: WKWebView failed after retrying (%@).", error.localizedDescription);
    [self showErrorMessage:@"The screen saver could not start its web renderer."];
}

#pragma mark - Configuration

- (BOOL)hasConfigureSheet
{
    return YES;
}

- (nullable NSWindow *)configureSheet
{
    if (self.configurationPanel == nil) {
        [self buildConfigurationPanel];
    }

    self.configurationOriginalSaverIndex = self.selectedSaverIndex;
    self.configurationOriginalFrameRate = self.frameRate;
    self.configurationOriginalObjectScalePercent = self.objectScalePercent;
    self.configurationOriginalPlaybackSpeedPercent = self.playbackSpeedPercent;
    [self synchronizeConfigurationControls];
    return self.configurationPanel;
}

- (void)buildConfigurationPanel
{
    NSRect panelFrame = NSMakeRect(0.0, 0.0, 500.0, 340.0);
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:panelFrame
                                                styleMask:NSWindowStyleMaskTitled
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    panel.title = @"Slightly After Dark";

    NSTextField *label = [NSTextField labelWithString:@"Screen saver:"];
    label.frame = NSMakeRect(24.0, 272.0, 110.0, 24.0);
    [panel.contentView addSubview:label];

    NSPopUpButton *popUpButton = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(140.0, 268.0, 332.0, 30.0)
                                                            pullsDown:NO];
    for (NSDictionary<NSString *, NSString *> *saver in self.savers) {
        [popUpButton addItemWithTitle:saver[@"title"]];
    }
    popUpButton.identifier = SADSaverPopUpIdentifier;
    popUpButton.target = self;
    popUpButton.action = @selector(configurationValueChanged:);
    [panel.contentView addSubview:popUpButton];

    NSTextField *frameRateLabel = [NSTextField labelWithString:@"Smoothness:"];
    frameRateLabel.frame = NSMakeRect(24.0, 214.0, 110.0, 24.0);
    [panel.contentView addSubview:frameRateLabel];

    NSSlider *frameRateSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(140.0, 210.0, 240.0, 28.0)];
    frameRateSlider.minValue = SADMinimumFrameRate;
    frameRateSlider.maxValue = SADMaximumFrameRate;
    frameRateSlider.numberOfTickMarks = 4;
    frameRateSlider.allowsTickMarkValuesOnly = NO;
    frameRateSlider.continuous = NO;
    frameRateSlider.identifier = SADFrameRateSliderIdentifier;
    frameRateSlider.target = self;
    frameRateSlider.action = @selector(configurationValueChanged:);
    frameRateSlider.enabled = self.legacyWebView != nil;
    frameRateSlider.toolTip = @"Compatibility renderer frame rate (15–60 FPS)";
    [panel.contentView addSubview:frameRateSlider];

    NSTextField *frameRateValueLabel = [NSTextField labelWithString:@""];
    frameRateValueLabel.frame = NSMakeRect(390.0, 214.0, 82.0, 24.0);
    frameRateValueLabel.alignment = NSTextAlignmentRight;
    [panel.contentView addSubview:frameRateValueLabel];

    NSTextField *objectScaleLabel = [NSTextField labelWithString:@"Object size:"];
    objectScaleLabel.frame = NSMakeRect(24.0, 158.0, 110.0, 24.0);
    [panel.contentView addSubview:objectScaleLabel];

    NSSlider *objectScaleSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(140.0, 154.0, 240.0, 28.0)];
    objectScaleSlider.minValue = SADMinimumObjectScalePercent;
    objectScaleSlider.maxValue = SADMaximumObjectScalePercent;
    objectScaleSlider.numberOfTickMarks = 7;
    objectScaleSlider.allowsTickMarkValuesOnly = YES;
    objectScaleSlider.continuous = NO;
    objectScaleSlider.identifier = SADObjectScaleSliderIdentifier;
    objectScaleSlider.target = self;
    objectScaleSlider.action = @selector(configurationValueChanged:);
    objectScaleSlider.toolTip = @"Scale foreground objects where the saver has them";
    [panel.contentView addSubview:objectScaleSlider];

    NSTextField *objectScaleValueLabel = [NSTextField labelWithString:@""];
    objectScaleValueLabel.frame = NSMakeRect(390.0, 158.0, 82.0, 24.0);
    objectScaleValueLabel.alignment = NSTextAlignmentRight;
    [panel.contentView addSubview:objectScaleValueLabel];

    NSTextField *playbackSpeedLabel = [NSTextField labelWithString:@"Motion speed:"];
    playbackSpeedLabel.frame = NSMakeRect(24.0, 102.0, 110.0, 24.0);
    [panel.contentView addSubview:playbackSpeedLabel];

    NSSlider *playbackSpeedSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(140.0, 98.0, 240.0, 28.0)];
    playbackSpeedSlider.minValue = SADMinimumPlaybackSpeedPercent;
    playbackSpeedSlider.maxValue = SADMaximumPlaybackSpeedPercent;
    playbackSpeedSlider.numberOfTickMarks = 7;
    playbackSpeedSlider.allowsTickMarkValuesOnly = YES;
    playbackSpeedSlider.continuous = NO;
    playbackSpeedSlider.identifier = SADPlaybackSpeedSliderIdentifier;
    playbackSpeedSlider.target = self;
    playbackSpeedSlider.action = @selector(configurationValueChanged:);
    playbackSpeedSlider.toolTip = @"Change animation speed independently of smoothness";
    [panel.contentView addSubview:playbackSpeedSlider];

    NSTextField *playbackSpeedValueLabel = [NSTextField labelWithString:@""];
    playbackSpeedValueLabel.frame = NSMakeRect(390.0, 102.0, 82.0, 24.0);
    playbackSpeedValueLabel.alignment = NSTextAlignmentRight;
    [panel.contentView addSubview:playbackSpeedValueLabel];

    NSTextField *note = [NSTextField wrappingLabelWithString:
        @"Object size affects foreground elements where available. Modern WebKit follows the display refresh rate automatically."];
    note.frame = NSMakeRect(24.0, 48.0, 448.0, 38.0);
    note.textColor = NSColor.secondaryLabelColor;
    note.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    [panel.contentView addSubview:note];

    NSButton *cancelButton = [NSButton buttonWithTitle:@"Cancel"
                                                target:self
                                                action:@selector(performCancel:)];
    cancelButton.frame = NSMakeRect(308.0, 12.0, 80.0, 32.0);
    cancelButton.identifier = SADCancelButtonIdentifier;
    cancelButton.keyEquivalent = @"\e";
    [panel.contentView addSubview:cancelButton];

    NSButton *doneButton = [NSButton buttonWithTitle:@"Done"
                                              target:self
                                              action:@selector(performDone:)];
    doneButton.frame = NSMakeRect(396.0, 12.0, 80.0, 32.0);
    doneButton.identifier = SADDoneButtonIdentifier;
    doneButton.keyEquivalent = @"\r";
    [panel.contentView addSubview:doneButton];
    panel.defaultButtonCell = doneButton.cell;

    self.saverPopUpButton = popUpButton;
    self.frameRateSlider = frameRateSlider;
    self.objectScaleSlider = objectScaleSlider;
    self.playbackSpeedSlider = playbackSpeedSlider;
    self.frameRateValueLabel = frameRateValueLabel;
    self.objectScaleValueLabel = objectScaleValueLabel;
    self.playbackSpeedValueLabel = playbackSpeedValueLabel;
    self.configurationPanel = panel;
}

- (void)synchronizeConfigurationControls
{
    [self.saverPopUpButton selectItemAtIndex:self.selectedSaverIndex];
    self.frameRateSlider.integerValue = self.frameRate;
    self.frameRateSlider.enabled = self.legacyWebView != nil;
    self.objectScaleSlider.integerValue = self.objectScalePercent;
    self.playbackSpeedSlider.integerValue = self.playbackSpeedPercent;
    self.frameRateValueLabel.stringValue = self.legacyWebView != nil
        ? [NSString stringWithFormat:@"%ld FPS", (long)self.frameRate]
        : @"Display";
    self.objectScaleValueLabel.stringValue = [NSString stringWithFormat:@"%ld%%", (long)self.objectScalePercent];
    self.playbackSpeedValueLabel.stringValue = [NSString stringWithFormat:@"%ld%%", (long)self.playbackSpeedPercent];
}

- (void)applyFrameRatePreservingAnimation
{
    BOOL shouldRearmTimer = self.isAnimating && self.legacyWebView != nil;
    NSTimeInterval currentTime = shouldRearmTimer
        ? [self currentLegacyAnimationTimeMilliseconds]
        : self.legacyAnimationOffsetMilliseconds;

    if (shouldRearmTimer) {
        [super stopAnimation];
    }
    [self updateAnimationTimeInterval];
    if (shouldRearmTimer) {
        self.legacyAnimationOffsetMilliseconds = currentTime;
        self.legacyAnimationEpoch = NSProcessInfo.processInfo.systemUptime;
        [super startAnimation];
    }
}

- (void)configurationValueChanged:(id)sender
{
    NSInteger index = self.saverPopUpButton.indexOfSelectedItem;
    if (index < 0 || index >= (NSInteger)self.savers.count) {
        index = 0;
    }

    NSInteger frameRate = (NSInteger)llround(self.frameRateSlider.doubleValue);
    frameRate = MAX(SADMinimumFrameRate, MIN(SADMaximumFrameRate, frameRate));
    NSInteger objectScale = (NSInteger)llround(self.objectScaleSlider.doubleValue / 25.0) * 25;
    objectScale = MAX(SADMinimumObjectScalePercent, MIN(SADMaximumObjectScalePercent, objectScale));
    NSInteger playbackSpeed = (NSInteger)llround(self.playbackSpeedSlider.doubleValue / 25.0) * 25;
    playbackSpeed = MAX(SADMinimumPlaybackSpeedPercent, MIN(SADMaximumPlaybackSpeedPercent, playbackSpeed));

    BOOL saverChanged = index != self.selectedSaverIndex;
    BOOL frameRateChanged = frameRate != self.frameRate;
    BOOL speedChanged = playbackSpeed != self.playbackSpeedPercent;
    self.selectedSaverIndex = index;
    self.objectScalePercent = objectScale;
    if (speedChanged) {
        if (self.legacyWebView != nil) {
            [self setPlaybackSpeedPercentPreservingPhase:playbackSpeed];
        } else {
            self.playbackSpeedPercent = playbackSpeed;
        }
    }
    if (frameRateChanged) {
        self.frameRate = frameRate;
        [self applyFrameRatePreservingAnimation];
    }
    [self synchronizeConfigurationControls];

    if (saverChanged) {
        [self loadSelectedSaver];
    } else {
        [self applyPagePresentationSettings];
    }
}

- (void)performCancel:(id)sender
{
    BOOL saverChanged = self.selectedSaverIndex != self.configurationOriginalSaverIndex;
    BOOL frameRateChanged = self.frameRate != self.configurationOriginalFrameRate;
    self.selectedSaverIndex = self.configurationOriginalSaverIndex;
    self.objectScalePercent = self.configurationOriginalObjectScalePercent;
    if (self.legacyWebView != nil) {
        [self setPlaybackSpeedPercentPreservingPhase:self.configurationOriginalPlaybackSpeedPercent];
    } else {
        self.playbackSpeedPercent = self.configurationOriginalPlaybackSpeedPercent;
    }
    if (frameRateChanged) {
        self.frameRate = self.configurationOriginalFrameRate;
        [self applyFrameRatePreservingAnimation];
    }
    [self synchronizeConfigurationControls];
    if (saverChanged) {
        [self loadSelectedSaver];
    } else {
        [self applyPagePresentationSettings];
    }
    [NSApp endSheet:self.configurationPanel returnCode:NSModalResponseCancel];
}

- (void)performDone:(id)sender
{
    [self configurationValueChanged:sender];
    ScreenSaverDefaults *defaults = [self screenSaverDefaults];
    [defaults setInteger:self.selectedSaverIndex forKey:SADSelectedSaverDefaultsKey];
    [defaults setInteger:self.frameRate forKey:SADFrameRateDefaultsKey];
    [defaults setInteger:self.objectScalePercent forKey:SADObjectScaleDefaultsKey];
    [defaults setInteger:self.playbackSpeedPercent forKey:SADPlaybackSpeedDefaultsKey];
    [defaults synchronize];
    [NSApp endSheet:self.configurationPanel returnCode:NSModalResponseOK];
}

- (void)dealloc
{
    self.modernWebView.navigationDelegate = nil;
    [self.modernWebView stopLoading];
    if ([self.legacyWebView respondsToSelector:NSSelectorFromString(@"setFrameLoadDelegate:")]) {
        [self.legacyWebView setValue:nil forKey:@"frameLoadDelegate"];
    }
}

@end
