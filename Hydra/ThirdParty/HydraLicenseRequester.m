#import "HydraLicenseRequester.h"

#define HYDRA_STORE_LINK @"http://sdegutis.github.io/hydra/"

@interface HydraLicenseRequester ()
@property NSString* email;
@property NSString* license;
@property NSString* error;
@end

@implementation HydraLicenseRequester

- (NSString*) windowNibName {
    return @"HydraLicenseRequester";
}

- (void) request {
    return; // uncomment during commits, until its done.
    
    // this is so we can cmd-tab to it; not ideal but too hard to get perfect
    [[NSApplication sharedApplication] setActivationPolicy:NSApplicationActivationPolicyRegular];
    
    if (![[self window] isVisible])
        [[self window] center];
    
    [[self window] orderFrontRegardless];
}

- (IBAction) acquire:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:HYDRA_STORE_LINK]];
}

static NSString* normalize(NSString* s) {
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (IBAction) validate:(id)sender {
    self.email = normalize(self.email);
    self.license = normalize(self.license);
    
    BOOL valid = [self.delegate tryLicense:self.license forEmail:self.email];
    if (valid) {
        NSAlert* alert = [[NSAlert alloc] init];
        alert.icon = [NSImage imageNamed:@"thumbsup.png"];
        alert.messageText = @"Your licensed verified successfully.";
        alert.informativeText = @"Thank you for your support! I hope you have a ton of fun using Hydra to do really cool things and also I hope that it increases your productivity by a ton.";
        [alert addButtonWithTitle:@"Continue Using Hydra"];
        [alert beginSheetModalForWindow:[self window]
                      completionHandler:^(NSModalResponse returnCode) {
                          [self.delegate closed];
                      }];
    }
    else {
        self.error = @"Invalid. Try again.";
    }
}

- (BOOL) enteredBothFields {
    self.error = nil;
    return [normalize(self.email) length] > 0 && [normalize(self.license) length] > 0;
}

+ (NSSet*) keyPathsForValuesAffectingEnteredBothFields {
    return [NSSet setWithArray:@[@"email", @"license"]];
}

@end