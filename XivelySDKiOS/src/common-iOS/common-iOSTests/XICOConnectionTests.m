 //
//  XICOConnectionTests.m
//  common-iOS
//
//  Created by gszajko on 09/07/15.
//  Copyright (c) 2015 LogMeIn Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>
#import "MQTTSession.h"

#import "XITimerProvider.h"
#import "XITimerImpl.h"
#import <Internals/Session/XICOSessionNotifications.h>

#define _ [OCMArg any]

@interface XICOConnection (XICOConnectionUnitTest)
@property(nonatomic, strong) MQTTSession* session;
@property(nonatomic, strong) NSURL* brokerUrl;
@property(nonatomic, strong) NSString* username;
@property(nonatomic, strong) NSString* password;

-(instancetype) initWithSdkConfig: (XISdkConfig*) config
                           logger: (id<XICOLogging>) logger
               mqttSessionFactory: (XICOMqttSessionFactory*) sessionFactory
                    timerProvider: (id<XITimerProvider>) timerProvider
                   connectionPool: (id<XICOConnectionPooling>) connectionPool
                    notifications: (XICOSessionNotifications *)notifications
                     initialState: (XICOConnectionState) initialState;

-(void) connectWithUrl: (NSURL*) brokerUrl
              username: (NSString*) username
              password: (NSString*) password
          cleanSession: (BOOL) cleanSession
              lastWill: (XILastWill*) lastWill;

-(void) disconnect;
-(void) suspend;
-(void) resume;

- (void)session:(MQTTSession*)session handleEvent:(MQTTSessionEvent)eventCode;
- (void)session:(MQTTSession*)session newMessage:(NSData*)data onTopic:(NSString*)topic;
- (void)session:(MQTTSession*)session handlePublishAck: (NSData*)data onTopic: (NSString*) topic withMessageId: (UInt16) messageId;
- (void)session:(MQTTSession*)session handleSubscribeAck: (NSString*) topic;
- (void)session:(MQTTSession*)session handleUnsubscribeAck: (NSString*) topic;

- (void) fireConnectionTimeout;
- (void) fireReconnect;
@end

@interface XICOConnectionTests : XCTestCase<XITimerProvider>
@property(nonatomic, strong) id mockConfig;
@property(nonatomic, strong) id mockSessionFactory;
@property(nonatomic, strong) id mockTimerProvider;
@property(nonatomic, strong) id mockTimer;
@property(nonatomic, strong) id mockMqttSession;
@property(nonatomic, strong) id mockListener;
@property(nonatomic, strong) id mockConnectionPool;
@property(nonatomic, strong) XICOConnection* connection;
@property(nonatomic, strong) XICOSessionNotifications *notifications;
@property(nonatomic, strong)XCTestExpectation *expectation;

@end

@implementation XICOConnectionTests

- (void)setUp {
    [super setUp];
    self.notifications = [XICOSessionNotifications new];
    _mockConfig = OCMStrictClassMock([XISdkConfig class]);
    _mockSessionFactory = OCMStrictClassMock([XICOMqttSessionFactory class]);
    _mockMqttSession = OCMStrictClassMock([MQTTSession class]);
    _mockListener = OCMStrictProtocolMock(@protocol(XICOConnectionListener));
    _mockConnectionPool = OCMStrictProtocolMock(@protocol(XICOConnectionPooling));
}

- (void)tearDown {
    [super tearDown];
}

-(XICOConnection*) createConnectionWithState: (XICOConnectionState) state {

    OCMExpect([_mockConfig mqttRetryAttempt]).andReturn(3);
    XICOConnection* connection = [[XICOConnection alloc] initWithSdkConfig: _mockConfig
                                                                    logger: nil
                                                        mqttSessionFactory: _mockSessionFactory
                                                             timerProvider: self
                                                            connectionPool: _mockConnectionPool
                                                             notifications:self.notifications
                                                              initialState: state];
    [connection addListener: _mockListener];
    return connection;
}

