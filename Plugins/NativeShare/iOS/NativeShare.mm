#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#ifdef UNITY_4_0 || UNITY_5_0
#import "iPhone_View.h"
#else
extern UIViewController* UnityGetGLViewController();
#endif

#define CHECK_IOS_VERSION( version )  ([[[UIDevice currentDevice] systemVersion] compare:version options:NSNumericSearch] != NSOrderedAscending)

// Credit: https://github.com/ChrisMaire/unity-native-sharing

// Credit: https://stackoverflow.com/a/29916845/2373034
@interface UNativeShareEmailItemProvider : NSObject <UIActivityItemSource>
@property (nonatomic, strong) NSString *subject;
@property (nonatomic, strong) NSString *body;
@end

// Credit: https://stackoverflow.com/a/29916845/2373034
@implementation UNativeShareEmailItemProvider
- (id)activityViewControllerPlaceholderItem:(UIActivityViewController *)activityViewController
{
	return [self body];
}

- (id)activityViewController:(UIActivityViewController *)activityViewController itemForActivityType:(NSString *)activityType
{
	return [self body];
}

- (NSString *)activityViewController:(UIActivityViewController *)activityViewController subjectForActivityType:(NSString *)activityType
{
	return [self subject];
}
@end

extern "C" void _NativeShare_Share( const char* files[], int filesCount, const char* subject, const char* text, const char* link ) 
{
	NSMutableArray *items = [NSMutableArray new];
	
	// Handle subject and text with modern email provider
	if( strlen( subject ) > 0 && CHECK_IOS_VERSION( @"7.0" ) )
	{
		UNativeShareEmailItemProvider *emailItem = [UNativeShareEmailItemProvider new];
		emailItem.subject = [NSString stringWithUTF8String:subject];
		emailItem.body = [NSString stringWithUTF8String:text];
		[items addObject:emailItem];
	}
	else if( strlen( text ) > 0 )
		[items addObject:[NSString stringWithUTF8String:text]];
	
	// Modern URL handling with proper encoding
	if( strlen( link ) > 0 )
	{
		NSString *urlRaw = [NSString stringWithUTF8String:link];
		NSURL *url = [NSURL URLWithString:urlRaw];
		if( url == nil )
		{
			if( CHECK_IOS_VERSION( @"9.0" ) )
			{
				url = [NSURL URLWithString:[urlRaw stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
			}
		}
		
		if( url != nil )
			[items addObject:url];
		else
			NSLog( @"Couldn't create a URL from link: %@", urlRaw );
	}
	
	// Modern file handling with proper type checking
	for( int i = 0; i < filesCount; i++ ) 
	{
		NSString *filePath = [NSString stringWithUTF8String:files[i]];
		NSURL *fileURL = [NSURL fileURLWithPath:filePath];
		
		// Check if it's an image
		UIImage *image = [UIImage imageWithContentsOfFile:filePath];
		if( image != nil )
		{
			[items addObject:image];
		}
		else
		{
			// For other file types, use file URL
			[items addObject:fileURL];
		}
	}
	
	if( strlen( subject ) == 0 && [items count] == 0 )
	{
		NSLog( @"Share canceled because there is nothing to share..." );
		UnitySendMessage( "NSShareResultCallbackiOS", "OnShareCompleted", "2" );
		return;
	}
	
	// Modern activity view controller setup
	UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
	if( strlen( subject ) > 0 )
		[activity setValue:[NSString stringWithUTF8String:subject] forKey:@"subject"];
	
	// Modern completion handler
	void (^shareResultCallback)(UIActivityType activityType, BOOL completed, UIActivityViewController *activityReference) = ^void( UIActivityType activityType, BOOL completed, UIActivityViewController *activityReference )
	{
		NSLog( @"Shared to %@ with result: %d", activityType, completed );
		
		if( activityReference )
		{
			const char *resultMessage = [[NSString stringWithFormat:@"%d%@", completed ? 1 : 2, activityType] UTF8String];
			char *result = (char*) malloc( strlen( resultMessage ) + 1 );
			strcpy( result, resultMessage );
			
			UnitySendMessage( "NSShareResultCallbackiOS", "OnShareCompleted", result );
			
			if( !completed && UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone )
				[activityReference dismissViewControllerAnimated:YES completion:nil];
		}
	};
	
	// Modern completion handler setup
	if( CHECK_IOS_VERSION( @"8.0" ) )
	{
		__block UIActivityViewController *activityReference = activity;
		activity.completionWithItemsHandler = ^( UIActivityType activityType, BOOL completed, NSArray *returnedItems, NSError *activityError )
		{
			if( activityError != nil )
				NSLog( @"Share error: %@", activityError );
			
			shareResultCallback( activityType, completed, activityReference );
			activityReference = nil;
		};
	}
	else
	{
		UnitySendMessage( "NSShareResultCallbackiOS", "OnShareCompleted", "" );
	}
	
	// Modern presentation handling
	UIViewController *rootViewController = UnityGetGLViewController();
	if( UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone )
	{
		// iPhone presentation
		if( CHECK_IOS_VERSION( @"13.0" ) )
		{
			activity.modalPresentationStyle = UIModalPresentationFullScreen;
		}
		[rootViewController presentViewController:activity animated:YES completion:nil];
	}
	else
	{
		// iPad presentation with modern popover
		if( CHECK_IOS_VERSION( @"13.0" ) )
		{
			activity.modalPresentationStyle = UIModalPresentationPopover;
			UIPopoverPresentationController *popPC = activity.popoverPresentationController;
			popPC.sourceView = rootViewController.view;
			popPC.sourceRect = CGRectMake( rootViewController.view.frame.size.width / 2, rootViewController.view.frame.size.height / 2, 1, 1 );
			popPC.permittedArrowDirections = 0;
			[rootViewController presentViewController:activity animated:YES completion:nil];
		}
		else
		{
			UIPopoverController *popup = [[UIPopoverController alloc] initWithContentViewController:activity];
			[popup presentPopoverFromRect:CGRectMake( rootViewController.view.frame.size.width / 2, rootViewController.view.frame.size.height / 2, 1, 1 ) inView:rootViewController.view permittedArrowDirections:0 animated:YES];
		}
	}
}