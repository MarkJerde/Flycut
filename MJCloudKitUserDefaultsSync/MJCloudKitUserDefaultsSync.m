//
//  MJCloudKitUserDefaultsSync.m
//
//  Created by Mark Jerde (http://github.com/MarkJerde)
//  Copyright (C) 2017 by Mark Jerde
//
//  Based on MKiCloudSync by Mugunth Kumar (@mugunthkumar)
//  Portions Copyright (C) 2011-2020 by Steinlogic

//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

//  As a side note, you might also consider
//	1) tweeting about this mentioning @mark_a_jerde
//	2) A paypal donation to mark.a.jerde@gmail.com
//	3) tweeting about this mentioning @mugunthkumar for his original contributions
//	4) A paypal donation to mugunth.kumar@gmail.com


#import "MJCloudKitUserDefaultsSync.h"
#import <CloudKit/CloudKit.h>

static NSString *prefix;
static NSArray *matchList;
static CKDatabase *publicDB;
static CKDatabase *privateDB;
static BOOL observingIdentityChanges = NO;
static BOOL observingActivity = NO;
static NSTimer *pollCloudKitTimer;
static int lastKnownLaunches = -1;
static NSString *databaseContainerIdentifier = nil;
static NSString *recordZoneName = @"MJCloudKitUserDefaultsSync";
static CKRecordZone *recordZone = nil;
static CKRecordZoneID *recordZoneID = nil;
static NSString *subscriptionID = @"UserDefaultSubscription";
static NSString *recordType = @"UserDefault";
static NSString *recordName = @"UserDefaults";
static BOOL oneAutomaticUpdateToICloudAfterUpdateFromICloud = NO;
static BOOL oneAutomaticUpdateFromICloudAfterUpdateToICloud = NO;
static BOOL refuseUpdateToICloudUntilAfterUpdateFromICloud = NO;
static BOOL oneTimeDeleteZoneFromICloud = NO;
static BOOL updatingToICloud = NO;
static BOOL updatingFromICloud = NO;
//static int additions = 0, changes = 0;
@implementation MJCloudKitUserDefaultsSync

