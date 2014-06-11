#import "AppDelegate.h"
#import "RootViewController.h"

#include <netinet/in.h>
#import <SystemConfiguration/SCNetworkReachability.h>

#import "GAI.h"
#import "GAIFields.h"
#import "GAITracker.h"
#import "GAIDictionaryBuilder.h"

#import "UAirship.h"
#import "UAConfig.h"
#import "UAPush.h"

#import "People.h"
#import "Leads.h"
#import "Companies.h"
#import "Tasks.h"
#import "Events.h"
#import "Tips.h"
#import "Job.h"

/** Google Analytics configuration constants **/
static NSString *const kGaPropertyId = @"UA-30717261-1"; // Job Agent property ID.
static int const kGaDispatchPeriod = 10;
static NSString *const kAllowTracking = @"allowTracking";
static BOOL *const kGaDryRun = YES;


@implementation AppDelegate

@synthesize window=_window;
@synthesize tabBarController=_tabBarController;
@synthesize navigationController =_navigationController;

@synthesize prevSearch;
@synthesize managedObjectModel;
@synthesize managedObjectContext;
@synthesize persistentStoreCoordinator;
@synthesize applicationDocumentsDirectory;


- (void)applicationDidBecomeActive:(UIApplication *)application {


}

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions {
    
    // get bundle defaults
    [self registerDefaultsFromSettingsBundle];
    
    // get user defaults object
    NSUserDefaults *newDefaults = [NSUserDefaults standardUserDefaults];

    // get system default country code
    [newDefaults setObject:[[NSLocale currentLocale] objectForKey:NSLocaleCountryCode] forKey:@"countryCode"];


    // add values from legacy settings.xml if found
    NSString *settingsFile = [self.applicationDocumentsDirectory stringByAppendingPathComponent:@"userSettings.xml"];
	
	if ([[NSFileManager defaultManager] fileExistsAtPath:settingsFile]) {
		NSDictionary *oldSettings = [NSMutableDictionary dictionaryWithContentsOfFile:settingsFile];
        
        [newDefaults setObject:[oldSettings objectForKey:@"city"] forKey:@"city"];
        [newDefaults setObject:[oldSettings objectForKey:@"state"] forKey:@"state"];
        if ([oldSettings objectForKey:@"postalcode"] != nil) {
            [newDefaults setObject:[oldSettings objectForKey:@"postalcode"] forKey:@"postalcode"];
        }
        [newDefaults setObject:[oldSettings objectForKey:@"country"] forKey:@"countryCode"];

    }
    [newDefaults synchronize];

    
    NSDictionary *appDefaults = @{kAllowTracking: @(YES)};
    
    // User must be able to opt out of tracking
    [GAI sharedInstance].optOut =
    ![[NSUserDefaults standardUserDefaults] boolForKey:kAllowTracking];
    
    [[NSUserDefaults standardUserDefaults] registerDefaults:appDefaults];
    
    // Initialize Google Analytics with a N-second dispatch interval. There is a
    // tradeoff between battery usage and timely dispatch.
    [GAI sharedInstance].dispatchInterval = kGaDispatchPeriod;
    [GAI sharedInstance].trackUncaughtExceptions = YES;
    [[GAI sharedInstance] setDryRun:kGaDryRun];
    // Set the log level to verbose.
//    [[GAI sharedInstance].logger setLogLevel:kGAILogLevelVerbose];
    self.tracker = [[GAI sharedInstance] trackerWithTrackingId:kGaPropertyId];

    // Populate AirshipConfig.plist with your app's info from https://go.urbanairship.com
    // or set runtime properties here.
    UAConfig *config = [UAConfig defaultConfig];
    
    
    // Call takeOff (which creates the UAirship singleton)
    [UAirship takeOff:config];

    // Request a custom set of notification types
    [UAPush shared].notificationTypes = (UIRemoteNotificationTypeBadge |
                                         UIRemoteNotificationTypeSound |
                                         UIRemoteNotificationTypeAlert );
    
    if (launchOptions != nil)
    {
        NSDictionary* dictionary = [launchOptions objectForKey:UIApplicationLaunchOptionsRemoteNotificationKey];
        if (dictionary != nil)
            [self handleRemoteNotification:dictionary];
    }
    
    return TRUE;
    
}

