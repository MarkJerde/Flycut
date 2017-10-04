//
//  FlycutOperator.h
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

#ifndef FlycutOperator_h
#define FlycutOperator_h

#import "FlycutStore.h"

@interface FlycutOperator : NSObject {
    int							stackPosition;
    int							favoritesStackPosition;
    int							stashedStackPosition;

    FlycutStore				*clippingStore;
    FlycutStore				*favoritesStore;
    FlycutStore				*stashedStore;

	SEL saveSelector;
	NSObject* saveTarget;

    BOOL disableStore;
}

// Basic functionality
-(int)indexOfClipping:(NSString*)contents ofType:(NSString*)type fromApp:(NSString *)appName withAppBundleURL:(NSString *)bundleURL;
-(bool)addClipping:(NSString*)contents ofType:(NSString*)type fromApp:(NSString *)appName withAppBundleURL:(NSString *)bundleURL target:(id)selectorTarget clippingAddedSelector:(SEL)clippingAddedSelectorclippingAddedSelector;
-(int)stackPosition;
-(NSString*)getPasteFromStackPosition;
-(NSString*)getPasteFromIndex:(int) position;
-(bool) saveFromStack;
-(bool)clearItemAtStackPosition;
-(void)clearList;
-(void)mergeList;

// Stack position manipulation functionality
-(bool)setStackPositionToOneMoreRecent;
-(bool)setStackPositionToOneLessRecent;
-(bool)setStackPositionToFirstItem;
-(bool)setStackPositionToLastItem;
-(bool)setStackPositionToTenMoreRecent;
-(bool)setStackPositionToTenLessRecent;
-(bool)setStackPositionTo:(int) newStackPosition;
-(void)adjustStackPositionIfOutOfBounds;
-(bool)stackPositionIsInBounds;

// Stack related
-(BOOL) isValidClippingNumber:(NSNumber *)number;
-(NSString *) clippingStringWithCount:(int)count;

// Save and load
-(void) saveEngine;
-(bool) loadEngineFromPList;
-(void) checkCloudKitUpdates;

// Preference related
-(void) setRememberNum:(int)newRemember;

// Initialization / cleanup related
-(void)applicationWillTerminate;;
-(void)awakeFromNibDisplaying:(int) displayNum withDisplayLength:(int) displayLength withSaveSelector:(SEL) selector forTarget:(NSObject*) target;

// Favorites Store related
-(bool)favoritesStoreIsSelected;
-(void)switchToFavoritesStore;
-(bool)restoreStashedStore;
-(void)toggleToFromFavoritesStore;
-(bool)saveFromStackToFavorites;

// Clippings Store related
-(int)jcListCount;
-(FlycutClipping*)clippingAtStackPosition;
-(NSArray *) previousDisplayStrings:(int)howMany containing:(NSString*)search;
-(NSArray *) previousIndexes:(int)howMany containing:(NSString*)search; // This method is in newest-first order.
-(void)setDisableStoreTo:(bool) value;
-(bool)storeDisabled;

@end

#endif /* FlycutOperator_h */
