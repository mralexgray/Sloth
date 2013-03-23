/*
 Sloth - Mac OS X Graphical User Interface front-end for lsof
 Copyright (C) 2004-2010 Sveinbjorn Thordarson <sveinbjornt@simnet.is>
 
 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; either version 2 of the License, or
 (at your option) any later version.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 
 You should have received a copy of the GNU General Public License
 along with this program; if not, write to the Free Software
 Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 
 */

#import "SlothController.h"
#import <Foundation/NSObject.h>
#import "NSBag.h"

@implementation SlothController
@synthesize activeInstances, activeDictionary, activeSet;

- (id)init
{
	if (self = [super init]) 
	{
		fileArray = [[NSMutableArray alloc] init];
    }
    return self;
}

+ (void)initialize 
{ 
	NSDictionary *registrationDefaults = [NSDictionary dictionaryWithContentsOfFile: 
										  [[NSBundle mainBundle] pathForResource: @"RegistrationDefaults" ofType: @"plist"]];
    [NSUserDefaults.standardUserDefaults registerDefaults: registrationDefaults];
}

- (void)awakeFromNib
{
	// sorting for tableview
	NSSortDescriptor *nameSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"name"
																	   ascending: YES selector:@selector(localizedCaseInsensitiveCompare:)];
	
	[tableView setSortDescriptors: @[nameSortDescriptor]];
	
	// dragging from tableview
	[tableView setDraggingSourceOperationMask:NSDragOperationEvery forLocal:NO];
	[tableView registerForDraggedTypes:@[NSStringPboardType]];
	
	// center and show window
	[slothWindow center];
	[slothWindow makeKeyAndOrderFront: self];
}


#pragma mark -

/************************************************************************************
 Run lsof and parse output for placement in the data browser
 This is the real juice function
 ************************************************************************************/

- (IBAction)refresh:(id)sender
{
	
	BOOL 		isDir	= FALSE;

	//first, make sure that we have a decent lsof
	NSString *launchPath = [NSUserDefaults.standardUserDefaults stringForKey:@"lsofPath"];
	if (![NSFileManager.defaultManager fileExistsAtPath: launchPath isDirectory: &isDir] || isDir)
	{
		[STUtil alert: @"Invalid executable" subText: @"The 'lsof' utility you specified in the Preferences does not exist"];
		return;
	}
	
	//clear former item list and empty output value stored
	[fileArray removeAllObjects];
	
	//start progress bar animation	
	[progressBar setUsesThreadedAnimation: TRUE];
	[progressBar startAnimation: self];
	
	NSOperationQueue *queue = [[NSOperationQueue alloc] init];
	NSBlockOperation *operation = [NSBlockOperation blockOperationWithBlock:^{

		NSArray		*lines;
		NSData		*data;
		NSString	*pid, *process, *ftype, *fname, *output = nil;
		NSPipe 		*pipe 	= NSPipe.pipe;
		int	i;

		// our command is:			lsof -F pcnt +c0
		//
		// OK, initialise task, run it, retrieve output
		{
			NSTask *lsof = [[NSTask alloc] init];
			[lsof setLaunchPath: launchPath];
			[lsof setArguments: @[@"-F", @"pcnt", @"+c0"]];
			[lsof setStandardOutput: pipe];
			[lsof launch];
			
			data = [[pipe fileHandleForReading] readDataToEndOfFile];
			
		}
		
		//get data output and format as an array of lines of text	
		output = [[NSString alloc] initWithData: data encoding: NSASCIIStringEncoding];
		lines = [output componentsSeparatedByString:@"\n"];
		
		// parse each line
		for (i = 0; i < [lines count]-1; i++)
		{
			NSString *line = lines[i];
			
			//read first character in line
			if ([line characterAtIndex: 0] == 'p')
			{
				pid = [line substringFromIndex: 1];
			}
			else if ([line characterAtIndex: 0] == 'c')
			{
				process = [line substringFromIndex: 1];
			}
			else if ([line characterAtIndex: 0] == 't')
			{
				ftype = [line substringFromIndex: 1];
			}
			else if ([line characterAtIndex: 0] == 'n')
			{
				//we don't report Sloth or lsof info
				if ([process caseInsensitiveCompare: PROGRAM_NAME] == NSOrderedSame || [process caseInsensitiveCompare: PROGRAM_LSOF_NAME] == NSOrderedSame)
					continue;
				
				//check if we use full path
				NSString *rawPath = [line substringFromIndex: 1];            
				BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath: rawPath];
				NSNumber *canReveal = @(fileExists);
				NSString *fullPath = rawPath;
				
				if (fileExists)
					fname = [rawPath lastPathComponent];
				else
					fname = rawPath;
				
				//order matters, see below
				NSMutableDictionary *fileInfo = [NSMutableDictionary dictionary];
				
				fileInfo[@"name"] = process;
				fileInfo[@"pid"] = @([pid intValue]);
				fileInfo[@"path"] = fname;
				fileInfo[@"fullPath"] = fullPath;
				fileInfo[@"canReveal"] = canReveal;
				
				//insert the desired elements
				if ([ftype caseInsensitiveCompare: @"VREG"] == NSOrderedSame || [ftype caseInsensitiveCompare: @"REG"] == NSOrderedSame) 
				{
					fileInfo[@"type"] = @"File";
				} 
				else if ([ftype caseInsensitiveCompare: @"VDIR"] == NSOrderedSame  || [ftype caseInsensitiveCompare: @"DIR"] == NSOrderedSame) 
				{
					fileInfo[@"type"] = @"Directory";
				} 
				else if ([ftype caseInsensitiveCompare: @"IPv6"] == NSOrderedSame || [ftype caseInsensitiveCompare: @"IPv4"] == NSOrderedSame) 
				{
					fileInfo[@"type"] = @"IP Socket";
				} 
				else  if ([ftype caseInsensitiveCompare: @"unix"] == NSOrderedSame) 
				{
					fileInfo[@"type"] = @"Unix Socket";
				} 
				else if ([ftype caseInsensitiveCompare: @"VCHR"] == NSOrderedSame || [ftype caseInsensitiveCompare: @"CHR"] == NSOrderedSame) 
				{
					fileInfo[@"type"] = @"Char Device";
				}
				else
				{
					continue;
				}
				[fileArray addObject: fileInfo];
			}
		}
	}];