+(void) updateToiCloud:(NSNotification*) notificationObject {
	DLog(@"Update to iCloud?");
	if ( updatingToICloud || updatingFromICloud || refuseUpdateToICloudUntilAfterUpdateFromICloud )
	{
		if ( updatingToICloud )
			DLog(@"NO.  Already updating to iCloud");
		if ( updatingFromICloud )
		{
			DLog(@"NO.  Currently updating from iCloud");
			oneAutomaticUpdateToICloudAfterUpdateFromICloud = YES;
		}
		if ( refuseUpdateToICloudUntilAfterUpdateFromICloud )
			DLog(@"NO.  Waiting until after update from iCloud");
	}
	else
	{
		updatingToICloud = YES;
		DLog(@"YES.  Updating to iCloud");
		CKRecordID *recordID = [[CKRecordID alloc] initWithRecordName:recordName zoneID:recordZoneID];
		[privateDB fetchRecordWithID:recordID completionHandler:^(CKRecord *record, NSError *error) {
			if (error
				&& !( nil != [error.userInfo objectForKey:@"ServerErrorDescription" ]
					 && [(NSString*)[error.userInfo objectForKey:@"ServerErrorDescription" ] isEqualToString:@"Record not found"	] ) ) {
					// Error handling for failed fetch from public database
					DLog(@"CloudKit Fetch failure: %@", error.localizedDescription);
					updatingToICloud = NO;
				}
			else {
				DLog(@"Updating to iCloud completion");
				// Modify the record and save it to the database

				if (error
					&& nil != [error.userInfo objectForKey:@"ServerErrorDescription" ]
					&& [(NSString*)[error.userInfo objectForKey:@"ServerErrorDescription" ] isEqualToString:@"Record not found"	] )
				{
					DLog(@"Updating to iCloud completion creation");
					record = [[CKRecord alloc] initWithRecordType:recordType recordID:recordID];
				}

				NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
				NSDictionary *dict = [defaults dictionaryRepresentation];
				if([defaults objectForKey:@"rememberNum"])
					DLog(@"oh I got it");
				if([dict objectForKey:@"rememberNum"])
					DLog(@"you got it");

				__block int additions = 0, changes = 0;
				// Maybe we could compare record and dict, creating an array of only the items which are not identical in both.
				[dict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
					if ( ( nil != prefix && [key hasPrefix:prefix] )
						|| ( nil != matchList && [matchList containsObject:key] ) ) {
						Boolean skip = NO;
						if ( nil == [record objectForKey: key] )
						{
							DLog(@"Adding %@.", key);
							additions++;
						}
						//else if ( ![(NSString*)record[key] isEqualToString:(NSString*)obj] )
						else if ( ( [obj isKindOfClass:[NSNumber class]] && [record[key] intValue] != [obj intValue] )
								 || ( [obj isKindOfClass:[NSString class]] && ![obj isEqualToString:record[key]] ) )
						{
							DLog(@"Changing %@.", key);
							if ( [obj isKindOfClass:[NSString class]] )
								DLog(@"obj is NSString -%@-.", obj);
							if ( [record[key] isKindOfClass:[NSString class]] )
								DLog(@"record[key] is NSString -%@-.", record[key]);
							if ( [obj isKindOfClass:[NSString class]] && [record[key] isKindOfClass:[NSString class]] && [obj isEqualToString:record[key]] )
								DLog(@"They are equal strings.");
							if ( obj == record[key] )
								DLog(@"They have equality.");
							changes++;
						}
						else
						{
							DLog(@"Skipping %@.", key);
							skip = YES;
						}
						if ( !skip )
							record[key] = obj;
					}
				}];
				DLog(@"To iCloud: Adding %i keys.  Modifying %i keys.", additions, changes);

				if ( additions + changes > 0 )
				{
					[privateDB saveRecord:record completionHandler:^(CKRecord *savedRecord, NSError *saveError) {
						DLog(@"Saving to iCloud.");
						if ( saveError )
						{
							// Error handling for failed save to public database
							DLog(@"CloudKit Save failure: %@", saveError.localizedDescription);
						}
						updatingToICloud = NO;

						if ( oneAutomaticUpdateFromICloudAfterUpdateToICloud )
						{
							oneAutomaticUpdateFromICloudAfterUpdateToICloud = NO;
							[self updateFromiCloud:nil];
						}
					}];
				}
				else
				{
					updatingToICloud = NO;

					if ( oneAutomaticUpdateFromICloudAfterUpdateToICloud )
					{
						oneAutomaticUpdateFromICloudAfterUpdateToICloud = NO;
						[self updateFromiCloud:nil];
					}
				}
			}
		}];
	}
}

