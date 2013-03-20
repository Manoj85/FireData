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
@property (strong, nonatomic) NSMutableDictionary *observedCoreDataEntities;
@property (copy, nonatomic) fcdm_void_managedobjectcontext writeManagedObjectContextCompletionBlock;
@end

@interface FireData (CoreData)
- (void)managedObjectContextObjectsDidChange:(NSNotification *)notification;
- (void)managedObjectContextDidSave:(NSNotification *)notification;
- (NSString *)coreDataEntityForFirebase:(Firebase *)firebase;
- (BOOL)isObservedCoreDataEntity:(NSString *)entity;
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
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (id)init
{
    self = [super init];
    if (self) {
        _coreDataKeyAttribute = @"firebaseKey";
        _coreDataDataAttribute = @"firebaseData";
        _observedCoreDataEntities = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)observeManagedObjectContext:(NSManagedObjectContext *)managedObjectContext
{
    [self removeObserverForManagedObjectContext];
    
    self.observedManagedObjectContext = managedObjectContext;
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter addObserver:self selector:@selector(managedObjectContextObjectsDidChange:) name:NSManagedObjectContextObjectsDidChangeNotification object:self.observedManagedObjectContext];
    [notificationCenter addObserver:self selector:@selector(managedObjectContextDidSave:) name:NSManagedObjectContextDidSaveNotification object:self.observedManagedObjectContext];
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

- (void)observeCoreDataEntity:(NSString *)coreDataEntity firebase:(Firebase *)firebase
{
    [self.observedCoreDataEntities setObject:firebase forKey:coreDataEntity];
    [self observeFirebase:firebase];
    [self deleteCoreDataManagedObjectsThatNoLongerExistInFirebase:firebase];
}

- (void)removeAllObservers
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    NSArray *firebases = [self.observedCoreDataEntities allValues];
    [firebases makeObjectsPerformSelector:@selector(removeAllObservers)];
}

- (void)replaceFirebaseFromCoreData
{
    [self.observedCoreDataEntities enumerateKeysAndObjectsUsingBlock:^(NSString *coreDataEntity, Firebase *firebase, BOOL *stop) {
        [firebase removeValue];
        
        NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:coreDataEntity];
        [fetchRequest setFetchBatchSize:25];
        NSArray *managedObjects = [self.observedManagedObjectContext executeFetchRequest:fetchRequest error:nil];
        [managedObjects enumerateObjectsUsingBlock:^(NSManagedObject *managedObject, NSUInteger idx, BOOL *stop) {
            [self updateFirebase:firebase withManagedObject:managedObject];
        }];
    }];
}
@end

@implementation FireData (CoreData)
- (void)managedObjectContextObjectsDidChange:(NSNotification *)notification
{
    NSMutableSet *managedObjects = [[NSMutableSet alloc] init];
    [managedObjects unionSet:[[notification userInfo] objectForKey:NSInsertedObjectsKey]];
    [managedObjects unionSet:[[notification userInfo] objectForKey:NSUpdatedObjectsKey]];
    
    __weak FireData *weakSelf = self;
    [managedObjects enumerateObjectsUsingBlock:^(NSManagedObject *managedObject, BOOL *stop) {
        FireData *strongSelf = weakSelf; if (!strongSelf) return;
        if (![strongSelf isObservedCoreDataEntity:[[managedObject entity] name]]) return;
        
        if (![managedObject primitiveValueForKey:strongSelf.coreDataKeyAttribute]) {
            [managedObject setPrimitiveValue:[[NSUUID UUID] UUIDString] forKey:strongSelf.coreDataKeyAttribute];
        }
        
        if (![[managedObject changedValues] objectForKey:strongSelf.coreDataDataAttribute]) {
            [managedObject setPrimitiveValue:nil forKey:strongSelf.coreDataDataAttribute];
        }
    }];
}

- (void)managedObjectContextDidSave:(NSNotification *)notification
{
    __weak FireData *weakSelf = self;
    
    NSSet *deletedObjects = [[notification userInfo] objectForKey:NSDeletedObjectsKey];
    [deletedObjects enumerateObjectsUsingBlock:^(NSManagedObject *managedObject, BOOL *stop) {
        FireData *strongSelf = weakSelf; if (!strongSelf) return;
        Firebase *firebase = [strongSelf firebaseForCoreDataEntity:[[managedObject entity] name]];
        if (firebase) {
            Firebase *child = [firebase childByAppendingPath:[managedObject valueForKey:self.coreDataKeyAttribute]];
            [child removeValue];
        }
    }];
    
    NSMutableSet *managedObjects = [[NSMutableSet alloc] init];
    [managedObjects unionSet:[[notification userInfo] objectForKey:NSInsertedObjectsKey]];
    [managedObjects unionSet:[[notification userInfo] objectForKey:NSUpdatedObjectsKey]];
    
    NSSet *changedObjects = [managedObjects filteredSetUsingPredicate:[NSPredicate predicateWithFormat:@"%K == nil", self.coreDataDataAttribute]];
    [changedObjects enumerateObjectsUsingBlock:^(NSManagedObject *managedObject, BOOL *stop) {
        FireData *strongSelf = weakSelf; if (!strongSelf) return;
        Firebase *firebase = [strongSelf firebaseForCoreDataEntity:[[managedObject entity] name]];
        if (firebase) {
            [strongSelf updateFirebase:firebase withManagedObject:managedObject];
        }
    }];
}

- (NSString *)coreDataEntityForFirebase:(Firebase *)firebase
{
    return [[self.observedCoreDataEntities allKeysForObject:firebase] lastObject];
}

- (BOOL)isObservedCoreDataEntity:(NSString *)entity
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
    return [self.observedCoreDataEntities objectForKey:entity];
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
