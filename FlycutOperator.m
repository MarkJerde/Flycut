//
//  FlycutOperator.m
//  Flycut
//
//  Flycut by Gennadiy Potapov and contributors. Based on Jumpcut by Steve Cook.
//  Copyright 2011 General Arcade. All rights reserved.
//
//  This code is open-source software subject to the MIT License; see the homepage
//  at <https://github.com/TermiT/Flycut> for details.
//

// FlycutOperator owns and interacts with the FlycutStores, providing
// manipulation of the stores.

#import <Foundation/Foundation.h>
#import "FlycutOperator.h"
#import "MJCloudKitUserDefaultsSync.h"

@implementation FlycutOperator

- (id)init
{
	[[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithInt:40],
		@"rememberNum",
        [NSNumber numberWithInt:40],
        @"favoritesRememberNum",
		[NSNumber numberWithInt:1],
		@"savePreference",
        [NSDictionary dictionary],
        @"store",
        [NSNumber numberWithBool:YES],
        @"skipPasswordFields",
		[NSNumber numberWithBool:YES],
		@"skipPboardTypes",
		@"PasswordPboardType",
		@"skipPboardTypesList",
		[NSNumber numberWithBool:NO],
		@"skipPasswordLengths",
		@"12, 20, 32",
		@"skipPasswordLengthsList",
		[NSNumber numberWithBool:NO],
		@"revealPasteboardTypes",
        [NSNumber numberWithBool:YES], // do not commit with YES.  Use NO
        @"removeDuplicates",
        [NSNumber numberWithBool:NO],
        @"saveForgottenClippings",
        [NSNumber numberWithBool:YES],
        @"saveForgottenFavorites",
        [NSNumber numberWithBool:YES], // do not commit with YES.  Use NO
        @"pasteMovesToTop",
        [NSNumber numberWithBool:NO],
        @"syncSettingsViaICloud",
        [NSNumber numberWithBool:NO],
        @"syncClippingsViaICloud",
        nil]];

	settingsSyncList = @[@"rememberNum",
						 @"favoritesRememberNum",
						 @"savePreference",
						 @"skipPasswordFields",
						 @"skipPboardTypes",
						 @"skipPboardTypesList",
						 @"skipPasswordLengths",
						 @"skipPasswordLengthsList",
						 @"removeDuplicates",
						 @"saveForgottenClippings",
						 @"saveForgottenFavorites",
						 @"pasteMovesToTop"];
	[settingsSyncList retain];

	return self;
}

- (void)awakeFromNibDisplaying:(int) dispNum withDisplayLength:(int) dispLength withSaveSelector:(SEL) selector forTarget:(NSObject*) target
{
	displayNum = dispNum;
	displayLength = dispLength;
	saveSelector = selector;
	saveTarget = target;

	// Initialize the FlycutStore
	[self initializeStoresAndLoadContents];

	// Stack position starts @ 0 by default
	stackPosition = favoritesStackPosition = stashedStackPosition = 0;

	[self registerOrDeregisterICloudSync];
}

-(void)addNotificationForBeginUpdatesWithSelector:(SEL)aSelector withTarget:(nullable id)aTarget
{
	beginUpdatesSelector = aSelector;
	beginUpdatesTarget = aTarget;
}

-(void)addNotificationForInsertRowsWithSelector:(SEL)aSelector withTarget:(nullable id)aTarget
{
	insertRowsSelector = aSelector;
	insertRowsTarget = aTarget;
}

-(void)addNotificationForDeleteRowsWithSelector:(SEL)aSelector withTarget:(nullable id)aTarget
{
	deleteRowsSelector = aSelector;
	deleteRowsTarget = aTarget;
}

-(void)addNotificationForEndUpdatesWithSelector:(SEL)aSelector withTarget:(nullable id)aTarget
{
	endUpdatesSelector = aSelector;
	endUpdatesTarget = aTarget;
}

