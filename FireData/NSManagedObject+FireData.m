//
//  NSManagedObject+Firebase.m
//  Firebase
//
//  Created by Jonathan Younger on 2/26/13.
//  Copyright (c) 2013 Overcommitted, LLC. All rights reserved.
//

#import "NSManagedObject+FireData.h"
#import "FireDataISO8601DateFormatter.h"

#define FirebaseSyncData [[NSUUID UUID] UUIDString]

@implementation NSManagedObject (FireData)

- (NSDictionary *)firedata_propertiesDictionaryWithCoreDataKeyAttribute:(NSString *)coreDataKeyAttribute coreDataDataAttribute:(NSString *)coreDataDataAttribute
{
    NSMutableDictionary *properties = [[NSMutableDictionary alloc] init];
    FireDataISO8601DateFormatter *dateFormatter = [FireDataISO8601DateFormatter sharedFormatter];
    
    for (id property in [[self entity] properties]) {
        NSString *name = [property name];
        if ([name isEqualToString:coreDataKeyAttribute] || [name isEqualToString:coreDataDataAttribute]) continue;
        
        if ([property isKindOfClass:[NSAttributeDescription class]]) {
            NSAttributeDescription *attributeDescription = (NSAttributeDescription *)property;
            if ([attributeDescription isTransient]) continue;
            
            NSString *name = [attributeDescription name];
            id value = [self valueForKey:name];
            
            NSAttributeType attributeType = [attributeDescription attributeType];
            if ((attributeType == NSDateAttributeType) && ([value isKindOfClass:[NSDate class]]) && (dateFormatter != nil)) {
                value = [dateFormatter stringFromDate:value];
            }
            [properties setValue:value forKey:name];
        } else if ([property isKindOfClass:[NSRelationshipDescription class]]) {
            NSRelationshipDescription *relationshipDescription = (NSRelationshipDescription *)property;
            NSString *name = [relationshipDescription name];
            
            if ([relationshipDescription isToMany]) {
                NSMutableArray *items = [[NSMutableArray alloc] init];
                for (NSManagedObject *managedObject in [self valueForKey:name]) {
                    [items addObject:[managedObject valueForKey:coreDataKeyAttribute]];
                }
                [properties setValue:[items sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)] forKey:name];
            } else {
                NSManagedObject *managedObject = [self valueForKey:name];
                [properties setValue:[managedObject valueForKey:coreDataKeyAttribute] forKey:name];
            }
        }
    }
    
    return [NSDictionary dictionaryWithDictionary:properties];
}

- (void)firedata_setPropertiesForKeysWithDictionary:(NSDictionary *)keyedValues coreDataKeyAttribute:(NSString *)coreDataKeyAttribute coreDataDataAttribute:(NSString *)coreDataDataAttribute
{
    FireDataISO8601DateFormatter *dateFormatter = [FireDataISO8601DateFormatter sharedFormatter];
    for (NSPropertyDescription *propertyDescription in [[self entity] properties]) {
        NSString *name = [propertyDescription name];
        if ([name isEqualToString:coreDataKeyAttribute] || [name isEqualToString:coreDataDataAttribute]) continue;
        
        if ([propertyDescription isKindOfClass:[NSAttributeDescription class]]) {
            id value = [keyedValues objectForKey:name];
            
            NSAttributeType attributeType = [(NSAttributeDescription *)propertyDescription attributeType];
            if ((attributeType == NSStringAttributeType) && ([value isKindOfClass:[NSNumber class]])) {
                value = [value stringValue];
            } else if (((attributeType == NSInteger16AttributeType) || (attributeType == NSInteger32AttributeType) || (attributeType == NSInteger64AttributeType) || (attributeType == NSBooleanAttributeType)) && ([value isKindOfClass:[NSString class]])) {
                value = [NSNumber numberWithInteger:[value integerValue]];
            } else if ((attributeType == NSFloatAttributeType) && ([value isKindOfClass:[NSString class]])) {
                value = [NSNumber numberWithDouble:[value doubleValue]];
            } else if ((attributeType == NSDateAttributeType) && ([value isKindOfClass:[NSString class]]) && (dateFormatter != nil)) {
                value = [dateFormatter dateFromString:value];
            }
            
            [self setValue:value forKey:name];
        } else if ([propertyDescription isKindOfClass:[NSRelationshipDescription class]]) {
            NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:[[(NSRelationshipDescription *)propertyDescription destinationEntity] name]];
            
            if ([(NSRelationshipDescription *)propertyDescription isToMany]) {
                NSArray *identifiers = [keyedValues objectForKey:name];
                NSMutableSet *items = [self mutableSetValueForKey:name];
                for (NSString *identifier in identifiers) {
                    [fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"%K == %@", coreDataKeyAttribute, identifier]];
                    NSArray *objects = [self.managedObjectContext executeFetchRequest:fetchRequest error:nil];
                    if ([objects count] == 1) {
                        NSManagedObject *managedObject = objects[0];
                        if (![items containsObject:managedObject]) {
                            [managedObject setValue:FirebaseSyncData forKey:coreDataDataAttribute];
                            [items addObject:managedObject];
                        }
                    }
                }
            } else {
                [fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"%K == %@", coreDataKeyAttribute, [keyedValues objectForKey:name]]];
                NSArray *objects = [self.managedObjectContext executeFetchRequest:fetchRequest error:nil];
                if ([objects count] == 1) {
                    NSManagedObject *managedObject = objects[0];
                    if (![[self valueForKey:name] isEqual:managedObject]) {
                        [managedObject setValue:FirebaseSyncData forKey:coreDataDataAttribute];
                        [self setValue:managedObject forKey:name];
                    }
                }
            }
        }
    }
    
    if ([[self changedValues] count] > 0) {
        [self setValue:FirebaseSyncData forKey:coreDataDataAttribute];
    }
}
@end