+(void) updateFromiCloud:(NSNotification*) notificationObject {
	DLog(@"Update from iCloud?");
	if ( updatingToICloud || updatingFromICloud )
	{
		if ( updatingFromICloud )
			DLog(@"NO.  Already updating from iCloud");
		if ( updatingToICloud )
		{
			DLog(@"NO.  Currently updating to iCloud");
			oneAutomaticUpdateFromICloudAfterUpdateToICloud = YES;
		}
	}
	else
	{
		updatingFromICloud = YES;
		DLog(@"Updating from iCloud");
		CKRecordID *recordID = [[CKRecordID alloc] initWithRecordName:recordName zoneID:recordZoneID];
		[privateDB fetchRecordWithID:recordID completionHandler:^(CKRecord *record, NSError *error) {
			if (error) {
				// Error handling for failed fetch from public database
				DLog(@"CloudKit Fetch failure: %@", error.localizedDescription);
				updatingFromICloud = NO;
			}
			else {
				DLog(@"Updating from iCloud completion");
				//NSUbiquitousKeyValueStore *iCloudStore = [NSUbiquitousKeyValueStore defaultStore];
				//NSDictionary *dict = [iCloudStore dictionaryRepresentation];

				/*// prevent NSUserDefaultsDidChangeNotification from being posted while we update from iCloud

				 [[NSNotificationCenter defaultCenter] removeObserver:self
				 name:NSUserDefaultsDidChangeNotification
				 object:nil];*/

				DLog(@"Got record -%@-_-%@-_-%@-_-%@-",[[[record recordID] zoneID] zoneName],[[[record recordID] zoneID] ownerName],[[record recordID] recordName],[record recordChangeTag]);

				__block int additions = 0, changes = 0;
				[[record allKeys] enumerateObjectsUsingBlock:^(id key, NSUInteger idx, BOOL *stop) {
					if ( ( nil != prefix && [key hasPrefix:prefix] )
						|| ( nil != matchList && [matchList containsObject:key] ) ) {
						BOOL skip = NO;
						NSObject *obj = [[NSUserDefaults standardUserDefaults] objectForKey: key];
						if ( nil == obj )
						{
							DLog(@"Adding %@.", key);
							additions++;
						}
						else if ( ( [obj isKindOfClass:[NSNumber class]] && [record[key] intValue] != [obj intValue] )
								 || ( [obj isKindOfClass:[NSString class]] && ![obj isEqualToString:record[key]] ) )
						{
							DLog(@"Changing %@.", key);
							if ( [obj isKindOfClass:[NSString class]] )
								DLog(@"obj is NSString -%@-.", obj);
							if ( [record[key] isKindOfClass:[NSString class]] )
								DLog(@"record[key] is NSString -%@-.", record[key]);
							if ( [obj isKindOfClass:[NSString class]] && [record[key] isKindOfClass:[NSString class]] && [obj isEqualToString:record[key]] && [obj isEqualToString:record[key]] )
								DLog(@"They are equal strings.");
							if ( obj == record[key] )
								DLog(@"They have equality.");
							changes++;
						}
						else
						{
							DLog(@"Skipping %@.", key);
							skip = YES;
						}
						if ( !skip )
							[[NSUserDefaults standardUserDefaults] setObject:[record objectForKey:key] forKey:key];
					}
				}];
				DLog(@"From iCloud: Adding %i keys.  Modifying %i keys.", additions, changes);

				if ( additions + changes > 0 )
				{
					DLog(@"Synchronizing defaults.");
					[[NSUserDefaults standardUserDefaults] synchronize];
					[self sendChangeNotifications];
				}

				/*// enable NSUserDefaultsDidChangeNotification notifications again

				 [[NSNotificationCenter defaultCenter] addObserver:self
				 selector:@selector(updateToiCloud:)
				 name:NSUserDefaultsDidChangeNotification
				 object:nil];*/

				refuseUpdateToICloudUntilAfterUpdateFromICloud = NO;
				updatingFromICloud = NO;
			}

			if ( oneAutomaticUpdateToICloudAfterUpdateFromICloud )
			{
				oneAutomaticUpdateToICloudAfterUpdateFromICloud = NO;
				[self updateToiCloud:nil];
			}
		}];
	}
}

+(void) startWithPrefix:(NSString*) prefixToSync withContainerIdentifier:(NSString*) containerIdentifier {
	DLog(@"Starting with prefix");

	// If we are already running and add criteria while updating to iCloud, we could push to iCloud before pulling the existing value from iCloud.  Avoid this by dispatching into another thread that will wait pause existing activity and wait for it to stop before adding new criteria.
	dispatch_async(dispatch_get_main_queue(), ^{
		DLog(@"Actually starting with prefix");
		while ( observingActivity || observingIdentityChanges || updatingFromICloud || updatingToICloud )
		{
			NSLog(@"Waiting for other sync to finish.");
			[self pause];
			[NSThread sleepForTimeInterval:0.1];
			NSLog(@"Waited for other sync to finish.");
		}

		if ( !changeNotificationHandlers )
			changeNotificationHandlers = [[NSMutableArray alloc] init];
		databaseContainerIdentifier = containerIdentifier;
		prefix = prefixToSync;

		refuseUpdateToICloudUntilAfterUpdateFromICloud = YES;

		[self attemptToEnable];
	});
}