-(void) initializeStoresAndLoadContents
{
	if ( nil != beginUpdatesTarget )
		[beginUpdatesTarget performSelector:beginUpdatesSelector];

	if ( clippingStore && [clippingStore jcListCount] > 0 ) {
		if ( nil != deleteRowsTarget )
			for ( int i = [clippingStore jcListCount] ; i > 0 ; i-- )
				[deleteRowsTarget performSelector:deleteRowsSelector withObject:[NSNumber numberWithInteger:(i-1)]];

		[clippingStore release];
	}
	if ( favoritesStore ) {
		[favoritesStore release];
	}

	// Fixme - These stores are not released elsewhere.
	clippingStore = [[FlycutStore alloc] initRemembering:[[NSUserDefaults standardUserDefaults] integerForKey:@"rememberNum"]
											  displaying:displayNum
									   withDisplayLength:displayLength];

	favoritesStore = [[FlycutStore alloc] initRemembering:[[NSUserDefaults standardUserDefaults] integerForKey:@"favoritesRememberNum"]
											   displaying:displayNum
										withDisplayLength:displayLength];
	stashedStore = NULL;

	// If our preferences indicate that we are saving, load the dictionary from the saved plist
	// and use it to get everything set up.
	if ( [[NSUserDefaults standardUserDefaults] integerForKey:@"savePreference"] >= 1 ) {
		[self loadEngineFromPList];
	}

	if ( nil != insertRowsTarget && [clippingStore jcListCount] > 0 )
		for ( int i = [clippingStore jcListCount] ; i > 0 ; i-- )
			[insertRowsTarget performSelector:insertRowsSelector withObject:[NSNumber numberWithInteger:(i-1)]];

	if ( nil != endUpdatesTarget )
		[endUpdatesTarget performSelector:endUpdatesSelector];
}

-(void) setRememberNum:(int) newRemember
{
	[clippingStore setRememberNum:newRemember];
}

-(void)toggleToFromFavoritesStore
{
    if (NULL != stashedStore)
        [self restoreStashedStore];
    else
        [self switchToFavoritesStore];
}

-(bool)favoritesStoreIsSelected
{
    return clippingStore == favoritesStore;
}

-(void)switchToFavoritesStore
{
    stashedStore = clippingStore;
    clippingStore = favoritesStore;
    stashedStackPosition = stackPosition;
    stackPosition = favoritesStackPosition;
}

- (bool)restoreStashedStore
{
    if (NULL != stashedStore)
    {
        clippingStore = stashedStore;
        stashedStore = NULL;
        favoritesStackPosition = stackPosition;
        stackPosition = stashedStackPosition;
        return YES;
    }
    return NO;
}

- (NSString*)getPasteFromStackPosition
{
	if ( [clippingStore jcListCount] > stackPosition ) {
		return [self getPasteFromIndex: stackPosition];
	}
	return nil;
}

- (bool)saveFromStack
{
    return [self saveFromStackWithPrefix:@""];
}

- (bool)saveFromStackWithPrefix:(NSString*) prefix
{
    if ( [clippingStore jcListCount] > stackPosition ) {
        // Get text from clipping store.
        NSString *pbFullText = [self clippingStringWithCount:stackPosition];
        pbFullText = [pbFullText stringByReplacingOccurrencesOfString:@"\r" withString:@"\r\n"];

        // Get the Desktop directory:
        NSArray *paths = NSSearchPathForDirectoriesInDomains
        (NSDesktopDirectory, NSUserDomainMask, YES);
        NSString *desktopDirectory = [paths objectAtIndex:0];

        // Get the timestamp string:
        NSDate *currentDate = [NSDate date];
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateFormat:@"YYYY-MM-dd 'at' HH.mm.ss"];
        NSString *dateString = [dateFormatter stringFromDate:currentDate];

        // Make a file name to write the data to using the Desktop directory:
        NSString *fileName = [NSString stringWithFormat:@"%@/%@%@Clipping %@.txt",
                              desktopDirectory, prefix, clippingStore == favoritesStore ? @"Favorite " : @"", dateString];

        // Save content to the file
        [pbFullText writeToFile:fileName
                  atomically:NO
                    encoding:NSNonLossyASCIIStringEncoding
                       error:nil];
        return YES;
    }
    return NO;
}

