//
//  slightly_after_darkView.m
//  slightly-after-dark
//
//  Created by dusty on 4/19/14.
//  Copyright (c) 2014 httpster. All rights reserved.
//

#import <WebKit/WebKit.h>

#import "slightly_after_darkView.h"

// ------------------------------------------------------------------------------------

typedef enum {
    SAVER_TOASTERS,
    SAVER_SIZE
} ScreenSaverType;

// ------------------------------------------------------------------------------------

@interface slightly_after_darkView()

@property (strong, nonatomic) IBOutlet  NSComboBox  *comboBox;
@property (strong, nonatomic)           NSArray     *comboBoxData;
@property (strong, nonatomic) IBOutlet  NSPanel     *optionsPanel;
@property (strong, nonatomic)           WebView     *webView;

@end

// ------------------------------------------------------------------------------------

@implementation slightly_after_darkView

// ------------------------------------------------------------------------------------
#pragma mark - init
// ------------------------------------------------------------------------------------

- (id)initWithFrame:(NSRect)frame isPreview:(BOOL)isPreview
{
    self = [super initWithFrame:frame isPreview:isPreview];
    if (self) {
        [self setAnimationTimeInterval:1/30.0];
//
//        NSDictionary *appDefaults = [NSDictionary dictionaryWithObject:SAVER_TOASTERS
//                                                                forKey:@"ScreenSaver"];
//        [[NSUserDefaults standardUserDefaults] registerDefaults:appDefaults];
        _comboBoxData = @[@"Flying Toasters", @"Fish", @"Globe", @"Hard Rain",
                          @"Bouncing Ball", @"Warp", @"Messages", @"Messages 2",
                          @"Fade Out", @"Logo", @"Rainstorm", @"Spotlight"];
        _webView = [[WebView alloc] initWithFrame:[self bounds]];
    }
    return self;
}

// ------------------------------------------------------------------------------------
#pragma mark - NSComboBoxDataSource methods
// ------------------------------------------------------------------------------------

- (NSInteger)numberOfItemsInComboBox:(NSComboBox *)aComboBox
{
    return _comboBoxData.count;
}

- (id)comboBox:(NSComboBox *)aComboBox objectValueForItemAtIndex:(NSInteger)index
{
    return _comboBoxData[index];
}

#pragma mark - screen saver helpers

- (void)setScreenSaverTo:(ScreenSaverType)screenSaver
{
    NSString *frameURL = nil;
    switch (screenSaver) {
        case SAVER_TOASTERS:
            frameURL = @"http://bryanbraun.github.io/after-dark-css/all/flying-toasters.html";
        break;
        default:
            // ..
        break;
    }
    [_webView setMainFrameURL:frameURL];
}

// ------------------------------------------------------------------------------------
#pragma mark - screen saver methods
// ------------------------------------------------------------------------------------

- (void)startAnimation
{
    [super startAnimation];
    
    [_webView setFrameLoadDelegate:self];
    [_webView setShouldUpdateWhileOffscreen:YES];
    [_webView setPolicyDelegate:self];
    [_webView setUIDelegate:self];
    [_webView setEditingDelegate:self];
    [_webView setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
    [_webView setAutoresizesSubviews:YES];
    [_webView setDrawsBackground:NO];
    [self addSubview:_webView];
    
    NSColor *color = [NSColor colorWithCalibratedWhite:0.0 alpha:1.0];
    [[_webView layer] setBackgroundColor:color.CGColor];
    
//    ScreenSaverType defaultScreenSaver = (ScreenSaverType) [[NSUserDefaults standardUserDefaults] objectForKey:@"ScreenSaver"];

    [self setScreenSaverTo:SAVER_TOASTERS];
}

- (void)stopAnimation
{
    [super stopAnimation];
}

- (void)drawRect:(NSRect)rect
{
    [super drawRect:rect];
}

- (void)animateOneFrame
{
    return;
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

@end