- (void)registerDefaultsFromSettingsBundle
{
    NSLog(@"Registering default values from Settings.bundle");
    NSUserDefaults * defs = [NSUserDefaults standardUserDefaults];
    [defs synchronize];
    
    NSString *settingsBundle = [[NSBundle mainBundle] pathForResource:@"Settings" ofType:@"bundle"];
    
    if(!settingsBundle)
    {
        NSLog(@"Could not find Settings.bundle");
        return;
    }
    
    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:[settingsBundle stringByAppendingPathComponent:@"Root.plist"]];
    NSArray *preferences = [settings objectForKey:@"PreferenceSpecifiers"];
    NSMutableDictionary *defaultsToRegister = [[NSMutableDictionary alloc] initWithCapacity:[preferences count]];
    
    for (NSDictionary *prefSpecification in preferences)
    {
        NSString *key = [prefSpecification objectForKey:@"Key"];
        if (key)
        {
            // check if value readable in userDefaults
            id currentObject = [defs objectForKey:key];
            if (currentObject == nil)
            {
                // not readable: set value from Settings.bundle
                id objectToSet = [prefSpecification objectForKey:@"DefaultValue"];
                [defaultsToRegister setObject:objectToSet forKey:key];
                NSLog(@"Setting object %@ for key %@", objectToSet, key);
            }
            else
            {
                // already readable: don't touch
                NSLog(@"Key %@ is readable (value: %@), nothing written to defaults.", key, currentObject);
            }
        }
    }
    
    [defs registerDefaults:defaultsToRegister];
    [defs synchronize];
}

- (void)application:(UIApplication *)app didReceiveRemoteNotification:(NSDictionary *)userInfo {
    [self handleRemoteNotification:userInfo];
}

-(void)handleRemoteNotification:(NSDictionary*)payload
{
    
    NSString *message = [[payload valueForKey:@"aps"] valueForKey:@"alert"];

    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"News"
                                                    message:message
                                                   delegate:self
                                          cancelButtonTitle:@"Ok"
                                          otherButtonTitles:nil, nil];
    [alert show];
    [UIApplication sharedApplication].applicationIconBadgeNumber = 0;
}


- (BOOL)connectedToNetwork  {
    // Create zero addy
    struct sockaddr_in zeroAddress;
    bzero(&zeroAddress, sizeof(zeroAddress));
    zeroAddress.sin_len = sizeof(zeroAddress);
    zeroAddress.sin_family = AF_INET;
    // Recover reachability flags
    SCNetworkReachabilityRef defaultRouteReachability = SCNetworkReachabilityCreateWithAddress(NULL, (struct sockaddr*)&zeroAddress);
    SCNetworkReachabilityFlags flags;
    BOOL didRetrieveFlags = SCNetworkReachabilityGetFlags(defaultRouteReachability, &flags);
    CFRelease(defaultRouteReachability);
    if (!didRetrieveFlags)
    {
        NSLog(@"Error. Could not recover network reachability flags");
        return 0;
    }
    BOOL isReachable = flags & kSCNetworkFlagsReachable;
    BOOL needsConnection = flags & kSCNetworkFlagsConnectionRequired;
    return (isReachable && !needsConnection) ? YES : NO;
}

#pragma mark log data to Google Analytics