//	//you can add more blocks
//	[operation addExecutionBlock:^{
//		NSLog(@"Another block");
//	}];

	[operation setCompletionBlock:^{
		NSLog(@"Doing something once the operation has finished...");
		activeSet = fileArray;
		[self filterResults];

		// update last run time
		[lastRunTextField setStringValue: [NSString stringWithFormat: @"Output at %@ ", [NSDate date]]];

		// stop progress bar and reload data
		[tableView reloadData];
		[progressBar stopAnimation: self];
	}];

	[queue addOperation:operation];
}

- (void) setActiveSet:(NSMutableArray *)aS {

	activeSet = aS;		if (!aS) return;
	activeDictionary 	= NSMutableDictionary.new;
	activeInstances 	= NSMutableDictionary.new;
	[activeSet enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
		NSString* group = obj[@"name"];
		if ( activeDictionary[group] )   [activeDictionary[group] addObject:obj];
		else [activeDictionary setValue:[NSMutableArray arrayWithObject:obj]
								 forKey:group];
	}];
	[activeDictionary.allKeys enumerateObjectsUsingBlock:^(NSString* name, NSUInteger idx, BOOL *stop) {
		__weak NSBag *bag = NSBag.new;
		[activeDictionary[name] enumerateObjectsUsingBlock:^(NSDictionary *d, NSUInteger idx, BOOL *stop) {
			[bag add:d[@"pid"]];
		}];
		[activeInstances setValue:@([bag objects].count) forKey:name];
	}];
//	[activeDictionary writeToFile:@"/Users/localadmin/Desktop/dictionary.plist" atomically: YES];

	[tableView reloadData];
}

