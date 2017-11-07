//
//  XIMessagingCreatorTest.m
//  common-iOS
//
//  Created by vfabian on 24/07/15.
//  Copyright (c) 2015 LogMeIn Inc. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>

#import "XIMessagingCreatorProxy.h"
#import "XIMSGMessagingCreator.h"
#import <Internals/Session/XICOSessionNotifications.h>

@interface XIMessagingCreatorTest : XCTestCase

@property(nonatomic, strong)XIMSGMessagingCreator *creator;
@property(nonatomic, strong)OCMockObject *mockProxy;
@property(nonatomic, strong)OCMockObject *mockConnectionPool;
@property(nonatomic, strong)OCMockObject *mockDelegate;
@property(nonatomic, strong)OCMockObject *mockPoolCancelable;
@property(nonatomic, strong)XCTestExpectation *expectation;
@property(nonatomic, strong)XICOSessionNotifications *notifications;
@property(nonatomic, strong)XILastWill* lastWill;
@end

@implementation XIMessagingCreatorTest

- (void)setUp {
    [super setUp];
    
    self.mockProxy = [OCMockObject mockForProtocol:@protocol(XIMessagingCreator)];
    self.mockConnectionPool = [OCMockObject mockForProtocol:@protocol(XICOConnectionPooling)];
    self.mockDelegate = [OCMockObject mockForProtocol:@protocol(XIMessagingCreatorDelegate)];
    self.notifications = [XICOSessionNotifications new];
    
    self.creator = [[XIMSGMessagingCreator alloc] initWithLogger:nil
                                                           proxy:(id<XIMessagingCreator>)self.mockProxy
                                                             jwt:(NSString*)nil
                                                  connectionPool:(id<XICOConnectionPooling>)self.mockConnectionPool
                                                   notifications:self.notifications];
    self.creator.delegate = (id<XIMessagingCreatorDelegate>)self.mockDelegate;
    self.mockPoolCancelable = [OCMockObject mockForProtocol:@protocol(XICOConnectionPoolCancelable)];
    self.lastWill = [[XILastWill alloc] initWithChannel: @"topic" message: [@"message" dataUsingEncoding: NSUTF8StringEncoding] qos: XIMessagingQoSAtLeastOnce retain: YES];
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testXIMSGMessagingCreatorCreation {
    XCTAssert(self.creator, @"Creator not created");
    XCTAssertEqual(self.creator.state, XIServiceCreatorStateIdle, @"Invalid start state");
    XCTAssertEqual(self.creator.delegate, self.mockDelegate, @"Invalid delegate");
    XCTAssertEqual(self.creator.messagingCreatorDelegate, self.mockDelegate, @"Invalid delegate");
}

- (void)testXIMSGMessagingCreatorCancleIdle {
    XCTAssert(self.creator, @"Creator not created");
    [self.creator cancel];
    XCTAssertEqual(self.creator.state, XIServiceCreatorStateCanceled, @"Invalid start state");
}

- (void)testXIMSGMessagingCreatorStartCreation {
    XCTAssert(self.creator, @"Creator not created");
    
    [[[self.mockConnectionPool expect] andReturn:self.mockPoolCancelable] requestConnectionWithCleanSession: YES
                                                                                                   lastWill: self.lastWill
                                                                                                        jwt: [OCMArg any]
                                                                                                   delegate: (id<XICOConnectionPoolDelegate>)self.creator];
    [self.creator createMessagingWithCleanSession: YES lastWill: self.lastWill];
    
    [self.mockConnectionPool verify];
    XCTAssertEqual(self.creator.state, XIServiceCreatorStateCreating, @"Invalid start state");
}

- (void)testXIMSGMessagingCreatorCreatingCancel {
    [self testXIMSGMessagingCreatorStartCreation];
    
    [[self.mockPoolCancelable expect] cancel];
    [self.creator cancel];
    [self.mockPoolCancelable verify];
    XCTAssertEqual(self.creator.state, XIServiceCreatorStateCanceled, @"Invalid canceled state");
}

- (void)testXIMSGMessagingCreatorCreatingCancelBySessionClose {
    [self testXIMSGMessagingCreatorStartCreation];
    
    [[self.mockPoolCancelable expect] cancel];
    
    [self.notifications.sessionNotificationCenter postNotificationName:XISessionDidCloseNotification object:nil];
    
    [self.mockPoolCancelable verify];
    XCTAssertEqual(self.creator.state, XIServiceCreatorStateCanceled, @"Invalid canceled state");
}

- (void)testXIMSGMessagingCreatorCreatingSuccess {
    [self testXIMSGMessagingCreatorStartCreation];
    OCMockObject *mockConnection = [OCMockObject mockForProtocol:@protocol(XICOConnecting)];
    [[mockConnection expect] addListener:[OCMArg any]];
    [[self.mockDelegate expect] messagingCreator:(id<XIMessagingCreator>)self.mockProxy didCreateMessaging:[OCMArg any]];
    [(id<XICOConnectionPoolDelegate>)self.creator connectionPool:(id<XICOConnectionPooling>)self.mockConnectionPool
                                             didCreateConnection:(id<XICOConnecting>)mockConnection];
    
    self.expectation = [self expectationWithDescription:@""];
    dispatch_async(dispatch_get_main_queue(), ^ {
        [self.mockDelegate verify];
        [mockConnection verify];
        XCTAssertEqual(XIServiceCreatorStateCreated, self.creator.state, @"Invalid created state");
        [self.expectation fulfill];
    });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testXIMSGMessagingCreatorCreatingError {
    [self testXIMSGMessagingCreatorStartCreation];
    NSError *error = [NSError errorWithDomain:@"ekwjfhe" code:89 userInfo:nil];
    
    [[self.mockDelegate expect] messagingCreator:(id<XIMessagingCreator>)self.mockProxy didFailToCreateMessagingWithError:error];
    [(id<XICOConnectionPoolDelegate>)self.creator connectionPool:(id<XICOConnectionPooling>)self.mockConnectionPool
                                             didFailToCreateConnection:error];
    
    self.expectation = [self expectationWithDescription:@""];
    dispatch_async(dispatch_get_main_queue(), ^ {
    //    [self.mockDelegate verify];
        XCTAssertEqual(XIServiceCreatorStateError, self.creator.state, @"Invalid created state");
        [self.expectation fulfill];
    });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testXIMSGMessagingCreatorCreatedCancel {
    [self testXIMSGMessagingCreatorStartCreation];
    OCMockObject *mockConnection = [OCMockObject mockForProtocol:@protocol(XICOConnecting)];
    [[mockConnection expect] addListener:[OCMArg any]];
    [[self.mockDelegate expect] messagingCreator:(id<XIMessagingCreator>)self.mockProxy didCreateMessaging:[OCMArg any]];
    [(id<XICOConnectionPoolDelegate>)self.creator connectionPool:(id<XICOConnectionPooling>)self.mockConnectionPool
                                             didCreateConnection:(id<XICOConnecting>)mockConnection];
    
    self.expectation = [self expectationWithDescription:@""];
    dispatch_async(dispatch_get_main_queue(), ^ {
        [self.mockDelegate verify];
        [mockConnection verify];
        
        [self.creator cancel];
        XCTAssertEqual(XIServiceCreatorStateCanceled, self.creator.state, @"Invalid canceled state");
        [self.expectation fulfill];
    });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testXIMSGMessagingCreatorFailedStateCancelError {
    [self testXIMSGMessagingCreatorStartCreation];
    NSError *error = [NSError errorWithDomain:@"ekwjfhe" code:89 userInfo:nil];
    
    [[self.mockDelegate expect] messagingCreator:(id<XIMessagingCreator>)self.mockProxy didFailToCreateMessagingWithError:error];
    [(id<XICOConnectionPoolDelegate>)self.creator connectionPool:(id<XICOConnectionPooling>)self.mockConnectionPool
                                       didFailToCreateConnection:error];
    
    self.expectation = [self expectationWithDescription:@""];
    dispatch_async(dispatch_get_main_queue(), ^ {
        
        [self.creator cancel];
        XCTAssertEqual(XIServiceCreatorStateCanceled, self.creator.state, @"Invalid canceled state");
        [self.expectation fulfill];
    });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}





- (void)testXIMessagingCreatorProxyCreation {
    OCMockObject *mockInternal = [OCMockObject mockForProtocol:@protocol(XIMessagingCreator)];
    XIMessagingCreatorProxy *proxy = [[XIMessagingCreatorProxy alloc] initWithInternal:(id<XIMessagingCreator>)mockInternal];
    XCTAssert(proxy, @"Proxy creation failed");
}

- (void)testXIMessagingCreatorProxyProxing {
    OCMockObject *mockInternal = [OCMockObject mockForProtocol:@protocol(XIMessagingCreator)];
    OCMockObject *mockMessaging = [OCMockObject mockForProtocol:@protocol(XIMessaging)];
    
    XIMessagingCreatorProxy *proxy = [[XIMessagingCreatorProxy alloc] initWithInternal:(id<XIMessagingCreator>)mockInternal];
    
    [[[mockInternal expect] andReturn:mockMessaging] resultMessaging];
    XCTAssertEqual(mockMessaging, proxy.resultMessaging,@"Result messaging error");
    [mockInternal verify];
    
    [[mockInternal expect] setMessagingCreatorDelegate:(id<XIMessagingCreatorDelegate>)mockMessaging];
    [proxy setMessagingCreatorDelegate:(id<XIMessagingCreatorDelegate>)mockMessaging];
    [mockInternal verify];
    
    [(id<XIMessagingCreator>)[[mockInternal expect] andReturnValue:OCMOCK_VALUE((XIServiceCreatorState)XIServiceCreatorStateCreating)] state];
    XCTAssertEqual(XIServiceCreatorStateCreating, proxy.state, @"State error");
    [mockInternal verify];
    
    [[[mockInternal expect] andReturn:mockMessaging] result];
    XCTAssertEqual(mockMessaging, proxy.result, @"Result error");
    [mockInternal verify];
    
    NSError *error = [NSError errorWithDomain:@"sdgsd" code:78 userInfo:nil];
    [[[mockInternal expect] andReturn:error] error];
    XCTAssertEqual(error, proxy.error, @"Error error");
    [mockInternal verify];
    
    [[[mockInternal expect] andReturn:mockMessaging] delegate];
    XCTAssertEqual(mockMessaging, proxy.delegate, @"Delegate error");
    [mockInternal verify];
    
    [[mockInternal expect] setDelegate:(id<NSFileManagerDelegate>)mockMessaging];
    proxy.delegate = mockMessaging;
    [mockInternal verify];
    
    [[mockInternal expect] createMessagingWithCleanSession: YES lastWill: self.lastWill];
    [proxy createMessagingWithCleanSession: YES lastWill: self.lastWill];
    
    [mockInternal verify];
    
    [[mockInternal expect] cancel];
    [proxy cancel];
    [mockInternal verify];
}


@end
