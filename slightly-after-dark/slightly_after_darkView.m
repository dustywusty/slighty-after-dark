//
//  slightly_after_darkView.m
//  slightly-after-dark
//
//  Created by dusty on 4/19/14.
//  Copyright (c) 2014 httpster. All rights reserved.
//

#import <WebKit/WebKit.h>

#import "slightly_after_darkView.h"

@interface slightly_after_darkView()

@property (strong, nonatomic) IBOutlet NSComboBox   *comboBox;
@property (strong, nonatomic) IBOutlet NSPanel      *optionsPanel;
@property (strong, nonatomic)          NSArray      *savers;
@property (strong, nonatomic)          WKWebView    *webView;
@property (assign, nonatomic)          NSInteger    screenSaverIndex;

@end

@implementation slightly_after_darkView

// ------------------------------------------------------------------------------------
#pragma mark - init
// ------------------------------------------------------------------------------------

- (id)initWithFrame:(NSRect)frame isPreview:(BOOL)isPreview
{
    self = [super initWithFrame:frame isPreview:isPreview];
    if (self) {

        // cool screensaverview stuff
        [self setAnimationTimeInterval:1/30.0];
        
        //savers
        _savers = [NSArray arrayWithObjects:
                   @{
                     @"title" : @"Flying Toasters",
                     @"filename" : @"flying-toasters"
                     },
                   @{
                     @"title" : @"Fish",
                     @"filename" : @"fish"
                     },
                   @{
                     @"title" : @"Globe",
                     @"filename" : @"globe"
                     },
                   @{
                     @"title" : @"Hard Rain",
                     @"filename" : @"hard-rain"
                     },
                   @{
                     @"title" : @"Bouncing Ball",
                     @"filename" : @"bouncing-ball"
                     },
                   @{
                     @"title" : @"Warp",
                     @"filename" : @"warp"
                     },
                   @{
                     @"title" : @"Messages",
                     @"filename" : @"messages"
                     },
                   @{
                     @"title" : @"Messages 2",
                     @"filename" : @"messages2"
                     },
                   @{
                     @"title" : @"Fade Out",
                     @"filename" : @"fade-out"
                     },
                   @{
                     @"title" : @"Logo",
                     @"filename" : @"logo"
                     },
                   @{
                     @"title" : @"Rainstorm",
                     @"filename" : @"rainstorm"
                     },
                   @{
                     @"title" : @"Spotlight",
                     @"filename" : @"spotlight"
                     }
        , nil];
        
        //defaults
        ScreenSaverDefaults *defaults = [ScreenSaverDefaults defaultsForModuleWithName:@"com.httpster.slightly-after-dark"];
        [defaults registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
                                    [NSNumber numberWithInt:1], @"ScreenSaver",
                                    nil]];
        NSInteger index = [defaults integerForKey:@"ScreenSaver"];
        _screenSaverIndex = (index >= 0 && index < _savers.count) ? index : 0;

        // WKWebView is created in startAnimation and released in stopAnimation so
        // the wallpaper host cannot retain an animated page after the saver stops.
        [self setWantsLayer:YES];
        self.layer.backgroundColor = NSColor.blackColor.CGColor;
        
        //set our selected saver in options TODO: make me work
        [_comboBox selectItemAtIndex:_screenSaverIndex];
        [_comboBox setObjectValue:[_savers objectAtIndex:_screenSaverIndex]];
    }
    return self;
}

// ------------------------------------------------------------------------------------
#pragma mark - NSComboBoxDataSource delegate methods
// ------------------------------------------------------------------------------------

- (NSInteger)numberOfItemsInComboBox:(NSComboBox *)aComboBox
{
    return _savers.count;
}

- (id)comboBox:(NSComboBox *)aComboBox objectValueForItemAtIndex:(NSInteger)index
{
    return [_savers[index] objectForKey:@"title"];
}

// ------------------------------------------------------------------------------------
#pragma mark - screen saver helper
// ------------------------------------------------------------------------------------

- (void)createWebViewIfNeeded
{
    if (_webView) {
        return;
    }

    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];

    _webView = [[WKWebView alloc] initWithFrame:self.bounds configuration:configuration];
    _webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    if (@available(macOS 12.0, *)) {
        _webView.underPageBackgroundColor = NSColor.blackColor;
    }

    [self addSubview:_webView];
}

- (void)loadSelectedScreenSaver
{
    NSURL *mainWebPageURL = [[NSBundle bundleForClass:[self class]] URLForResource:[_savers[_screenSaverIndex] objectForKey:@"filename"]
                                                                     withExtension:@"html"
                                                                      subdirectory:@"after-dark-css/all"];
    if (!mainWebPageURL) {
        return;
    }

    NSURL *resourceDirectoryURL = [[mainWebPageURL URLByDeletingLastPathComponent] URLByDeletingLastPathComponent];
    [_webView loadFileURL:mainWebPageURL allowingReadAccessToURL:resourceDirectoryURL];
}

- (void)tearDownWebView
{
    [_webView stopLoading];
    [_webView removeFromSuperview];
    _webView = nil;
}

- (void)setScreenSaverForIndex:(NSInteger)index
{
    if (index < 0 || index >= _savers.count) {
        return;
    }

    _screenSaverIndex = index;
    if (_webView) {
        [self loadSelectedScreenSaver];
    }
}

// ------------------------------------------------------------------------------------
#pragma mark - screen saver view
// ------------------------------------------------------------------------------------

- (void)startAnimation
{
    [super startAnimation];
    [self createWebViewIfNeeded];
    [self loadSelectedScreenSaver];
}

- (void)stopAnimation
{
    [super stopAnimation];
    [self tearDownWebView];
}

- (void)drawRect:(NSRect)rect
{
    [super drawRect:rect];
}

- (void)animateOneFrame
{
    return;
}

- (void)dealloc
{
    [self tearDownWebView];
}

// ------------------------------------------------------------------------------------
#pragma mark - option panel
// ------------------------------------------------------------------------------------

- (BOOL)hasConfigureSheet
{
    return YES;
}

- (NSWindow*)configureSheet
{
    if (!_optionsPanel) {
        [[NSBundle bundleForClass:[self class]] loadNibNamed:@"optionsPanel" owner:self topLevelObjects:nil];
    }
    return _optionsPanel;
}

- (IBAction)performCancel:(id)sender
{
    [NSApp endSheet:_optionsPanel];
}

- (IBAction)performDone:(id)sender
{
    NSInteger index = [_comboBox indexOfSelectedItem];
    if (index < 0 || index >= _savers.count) {
        [NSApp endSheet:_optionsPanel];
        return;
    }
    
    ScreenSaverDefaults *defaults = [ScreenSaverDefaults defaultsForModuleWithName:@"com.httpster.slightly-after-dark"];
    [defaults setInteger:index forKey:@"ScreenSaver"];
    [defaults synchronize];
    
    [self setScreenSaverForIndex:index];
    [NSApp endSheet:_optionsPanel];
}

@end