// creates a subset of the list of files based on our filtering criterion
- (void)filterResults
{
	NSEnumerator *e = [fileArray objectEnumerator];
	id object;
	

	subset = [[NSMutableArray alloc] init];
	
	NSString *regex = [[NSString alloc] initWithString: [filterTextField stringValue]];
	
	while ( object = [e nextObject] )
	{
		BOOL filtered = NO;
		
		// let's see if it gets filtered by the checkboxes
		if ([object[@"type"] isEqualToString: @"File"] && ![NSUserDefaults.standardUserDefaults boolForKey: @"showRegularFilesEnabled"])
			filtered = YES;
		if ([object[@"type"] isEqualToString: @"Directory"] && ![NSUserDefaults.standardUserDefaults boolForKey: @"showDirectoriesEnabled"])
			filtered = YES;
		if ([object[@"type"] isEqualToString: @"IP Socket"] && ![NSUserDefaults.standardUserDefaults boolForKey: @"showIPSocketsEnabled"])
			filtered = YES;
		if ([object[@"type"] isEqualToString: @"Unix Socket"] && ![NSUserDefaults.standardUserDefaults boolForKey: @"showUnixSocketsEnabled"])
			filtered = YES;
		if ([object[@"type"] isEqualToString: @"Char Device"] && ![NSUserDefaults.standardUserDefaults boolForKey: @"showCharacterDevicesEnabled"])
			filtered = YES;
		
		// see if regex in search field filters it out
		if (!filtered && [[filterTextField stringValue] length] > 0)
		{
			if ([object[@"name"] isMatchedByRegex: regex] == YES) 
				[subset addObject:object];
			else if ([[object[@"pid"] stringValue] isMatchedByRegex: regex] == YES) 
				[subset addObject:object];
			else if ([object[@"path"] isMatchedByRegex: regex] == YES) 
				[subset addObject:object];
			else if ([object[@"fullPath"] isMatchedByRegex: regex] == YES) 
				[subset addObject:object];
			else if ([object[@"type"] isMatchedByRegex: regex] == YES) 
				[subset addObject:object];
		}
		else if (!filtered)
			[subset addObject:object];
	}
	
	
	self.activeSet = subset;
	
	/*	NSSortDescriptor *nameSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"name"
	 ascending: YES selector:@selector(localizedCaseInsensitiveCompare:)];
	 
	 activeSet = [[NSMutableArray arrayWithArray: [subset sortedArrayUsingDescriptors: [NSArray arrayWithObject: nameSortDescriptor]] ] retain];
	 */
	
	//activeSet = [subset sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
	
	[numItemsTextField setStringValue: [NSString stringWithFormat: @"%ld items", (unsigned long)[activeSet count]]];
}


#pragma mark -


/************************************************************************************
 Send currently selected processes the termination signal (SIGKILL or SIGTERM)
 ************************************************************************************/

- (IBAction)kill:(id)sender
{
	int i;
	NSIndexSet *selectedRows = [tableView selectedRowIndexes];
	NSMutableDictionary *processesToTerminateNamed = [NSMutableDictionary dictionaryWithCapacity: 65536];
	NSMutableDictionary *processesToTerminatePID = [NSMutableDictionary dictionaryWithCapacity: 65536];
	
	// First, let's make sure there are selected items by checking for sane value
	if ([tableView selectedRow] < 0 || [tableView selectedRow] > [activeSet count])
		return;
	
	// Let's get the PIDs and names of all selected processes, using dictionaries to avoid duplicate entries
	for (i = 0; i < [activeSet count]; i++)
	{
		if ([selectedRows containsIndex: i])
		{
			processesToTerminateNamed[activeSet[i][@"name"]] = activeSet[i][@"name"];
			
			processesToTerminatePID[activeSet[i][@"name"]] = activeSet[i][@"pid"];
		}
	}
	
	// Create comma-separated list of selected processes
	NSString *processesToKillStr = [[processesToTerminateNamed allKeys] componentsJoinedByString: @", "];
	
	// Ask user to confirm that he really wants to kill these
	if (![STUtil proceedWarning: @"Are you sure you want to kill the selected processes?" 
						subText: [NSString stringWithFormat: @"This will terminate these processes: %@", processesToKillStr] 
					 actionText: @"Kill"])
		return;
	
	// Get signal to send to process based on prefs
    int sigValue = [NSUserDefaults.standardUserDefaults boolForKey: @"sigKill"] ? SIGKILL : SIGTERM;
	
	// iterate through list of PIDs, send each of them the kill/term signal
	for (i = 0; i < [processesToTerminatePID count]; i++)
	{
		int pid = [[processesToTerminatePID allValues][i] intValue];
		int ret = kill(pid, sigValue);
		if (ret)
		{
			[STUtil alert: [NSString stringWithFormat: @"Failed to kill process %@", [processesToTerminateNamed allValues][i]]
				  subText: @"The process may be owned by another user.  Relaunch Sloth as root to kill it."];
			return;
		}
	}
	
	[self refresh: self];
}

/*********************************************************
 Reveal currently selected item on the list in the Finder
 *********************************************************/
