//
//  FireData.m
//  FireData
//
//  Created by Jonathan Younger on 3/20/13.
//  Copyright (c) 2013 Overcommitted, LLC. All rights reserved.
//

#import "FireData.h"
#import "NSManagedObject+FireData.h"

typedef void (^fcdm_void_managedobjectcontext) (NSManagedObjectContext *context);

@interface FireData ()
@property (strong, nonatomic) NSManagedObjectContext *observedManagedObjectContext;
@property (strong, nonatomic) NSManagedObjectContext *writeManagedObjectContext;
@property (strong, nonatomic) NSMutableDictionary *linkedEntities;
@property (copy, nonatomic) fcdm_void_managedobjectcontext writeManagedObjectContextCompletionBlock;
@end

@interface FireData (CoreData)
- (void)managedObjectContextObjectsDidChange:(NSNotification *)notification;
- (void)managedObjectContextDidSave:(NSNotification *)notification;
- (NSString *)coreDataEntityForFirebase:(Firebase *)firebase;
- (BOOL)isCoreDataEntityLinked:(NSString *)entity;
- (NSManagedObject *)fetchCoreDataManagedObjectWithEntityName:(NSString *)entityName firebaseKey:(NSString *)firebaseKey;
- (void)deleteCoreDataManagedObjectsThatNoLongerExistInFirebase:(Firebase *)firebase;
@end

@interface FireData (Firebase)
- (Firebase *)firebaseForCoreDataEntity:(NSString *)entity;
- (void)observeFirebase:(Firebase *)firebase;
- (void)updateFirebase:(Firebase *)firebase withManagedObject:(NSManagedObject *)managedObject;
@end

@implementation FireData
- (void)dealloc
{
    [self stopObserving];
}

+ (NSString *)firebaseKey
{
    return [[NSUUID UUID] UUIDString];
}

- (id)init
{
    self = [super init];
    if (self) {
        _coreDataKeyAttribute = @"firebaseKey";
        _coreDataDataAttribute = @"firebaseData";
        _linkedEntities = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)observeManagedObjectContext:(NSManagedObjectContext *)managedObjectContext
{
    [self removeObserverForManagedObjectContext];
    self.observedManagedObjectContext = managedObjectContext;
}

- (void)removeObserverForManagedObjectContext
{
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    if (self.observedManagedObjectContext) {
        [notificationCenter removeObserver:self name:NSManagedObjectContextObjectsDidChangeNotification object:self.observedManagedObjectContext];
        [notificationCenter removeObserver:self name:NSManagedObjectContextDidSaveNotification object:self.observedManagedObjectContext];
    }
    
    self.observedManagedObjectContext = nil;
}

- (void)setWriteManagedObjectContext:(NSManagedObjectContext *)writeManagedObjectContext withCompletionBlock:(void (^)(NSManagedObjectContext *error))block
{
    self.writeManagedObjectContext = writeManagedObjectContext;
    self.writeManagedObjectContextCompletionBlock = [block copy];
}

- (void)linkCoreDataEntity:(NSString *)coreDataEntity withFirebase:(Firebase *)firebase
{
    [self.linkedEntities setObject:firebase forKey:coreDataEntity];
}

- (void)unlinkCoreDataEntity:(NSString *)coreDataEntity
{
    [[self.linkedEntities objectForKey:coreDataEntity] removeAllObservers];
    [self.linkedEntities removeObjectForKey:coreDataEntity];
}

- (void)startObserving
{
    [self.linkedEntities enumerateKeysAndObjectsUsingBlock:^(NSString *coreDataEntity, Firebase *firebase, BOOL *stop) {
        [self deleteCoreDataManagedObjectsThatNoLongerExistInFirebase:firebase];
        [self observeFirebase:firebase];
    }];
    
    if (self.observedManagedObjectContext) {
        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        [notificationCenter addObserver:self selector:@selector(managedObjectContextObjectsDidChange:) name:NSManagedObjectContextObjectsDidChangeNotification object:self.observedManagedObjectContext];
        [notificationCenter addObserver:self selector:@selector(managedObjectContextDidSave:) name:NSManagedObjectContextDidSaveNotification object:self.observedManagedObjectContext];
    }
}

- (void)stopObserving
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    NSArray *firebases = [self.linkedEntities allValues];
    [firebases makeObjectsPerformSelector:@selector(removeAllObservers)];
}