+(void) startWithKeyMatchList:(NSArray*) keyMatchList withContainerIdentifier:(NSString*) containerIdentifier {
	NSLog(@"Starting with match list length %lu atop %lu", (unsigned long)[keyMatchList count], (unsigned long)[matchList count]);

	// If we are already running and add criteria while updating to iCloud, we could push to iCloud before pulling the existing value from iCloud.  Avoid this by dispatching into another thread that will wait pause existing activity and wait for it to stop before adding new criteria.
	dispatch_async(dispatch_get_main_queue(), ^{
		NSLog(@"Actually starting with match list length %lu atop %lu", (unsigned long)[keyMatchList count], (unsigned long)[matchList count]);
		while ( observingActivity || observingIdentityChanges || updatingFromICloud || updatingToICloud )
		{
			NSLog(@"Waiting for other sync to finish.");
			[self pause];
			[NSThread sleepForTimeInterval:0.1];
			NSLog(@"Waited for other sync to finish.");
		}

		if ( !changeNotificationHandlers )
			changeNotificationHandlers = [[NSMutableArray alloc] init];
		databaseContainerIdentifier = containerIdentifier;

		NSArray *toRelease = nil;
		if ( matchList )
			toRelease = matchList;
		else
			matchList = [[NSArray alloc] init];

		// Add to existing array.
		matchList = [matchList arrayByAddingObjectsFromArray:keyMatchList];
		// Remove duplicates.
		matchList = [[NSSet setWithArray:matchList] allObjects];

		[matchList retain];

		if ( toRelease )
			[toRelease release];

		NSLog(@"Match list length is now %lu", (unsigned long)[matchList count]);

		refuseUpdateToICloudUntilAfterUpdateFromICloud = YES;

		[self attemptToEnable];
	});
}

+(void) pause {
	[self stopObservingActivity];
	[self stopObservingIdentityChanges];
}

+(void) resume {
	[self attemptToEnable];
}

+(void) stopForKeyMatchList:(NSArray*) keyMatchList {
	NSLog(@"Stopping match list length %lu from %lu", (unsigned long)[keyMatchList count], (unsigned long)[matchList count]);

	if ( !matchList )
		return;

	NSArray *toRelease = matchList;

	NSMutableArray *mutableList = [[NSMutableArray alloc] initWithArray:matchList];
	[mutableList removeObjectsInArray:keyMatchList];
	matchList = mutableList;
	[matchList retain];

	[toRelease release];

	NSLog(@"Match list length is now %lu", (unsigned long)[matchList count]);

	if ( 0 == matchList.count )
		[self stop];
}

+(void) stop {
	NSLog(@"Stopping.");
	[self stopObservingActivity];
	[self stopObservingIdentityChanges];
	if ( matchList )
		[matchList release];
	matchList = nil;
	prefix = nil;
	changeNotificationHandlers = nil;
	NSLog(@"Stopped.");
}

static NSMutableArray *changeNotificationHandlers = nil;
+(void) addChangeNotificationSelector:(SEL)aSelector withTarget:(nullable id)aTarget {
	NSLog(@"Registering change notification selector.");
	if ( !changeNotificationHandlers )
		changeNotificationHandlers = [[NSMutableArray alloc] init];
	[changeNotificationHandlers addObject:aTarget];
	[changeNotificationHandlers addObject:[NSValue valueWithPointer:aSelector]];
}

+(void) removeChangeNotificationsForTarget:(nullable id) aTarget {
	NSLog(@"Removing change notification selector(s).");
	while ( changeNotificationHandlers )
	{
		NSUInteger index = [changeNotificationHandlers indexOfObjectIdenticalTo:aTarget];
		if ( NSNotFound == index )
			return;
		NSLog(@"Removing a change notification selector.");
		[changeNotificationHandlers removeObjectAtIndex:index]; // Target
		[changeNotificationHandlers removeObjectAtIndex:index]; // Selector
	}
}

