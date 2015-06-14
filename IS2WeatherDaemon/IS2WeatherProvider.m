//
//  IS2WeatherProvider.m
//  InfoStats2
//
//  Created by Matt Clarke on 02/06/2015.
//

/*
 *
 *  Updating weather on iOS is a glorious pain in the arse. This daemon simplifies things 
 *  nicely enough for it all to work, and be readable too when doing so. Enjoy!
 *
 *  I don't recommend iterfacing with this daemon yourself; please use the provided public
 *  API, else you may release gremlins into your system.
 *
 *  Licensed under the BSD license.
 *
 */

#import "IS2WeatherProvider.h"
#import <Weather/TWCCityUpdater.h>
#import <objc/runtime.h>
#import <Weather/Weather.h>
#import "Reachability.h"
#import <notify.h>

@interface WeatherPreferences (iOS7)
- (id)loadSavedCityAtIndex:(int)arg1;
@end

@interface WeatherLocationManager (iOS8)
- (bool)localWeatherAuthorized;
- (void)_setAuthorizationStatus:(int)arg1;
- (void)setLocationTrackingReady:(bool)arg1 activelyTracking:(bool)arg2;
@end

@interface City (iOS7)
@property (assign, nonatomic) BOOL isRequestedByFrameworkClient;
@end

@interface TWCLocationUpdater : TWCUpdater
+(id)sharedLocationUpdater;
-(void)updateWeatherForLocation:(id)arg1 city:(id)arg2 withCompletionHandler:(id)arg3;
@end

@interface CLLocationManager (Private)
+(void)setAuthorizationStatus:(bool)arg1 forBundleIdentifier:(id)arg2;
-(id)initWithEffectiveBundleIdentifier:(id)arg1;
-(void)requestAlwaysAuthorization;
-(void)setPausesLocationUpdatesAutomatically:(bool)arg1;
-(void)setPersistentMonitoringEnabled:(bool)arg1;
-(void)setPrivateMode:(bool)arg1;
@end

static City *currentCity;
static int notifyToken;
static int authorisationStatus;

@implementation IS2WeatherUpdater

-(id)init {
    [City initialize];
    
    self = [super init];
    if (self) {
        self.locationManager = [[CLLocationManager alloc] init];
        [self.locationManager setDesiredAccuracy:kCLLocationAccuracyKilometer];
        [self.locationManager setDistanceFilter:500.0];
        [self.locationManager setDelegate:self];
        [self.locationManager setActivityType:CLActivityTypeOther];
        
        if ([self.locationManager respondsToSelector:@selector(setPersistentMonitoringEnabled:)]) {
            [self.locationManager setPersistentMonitoringEnabled:NO];
        }
        
        if ([self.locationManager respondsToSelector:@selector(setPrivateMode:)]) {
            [self.locationManager setPrivateMode:YES];
        }

        authorisationStatus = kCLAuthorizationStatusNotDetermined;
    }
    
    return self;
}

-(void)updateWeather {
    Reachability *reach = [Reachability reachabilityForInternetConnection];
    
    if (reach.isReachable) {
        [self fullUpdate];
        return;
    } else {
        // No data connection; allow for extrapolated data to be used instead from
        // the current City instance.
        NSLog(@"*** [InfoStats2 | Weather] :: No data connection; using extrapolated data from last update.");
        notify_post("com.matchstic.infostats2/weatherUpdateCompleted");
        return;
    }
}

// Backend

-(void)fullUpdate {
    //BOOL localWeather = [CLLocationManager locationServicesEnabled];
    
    if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 8.0) {
        [[WeatherLocationManager sharedWeatherLocationManager] setLocationTrackingReady:NO activelyTracking:NO];
        [[WeatherLocationManager sharedWeatherLocationManager] _setAuthorizationStatus:authorisationStatus];
    }
    
    if (authorisationStatus == kCLAuthorizationStatusAuthorized) {
        NSLog(@"*** [InfoStats2 | Weather] :: Updating, and also getting a new location");
        
        currentCity = [[WeatherPreferences sharedPreferences] localWeatherCity];
        [currentCity associateWithDelegate:self];
        
        [[WeatherPreferences sharedPreferences] setLocalWeatherEnabled:YES];
        
        // Force finding of new location, and then update from there.
        [self.locationManager startUpdatingLocation];
    } else if (authorisationStatus == kCLAuthorizationStatusDenied) {
        NSLog(@"*** [InfoStats2 | Weather] :: Updating first city in Weather.app");
        
        currentCity = [[WeatherPreferences sharedPreferences] loadSavedCityAtIndex:0];
        [currentCity associateWithDelegate:self];
        
        [[WeatherPreferences sharedPreferences] setLocalWeatherEnabled:NO];
        
        [self updateCurrentCityWithoutLocation];
    }
}

