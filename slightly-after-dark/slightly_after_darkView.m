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
@property (strong, nonatomic)          WebView      *webView;

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
        NSInteger index = [defaults integerForKey:@"ScreenSaver"] > 0 ? [defaults integerForKey:@"ScreenSaver"] : 1;
        
        //webview
        _webView = [[WebView alloc] initWithFrame:[self bounds]];
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
        
        //set our saver
        [self setScreenSaverForIndex:index];
        
        //set our selected saver in options TODO: make me work
        [_comboBox selectItemAtIndex:index];
        [_comboBox setObjectValue: [_savers objectAtIndex:index]];
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

- (void)setScreenSaverForIndex:(NSInteger)index
{
    NSURL *mainWebPageURL = [[NSBundle bundleForClass:[self class]] URLForResource:[_savers[index] objectForKey:@"filename"]
                                                                     withExtension:@"html"
                                                                      subdirectory:@"after-dark-css/all"];
    
    [[_webView mainFrame] loadRequest:[NSURLRequest requestWithURL:mainWebPageURL]];

    [self stopAnimation];
    [self startAnimation];
}

// ------------------------------------------------------------------------------------
#pragma mark - screen saver view
// ------------------------------------------------------------------------------------

- (void)startAnimation
{
    [super startAnimation];
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

- (IBAction)performDone:(id)sender
{
    NSInteger index = [_comboBox indexOfSelectedItem];
    
    ScreenSaverDefaults *defaults = [ScreenSaverDefaults defaultsForModuleWithName:@"com.httpster.slightly-after-dark"];
    [defaults setInteger:index forKey:@"ScreenSaver"];
    [defaults synchronize];
    
    [self setScreenSaverForIndex:index];
    [NSApp endSheet:_optionsPanel];
}

@end
