FireData
========
FireData seamlessly integrated Core Data with[Firebase](http://www.firebase.com).


Usage
-----
Include both Firebase and FireData in your application.

    #import <Firebase/Firebase.h>
    #import <FireData/FireData.h>

Initialize an instance of FireData
    
    FireData *firedata = [[FireData alloc] init];
        
Listen for changes from the default managed object context

    [firedata observeManagedObjectContext:self.managedObjectContext];
    
Create a new managed object context to write changes from Firebase; set its parent to the default managed object context.

    NSManagedObjectContext *writingContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    [writingContext setParentContext:self.managedObjectContext];
    [firedata setWriteManagedObjectContext:writingContext withCompletionBlock:^(NSManagedObjectContext *context) {
        NSError *error = nil;
        if ([context hasChanges] && ![context save:&error]) {
            NSLog(@"Error saving: %@", error);
        }
    }];
    
Get a reference to Firebase

    Firebase *firebase = [[Firebase alloc] initWithUrl:@"https://EXAMPLE.firebaseio.com/"];
    
Observe the Core Data and Firebase references that are to be synced

    [firedata observeCoreDataEntity:@"Book" firebase:[firebase childByAppendingPath:@"books"]];
    
Hold on to FireData
    
    self.firedata = firedata;

License
-------
[MIT](http://firebase.mit-license.org).