-(void) testInitConnectExpectConnecting {
    
    _connection = [self createConnectionWithState: XICOConnectionStateInit];
    
    // arrange
    XILastWill* lastwill = [[XILastWill alloc] initWithChannel: @"topic"
                                                     message: [@"message" dataUsingEncoding: NSUTF8StringEncoding]
                                                         qos: XIMessagingQoSAtMostOnce
                                                      retain: YES];
    
    OCMExpect([_mockSessionFactory createMqttSessionWithClientId: @""
                                                        username: @"username"
                                                        password: @"password"
                                                       keepalive: 30
                                                    cleanSession: YES
                                                        lastWill: lastwill]).andReturn(_mockMqttSession);
    OCMExpect([_mockMqttSession setDelegate: _]);
    OCMExpect([_mockMqttSession connectToHost: @"broker.url"
                                         port: 1234
                                     usingSSL: YES]);
    OCMExpect([_mockConfig mqttConnectTimeout]).andReturn(5l);
    XCTestExpectation* connecting = [self expectationWithDescription: @"connecting"];
    OCMExpect([_mockListener connection: _ willConnectToBroker: _]).andDo(^(NSInvocation* invocation) {
        [connecting fulfill];
    });
    
    // act
    [_connection connectWithUrl: [NSURL URLWithString: @"ssl://broker.url:1234"]
                       username: @"username"
                       password: @"password"
                   cleanSession: YES
                       lastWill: lastwill];
    
    [self waitForExpectationsWithTimeout: 2.f handler: nil];
    
    // assert
    OCMVerifyAll(_mockConfig);
    OCMVerifyAll(_mockSessionFactory);
    OCMVerifyAll(_mockMqttSession);
    XCTAssertEqual(XICOConnectionStateConnecting, [_connection state]);
}

-(void) testInitSuspendExpectSuspended {
    
    _connection = [self createConnectionWithState: XICOConnectionStateInit];
    [[self.mockListener expect] connectionWasSuspended:self.connection];
    
    [[[self.mockConfig stub] andReturnValue:OCMOCK_VALUE(5)] mqttRetryAttempt];
    
    [self.notifications.sessionNotificationCenter postNotificationName:XISessionDidSuspendNotification object:nil];
    
    [self.mockConfig verify];
    
    self.expectation = [self expectationWithDescription:@""];
    dispatch_async(dispatch_get_main_queue(), ^ {
        [self.mockListener verify];
        [self.expectation fulfill];
    });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    
    
}

-(void) testConnectingConnectedExpectConnected {
    
    _connection = [self createConnectionWithState: XICOConnectionStateConnecting];
    
    // arrange
    OCMExpect([_mockConfig mqttRetryAttempt]).andReturn(3);
    XCTestExpectation* connected = [self expectationWithDescription: @"connected"];
    OCMExpect([_mockListener connection: _ didConnectedToBroker: _]).andDo(^(NSInvocation* invocation) {
        [connected fulfill];
    });

    // act
    [_connection session: _mockMqttSession handleEvent: MQTTSessionEventConnected];
    
    [self waitForExpectationsWithTimeout: 2.f handler: nil];
    
    // assert
    OCMVerifyAll(_mockConfig);
    OCMVerifyAll(_mockListener);
    XCTAssertEqual(XICOConnectionStateConnected, [_connection state]);
}

-(void) testConnectingDisconnectExpectDisconnected {
    
    _connection = [self createConnectionWithState: XICOConnectionStateConnecting];
    _connection.session = _mockMqttSession;
    
    // arrange
    OCMExpect([_mockMqttSession setDelegate: _]);
    OCMExpect([_mockMqttSession close]);
    
    // act
    [_connection disconnect];
    
    // assert
    OCMVerifyAll(_mockListener);
    OCMVerifyAll(_mockMqttSession);
    XCTAssertEqual(XICOConnectionStateInit, [_connection state]);
}

-(void) testConnectingErrorExpectReconnecting {
    _connection = [self createConnectionWithState: XICOConnectionStateConnecting];
    _connection.session = _mockMqttSession;

    // arrange
    OCMExpect([_mockConfig mqttWaitOnReconnect]).andReturn(1l);
    XCTestExpectation* reconnecting = [self expectationWithDescription: @"reconnecting"];
    OCMExpect([_mockListener connection: _ willReconnectToBroker: _]).andDo(^(NSInvocation* invocation) {
        [reconnecting fulfill];
    });
    
    // act
    [_connection session: _mockMqttSession handleEvent: MQTTSessionEventConnectionError];
    
    [self waitForExpectationsWithTimeout: 2.f handler: nil];
    
    // assert
    OCMVerifyAll(_mockConfig);
    OCMVerifyAll(_mockListener);
    XCTAssertEqual(XICOConnectionStateReconnecting, [_connection state]);
}

