//
//  FireData.h
//  FireData
//
//  Created by Jonathan Younger on 3/20/13.
//  Copyright (c) 2013 Overcommitted, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Firebase/Firebase.h>
#import <CoreData/CoreData.h>


@interface FireData : NSObject

/**
 * Set this property to the Core Data unique key attribute used by Firebase.
 * @default firebaseKey
 * @return The Core Data unique key attribute
 */
@property (copy, nonatomic) NSString *coreDataKeyAttribute;

/**
 * Set this property to the Core Data data attribute used by Firebase.
 * @default firebaseData
 * @return The Core Data data attribute
 */
@property (copy, nonatomic) NSString *coreDataDataAttribute;

/**
 * observeManagedObjectContext: is used to listen for data changes for the specified managed object context.
 *
 * @param managedObjectContext The managed object context to listen for changes on.
 */
- (void)observeManagedObjectContext:(NSManagedObjectContext *)managedObjectContext;

/**
 * setWriteManagedObjectContext:withCompletionBlock: is used to write changes from Firebase to the specified managed object context.
 *
 * @param managedObjectContext The managed object context to write changes to.
 * @param block The block that should be called to save changes written to the managed object context.
 */
- (void)setWriteManagedObjectContext:(NSManagedObjectContext *)writeManagedObjectContext withCompletionBlock:(void (^)(NSManagedObjectContext *error))block;

/**
 * observeCoreDataEntity:firebase: is used to listen for data changes for the specified Core Data entity and Firebase reference.
 *
 * @param coreDataEntity The Core Data entity name to listen for changes to.
 * @param firebase The Firebase reference to listen for changes to.
 */
- (void)observeCoreDataEntity:(NSString *)coreDataEntity firebase:(Firebase *)firebase;

/**
 * Detach all previously attached observers.
 */
- (void)removeAllObservers;

/**
 * Replace all Firebase data with values from Core Data.
 */
- (void)replaceFirebaseFromCoreData;
@end