- (IBAction)reveal:(id)sender
{
    BOOL		isDir, i;
	NSIndexSet	*selectedRows = [tableView selectedRowIndexes];
	NSMutableDictionary *filesToReveal = [NSMutableDictionary dictionaryWithCapacity: 65536];
	
	// First, let's make sure there are selected items by checking for sane value
	if ([tableView selectedRow] < 0 || [tableView selectedRow] > [activeSet count])
		return;
	
	// Let's get the PIDs and names of all selected processes, using dictionaries to avoid duplicate entries
	for (i = 0; i < [activeSet count]; i++)
	{
		if ([selectedRows containsIndex: i])
		{
			filesToReveal[activeSet[i][@"fullPath"]] = activeSet[i][@"fullPath"];
		}
	}
	
	// if more than 3 items are selected, we ask the user to confirm
	if ([filesToReveal count] > 3)
	{
		if (![STUtil proceedWarning: @"Are you sure you want to reveal the selected files?" 
							subText: [NSString stringWithFormat: @"This will reveal %ld files in the Finder", (unsigned long)[filesToReveal count]]
						 actionText: @"Reveal"])
			return;
	}

	// iterate through files and reveal them using NSWorkspace
	for (i = 0; i < [filesToReveal count]; i++)
	{	
		NSString *path = [filesToReveal allKeys][i];
		if ([[NSFileManager defaultManager] fileExistsAtPath: path isDirectory: &isDir]) 
		{
			if (isDir)
				[[NSWorkspace sharedWorkspace] selectFile: NULL inFileViewerRootedAtPath: path];
			else
				[[NSWorkspace sharedWorkspace] selectFile: path inFileViewerRootedAtPath: NULL];
		}
	}
}

#pragma mark -

- (IBAction)relaunchAsRoot:(id)sender;
{
	NSTask	*theTask = [[NSTask alloc] init];
	
	//open Terminal.app
	[[NSWorkspace sharedWorkspace] launchApplication: @"Terminal.app"];
	
	//the applescript command to run as root via sudo
	NSString *osaCmd = [NSString stringWithFormat: @"tell application \"Terminal\"\n\tdo script \"sudo -b '%@'\"\nend tell",  [[NSBundle mainBundle] executablePath]];
	
	//initialize task -- we launc the AppleScript via the 'osascript' CLI program
	[theTask setLaunchPath: @"/usr/bin/osascript"];
	[theTask setArguments: @[@"-e", osaCmd]];
	
	//launch, wait until it's done and then release it
	[theTask launch];
	[theTask waitUntilExit];
	
	[[NSApplication sharedApplication] terminate: self];
}



#pragma mark -

//////////// delegate and data source methods for the NSTableView /////////////


- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
		return item == nil ? activeDictionary.count :
		[item isKindOfClass:NSDictionary.class] ? 1 : [item count];
}


- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
	item = item ?: activeDictionary;

    if ([item isKindOfClass:NSArray.class]) {
        return item[index];
    }
    else if ([item isKindOfClass:NSDictionary.class]) {
        return item[[item allKeys][index]];
    }
    return nil;
}



- (id)outlineView:(NSOutlineView *)outline objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item
{
	if ([item isKindOfClass:[NSString class]]) {
		return item;
	} else if ([item isKindOfClass:[NSArray class]]) {
		NSArray *keys = [activeDictionary allKeysForObject:item];
		return [column.identifier caseInsensitiveCompare: @"1"] == NSOrderedSame ?
		item[0] : ///keys[0] :
		[column.identifier caseInsensitiveCompare: @"2"] == NSOrderedSame ?
			[NSString stringWithFormat:@"Instances: %@", activeInstances[item[0][@"name"]]] : nil;
//		[@"pid"] :

nil;
	}
	else if ([item isKindOfClass:NSDictionary.class])
		return [column.identifier caseInsensitiveCompare: @"1"] == NSOrderedSame ?
			item[@"name"] :
			[column.identifier caseInsensitiveCompare: @"2"] == NSOrderedSame ?
			item[@"pid"] :
			[column.identifier caseInsensitiveCompare: @"3"] == NSOrderedSame ?
			item[@"type"] :
			[column.identifier caseInsensitiveCompare: @"4"] == NSOrderedSame ?
			^{
//				if ([NSUserDefaults.standardUserDefaults boolForKey: @"showEntireFilePathEnabled"])
					return item[@"fullPath"];
//				else
//					return item[@"path"];
			}() : nil;
			

    return nil;
}


- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
	if ([item isKindOfClass:[NSArray class]] || [item isKindOfClass:[NSDictionary class]]) {
        if ([item count] > 0) {
            return YES;
		}
    }

    return NO;
}

