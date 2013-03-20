//
//  FireDataISO8601DateFormatter.h
//  FireData
//
//  Created by Jonathan Younger on 3/20/13.
//  Copyright (c) 2013 Overcommitted, LLC. All rights reserved.
//

#import "ISO8601DateFormatter.h"

@interface FireDataISO8601DateFormatter : ISO8601DateFormatter
+ (FireDataISO8601DateFormatter *)sharedFormatter;
@end