- (void)trackPVFull:(NSString*)screenName :(NSString*)eventCategory :(NSString*)eventAction :(NSString*)eventLabel
{
    
    // Google Analytics v3
    id<GAITracker> tracker = [[GAI sharedInstance] defaultTracker];
    
    // Sending the same screen view hit using [GAIDictionaryBuilder createAppView]
    [tracker send:[[[GAIDictionaryBuilder createAppView] set:screenName
                                                      forKey:kGAIScreenName] build]];
    
    if (eventCategory != nil) {
        // Send category (params) with screen hit
        [tracker send:[[GAIDictionaryBuilder createEventWithCategory:eventCategory     // Event category (required)
                                                          action:eventAction  // Event action (required)
                                                          label:eventLabel          // Event label
                                                          value:nil] build]];    // Event value
    }

    // Clear the screen name field when we're done.
    [tracker set:kGAIScreenName
           value:nil];
}

- (void)trackPV:(NSString*)screenName
{
//    NSLog(@"logging pv for %@",screenName);
    
    // Google Analytics v3
    id<GAITracker> tracker = [[GAI sharedInstance] defaultTracker];
    
    // Sending the same screen view hit using [GAIDictionaryBuilder createAppView]
    [tracker send:[[[GAIDictionaryBuilder createAppView] set:screenName
                                                      forKey:kGAIScreenName] build]];
    
    // Clear the screen name field when we're done.
    [tracker set:kGAIScreenName
           value:nil];
    
}


- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application
{
	// low on memory: do whatever you can to reduce your memory foot print here
}


- (void)applicationDidFinishLaunching:(UIApplication *)application
{
    
	NSManagedObjectContext *context = [self managedObjectContext];
    if (!context) {
        // Handle the error.
    }
	
    Leads *leadsVC = [[Leads alloc] initWithNibName:nil bundle:nil];
    leadsVC.managedObjectContext = context;
	
    Companies *companiesVC = [[Companies alloc] initWithNibName:nil bundle:nil];
    companiesVC.managedObjectContext = context;
	
    People *peopleVC = [[People alloc]  initWithNibName:nil bundle:nil];
    peopleVC.managedObjectContext = context;
    
    Events *eventsVC = [[Events alloc] initWithNibName:nil bundle:nil];
    eventsVC.managedObjectContext = context;
	
    Tasks *tasksVC = [[Tasks alloc] initWithNibName:nil bundle:nil];
    tasksVC.managedObjectContext = context;


    [[UIApplication sharedApplication] registerForRemoteNotificationTypes:(UIRemoteNotificationTypeBadge | UIRemoteNotificationTypeSound)];
}


// Delegation methods
- (void)application:(UIApplication *)app didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)devToken {
    // device token handled by UA library
}

- (void)application:(UIApplication *)app didFailToRegisterForRemoteNotificationsWithError:(NSError *)err {
    NSLog(@"Error in registration. Error: %@", err);
}


/**
 applicationWillTerminate: saves changes in the application's managed object context before the application terminates.
 */
- (void)applicationWillTerminate:(UIApplication *)application {
    
    NSError *error;
    if (managedObjectContext != nil) {
        if ([managedObjectContext hasChanges] && ![managedObjectContext save:&error]) {
            // Handle the error.
        } 
    }
    
    // Store user settings
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults synchronize];

}

- (void)applicationDidEnterBackground:(UIApplication *)application {

    NSError *error;
    if (managedObjectContext != nil) {
        if ([managedObjectContext hasChanges] && ![managedObjectContext save:&error]) {
            // Handle the error.
        } 
    }
    
    
    // Store user settings
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults synchronize];

}

#pragma mark -
#pragma mark Saving

/**
 Performs the save action for the application, which is to send the save:
 message to the application's managed object context.
 */
- (IBAction)saveAction:(id)sender {
    
    NSError *error = nil;
    if (![[self managedObjectContext] save:&error]) {
        // Handle error
		NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
//		exit(-1);  // Fail
    }
	
}

#pragma mark userSettings
/**
 Returns userSettings dictionary. Now used only for recent searches
 */