/*

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {

    return (item == nil) ? activeDictionary.allKeys.count : [activeDictionary[item]count];
}


- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    if (item == nil) return YES;
	else if ( [activeDictionary.allKeys containsObject:item] )
		return [activeDictionary[item]count];
	else return -1;
}


- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {

    return (item == nil) ? activeDictionary[item][item][index][@"name"] : @"child";

	//[FileSystemItem rootItem] : [(FileSystemItem *)item childAtIndex:index];
}


- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{

	return activeDictionary[item][1];
//	return (item == nil) ? @"/" : [activeDictionary.] relativePath];
//
//	}	NSArray* group = activeDictionary[item]indexOfObject:item]
//	if ([[tableColumn identifier] caseInsensitiveCompare: @"1"] == NSOrderedSame)
//	{
//		return(] [rowIndex][@"name"]);
//	}
//	else if ([[tableColumn identifier] caseInsensitiveCompare: @"2"] == NSOrderedSame)
//	{
//		return([activeSet[rowIndex][@"pid"] stringValue]);
//	}
//	else if ([[tableColumn identifier] caseInsensitiveCompare: @"3"] == NSOrderedSame)
//	{
//		return(activeSet[rowIndex][@"type"]);
//	}
//	else if ([[tableColumn identifier] caseInsensitiveCompare: @"4"] == NSOrderedSame)
//	{
//		if ([NSUserDefaults.standardUserDefaults boolForKey: @"showEntireFilePathEnabled"])
//			return(activeSet[rowIndex][@"fullPath"]);
//		else
//			return(activeSet[rowIndex][@"path"]);
//	}

//	return  [self tableView:outlineView objectValueForTableColumn:tableColumn row:]
//
}
*/
#pragma mark -

//////////// delegate and data source methods for the NSTableView /////////////

- (int)numberOfRowsInTableView:(NSTableView *)aTableView
{
	return([activeSet count]);
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
	if ([[aTableColumn identifier] caseInsensitiveCompare: @"1"] == NSOrderedSame)
	{
		return(activeSet[rowIndex][@"name"]);
	}
	else if ([[aTableColumn identifier] caseInsensitiveCompare: @"2"] == NSOrderedSame)
	{
		return([activeSet[rowIndex][@"pid"] stringValue]);
	}
	else if ([[aTableColumn identifier] caseInsensitiveCompare: @"3"] == NSOrderedSame)
	{
		return(activeSet[rowIndex][@"type"]);
	}
	else if ([[aTableColumn identifier] caseInsensitiveCompare: @"4"] == NSOrderedSame)
	{
		if ([NSUserDefaults.standardUserDefaults boolForKey: @"showEntireFilePathEnabled"])
			return(activeSet[rowIndex][@"fullPath"]);
		else
			return(activeSet[rowIndex][@"path"]);
	}
	/*else if ([[aTableColumn identifier] caseInsensitiveCompare: @"5"] == NSOrderedSame)
	 {
	 return([[rows objectAtIndex: rowIndex] objectAtIndex: 4]);
	 }
	 else if ([[aTableColumn identifier] caseInsensitiveCompare: @"6"] == NSOrderedSame)
	 {
	 return([[rows objectAtIndex: rowIndex] objectAtIndex: 5]);
	 }
	 else if ([[aTableColumn identifier] caseInsensitiveCompare: @"7"] == NSOrderedSame)
	 {
	 return([[rows objectAtIndex: rowIndex] objectAtIndex: 6]);
	 }
	 else if ([[aTableColumn identifier] caseInsensitiveCompare: @"8"] == NSOrderedSame)
	 {
	 return([[rows objectAtIndex: rowIndex] objectAtIndex: 7]);
	 }
	 else if ([[aTableColumn identifier] caseInsensitiveCompare: @"9"] == NSOrderedSame)
	 {
	 return([[rows objectAtIndex: rowIndex] objectAtIndex: 8]);
	 }*/
	return @"";
}

- (void)tableView:(NSTableView *)aTableView sortDescriptorsDidChange:(NSArray *)oldDescriptors
{
	NSArray *newDescriptors = [tableView sortDescriptors];
	[activeSet sortUsingDescriptors: newDescriptors];
	[tableView reloadData];
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	if ([tableView selectedRow] >= 0 && [tableView selectedRow] < [activeSet count])
	{
		NSMutableDictionary *item = activeSet[[tableView selectedRow]];
		BOOL canReveal = [item[@"canReveal"] boolValue];
		[revealButton setEnabled: canReveal];
		[killButton setEnabled: YES];
	}
	else
	{
		[revealButton setEnabled: NO];
		[killButton setEnabled: NO];
	}
}