-(void) testConnectingAuthFailedExpectError {
    _connection = [self createConnectionWithState: XICOConnectionStateConnecting];
    
    // arrange
    XCTestExpectation* connectionError = [self expectationWithDescription: @"connection error"];
    OCMExpect([_mockListener connection: _ didFailToConnect: _]).andDo(^(NSInvocation* invocation) {
        [connectionError fulfill];
    });
    
    // act
    [_connection session: _mockMqttSession handleEvent: MQTTSessionEventConnectionRefused];
    
    [self waitForExpectationsWithTimeout: 2.f handler: nil];
    
    // assert
    OCMVerifyAll(_mockListener);
    XCTAssertEqual(XICOConnectionStateError, [_connection state]);
    XCTAssertEqual(XICODisconnectReasonNotAuthorized, [_connection disconnectReason]);
}

-(void) testConnectingSuspendExpectSuspended {
    [self testInitConnectExpectConnecting];
    
    [[_mockMqttSession expect] close];
    [[self.mockListener expect] connectionWasSuspended:self.connection];
    [[[self.mockConfig stub] andReturnValue:OCMOCK_VALUE(5)] mqttRetryAttempt];
    [[self.mockTimer expect] cancel];
    
    [self.notifications.sessionNotificationCenter postNotificationName:XISessionDidSuspendNotification object:nil];
    
    [self.mockTimer verify];
    [self.mockConfig verify];
    [_mockMqttSession verify];
    
    self.expectation = [self expectationWithDescription:@""];
    dispatch_async(dispatch_get_main_queue(), ^ {
        [self.mockListener verify];
        [self.expectation fulfill];
    });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testConnectedSuspend {
    _connection = [self createConnectionWithState: XICOConnectionStateConnected];
    _connection.session = _mockMqttSession;
    
    [[_mockMqttSession expect] close];
    [[self.mockListener expect] connectionWasSuspended:self.connection];
    [[[self.mockConfig stub] andReturnValue:OCMOCK_VALUE(5)] mqttRetryAttempt];
    [[self.mockTimer expect] cancel];
    
    [self.notifications.sessionNotificationCenter postNotificationName:XISessionDidSuspendNotification object:nil];
    
    [self.mockTimer verify];
    [self.mockConfig verify];
    [_mockMqttSession verify];
    
    self.expectation = [self expectationWithDescription:@""];
    dispatch_async(dispatch_get_main_queue(), ^ {
        [self.mockListener verify];
        [self.expectation fulfill];
    });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testReconnectingSuspend {
    _connection = [self createConnectionWithState: XICOConnectionStateReconnecting];
    _connection.session = _mockMqttSession;
    
    [[_mockMqttSession expect] close];
    [[self.mockListener expect] connectionWasSuspended:self.connection];
    [[[self.mockConfig stub] andReturnValue:OCMOCK_VALUE(5)] mqttRetryAttempt];
    [[self.mockTimer expect] cancel];
    
    [self.notifications.sessionNotificationCenter postNotificationName:XISessionDidSuspendNotification object:nil];
    
    [self.mockTimer verify];
    [self.mockConfig verify];
    [_mockMqttSession verify];
    
    self.expectation = [self expectationWithDescription:@""];
    dispatch_async(dispatch_get_main_queue(), ^ {
        [self.mockListener verify];
        [self.expectation fulfill];
    });
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}


-(void) testConnectingConnectionTimeoutExpectError {
    
    _connection = [self createConnectionWithState: XICOConnectionStateConnecting];

    // arrange
    XCTestExpectation* fail = [self expectationWithDescription: @"timeout"];
    OCMExpect([_mockListener connection: _ didFailToConnect: _]).andDo(^(NSInvocation* invocation) {
        [fail fulfill];
    });

    // act
    [_connection fireConnectionTimeout];
    [self waitForExpectationsWithTimeout: 2.f handler: nil];
    
    // assert
    OCMVerifyAll(_mockListener);
    XCTAssertEqual(XICOConnectionStateError, [_connection state]);
    XCTAssertEqual(XICODisconnectReasonNetworkError, [_connection disconnectReason]);
}

-(void) testConnectedDisconnectExpectInit {
    
    _connection = [self createConnectionWithState: XICOConnectionStateConnected];
    _connection.session = _mockMqttSession;
    
    // arrange
    OCMExpect([_mockMqttSession setDelegate: _]);
    OCMExpect([_mockMqttSession close]);
    
    // act
    [_connection disconnect];
    
    // assert
    XCTAssertEqual(XICOConnectionStateInit, [_connection state]);
    XCTAssertEqual(XICODisconnectReasonDisconnect, [_connection disconnectReason]);
    OCMVerifyAll(_mockListener);
    OCMVerifyAll(_mockMqttSession);
}

-(void) testConnectedSubscribeExpectSubscribed {
    _connection = [self createConnectionWithState: XICOConnectionStateConnected];
    _connection.session = _mockMqttSession;
    
    // arrange
    XCTestExpectation* subscribing = [self expectationWithDescription: @"willSubscribe"];
    OCMExpect([_mockListener connection: _ willSubscribeToTopic: @"topic"]).andDo(^(NSInvocation* invocation) {
        dispatch_async(dispatch_get_main_queue(), ^() {
            [_connection session: _mockMqttSession handleSubscribeAck: @"topic" qos:1];
        });
        [subscribing fulfill];
    });
    XCTestExpectation* subscribed = [self expectationWithDescription: @"didSubscribe"];
    OCMExpect([_mockListener connection:_ didSubscribeToTopic: @"topic" qos:XICOQOSAtLeastOnce]).andDo(^(NSInvocation* invocation) {
        [subscribed fulfill];
    });
    OCMExpect([_mockMqttSession subscribeToTopic: @"topic" atLevel: XICOQOSAtLeastOnce]);
    
    // act
    [_connection subscribeToTopic: @"topic" qos: XICOQOSAtLeastOnce];
    [self waitForExpectationsWithTimeout: 2.f handler: nil];
    
    // assert
    OCMVerifyAll(_mockListener);
    OCMVerifyAll(_mockMqttSession);
    XCTAssertEqual(XICOConnectionStateConnected, [_connection state]);
}

-(void) testConnectedSubscribeExpectUnsubscribed {
    _connection = [self createConnectionWithState: XICOConnectionStateConnected];
    _connection.session = _mockMqttSession;
    
    // arrange
    XCTestExpectation* unsubscribing = [self expectationWithDescription: @"willUnsubscribe"];
    OCMExpect([_mockListener connection: _ willUnsubscribeFromTopic: @"topic"]).andDo(^(NSInvocation* invocation) {
        dispatch_async(dispatch_get_main_queue(), ^() {
            [_connection session: _mockMqttSession handleUnsubscribeAck: @"topic"];
        });
        [unsubscribing fulfill];
    });
    XCTestExpectation* unsubscribed = [self expectationWithDescription: @"didUnsubscribe"];
    OCMExpect([_mockListener connection: _ didUnsubscribeFromTopic: @"topic"]).andDo(^(NSInvocation* invocation) {
        [unsubscribed fulfill];
    });
    OCMExpect([_mockMqttSession unsubscribeTopic: @"topic"]);
    
    // act
    [_connection unsubscribeFromTopic: @"topic"];
    [self waitForExpectationsWithTimeout: 2.f handler: nil];
    
    // assert
    OCMVerifyAll(_mockListener);
    OCMVerifyAll(_mockMqttSession);
    XCTAssertEqual(XICOConnectionStateConnected, [_connection state]);
}

-(void) testConnectedPublishExpextAckReceived {
    _connection = [self createConnectionWithState: XICOConnectionStateConnected];
    _connection.session = _mockMqttSession;
    
    // arrange
    NSString* message = @"message";
    XCTestExpectation* publishAckReceived = [self expectationWithDescription: @"publishAck"];
    OCMExpect([_mockListener connection: _
          didReceivePublishAckFromTopic: @"topic"
                               withData: _
                              messageId: 1]).andDo(^(NSInvocation* invocation){
        
        [publishAckReceived fulfill];
    });
    
    OCMExpect([_mockMqttSession publishDataAtLeastOnce: _ onTopic: @"topic" retain:NO]).andDo(^(NSInvocation* invocation){
        
        dispatch_async(dispatch_get_main_queue(), ^(){
            [_connection session: _mockMqttSession
                handlePublishAck: [message dataUsingEncoding: NSUTF8StringEncoding]
                         onTopic: @"topic"
                   withMessageId: 1];
        });
    });
    
    // act
    [_connection publishData: [message dataUsingEncoding: NSUTF8StringEncoding]
                     toTopic: @"topic"
                     withQos: XICOQOSAtLeastOnce
                      retain: NO];
    
    [self waitForExpectationsWithTimeout: 2.f handler: nil];
    
    // assert
    OCMVerifyAll(_mockListener);
    OCMVerifyAll(_mockMqttSession);
    XCTAssertEqual(XICOConnectionStateConnected, [_connection state]);
}

-(void) testConnectedMessageReceivedExpectMessageReceived {
    _connection = [self createConnectionWithState: XICOConnectionStateConnected];
    _connection.session = _mockMqttSession;
    
    // arrange
    NSString* message = @"message";
    NSData* data = [message dataUsingEncoding: NSUTF8StringEncoding];
    OCMExpect([_mockListener connection: _
                         didReceiveData: _
                              fromTopic: @"topic"]);
    
    // act
    [_connection session: _mockMqttSession newMessage: data onTopic: @"topic"];
    
    // assert
    XCTAssertEqual(XICOConnectionStateConnected, [_connection state]);
}

-(void) testConnectedErrorExpectReconnecting {
    _connection = [self createConnectionWithState: XICOConnectionStateConnected];
    _connection.session = _mockMqttSession;
    
    // arrange
    OCMExpect([_mockConfig mqttWaitOnReconnect]).andReturn(1l);
    XCTestExpectation* reconnecting = [self expectationWithDescription: @"reconnecting"];
    OCMExpect([_mockListener connection: _ willReconnectToBroker: _]).andDo(^(NSInvocation* invocation) {
        [reconnecting fulfill];
    });
    
    // act
    [_connection session: _mockMqttSession handleEvent: MQTTSessionEventConnectionError];
    
    [self waitForExpectationsWithTimeout: 2.f handler: nil];
    
    // assert
    OCMVerifyAll(_mockConfig);
    OCMVerifyAll(_mockListener);
    XCTAssertEqual(XICOConnectionStateReconnecting, [_connection state]);
}

-(void) testReconnectingConnectExpectConnecting {
    _connection = [self createConnectionWithState: XICOConnectionStateReconnecting];
    _connection.session = _mockMqttSession;
    _connection.username = @"username";
    _connection.password = @"password";
    _connection.brokerUrl = [NSURL URLWithString: @"ssl://broker.url:1234"];
    
    // arrange
    OCMExpect([_mockMqttSession setDelegate: _]);
    OCMExpect([_mockMqttSession connectToHost: @"broker.url"
                                         port: 1234
                                     usingSSL: YES]);
    OCMExpect([_mockConfig mqttConnectTimeout]).andReturn(5l);
    XCTestExpectation* connecting = [self expectationWithDescription: @"connecting"];
    OCMExpect([_mockListener connection: _ willConnectToBroker: _]).andDo(^(NSInvocation* invocation) {
        [connecting fulfill];
    });

    // act
    [_connection fireReconnect];
    [self waitForExpectationsWithTimeout: 2.f handler: nil];
    
    // assert
    OCMVerifyAll(_mockMqttSession);
    OCMVerifyAll(_mockSessionFactory);
    OCMVerifyAll(_mockListener);
    XCTAssertEqual(XICOConnectionStateConnecting, [_connection state]);
}

-(void) testReconnectingConnectionTimeoutExpectError {
    _connection = [self createConnectionWithState: XICOConnectionStateReconnecting];
    
    // arrange
    XCTestExpectation* fail = [self expectationWithDescription: @"didFailToConnect"];
    OCMExpect([_mockListener connection: _ didFailToConnect: _]).andDo(^(NSInvocation* invocation){
        [fail fulfill];
    });
    
    // act
    [_connection fireConnectionTimeout];
    [self waitForExpectationsWithTimeout: 2.f handler: nil];
    
    // assert
    OCMVerifyAll(_mockListener);
    XCTAssertEqual(XICOConnectionStateError, [_connection state]);
    XCTAssertEqual(XICODisconnectReasonNetworkError, [_connection disconnectReason]);
}

-(void) testReconnectingDisconnectExpectInit {
    _connection = [self createConnectionWithState: XICOConnectionStateReconnecting];
    _connection.session = _mockMqttSession;
    
    // arrange
    OCMExpect([_mockMqttSession setDelegate: nil]);
    OCMExpect([_mockMqttSession close]);
    
    // act
    [_connection disconnect];
    
    // assert
    OCMVerifyAll(_mockListener);
    OCMVerifyAll(_mockMqttSession);
    XCTAssertEqual(XICOConnectionStateInit, [_connection state]);
    XCTAssertEqual(XICODisconnectReasonDisconnect, [_connection disconnectReason]);
}
/*
    connected:suspend       suspended
    connecting:suspend      suspended
    reconnecting:suspend    suspended
    suspneded:resume        ?
 */

- (id<XITimer>)getTimer {

    id mockTimer = OCMStrictProtocolMock(@protocol(XITimer));
    OCMStub([mockTimer setDelegate: _]);
    [[[mockTimer expect] ignoringNonObjectArgs] startWithTimeout: 1.f periodic: NO];
    self.mockTimer = mockTimer;
    return mockTimer;
}

@end