- (bool)saveFromStackToFavorites
{
    if ( clippingStore != favoritesStore && [clippingStore jcListCount] > stackPosition ) {
        if ( [favoritesStore rememberNum] == [favoritesStore jcListCount]
            && [[[NSUserDefaults standardUserDefaults] valueForKey:@"saveForgottenFavorites"] boolValue] )
        {
            // favoritesStore is full, so save the last entry before it gets lost.
            [self switchToFavoritesStore];

            // Set to last item, save, and restore position.
            stackPosition = [favoritesStore rememberNum]-1;
            [self saveFromStackWithPrefix:@"Autosave "];
            stackPosition = favoritesStackPosition;

            // Restore prior state.
            [self restoreStashedStore];
        }
        // Get text from clipping store.
        [favoritesStore addClipping:[clippingStore clippingAtPosition:stackPosition] ];
        [self clearItemAtStackPosition];
        return YES;
    }
    return NO;
}

- (NSString*)getPasteFromIndex:(int) position {
	NSString *clipping = [self getClipFromCount:position];

	if ( [[NSUserDefaults standardUserDefaults] boolForKey:@"pasteMovesToTop"] ) {
		[clippingStore clippingMoveToTop:position];
		stackPosition = 0;
	}
	return clipping;
}

-(NSString*)getClipFromCount:(int)indexInt
{
    NSString *pbFullText;
    NSArray *pbTypes;
    if ( (indexInt + 1) > [clippingStore jcListCount] ) {
        // We're asking for a clipping that isn't there yet
		// This only tends to happen immediately on startup when not saving, as the entire list is empty.
        DLog(@"Out of bounds request to jcList ignored.");
        return nil;
    }
    return [self clippingStringWithCount:indexInt];
}