+(void) sendChangeNotifications {
	NSLog(@"Sending change notification selector(s).");
	if (changeNotificationHandlers)
	{
		for ( int i = 0 ; i < [changeNotificationHandlers count] / 2 ; i++ )
		{
			NSLog(@"Sending a change notification selector.");
			[changeNotificationHandlers[i] performSelector:[changeNotificationHandlers[i+1] pointerValue]];
		}
	}
}

+(void) identityDidChange:(NSNotification*) notificationObject {
	DLog(@"iCloud Identity Change Detected");
	[self attemptToEnable];
}

+(void) checkCloudKitUpdates {
	DLog(@"Got checkCloudKitUpdates");
	[self updateFromiCloud:nil];
}

+(void) attemptToEnable {
	DLog(@"Attempting to enable");
	if ( nil == changeNotificationHandlers )
		changeNotificationHandlers = [NSMutableArray init];
	[[CKContainer defaultContainer] accountStatusWithCompletionHandler: ^(CKAccountStatus accountStatus, NSError *error) {
		switch ( accountStatus ) {
			case CKAccountStatusAvailable:  // is iCloud enabled
				DLog(@"iCloud Available");
				[self startObservingActivity];
				//[self incrementCloudKitRecordOfType:@"LaunchCounter" named:@"LaunchCounter" atKey:@"launches"];
				break;

			case CKAccountStatusNoAccount:
				DLog(@"No iCloud account");
				[self stopObservingActivity];
				break;

			case CKAccountStatusRestricted:
				DLog(@"iCloud restricted");
				[self stopObservingActivity];
				break;

			case CKAccountStatusCouldNotDetermine:
				DLog(@"Unable to determine iCloud status");
				[self stopObservingActivity];
				break;
		}

		[self startObservingIdentityChanges];
	}];
}

+(void) startObservingActivity {
	DLog(@"Should start observing activity?");
	if ( !observingActivity )
	{
		DLog(@"YES.  Start observing activity.");
		observingActivity = YES;

		// Setup database connections.
		CKContainer *container = [CKContainer containerWithIdentifier:databaseContainerIdentifier];
		publicDB = [container publicCloudDatabase];
		privateDB = [container privateCloudDatabase];

		// Create a zone if needed.
		recordZoneID = [[CKRecordZoneID alloc] initWithZoneName:recordZoneName ownerName:CKOwnerDefaultName];
		recordZone = [[CKRecordZone alloc] initWithZoneID:recordZoneID];
		DLog(@"Created CKRecordZone.zoneID %@:%@", recordZone.zoneID.zoneName, recordZone.zoneID.ownerName);
		if ( oneTimeDeleteZoneFromICloud )
		{
			observingActivity = NO;
			oneTimeDeleteZoneFromICloud = NO;
			DLog(@"Deleting CKRecordZone one time.");
			CKModifyRecordZonesOperation *deleteOperation = [[CKModifyRecordZonesOperation alloc] initWithRecordZonesToSave:@[] recordZoneIDsToDelete:@[recordZoneID]];
			deleteOperation.modifyRecordZonesCompletionBlock = ^(NSArray *savedRecordZones, NSArray *deletedRecordZoneIDs, NSError *error) {
				if ( nil != error )
				{
					DLog(@"CloudKit Delete Record Zones failure: %@", error.localizedDescription);
				}
				else
				{
					DLog(@"Deleted CKRecordZone.");
				}
				[self startObservingActivity];
			};
			[privateDB addOperation:deleteOperation];
			return;
		}
		CKModifyRecordZonesOperation *operation = [[CKModifyRecordZonesOperation alloc] initWithRecordZonesToSave:@[recordZone] recordZoneIDsToDelete:@[]];
		operation.modifyRecordZonesCompletionBlock = ^(NSArray *savedRecordZones, NSArray *deletedRecordZoneIDs, NSError *error) {
			if ( nil != error )
			{
				DLog(@"CloudKit Modify Record Zones failure: %@", error.localizedDescription);
				[self stopObservingActivity];
			}
			else
			{
				DLog(@"Recorded CKRecordZone.zoneID %@:%@", ((CKRecordZone*)savedRecordZones[0]).zoneID.zoneName, ((CKRecordZone*)savedRecordZones[0]).zoneID.ownerName);
				// Find out when things change
				[self subscribeToDatabase];

				// Pull from iCloud now, pushing afterward.
				// If we push first, we overwrite the sync.
				// If we don't push after the pull, we won't push until something changes.
				oneAutomaticUpdateToICloudAfterUpdateFromICloud = YES;
				[self updateFromiCloud:nil];
			}

		};
		[privateDB addOperation:operation];

		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(updateToiCloud:)
													 name:NSUserDefaultsDidChangeNotification
												   object:nil];
	}
}

