//
//  FireDataISO8601DateFormatter.m
//  FireData
//
//  Created by Jonathan Younger on 3/20/13.
//  Copyright (c) 2013 Overcommitted, LLC. All rights reserved.
//

#import "FireDataISO8601DateFormatter.h"

@implementation FireDataISO8601DateFormatter
+ (FireDataISO8601DateFormatter *)sharedFormatter
{
	NSMutableDictionary *dictionary = [[NSThread currentThread] threadDictionary];
	static NSString *dateFormatterKey = @"FireDataISO8601DateFormatter";
	
    FireDataISO8601DateFormatter *dateFormatter = [dictionary objectForKey:dateFormatterKey];
    if (dateFormatter == nil) {
        dateFormatter = [[FireDataISO8601DateFormatter alloc] init];
        dateFormatter.includeTime = YES;
        [dictionary setObject:dateFormatter forKey:dateFormatterKey];
    }
    return dateFormatter;
}
@end