- (void)replaceFirebaseFromCoreData
{
    [self.linkedEntities enumerateKeysAndObjectsUsingBlock:^(NSString *coreDataEntity, Firebase *firebase, BOOL *stop) {
        [firebase removeValue];
        
        NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:coreDataEntity];
        [fetchRequest setFetchBatchSize:25];
        NSArray *managedObjects = [self.observedManagedObjectContext executeFetchRequest:fetchRequest error:nil];
        for (NSManagedObject *managedObject in managedObjects) {
            [self updateFirebase:firebase withManagedObject:managedObject];
        };
    }];
}


@end

@implementation FireData (CoreData)
- (void)managedObjectContextObjectsDidChange:(NSNotification *)notification
{
    NSMutableSet *managedObjects = [[NSMutableSet alloc] init];
    [managedObjects unionSet:[[notification userInfo] objectForKey:NSInsertedObjectsKey]];
    [managedObjects unionSet:[[notification userInfo] objectForKey:NSUpdatedObjectsKey]];

    for (NSManagedObject *managedObject in managedObjects) {
        if (![self isCoreDataEntityLinked:[[managedObject entity] name]]) return;
        
        if (![managedObject primitiveValueForKey:self.coreDataKeyAttribute]) {
            [managedObject setPrimitiveValue:[[self class] firebaseKey] forKey:self.coreDataKeyAttribute];
        }
        
        if (![[managedObject changedValues] objectForKey:self.coreDataDataAttribute]) {
            [managedObject setPrimitiveValue:nil forKey:self.coreDataDataAttribute];
        }
    };
}

- (void)managedObjectContextDidSave:(NSNotification *)notification
{
    NSSet *deletedObjects = [[notification userInfo] objectForKey:NSDeletedObjectsKey];
    for (NSManagedObject *managedObject in deletedObjects) {
        Firebase *firebase = [self firebaseForCoreDataEntity:[[managedObject entity] name]];
        if (firebase) {
            Firebase *child = [firebase childByAppendingPath:[managedObject valueForKey:self.coreDataKeyAttribute]];
            [child removeValue];
        }
    };
    
    NSMutableSet *managedObjects = [[NSMutableSet alloc] init];
    [managedObjects unionSet:[[notification userInfo] objectForKey:NSInsertedObjectsKey]];
    [managedObjects unionSet:[[notification userInfo] objectForKey:NSUpdatedObjectsKey]];
    
    NSSet *changedObjects = [managedObjects filteredSetUsingPredicate:[NSPredicate predicateWithFormat:@"%K == nil", self.coreDataDataAttribute]];
    for (NSManagedObject *managedObject in changedObjects) {
        Firebase *firebase = [self firebaseForCoreDataEntity:[[managedObject entity] name]];
        if (firebase) {
            [self updateFirebase:firebase withManagedObject:managedObject];
        }
    };
}

- (NSString *)coreDataEntityForFirebase:(Firebase *)firebase
{
    return [[self.linkedEntities allKeysForObject:firebase] lastObject];
}

- (BOOL)isCoreDataEntityLinked:(NSString *)entity
{
    return [self firebaseForCoreDataEntity:entity] != nil;
}

- (NSManagedObject *)fetchCoreDataManagedObjectWithEntityName:(NSString *)entityName firebaseKey:(NSString *)firebaseKey
{
    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:entityName];
    [fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"%K == %@", self.coreDataKeyAttribute, firebaseKey]];
    [fetchRequest setFetchLimit:1];
    return [[self.writeManagedObjectContext executeFetchRequest:fetchRequest error:nil] lastObject];
}

