//
//  NSManagedObject+Firebase.h
//  Firebase
//
//  Created by Jonathan Younger on 2/26/13.
//  Copyright (c) 2013 Overcommitted, LLC. All rights reserved.
//

#import <CoreData/CoreData.h>

@interface NSManagedObject (FireData)
- (NSDictionary *)firedata_propertiesDictionaryWithCoreDataKeyAttribute:(NSString *)coreDataKeyAttribute coreDataDataAttribute:(NSString *)coreDataDataAttribute;
- (void)firedata_setPropertiesForKeysWithDictionary:(NSDictionary *)keyedValues coreDataKeyAttribute:(NSString *)coreDataKeyAttribute coreDataDataAttribute:(NSString *)coreDataDataAttribute;
@end
