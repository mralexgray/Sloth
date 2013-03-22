//
//  SlothDarkView.m
//  Sloth
//
//  Created by Alex Gray on 3/22/13.
//  Copyright (c) 2013 Sveinbjorn Thordarson. All rights reserved.
//

#import "SlothDarkView.h"


@implementation SlothDarkButtonCell

-(NSRect)drawTitle:(NSAttributedString *)title withFrame:(NSRect)frame
												  inView:(NSView *)controlView
{	buttonType = 0;
	NSRect textRect = frame;
	// Adjust Text Rect based on control type and size
	if(buttonType != NSSwitchButton && buttonType != NSRadioButton) {

		textRect.origin.x += 5;
		textRect.size.width -= 10;
		textRect.size.height -= 2;
	}

	NSMutableAttributedString *newTitle = [title mutableCopy];

	//If button is set to show alternate title then
	//display alternate title
	if([self showsStateBy] == 0 && [self highlightsBy] == 1)
		if([self isHighlighted])
			if([self alternateTitle])
				[newTitle setAttributedString: [self attributedAlternateTitle]];

	//If button is set to show alternate title then
	//display alternate title
	if([self showsStateBy] == 1 && [self highlightsBy] == 3)
		if([self state] == 1)
			if([self alternateTitle])
				[newTitle setAttributedString: [self attributedAlternateTitle]];
			//Make sure we aren't trying to edit an
	//empty string.
	if([newTitle length] > 0) {
		[newTitle beginEditing];

		// Removed so Shadows could be used
		// TODO: Find out why I had this in here in the first place, no cosmetic difference
		//[newTitle removeAttribute: NSShadowAttributeName
		 //range: NSMakeRange(0, [newTitle length])];

		NSRange all = NSMakeRange(0, newTitle.length);
		[newTitle addAttribute: NSForegroundColorAttributeName
							 value:self.isEnabled ? [NSColor whiteColor]
												  : [NSColor grayColor]	 range: all];
		[newTitle endEditing];
		//Make the super class do the drawing
		[super drawTitle: newTitle withFrame: textRect inView: controlView];
	}
	return textRect;
}
@end
@implementation SlothDarkView

//- (void) awakeFromNib {
//
//	[self.subviews enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
//		if ([obj isKindOfClass:NSButton.class]) {
//		NSFont *font = [NSFont fo]
//		[(NSButton*)object.cell setFont:font];
//	}];
//}
- (void)drawRect:(NSRect)rect {

	NSRect bounds = self.bounds;
	// Draw background gradient
	NSGradient *gradient = [[NSGradient alloc] initWithColorsAndLocations:
							[NSColor colorWithDeviceWhite:0.15f alpha:1.0f], 0.0f,
							[NSColor colorWithDeviceWhite:0.19f alpha:1.0f], 0.5f,
							[NSColor colorWithDeviceWhite:0.20f alpha:1.0f], 0.5f,
							[NSColor colorWithDeviceWhite:0.25f alpha:1.0f], 1.0f,
							nil];
	[gradient drawInRect:bounds angle:90.0f];
	// Stroke bounds
	[[NSColor blackColor] setStroke];
	[NSBezierPath strokeRect:bounds];
}

@end