-(void)updateLocalCityWithLocation:(CLLocation*)location {
    if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 8.0) {
        [[objc_getClass("TWCLocationUpdater") sharedLocationUpdater] updateWeatherForLocation:location city:currentCity];
    } else {
        [[LocationUpdater sharedLocationUpdater] updateWeatherForLocation:location city:currentCity];
    }
}

-(void)updateCurrentCityWithoutLocation {
    if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 8.0)
        [[objc_getClass("TWCCityUpdater") sharedCityUpdater] updateWeatherForCity:currentCity];
    else
        [[WeatherIdentifierUpdater sharedWeatherIdentifierUpdater] updateWeatherForCity:currentCity];
}

#pragma mark Delegates

-(void)cityDidStartWeatherUpdate:(id)city {
    // Nothing to do here currently.
}

-(void)cityDidFinishWeatherUpdate:(City*)city {
    currentCity = city;
    
    // We should save this data to be loaded into the SpringBoard portion.
    
    /*
     * WeatherPreferences seems to be a pain when saving cities, and requires isCelsius to 
     * be re-set again. No idea why, but hey, goddammit Apple.
     */
    BOOL isCelsius = [[WeatherPreferences sharedPreferences] isCelsius];
    
    if ([currentCity isLocalWeatherCity]) {
        [[WeatherPreferences sharedPreferences] saveToDiskWithLocalWeatherCity:city];
    } else {
        NSMutableArray *cities = [[[WeatherPreferences sharedPreferences] loadSavedCities] mutableCopy];
        [cities removeObjectAtIndex:0];
        [cities insertObject:city atIndex:0];
        
        [[WeatherPreferences sharedPreferences] saveToDiskWithCities:cities activeCity:0];
    }
    
    [[WeatherPreferences sharedPreferences] setCelsius:isCelsius];
    
    NSLog(@"*** [InfoStats2 | Weather] :: Updated, returning data.");
    
    // Return a message back to SpringBoard that updating is now done.
    notify_post("com.matchstic.infostats2/weatherUpdateCompleted");
}

- (void)locationManager:(id)arg1 didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    NSLog(@"*** [InfoStats2 | Weather] :: Location manager auth state changed to %d.", status);
    
    int oldStatus = authorisationStatus;
    authorisationStatus = status;
    
    if (oldStatus == kCLAuthorizationStatusAuthorized && oldStatus != status) {
        [self.locationManager stopUpdatingLocation];
        
        // That update failed. We should re-run for first city in Weather.app
        [self updateWeather];
    }
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
    NSLog(@"*** [InfoStats2 | Weather] :: Location manager did update locations.");
    
    // Locations updated! We can now ask for an update to weather with the new locations.
    CLLocation *mostRecentLocation = [[locations lastObject] copy];
    [self updateLocalCityWithLocation:mostRecentLocation];
    
    [self.locationManager stopUpdatingLocation];
}

#pragma mark Message listening from SpringBoard

- (void)timerFireMethod:(NSTimer *)timer {
    
	int status, check;
	static char first = 0;
	if (!first) {
		status = notify_register_check("com.matchstic.infostats2/requestWeatherUpdate", &notifyToken);
		if (status != NOTIFY_STATUS_OK) {
			fprintf(stderr, "registration failed (%u)\n", status);
			return;
		}
        
		first = 1;
        
        return; // We don't want to update the weather on the first run, only when requested.
	}
    
	status = notify_check(notifyToken, &check);
	if (status == NOTIFY_STATUS_OK && check != 0) {
		NSLog(@"*** [InfoStats2 | Weather] :: Weather update request received.");
        
        dispatch_async(dispatch_get_main_queue(), ^(void){
            [self updateWeather];
        });
	}
}

@end