+(void) subscribeToDatabase {
	DLog(@"Subscribing to database.");
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"TRUEPREDICATE" ];
	CKQuerySubscription *subscription =
#if TARGET_IPHONE_SIMULATOR
	nil; // Simulator doesn't support remote notifications.
#else // TARGET_IPHONE_SIMULATOR
	[[CKQuerySubscription alloc] initWithRecordType:recordType
										  predicate:predicate
									 subscriptionID:subscriptionID
											options:CKQuerySubscriptionOptionsFiresOnRecordCreation | CKQuerySubscriptionOptionsFiresOnRecordUpdate | CKQuerySubscriptionOptionsFiresOnRecordDeletion];
#endif // TARGET_IPHONE_SIMULATOR
	if ( nil == subscription )
	{
		DLog(@"Using polling instead.");
		// CKQuerySubscription was added after the core CloudKit APIs, so on OS versions that don't support it we will poll instead as there appears to be no alternative subscription API.

		// Some acrobatics are required to get the timer working.  Without being contained in the dispatch_async, it would never fire on its own, even if added to the NSRunLoop mainRunLoop.
		dispatch_async(dispatch_get_main_queue(), ^{
			pollCloudKitTimer = [[NSTimer scheduledTimerWithTimeInterval:(1.0)
																  target:self
																selector:@selector(pollCloudKit:)
																userInfo:nil
																 repeats:YES] retain];

			[pollCloudKitTimer fire];
		});
	}
	else
	{
		CKNotificationInfo *notification = [[CKNotificationInfo alloc] init];
		notification.shouldSendContentAvailable = YES;
		subscription.notificationInfo = notification;

		DLog(@"Fetching existing subscription.");
		[privateDB fetchSubscriptionWithID:subscription.subscriptionID completionHandler:^(CKSubscription * _Nullable existingSubscription, NSError * _Nullable error) {
			DLog(@"Fetched existing subscription.");
			if ( nil == existingSubscription )
			{
				DLog(@"No existing subscription. Saving ours.");
				// In the not-yet-subscribed-but-everything-working case, error will contain k/v @"ServerErrorDescription" : @"subscription not found"
				[privateDB saveSubscription:subscription completionHandler:^(CKSubscription * _Nullable subscription, NSError * _Nullable error) {
					DLog(@"Saved subscription.");
					if ( nil != error )
					{
						DLog(@"CloudKit Subscription failure: %@", error.localizedDescription);
						[self stopObservingActivity];
					}
				}];
			}
		}];
	}
}

+(void) stopObservingActivity {
	DLog(@"Should stop observing activity?");
	if ( observingActivity )
	{
		DLog(@"YES.  Stop observing activity.");
		observingActivity = NO;

		if ( pollCloudKitTimer )
		{
			[pollCloudKitTimer invalidate];
			pollCloudKitTimer = nil;
		}

		[privateDB deleteSubscriptionWithID:subscriptionID completionHandler:^(NSString * _Nullable subscriptionID, NSError * _Nullable error) {
			DLog(@"Stopped observing activity.");
			// We check for an existing subscription before saving a new subscription so the result here doesn't matter."
		}];

		// Clear database connections.
		publicDB = privateDB = nil;

		[[NSNotificationCenter defaultCenter] removeObserver:self
												  name:NSUserDefaultsDidChangeNotification
													  object:nil];
	}
}