-(BOOL)shouldSkip:(NSString *)contents ofType:(NSString *)type
{
	// Check to see if we are skipping passwords based on length and characters.
	if ( [[NSUserDefaults standardUserDefaults] boolForKey:@"skipPasswordFields"] )
	{
		// Check to see if they want a little help figuring out what types to enter.
		if ( [[NSUserDefaults standardUserDefaults] boolForKey:@"revealPasteboardTypes"] )
			[clippingStore addClipping:type ofType:type fromAppLocalizedName:@"Flycut" fromAppBundleURL:nil atTimestamp:0];

		__block bool skipClipping = NO;

		// Check the array of types to skip.
		if ( [[NSUserDefaults standardUserDefaults] boolForKey:@"skipPboardTypes"] )
		{
			NSArray *typesArray = [[[[NSUserDefaults standardUserDefaults] stringForKey:@"skipPboardTypesList"] stringByReplacingOccurrencesOfString:@" " withString:@""] componentsSeparatedByString: @","];
			[typesArray enumerateObjectsUsingBlock:^(id typeString, NSUInteger idx, BOOL *stop)
			{
				if ( [type isEqualToString:typeString] )
				{
					skipClipping = YES;
					stop = YES;
				}
			}];
		}
		if (skipClipping)
			return YES;

		// Check the array of lengths to skip for suspicious strings.
		if ( [[NSUserDefaults standardUserDefaults] boolForKey:@"skipPasswordLengths"] )
		{
			int contentsLength = [contents length];
			NSArray *lengthsArray = [[[[NSUserDefaults standardUserDefaults] stringForKey:@"skipPasswordLengthsList"] stringByReplacingOccurrencesOfString:@" " withString:@""] componentsSeparatedByString: @","];
			[lengthsArray enumerateObjectsUsingBlock:^(id lengthString, NSUInteger idx, BOOL *stop)
			{
				if ( [lengthString integerValue] == contentsLength )
				{
					NSRange uppercaseLetter = [contents rangeOfCharacterFromSet: [NSCharacterSet uppercaseLetterCharacterSet]];
					NSRange lowercaseLetter = [contents rangeOfCharacterFromSet: [NSCharacterSet lowercaseLetterCharacterSet]];
					NSRange decimalDigit = [contents rangeOfCharacterFromSet: [NSCharacterSet decimalDigitCharacterSet]];
					NSRange punctuation = [contents rangeOfCharacterFromSet: [NSCharacterSet punctuationCharacterSet]];
					NSRange symbol = [contents rangeOfCharacterFromSet: [NSCharacterSet symbolCharacterSet]];
					NSRange control = [contents rangeOfCharacterFromSet: [NSCharacterSet controlCharacterSet]];
					NSRange illegal = [contents rangeOfCharacterFromSet: [NSCharacterSet illegalCharacterSet]];
					NSRange whitespaceAndNewline = [contents rangeOfCharacterFromSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
					if ( NSNotFound == control.location
						&& NSNotFound == illegal.location
						&& NSNotFound == whitespaceAndNewline.location
						&& NSNotFound != uppercaseLetter.location
						&& NSNotFound != lowercaseLetter.location
						&& NSNotFound != decimalDigit.location
						&& ( NSNotFound != punctuation.location
							|| NSNotFound != symbol.location ) )
					{
						skipClipping = YES;
						stop = YES;
					}
				}
			}];

			if (skipClipping)
				return YES;
		}
	}
	return NO;
}

-(void)setDisableStoreTo:(bool) value
{
    disableStore = value;
}

-(bool)storeDisabled
{
	return disableStore;
}

-(int)indexOfClipping:(NSString*)contents ofType:(NSString*)type fromApp:(NSString *)appName withAppBundleURL:(NSString *)bundleURL
{
	return [clippingStore indexOfClipping:contents
								   ofType:type
					 fromAppLocalizedName:appName
						 fromAppBundleURL:bundleURL
							  atTimestamp:[[NSDate date] timeIntervalSince1970]];
}

-(bool)addClipping:(NSString*)contents ofType:(NSString*)type fromApp:(NSString *)appName withAppBundleURL:(NSString *)bundleURL target:(id)selectorTarget clippingAddedSelector:(SEL)clippingAddedSelector
{
	if ( [clippingStore jcListCount] == 0 || ! [contents isEqualToString:[clippingStore clippingContentsAtPosition:0]]) {

		if ( nil != beginUpdatesTarget )
			[beginUpdatesTarget performSelector:beginUpdatesSelector];

        if ( [clippingStore rememberNum] == [clippingStore jcListCount]
            && [[[NSUserDefaults standardUserDefaults] valueForKey:@"saveForgottenClippings"] boolValue] )
        {
            // clippingStore is full, so save the last entry before it gets lost.
            // Set to last item, save, and restore position.
            int savePosition = stackPosition;
			stackPosition = [clippingStore rememberNum]-1;
			if ( deleteRowsTarget )
				[deleteRowsTarget performSelector:deleteRowsSelector withObject:[NSNumber numberWithInteger:(stackPosition)]];
            [self saveFromStackWithPrefix:@"Autosave "];
            stackPosition = savePosition;
        }

		int startingCount = [clippingStore jcListCount];
		bool success = [clippingStore addClipping:contents
										   ofType:type
							 fromAppLocalizedName:appName
								 fromAppBundleURL:bundleURL
									  atTimestamp:[[NSDate date] timeIntervalSince1970]];
		int increase = [clippingStore jcListCount] - startingCount;

		if ( clippingStore != favoritesStore && insertRowsTarget )
			while ( increase > 0 )
			{
			[insertRowsTarget performSelector:insertRowsSelector withObject:[NSNumber numberWithInteger:(stackPosition)]];
				increase--;
			}

		if ( nil != endUpdatesTarget )
			[endUpdatesTarget performSelector:endUpdatesSelector];

//		The below tracks our position down down down... Maybe as an option?
//		if ( [clippingStore jcListCount] > 1 ) stackPosition++;
		stackPosition = 0;
        [selectorTarget performSelector:clippingAddedSelector];
		if ( [[NSUserDefaults standardUserDefaults] integerForKey:@"savePreference"] >= 2 )
            [self saveEngine];

		return success;
    }
	return  NO;
}

-(int)jcListCount
{
	return [clippingStore jcListCount];
}

-(int)rememberNum
{
	return [clippingStore rememberNum];
}

-(int)stackPosition
{
	return stackPosition;
}

-(bool)setStackPositionToFirstItem
{
	if ( [clippingStore jcListCount] > 0 ) {
		stackPosition = 0;
		return YES;
	}
	return NO;
}

-(bool)setStackPositionToLastItem
{
	if ( [clippingStore jcListCount] > 0 ) {
		stackPosition = [clippingStore jcListCount] - 1;
		return YES;
	}
	return NO;
}

-(bool)setStackPositionToTenMoreRecent
{
	if ( [clippingStore jcListCount] > 0 ) {
		stackPosition = stackPosition - 10; if ( stackPosition < 0 ) stackPosition = 0;
		return YES;
	}
	return NO;
}

-(bool)setStackPositionToTenLessRecent
{
	if ( [clippingStore jcListCount] > 0 ) {
		stackPosition = stackPosition + 10; if ( stackPosition >= [clippingStore jcListCount] ) stackPosition = [clippingStore jcListCount] - 1;
		return YES;
	}
	return NO;
}

-(bool)clearItemAtStackPosition
{
    if ([clippingStore jcListCount] == 0)
        return NO;

	if ( nil != beginUpdatesTarget )
		[beginUpdatesTarget performSelector:beginUpdatesSelector];

    [clippingStore clearItem:stackPosition];


	if ( clippingStore != favoritesStore && deleteRowsTarget )
		[deleteRowsTarget performSelector:deleteRowsSelector withObject:[NSNumber numberWithInteger:(stackPosition)]];

	if ( nil != endUpdatesTarget )
		[endUpdatesTarget performSelector:endUpdatesSelector];

    return YES;
}

-(bool)setStackPositionTo:(int) newStackPosition
{
	if ( [clippingStore jcListCount] >= newStackPosition ) {
		stackPosition = newStackPosition;
		return YES;
	}
	return NO;
}

// Would probably be good to just prevent this scenario where it originates and
// delete this check.
-(void)adjustStackPositionIfOutOfBounds
{
	if (stackPosition >= [clippingStore jcListCount] && stackPosition != 0) { // deleted last item
		stackPosition = [clippingStore jcListCount] - 1;
	}
}

-(bool)stackPositionIsInBounds
{
	return ( [clippingStore jcListCount] > 0 && [clippingStore jcListCount] > stackPosition );
}

-(void)clearList
{
    [clippingStore clearList];
}

-(void)mergeList
{
    [clippingStore mergeList];
}

-(BOOL) isValidClippingNumber:(NSNumber *)number {
    return ( ([number intValue] + 1) <= [clippingStore jcListCount] );
}

-(NSString *) clippingStringWithCount:(int)count {
    if ( [self isValidClippingNumber:[NSNumber numberWithInt:count]] ) {
        return [clippingStore clippingContentsAtPosition:count];
    } else { // It fails -- we shouldn't be passed this, but...
        return @"";
    }
}

-(void) registerOrDeregisterICloudSync
{
	if ( [[NSUserDefaults standardUserDefaults] boolForKey:@"syncSettingsViaICloud"] ) {
		[MJCloudKitUserDefaultsSync startWithKeyMatchList:settingsSyncList
								  withContainerIdentifier:@"iCloud.com.mark-a-jerde.Flycut"];
	}
	else {
		[MJCloudKitUserDefaultsSync stopForKeyMatchList:settingsSyncList];
	}

	if ( [[NSUserDefaults standardUserDefaults] boolForKey:@"syncClippingsViaICloud"] ) {
		[MJCloudKitUserDefaultsSync removeNotificationsFor:MJSyncNotificationChanges forTarget:self];
		[MJCloudKitUserDefaultsSync addNotificationFor:MJSyncNotificationChanges withSelector:@selector(checkPreferencesChanges:) withTarget: self];

		[MJCloudKitUserDefaultsSync removeNotificationsFor:MJSyncNotificationConflicts forTarget:self];
		[MJCloudKitUserDefaultsSync addNotificationFor:MJSyncNotificationConflicts withSelector:@selector(checkPreferencesConflicts:) withTarget: self];

		[MJCloudKitUserDefaultsSync startWithKeyMatchList:@[@"store"]
								  withContainerIdentifier:@"iCloud.com.mark-a-jerde.Flycut"];
	}
	else {
		[MJCloudKitUserDefaultsSync removeNotificationsFor:MJSyncNotificationChanges forTarget:self];

		[MJCloudKitUserDefaultsSync stopForKeyMatchList:@[@"store"]];
	}
}

-(NSDictionary*) checkPreferencesChanges:(NSDictionary*)changes
{
	if ( [changes valueForKey:@"store"] )
		[self initializeStoresAndLoadContents];
	return nil;
}

-(NSDictionary*) checkPreferencesConflicts:(NSDictionary*)changes
{
	NSMutableDictionary *corrections = nil;
	if ( [changes valueForKey:@"store"] )
	{
		// Just clobber back, for now.  They already finished their save, so they won't notice and will just think we made a calculated change.
		NSLog(@"Oh.  My changes were clobbered.  I will clobber back.");
		if ( !corrections )
			corrections = [[NSMutableDictionary alloc] init];
		corrections[@"store"] = [changes valueForKey:@"store"][1]; // We win.
	}
	return corrections;
}

-(void) checkCloudKitUpdates
{
	[MJCloudKitUserDefaultsSync checkCloudKitUpdates];
}

-(bool) loadEngineFromPList
{
    NSDictionary *loadDict = [[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"store"] copy];   
    NSArray *savedJCList;
	NSRange loadRange;

    int rangeCap;

    if ( loadDict != nil ) {

        savedJCList = [loadDict objectForKey:@"jcList"];

        if ( [savedJCList isKindOfClass:[NSArray class]] ) {
            int rememberNumPref = [[NSUserDefaults standardUserDefaults] 
                                   integerForKey:@"rememberNum"];
            // There's probably a nicer way to prevent the range from going out of bounds, but this works.
			rangeCap = [savedJCList count] < rememberNumPref ? [savedJCList count] : rememberNumPref;
			loadRange = NSMakeRange(0, rangeCap);
            NSArray *toBeRestoredClips = [[[savedJCList subarrayWithRange:loadRange] reverseObjectEnumerator] allObjects];
            for( NSDictionary *aSavedClipping in toBeRestoredClips)
				[clippingStore addClipping:[aSavedClipping objectForKey:@"Contents"]
									ofType:[aSavedClipping objectForKey:@"Type"]
					  fromAppLocalizedName:[aSavedClipping objectForKey:@"AppLocalizedName"]
						  fromAppBundleURL:[aSavedClipping objectForKey:@"AppBundleURL"]
							   atTimestamp:[[aSavedClipping objectForKey:@"Timestamp"] integerValue]];

            // Now for the favorites, same thing.
            savedJCList =[loadDict objectForKey:@"favoritesList"];
            if ( [savedJCList isKindOfClass:[NSArray class]] ) {
            rememberNumPref = [[NSUserDefaults standardUserDefaults]
                               integerForKey:@"favoritesRememberNum"];
            rangeCap = [savedJCList count] < rememberNumPref ? [savedJCList count] : rememberNumPref;
            loadRange = NSMakeRange(0, rangeCap);
            toBeRestoredClips = [[[savedJCList subarrayWithRange:loadRange] reverseObjectEnumerator] allObjects];
            for( NSDictionary *aSavedClipping in toBeRestoredClips)
                [favoritesStore addClipping:[aSavedClipping objectForKey:@"Contents"]
                                     ofType:[aSavedClipping objectForKey:@"Type"]
                       fromAppLocalizedName:[aSavedClipping objectForKey:@"AppLocalizedName"]
                           fromAppBundleURL:[aSavedClipping objectForKey:@"AppBundleURL"]
                                atTimestamp:[[aSavedClipping objectForKey:@"Timestamp"] integerValue]];
            }
        } else DLog(@"Not array");
        [loadDict release];
        return YES;
    }
    return NO;
}

-(bool)setStackPositionToOneLessRecent
{
	stackPosition++;
	if ( [clippingStore jcListCount] > stackPosition ) {
		return YES;
	} else {
		if ( [[NSUserDefaults standardUserDefaults] boolForKey:@"wraparoundBezel"] ) {
			stackPosition = 0;
			return YES;
		} else {
			stackPosition--;
		}
	}
	return NO;
}

-(bool)setStackPositionToOneMoreRecent
{
	stackPosition--;
	if ( stackPosition < 0 ) {
		if ( [[NSUserDefaults standardUserDefaults] boolForKey:@"wraparoundBezel"] ) {
			stackPosition = [clippingStore jcListCount] - 1;
			return YES;
		} else {
			stackPosition = 0;
			return NO;
		}
	}
	if ( [clippingStore jcListCount] > stackPosition ) {
		return YES;
	}
	return NO;
}

-(FlycutClipping*)clippingAtStackPosition
{
    return [clippingStore clippingAtPosition:stackPosition];
}

- (void)saveStore:(FlycutStore *)store toKey:(NSString *)key onDict:(NSMutableDictionary *)saveDict {
    NSMutableArray *jcListArray = [NSMutableArray array];
    for ( int i = 0 ; i < [store jcListCount] ; i++ )
    {
        FlycutClipping *clipping = [store clippingAtPosition:i];
        NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                     [clipping contents], @"Contents",
                                     [clipping type], @"Type",
                                     [NSNumber numberWithInt:i], @"Position",nil];

        NSString *val = [clipping appLocalizedName];
        if ( nil != val )
            [dict setObject:val forKey:@"AppLocalizedName"];

        val = [clipping appBundleURL];
        if ( nil != val )
            [dict setObject:val forKey:@"AppBundleURL"];

        int timestamp = [clipping timestamp];
        if ( timestamp > 0 )
            [dict setObject:[NSNumber numberWithInt:timestamp] forKey:@"Timestamp"];

        [jcListArray addObject:dict];
    }
    [saveDict setObject:jcListArray forKey:key];
}