- (NSMutableDictionary *) getUserSettings {
	
    NSString *settingsFile = [self.applicationDocumentsDirectory stringByAppendingPathComponent:@"userSettings.xml"];
	
	if ([[NSFileManager defaultManager] fileExistsAtPath:settingsFile]) {
		return [NSMutableDictionary dictionaryWithContentsOfFile:settingsFile];
	} else {
        return nil;
    }
}


#pragma mark -
#pragma mark Core Data stack

/**
 Returns the managed object context for the application.
 If the context doesn't already exist, it is created and bound to the persistent store coordinator for the application.
 */
- (NSManagedObjectContext *) managedObjectContext {
    
    if (managedObjectContext != nil) {
        return managedObjectContext;
    }
    
    NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
    if (coordinator != nil) {
        managedObjectContext = [[NSManagedObjectContext alloc] init];
        [managedObjectContext setPersistentStoreCoordinator: coordinator];
    }
    return managedObjectContext;
}


/**
 Returns the managed object model for the application.
 If the model doesn't already exist, it is created by merging all of the models found in the application bundle.
 */
- (NSManagedObjectModel *)managedObjectModel {
    
    if (managedObjectModel != nil) {
        return managedObjectModel;
    }
    managedObjectModel = [NSManagedObjectModel mergedModelFromBundles:nil];    
    return managedObjectModel;
}


/**
 Returns the persistent store coordinator for the application.
 If the coordinator doesn't already exist, it is created and the application's store added to it.
 */
- (NSPersistentStoreCoordinator *)persistentStoreCoordinator {
    
    if (persistentStoreCoordinator != nil) {
        return persistentStoreCoordinator;
    }
    
    NSURL *storeUrl = [NSURL fileURLWithPath: [[self applicationDocumentsDirectory] stringByAppendingPathComponent: @"jobagent.sqlite"]];
    
    NSError *error = nil;
    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
    						 [NSNumber numberWithBool:YES], NSMigratePersistentStoresAutomaticallyOption,
    						 [NSNumber numberWithBool:YES], NSInferMappingModelAutomaticallyOption, nil];
    persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel: [self managedObjectModel]];
    if (![persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeUrl options:options error:&error]) {
        // Handle the error.
    }    
    
    return persistentStoreCoordinator;
}


#pragma mark -
#pragma mark Application's documents directory

/**
 Returns the path to the application's documents directory.
 */
- (NSString *)applicationDocumentsDirectory {
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    return basePath;
}

#pragma mark GET from sqlite
-(NSArray *)getEvents:(NSString *)eventName {
	NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
	[fetchRequest setEntity: [NSEntityDescription entityForName:@"Event" inManagedObjectContext:managedObjectContext]];
	[fetchRequest setResultType:NSDictionaryResultType];
	if (eventName) {
		NSPredicate *predicate = [NSPredicate predicateWithFormat:@"name LIKE %@", eventName];
		[fetchRequest setPredicate:predicate];	
	}
	
	NSError *error = nil;
	return [managedObjectContext executeFetchRequest: fetchRequest error: &error];	
}

-(NSArray *)getJobs:(NSString *)jobName {
	NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
	[fetchRequest setEntity: [NSEntityDescription entityForName:@"Job" inManagedObjectContext:managedObjectContext]];
	[fetchRequest setResultType:NSDictionaryResultType];
	if (jobName) {
		NSPredicate *predicate = [NSPredicate predicateWithFormat:@"title LIKE %@", jobName];
		[fetchRequest setPredicate:predicate];	
	}
	
	NSError *error = nil;
	return [managedObjectContext executeFetchRequest: fetchRequest error: &error];
	
}


-(NSArray *)getCompanies:(NSString *)companyName {
	NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
	[fetchRequest setEntity: [NSEntityDescription entityForName:@"Company" inManagedObjectContext:managedObjectContext]];
	[fetchRequest setResultType:NSDictionaryResultType];
	if (companyName.length > 0) {
		NSPredicate *predicate = [NSPredicate predicateWithFormat:@"coName LIKE %@", companyName];
		[fetchRequest setPredicate:predicate];	
	}
	
	NSError *error = nil;
	return [managedObjectContext executeFetchRequest: fetchRequest error: &error];
	
}

