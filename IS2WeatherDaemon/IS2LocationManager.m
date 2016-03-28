//
//  IS2LocationManager.m
//  
//
//  Created by Matt Clarke on 06/03/2016.
//
//

#import "IS2LocationManager.h"

@implementation IS2LocationManager

-(id)init {
    self = [super init];
    
    if (self) {
        self.locationManager = [[CLLocationManager alloc] init];
        
        // We'll default to manual updating.
        _interval = kManualUpdate;
        
        [self.locationManager setDesiredAccuracy:kCLLocationAccuracyBest];
        [self.locationManager setDistanceFilter:kCLDistanceFilterNone];
        [self.locationManager setDelegate:self];
        [self.locationManager setActivityType:CLActivityTypeAutomotiveNavigation]; // Allows use of GPS
        
        authorisationStatus = kCLAuthorizationStatusNotDetermined;
    }
    
    return self;
}

-(void)setLocationUpdateInterval:(IS2LocationUpdateInterval)interval {
    switch (interval) {
        case kTurnByTurn:
            [self.locationManager stopUpdatingLocation];
            [self.locationManager setDesiredAccuracy:kCLLocationAccuracyBest];
            [self.locationManager setDistanceFilter:10];
            [self.locationManager startUpdatingLocation];
            break;
        case k100Meters:
            [self.locationManager stopUpdatingLocation];
            [self.locationManager setDesiredAccuracy:kCLLocationAccuracyBest];
            [self.locationManager setDistanceFilter:100];
            [self.locationManager startUpdatingLocation];
            break;
        case k1Kilometer:
            [self.locationManager stopUpdatingLocation];
            [self.locationManager setDesiredAccuracy:kCLLocationAccuracyHundredMeters];
            [self.locationManager setDistanceFilter:500];
            [self.locationManager startUpdatingLocation];
            break;
        case kManualUpdate:
            [self.locationManager setDesiredAccuracy:kCLLocationAccuracyBest];
            [self.locationManager setDistanceFilter:kCLDistanceFilterNone];
            [self.locationManager stopUpdatingLocation];
            break;
            
        default:
            break;
    }
    
    _interval = interval;
}

-(void)registerNewCallbackForLocationData:(void(^)(CLLocation*))callback {
    if (!_locationCallbacks) {
        _locationCallbacks = [NSMutableArray array];
    }
    
    [_locationCallbacks addObject:callback];
}

-(void)registerNewCallbackForAuth:(void(^)(int))callback {
    if (!_authCallbacks) {
        _authCallbacks = [NSMutableArray array];
    }
    
    [_authCallbacks addObject:callback];
}

-(int)currentAuthorisationStatus {
    return authorisationStatus;
}

- (void)locationManager:(id)arg1 didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    NSLog(@"[InfoStats2d | Location Manager] :: Auth state changed to %d.", status);
    
    int oldStatus = authorisationStatus;
    authorisationStatus = status;
    
    for (void(^callback)(int) in _authCallbacks) {
        callback(authorisationStatus);
    }
    
    if (oldStatus == kCLAuthorizationStatusAuthorized && oldStatus != status) {
        [self.locationManager stopUpdatingLocation];
    } else if (_interval != kManualUpdate && authorisationStatus == kCLAuthorizationStatusAuthorized) {
        [self.locationManager startUpdatingLocation];
    }
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
    NSLog(@"[InfoStats2d | Location Manager] :: Did update locations, with array count %d.", locations.count);
    
    if (_locationStoppedTimer) {
        [_locationStoppedTimer invalidate];
        _locationStoppedTimer = nil;
    }
    
    // Locations updated! We can now ask for an update to weather with the new locations.
    CLLocation *mostRecentLocation = [[locations lastObject] copy];

    // Give callbacks our new location.
    for (void(^callback)(CLLocation*) in _locationCallbacks) {
        callback(mostRecentLocation);
    }
    
    if (_interval == kManualUpdate) {
        [self.locationManager stopUpdatingLocation];
    } else {
        _locationStoppedTimer = [NSTimer scheduledTimerWithTimeInterval:5 target:self selector:@selector(_locationStoppedTimer:) userInfo:nil repeats:NO];
    }
}

-(void)_locationStoppedTimer:(id)sender {
    [_locationStoppedTimer invalidate];
    _locationStoppedTimer = nil;
    
    // Get one last location.
    
}

@end