- (BOOL)tableView:(NSTableView *)aTableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard *)pboard
{
	int i;
	NSString *dragString = [NSString string];
	
	// Iterate through the list of displayed rows, each one that is selected goes to the clipboard
	for (i = 0; i < [activeSet count]; i++)
	{
		if ([rowIndexes containsIndex: i])
		{
			NSString *filePath;
			
			if ([NSUserDefaults.standardUserDefaults boolForKey: @"showEntireFilePathEnabled"])
				filePath = activeSet[i][@"fullPath"];
			else
				filePath = activeSet[i][@"path"];
			
			NSString *rowString = [NSString stringWithFormat: @"%@\t%@\t%@\t%@\n",
								   activeSet[i][@"name"],
								   [activeSet[i][@"pid"] stringValue],
								   activeSet[i][@"type"],
								   filePath];
			dragString = [dragString stringByAppendingString: rowString];
		}
	}
	
	[pboard declareTypes:@[NSStringPboardType] owner: self];
	[pboard setString: dragString forType:NSStringPboardType];
	return YES;	
}

#pragma mark -

- (void)controlTextDidChange:(NSNotification *)aNotification
{	
	// two possible senders for this notification:  either lsofPathTextField or the resultFilter
	if ([aNotification object] == lsofPathTextField)
	{
		[NSUserDefaults.standardUserDefaults setObject: [lsofPathTextField stringValue]  forKey:@"lsofPath"];
	}
	else
	{
		[self filterResults];
		[tableView reloadData];
	}
}

/*****************************************
 - Delegate for enabling and disabling menu items
 *****************************************/
- (BOOL)validateMenuItem: (NSMenuItem *)anItem 
{
	//reveal in finder / kill process only enabled when something is selected
	if (( [[anItem title] isEqualToString:@"Reveal in Finder"] || [[anItem title] isEqualToString:@"Kill Process"]) && [tableView selectedRow] < 0)
		return NO;
	
	return YES;
}


- (IBAction)checkboxClicked: (id)sender
{
	[self filterResults];
	[tableView reloadData];
}

#pragma mark -

//////////// PREFERENCES HANDLING ////////////////


/************************************************************************************
 Open window with Sloth Preferences
 ************************************************************************************/

- (IBAction)showPrefs:(id)sender
{
	[lsofPathTextField updateTextColoring];
	[prefsWindow center];
	[prefsWindow makeKeyAndOrderFront: sender];
}

- (IBAction)applyPrefs:(id)sender
{
	[prefsWindow performClose: self];
}

- (IBAction)restoreDefaultPrefs:(id)sender
{
	[lsofPathTextField setStringValue: PROGRAM_DEFAULT_LSOF_PATH];
}

/************************************************************************************
 Open window with lsof version information output
 ************************************************************************************/

- (NSString *) lsofVersionInfo
{
	BOOL			isDir;
	NSTask			*task;
	NSPipe			*pipe = [NSPipe pipe];
	NSData			*data;
    
	//get lsof path from prefs
	NSString *launchPath = [NSUserDefaults.standardUserDefaults stringForKey:@"lsofPath"];
	
	//make sure it exists
	if (![[NSFileManager defaultManager] fileExistsAtPath: launchPath isDirectory: &isDir] || isDir)
	{
		[STUtil alert: @"Invalid executable" subText: @"The 'lsof' utility you specified in the Preferences does not exist"];
		return NULL;
	}
	
	//run lsof -v to get version info
	task = [[NSTask alloc] init];
	[task setLaunchPath: launchPath];
	[task setArguments: @[@"-v"]];
	[task setStandardOutput: pipe];
	[task setStandardError: pipe];
	[task launch];
	
	//read the output from the command
	data = [[pipe fileHandleForReading] readDataToEndOfFile];
	
    
    return [[NSString alloc] initWithData: data encoding: NSASCIIStringEncoding];
}

- (IBAction)showLsofVersionInfo:(id)sender
{
	[lsofVersionTextView setString: [self lsofVersionInfo]];
	[lsofVersionWindow center];
	[lsofVersionWindow makeKeyAndOrderFront: sender];
}

#pragma mark -

- (IBAction)supportSlothDevelopment:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL: [NSURL URLWithString: PROGRAM_DONATIONS]];
}

- (IBAction)visitSlothWebsite:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL: [NSURL URLWithString: PROGRAM_WEBSITE]];
}

@end