+(void) startObservingIdentityChanges {
	DLog(@"Should start observing identity changes?");
	if ( !observingIdentityChanges )
	{
		DLog(@"YES.  Start observing identity changes.");
		observingIdentityChanges = YES;
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(identityDidChange:)
													 name:NSUbiquityIdentityDidChangeNotification
												   object:nil];
	}
}

+(void) stopObservingIdentityChanges {
	DLog(@"Should stop observing identity changes?");
	if ( observingIdentityChanges )
	{
		DLog(@"YES.  Stop observing identity changes.");
		observingIdentityChanges = NO;
		[[NSNotificationCenter defaultCenter] removeObserver:self
												  name:NSUbiquityIdentityDidChangeNotification
													  object:nil];
	}
}

CKServerChangeToken *previousChangeToken = nil;
+(void)pollCloudKit:(NSTimer *)timer {
	// CKFetchRecordChangesOperation is OS X 10.10 to 10.12, but CKQuerySubscription is 10.12+ so for code exclusive to our pre-CKQuerySubscription support we can use things that were deprecated when CKQuerySubscription was added.
	DLog(@"Polling");
	CKFetchRecordChangesOperation *operation = [[CKFetchRecordChangesOperation alloc] initWithRecordZoneID:recordZone.zoneID previousServerChangeToken:previousChangeToken];
	operation.recordChangedBlock = ^(CKRecord *record) {
		DLog(@"Polling got record change");
		[self checkCloudKitUpdates];
	};
	operation.fetchRecordChangesCompletionBlock = ^(CKServerChangeToken * _Nullable serverChangeToken, NSData * _Nullable clientChangeTokenData, NSError * _Nullable operationError) {
		DLog(@"Polling completion");
		if ( nil == operationError )
		{
			DLog(@"Polling completion GOOD");
			previousChangeToken = serverChangeToken;
		}
	};

	[privateDB addOperation:operation];

	/*CKFetchRecordZonesOperation *operation = [[CKFetchRecordZonesOperation alloc] initWithRecordZoneIDs:recordZoneID];
	operation.fetchAllRecordZonesOperation*/
	/*let predicate = NSPredicate(format: "UPC = %@", subStr)

	let query = CKQuery(recordType: "Food", predicate: predicate)

	publicDatabase.performQuery(query, inZoneWithID: nil,
								completionHandler:*/
}

+(void) incrementCloudKitRecordOfType:(NSString*) recordType named:(NSString*) recordName atKey:(NSString*) recordKey onDB:(CKDatabase*) database {
	NSLog(@"SHOULD NOT BE CALLED");
	CKRecordID *recordID = [[CKRecordID alloc] initWithRecordName:recordName];
	[database fetchRecordWithID:recordID completionHandler:^(CKRecord *record, NSError *error) {
		if(error) {
			NSLog(@"%@", error);
			record = [[CKRecord alloc] initWithRecordType:recordType recordID:recordID];
			[record setValue:@"0" forKey:recordKey];
		} else {
			NSLog(@"Fetched successfully");
		}

		int value = [(NSNumber*)record[recordKey] intValue];
		value++;
		lastKnownLaunches = value;
		record[recordKey] = [NSNumber numberWithInt:value];
		NSLog(@"%i %@!",value, recordKey);

		[database saveRecord:record completionHandler:^(CKRecord *record, NSError *error) {
			if(error) {
				NSLog(@"Uh oh, there was an error updating ... %@", error);
				[self stopObservingActivity];
			} else {
				NSLog(@"Updated record successfully");
			}
		}];
	}];
}

+ (void) dealloc {
	NSLog(@"Deallocating");
	[self stop];
	NSLog(@"Deallocated");
}
@end
