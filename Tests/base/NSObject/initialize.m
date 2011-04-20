#import <Foundation/NSThread.h>
#import <Foundation/NSLock.h>
#import "Testing.h"

@interface SlowInit0 @end

@interface SlowInit1 : SlowInit0 
+ (void)doNothing;
@end
@interface SlowInit2
+ (void)doNothing;
@end
NSCondition *l;
static volatile int init0, init1, init2, init3;
@implementation SlowInit0
+ (void)initialize
{
	init0 = 1;
}
@end
@implementation SlowInit1
/**
 * Called from main thread.
 */
+ (void)initialize
{
	PASS(init0 == 1, "Superclass +initialize called before subclass");
	// Spin until we've entered the second +initialize method
	while (init2 == 0) {}
	// Wake up the other thread
	[l signal];
	[l unlock];
	// Trigger the 
	[SlowInit2 doNothing];
	init1 = 1;

}
+ (void)doNothing {}
@end
@implementation SlowInit2
/**
 * Called from the second thread. 
 */
+ (void)initialize
{
	init2++;
	// Sleep until the main thread is ready for us
	[l lock];
	// If the runtime is doing the wrong thing and this is called twice, then
	// there will be no signal.  We don't want to deadlock, so make sure that
	// this times out after a short while.
	[l waitUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.5]];
	[l unlock];
	[NSThread sleepForTimeInterval: 1];
	PASS(init1 == 0, "First initialize method did not finish too early");
	init3++;
}
static volatile int finished = 2;
+ (void)doNothing
{
	PASS(init2 == 1, "+initialize called exactly once");
	PASS(init3 == 1, "+initialize completed before another method started");
	finished--;
}
@end

@interface Trampoline : NSObject
+ (void)launch: (id)ignored;
@end
@implementation Trampoline
/**
 * Launch the second thread.  NSThread retains its arguments in the main
 * thread, we need to ensure that nothing triggers the second +initialize
 * method until we're in the second thread.
 */
+ (void)launch: (id)ignored
{
	[NSAutoreleasePool new];
	[SlowInit2 doNothing];
}
@end

/**
 * Test the behaviour of +initialize.  In a well-behaved runtime, both
 * +initialize methods will be allowed to run concurrently, however the first
 * one will block implicitly until the second one has completed.
 */
int main(void)
{
	[NSAutoreleasePool new];
	l = [NSCondition new];
	[l lock];
	[NSThread detachNewThreadSelector: @selector(launch:) toTarget: [Trampoline class] withObject: nil];
	[NSThread sleepForTimeInterval: 0.5];
	[SlowInit1 doNothing];
	[l lock];
	[l unlock];
	while (finished)
	[NSThread sleepForTimeInterval: 0.01];
	return 0;
}