-(void) saveEngine {
    NSMutableDictionary *saveDict;
    saveDict = [NSMutableDictionary dictionaryWithCapacity:3];
    [saveDict setObject:@"0.7" forKey:@"version"];
    [saveDict setObject:[NSNumber numberWithInt:[[NSUserDefaults standardUserDefaults] integerForKey:@"rememberNum"]]
                 forKey:@"rememberNum"];
    [saveDict setObject:[NSNumber numberWithInt:[[NSUserDefaults standardUserDefaults] integerForKey:@"favoritesRememberNum"]]
                 forKey:@"favoritesRememberNum"];

	[saveTarget performSelector:saveSelector withObject:saveDict];

    [self saveStore:clippingStore toKey:@"jcList" onDict:saveDict];
    [self saveStore:favoritesStore toKey:@"favoritesList" onDict:saveDict];

    [[NSUserDefaults standardUserDefaults] setObject:saveDict forKey:@"store"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)applicationWillTerminate {
	if ( [[NSUserDefaults standardUserDefaults] integerForKey:@"savePreference"] >= 1 ) {
		DLog(@"Saving on exit");
        [self saveEngine];
    } else {
        // Remove clips from store
        [[NSUserDefaults standardUserDefaults] setValue:[NSDictionary dictionary] forKey:@"store"];
        DLog(@"Saving preferences on exit");
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

-(NSArray *) previousIndexes:(int)howMany containing:(NSString*)search // This method is in newest-first order.
{
	return [clippingStore previousIndexes:howMany containing:search];
}

-(NSArray *) previousDisplayStrings:(int)howMany containing:(NSString*)search
{
	return [clippingStore previousDisplayStrings:howMany containing:search];
}

@end