- (void)updateCoreDataEntity:(NSString *)entityName firebaseKey:(NSString *)firebaseKey properties:(NSDictionary *)properties
{
    if ((id)properties == [NSNull null]) return;
    
    NSManagedObject *managedObject = [self fetchCoreDataManagedObjectWithEntityName:entityName firebaseKey:firebaseKey];
    if (!managedObject) {
        managedObject = [NSEntityDescription insertNewObjectForEntityForName:entityName inManagedObjectContext:self.writeManagedObjectContext];
        [managedObject setValue:firebaseKey forKey:self.coreDataKeyAttribute];
    }
    
    [managedObject firedata_setPropertiesForKeysWithDictionary:properties coreDataKeyAttribute:self.coreDataKeyAttribute coreDataDataAttribute:self.coreDataDataAttribute];
    
    if ([self.writeManagedObjectContext hasChanges] && self.writeManagedObjectContextCompletionBlock) {
        self.writeManagedObjectContextCompletionBlock(self.writeManagedObjectContext);
    }
}

- (void)deleteCoreDataManagedObjectsThatNoLongerExistInFirebase:(Firebase *)firebase
{
    NSString *coreDataEntity = [self coreDataEntityForFirebase:firebase];
    if (!coreDataEntity) return;
    
    void (^identifierBlock)(FDataSnapshot *snapshot) = ^(FDataSnapshot *snapshot) {
        NSMutableArray *uniqueIdentifiers = [[NSMutableArray alloc] init];
        for (FDataSnapshot *child in snapshot.children) {
            [uniqueIdentifiers addObject:child.name];
        };
        
        NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:coreDataEntity];
        [fetchRequest setIncludesPropertyValues:NO];
        [fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"NOT (%K IN %@)", self.coreDataKeyAttribute, uniqueIdentifiers]];
        
        NSArray *objects = [self.writeManagedObjectContext executeFetchRequest:fetchRequest error:nil];
        for (NSManagedObject *managedObject in objects) {
            [self.writeManagedObjectContext deleteObject:managedObject];
        }
        
        if (self.writeManagedObjectContextCompletionBlock) {
            self.writeManagedObjectContextCompletionBlock(self.writeManagedObjectContext);
        }
    };
    [firebase observeSingleEventOfType:FEventTypeValue withBlock:identifierBlock];
}
@end

@implementation FireData (Firebase)
- (Firebase *)firebaseForCoreDataEntity:(NSString *)entity
{
    return [self.linkedEntities objectForKey:entity];
}

- (void)observeFirebase:(Firebase *)firebase
{
    void (^updatedBlock)(FDataSnapshot *snapshot) = ^(FDataSnapshot *snapshot) {
        NSString *coreDataEntity = [self coreDataEntityForFirebase:firebase];
        if (!coreDataEntity) return;
        [self updateCoreDataEntity:coreDataEntity firebaseKey:snapshot.name properties:snapshot.value];
    };
    [firebase observeEventType:FEventTypeChildAdded withBlock:updatedBlock];
    [firebase observeEventType:FEventTypeChildChanged withBlock:updatedBlock];
    
    void (^removedBlock)(FDataSnapshot *snapshot) = ^(FDataSnapshot *snapshot) {
        NSString *coreDataEntity = [self coreDataEntityForFirebase:firebase];
        if (!coreDataEntity) return;
        
        NSManagedObject *managedObject = [self fetchCoreDataManagedObjectWithEntityName:coreDataEntity firebaseKey:snapshot.name];
        if (managedObject) {
            [self.writeManagedObjectContext deleteObject:managedObject];
            
            if (self.writeManagedObjectContextCompletionBlock) {
                self.writeManagedObjectContextCompletionBlock(self.writeManagedObjectContext);
            }
        }
    };
    [firebase observeEventType:FEventTypeChildRemoved withBlock:removedBlock];
}

- (void)updateFirebase:(Firebase *)firebase withManagedObject:(NSManagedObject *)managedObject
{
    NSDictionary *properties = [managedObject firedata_propertiesDictionaryWithCoreDataKeyAttribute:self.coreDataKeyAttribute coreDataDataAttribute:self.coreDataDataAttribute];
    Firebase *child = [firebase childByAppendingPath:[managedObject valueForKey:self.coreDataKeyAttribute]];
    NSString *childName = child.name;
    [child setValue:properties withCompletionBlock:^(NSError *error) {
        if (error) {
            NSLog(@"Error updating %@: %@", childName, error);
        }
    }];
}
@end
