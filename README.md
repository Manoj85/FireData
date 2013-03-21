FireData
========
FireData seamlessly integrates Core Data with [Firebase](http://www.firebase.com).


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
        if ([context save:&error]) {
            if (![self.managedObjectContext save:&error]) {
                NSLog(@"Error saving: %@", error);
            }
        } else {
            NSLog(@"Error saving: %@", error);
        }
    }];
    
Get a reference to Firebase

    Firebase *firebase = [[Firebase alloc] initWithUrl:@"https://EXAMPLE.firebaseio.com/"];
    
Link the Core Data and Firebase references that are to be synced

    [firedata linkCoreDataEntity:@"Book" withFirebase:[firebase childByAppendingPath:@"books"]];
    
Check the existing data in Firebase

    [firebase observeSingleEventOfType:FEventTypeValue withBlock:^(FDataSnapshot *snapshot) {
        // If Firebase is empty then replace with the data from Core Data
        if (snapshot.value == [NSNull null]) {
            [firedata replaceFirebaseFromCoreData];
        }
    
        // Start observing changes between Core Data and Firebase
        [firedata startObserving];
    }];
    
Hold on to FireData
    
    self.firedata = firedata;


Example Application
-------------------

* [CoreDataBooks](https://github.com/daikini/FireBooks) sample application that has been updated to support Firebase using FireData. 

    
Known Issues
------------

* [Firebase](http://www.firebase.com) does not currently persistent offline changes to disk. Full offline support backed by disk will be coming in the future.[[1]](https://groups.google.com/d/msg/firebase-talk/lVFOh9Wqwog/FvqWiiuP-_MJ)


License
-------
[MIT](https://github.com/overcommitted/FireData/blob/master/LICENSE).


[1] https://groups.google.com/d/msg/firebase-talk/lVFOh9Wqwog/FvqWiiuP-_MJ