#pragma mark SAVE to DB

- (void)setCompany:(NSString *)companyName {
	if ([companyName length] > 0) {
		NSFetchRequest *companyFetchRequest = [[NSFetchRequest alloc] init];
		[companyFetchRequest setEntity: [NSEntityDescription entityForName:@"Company" inManagedObjectContext:managedObjectContext]];
		NSPredicate *predicate = [NSPredicate predicateWithFormat:@"coName LIKE[cd] %@", companyName];
		[companyFetchRequest setPredicate:predicate];	
		
		NSError *error = nil;
		NSArray *companies = [managedObjectContext executeFetchRequest: companyFetchRequest error: &error];
		
		if ([companies count] == 0) {
			// insert new company
			NSManagedObject *company = [NSEntityDescription insertNewObjectForEntityForName: @"Company" inManagedObjectContext: managedObjectContext];
			[company setValue:companyName forKey:@"coName"];	
		} else {
			// company already exists
		}
		
	}
}

-(NSArray *)getPeople:(NSString *)personName {
	NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
	[fetchRequest setEntity: [NSEntityDescription entityForName:@"Person" inManagedObjectContext:managedObjectContext]];
	[fetchRequest setResultType:NSDictionaryResultType];
	if (personName) {
		NSPredicate *predicate = [NSPredicate predicateWithFormat:@"name LIKE %@", personName];
		[fetchRequest setPredicate:predicate];	
	}
	
	NSError *error = nil;
	return [managedObjectContext executeFetchRequest: fetchRequest error: &error];
	
}

-(NSArray *)getPerson:(NSString *)personName {
        NSString *firstName = [NSString stringWithFormat:@"%@",[personName substringToIndex:[personName rangeOfString:@" "].location]];
        NSString *lastName = [personName substringFromIndex:[personName rangeOfString:@" "].location+1];
        NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
        [fetchRequest setEntity: [NSEntityDescription entityForName:@"Person" inManagedObjectContext:managedObjectContext]];
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"firstName LIKE[cd] %@ AND lastName LIKE[cd] %@", firstName, lastName];
        [fetchRequest setPredicate:predicate];	
        
        NSError *error = nil;
        NSArray *people = [managedObjectContext executeFetchRequest: fetchRequest error: &error];
        return people;
}


- (void)setPerson:(NSString *)personName withCo:(NSString *)companyName {
	if ([personName length] > 0) {
		NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
		[fetchRequest setEntity: [NSEntityDescription entityForName:@"Person" inManagedObjectContext:managedObjectContext]];

        NSString *firstName = @"";
        NSString *lastName = personName;
        NSPredicate *predicate;

        if ([personName rangeOfString:@" "].location != NSNotFound) {
            firstName = [personName substringToIndex:[personName rangeOfString:@" "].location];
            lastName = [personName substringFromIndex:[personName rangeOfString:@" "].location+1];
            predicate = [NSPredicate predicateWithFormat:@"lastName LIKE[c] %@ AND firstName LIKE[c] %@", lastName, firstName];
        } else {
            predicate = [NSPredicate predicateWithFormat:@"lastName LIKE[c] %@ AND NOT firstName.length > 0", lastName];
        }
		[fetchRequest setPredicate:predicate];	
		
		NSError *error = nil;
        NSArray *people = [managedObjectContext executeFetchRequest: fetchRequest error: &error];

		if ([people count] == 0) { 	// person not found
			// insert new person
			NSManagedObject *person = [NSEntityDescription insertNewObjectForEntityForName: @"Person" inManagedObjectContext: managedObjectContext];

			[person setValue:firstName forKey:@"firstName"];	
			[person setValue:lastName forKey:@"lastName"];	
			[person setValue:companyName forKey:@"company"];	
		}
		
	}
}




@end