//
//  XICOConnection.m
//  common-iOS
//
//  Created by gszajko on 09/07/15.
//  Copyright (c) 2015 LogMeIn Inc. All rights reserved.
//

#import "XICOConnection.h"
#import "MQTTSession.h"

#import "XICommonError.h"
#import "XITimerProvider.h"
#import "XITimer.h"
#import <XivelySDK/XICommonError.h>

#import "NSMutableArray+nonRetaining.h"

UInt16 const XIQoS0MessageId = 0x1111;

typedef NS_ENUM(NSInteger, XICOConnectionEvent) {
    XICOConnectionEventConnect,
    XICOConnectionEventDisconnect,
    XICOConnectionEventSubscribe,
    XICOConnectionEventUnsubscribe,
    XICOConnectionEventPublish,
    XICOConnectionEventSuspend,
    XICOConnectionEventResume,
    
    XICOConnectionEventConnected,
    XICOConnectionEventConnectionError,
    XICOConnectionEventConnectionNotAuthorized,
    
    XICOConnectionEventConnectionTimeout,
    XICOConnectionEventReconnect,
    
    XICOConnectionEventMessageReceived,
    
    XICOConnectionEventPublishAckReceived,
    XICOConnectionEventSubscribeAckReceived,
    XICOConnectionEventSubscribeFailed,
    XICOConnectionEventUnsubscribeAckReceived,
    
};

@interface XICOConnection () <XITimerDelegate>
@property(nonatomic, strong) XISdkConfig* config;
@property(nonatomic, strong) XICOMqttSessionFactory* sessionFactory;
@property(nonatomic, strong) MQTTSession* session;
@property(nonatomic, strong) XICOFiniteStateMachine* fsm;
@property(nonatomic, strong) id<XICOLogging> log;
@property(nonatomic, strong) NSURL* brokerUrl;
@property(nonatomic, strong) NSString* username;
@property(nonatomic, strong) NSString* password;
@property(nonatomic, strong) id<XITimerProvider> timerProvider;
@property(nonatomic, strong) id<XITimer> connectionTimeoutTimer;
@property(nonatomic, strong) id<XITimer> reconnectTimer;
@property(nonatomic, assign) int reconnectCounter;
@property(nonatomic, strong) NSMutableArray* listeners;
@property(nonatomic, weak) id<XICOConnectionPooling> connectionPool;
@property(nonatomic, strong) NSError *error;
@property(nonatomic, assign) XICODisconnectReason disconnectReason;
@property(nonatomic, strong) XICOSessionNotifications *notifications;
@property(nonatomic) BOOL cleanSession;
@property(nonatomic, strong) XILastWill* lastWill;
@end

@implementation XICOConnection
#pragma mark -
#pragma mark Property getters/setters
-(XICOConnectionState) state {
    return _fsm.state;
}

#pragma mark -
#pragma mark Constructor
-(instancetype) initWithSdkConfig: (XISdkConfig*) config
                           logger: (id<XICOLogging>) logger
               mqttSessionFactory: (XICOMqttSessionFactory*) sessionFactory
                    timerProvider: (id<XITimerProvider>) timerProvider
                   connectionPool: (id<XICOConnectionPooling>) connectionPool
                    notifications: (XICOSessionNotifications *)notifications{
    
    return [self initWithSdkConfig: config
                            logger: logger
                mqttSessionFactory: sessionFactory
                     timerProvider: timerProvider
                    connectionPool: connectionPool
                     notifications:notifications
                      initialState: XICOConnectionStateInit];
}

-(instancetype) initWithSdkConfig: (XISdkConfig*) config
                           logger: (id<XICOLogging>) logger
               mqttSessionFactory: (XICOMqttSessionFactory*) sessionFactory
                    timerProvider: (id<XITimerProvider>) timerProvider
                   connectionPool: (id<XICOConnectionPooling>) connectionPool
                    notifications: (XICOSessionNotifications *)notifications
                     initialState: (XICOConnectionState) initialState {
    
    if ((self = [super init])) {
        assert(notifications);
        self.config = config;
        self.log = logger;
        self.sessionFactory = sessionFactory;
        self.timerProvider = timerProvider;
        self.reconnectCounter = self.config.mqttRetryAttempt;
        self.fsm = [[XICOFiniteStateMachine alloc] initWithInitialState: initialState];
        self.listeners = [NSMutableArray XINonRetainingArrayWithCapacity: 0];
        self.connectionPool = connectionPool;
        self.notifications = notifications;
        
        // init
        {
            [self.fsm addTransitionWithState: XICOConnectionStateInit
                                       event: XICOConnectionEventConnect
                                      object: self
                                    selector: @selector(onConnect:)];
            [self.fsm addTransitionWithState: XICOConnectionStateInit
                                       event: XICOConnectionEventSuspend
                                      object: self
                                    selector: @selector(onSuspend:)];
        }
        
        // connecting
        {
            [self.fsm addTransitionWithState: XICOConnectionStateConnecting
                                       event: XICOConnectionEventConnected
                                      object: self
                                    selector: @selector(onConnected:)];
            [self.fsm addTransitionWithState: XICOConnectionStateConnecting
                                       event: XICOConnectionEventDisconnect
                                      object: self
                                    selector: @selector(onDisconnect:)];
            [self.fsm addTransitionWithState: XICOConnectionStateConnecting
                                       event: XICOConnectionEventConnectionError
                                      object: self
                                    selector: @selector(onConnectionError:)];
            [self.fsm addTransitionWithState: XICOConnectionStateConnecting
                                       event: XICOConnectionEventConnectionNotAuthorized
                                      object: self
                                    selector: @selector(onConnectionNotAuthorized:)];
            [self.fsm addTransitionWithState: XICOConnectionStateConnecting
                                       event: XICOConnectionEventSuspend
                                      object: self
                                    selector: @selector(onSuspend:)];
            [self.fsm addTransitionWithState: XICOConnectionStateConnecting
                                       event: XICOConnectionEventConnectionTimeout
                                      object: self
                                    selector: @selector(onConnectionTimeout:)];
        }
        
        // connected
        {
            [self.fsm addTransitionWithState: XICOConnectionStateConnected
                                       event: XICOConnectionEventDisconnect
                                      object: self
                                    selector: @selector(onDisconnect:)];
            [self.fsm addTransitionWithState: XICOConnectionStateConnected
                                       event: XICOConnectionEventSubscribe
                                      object: self
                                    selector: @selector(onSubscribe:)];
            [self.fsm addTransitionWithState: XICOConnectionStateConnected
                                       event: XICOConnectionEventSubscribeAckReceived
                                      object: self
                                    selector: @selector(onSubscribeAckReceived:)];
            [self.fsm addTransitionWithState: XICOConnectionStateConnected
                                       event: XICOConnectionEventSubscribeFailed
                                      object: self
                                    selector: @selector(onSubscribeFailed:)];
            
            [self.fsm addTransitionWithState: XICOConnectionStateConnected
                                       event: XICOConnectionEventUnsubscribe
                                      object: self
                                    selector: @selector(onUnsubscribe:)];
            [self.fsm addTransitionWithState: XICOConnectionStateConnected
                                       event: XICOConnectionEventUnsubscribeAckReceived
                                      object: self
                                    selector: @selector(onUnsubscribeAckReceived:)];
            [self.fsm addTransitionWithState: XICOConnectionStateConnected
                                       event: XICOConnectionEventPublish
                                      object: self
                                    selector: @selector(onPublish:)];
            [self.fsm addTransitionWithState: XICOConnectionStateConnected
                                       event: XICOConnectionEventPublishAckReceived
                                      object: self
                                    selector: @selector(onPublishAckReceived:)];
            [self.fsm addTransitionWithState: XICOConnectionStateConnected
                                       event: XICOConnectionEventMessageReceived
                                      object: self
                                    selector: @selector(onMessageReceived:)];
            [self.fsm addTransitionWithState: XICOConnectionStateConnected
                                       event: XICOConnectionEventConnectionError
                                      object: self
                                    selector: @selector(onConnectionError:)];
            [self.fsm addTransitionWithState: XICOConnectionStateConnected
                                       event: XICOConnectionEventSuspend
                                      object: self
                                    selector: @selector(onSuspend:)];
        }
        
        // suspended
        {
            [self.fsm addTransitionWithState: XICOConnectionStateSuspended
                                       event: XICOConnectionEventResume
                                      object: self
                                    selector: @selector(onResume:)];
            [self.fsm addTransitionWithState: XICOConnectionStateSuspended
                                       event: XICOConnectionEventConnect
                                      object: self
                                    selector: @selector(onConnect:)];
        }
        
        // reconnecting
        {
            [self.fsm addTransitionWithState: XICOConnectionStateReconnecting
                                       event: XICOConnectionEventConnect
                                      object: self
                                    selector: @selector(onConnect:)];
            [self.fsm addTransitionWithState: XICOConnectionStateReconnecting
                                       event: XICOConnectionEventConnectionTimeout
                                      object: self
                                    selector: @selector(onConnectionTimeout:)];
            [self.fsm addTransitionWithState: XICOConnectionStateReconnecting
                                       event: XICOConnectionEventReconnect
                                      object: self
                                    selector: @selector(onReconnect:)];
            [self.fsm addTransitionWithState: XICOConnectionStateReconnecting
                                       event: XICOConnectionEventDisconnect
                                      object: self
                                    selector: @selector(onDisconnect:)];
            [self.fsm addTransitionWithState: XICOConnectionStateReconnecting
                                       event: XICOConnectionEventSuspend
                                      object: self
                                    selector: @selector(onSuspend:)];
        }
        
        [self.notifications.sessionNotificationCenter addObserver:self
                                                         selector:@selector(onSessionDidSuspend:)
                                                             name:XISessionDidSuspendNotification
                                                           object:nil];
        
        [self.notifications.sessionNotificationCenter addObserver:self
                                                         selector:@selector(onSessionDidResume:)
                                                             name:XISessionDidResumeNotification
                                                           object:nil];
    }
    return self;
}

-(void) dealloc {
    [self.notifications.sessionNotificationCenter removeObserver:self];
    [self stopTimers];
}

#pragma mark -
#pragma mark Notifications
- (void)onSessionDidSuspend:(NSNotification *)notification {
    [self.fsm doEvent: XICOConnectionEventSuspend];
}

- (void)onSessionDidResume:(NSNotification *)notification {
    [self.fsm doEvent: XICOConnectionEventResume];
}

#pragma mark -
#pragma mark FSM transitions
-(XICOConnectionState) onConnect: (NSDictionary*) parameters {
    
    if (parameters) {
        
        self.brokerUrl = parameters[@"brokerUrl"];
        self.username = parameters[@"username"];
        self.password = parameters[@"password"];
        self.cleanSession = [parameters[@"cleanSession"] boolValue];
        self.lastWill = parameters[@"lastWill"];
    }
    
    if (!self.brokerUrl || !self.username || !self.password) {
        assert(0);
    }
    
    [self.log info: @"connect to: '%@'", self.brokerUrl];
    
    if (!self.session) {
        self.session = [self.sessionFactory createMqttSessionWithClientId: self.cleanSession ? @"" : self.username
                                                                 username: self.username
                                                                 password: self.password
                                                                keepalive: 30
                                                             cleanSession: self.cleanSession
                                                                 lastWill: self.lastWill];
    }
    
    if (!self.session) {
        
        return [self returnWithError: XIErrorInternal];
    }
    
    [self.session setDelegate: self];
    
    [self.session connectToHost: self.brokerUrl.host
                           port: [self.brokerUrl.port unsignedIntValue]
                       usingSSL: [self.brokerUrl.scheme compare: @"ssl" options: NSCaseInsensitiveSearch] == NSOrderedSame];
    
    [self startConnectionTimeoutTimer];
    
    __weak XICOConnection* weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^() { @autoreleasepool {
        for (id<XICOConnectionListener> listener in [weakSelf.listeners copy]) {
            if ([listener respondsToSelector: @selector(connection:willConnectToBroker:)])
                [listener connection: weakSelf willConnectToBroker: weakSelf.brokerUrl];
        }
    }});
    
    return XICOConnectionStateConnecting;
}

-(XICOConnectionState) onReconnect: (id) object {
    
    [self.log info: @"reconnect"];
    
    if (self.reconnectCounter-- == 0) {
        
        [self stopTimers];
        return [self returnWithError: XIErrorNetwork];
    }
    
    __weak XICOConnection* weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^() { @autoreleasepool {
        [weakSelf.fsm doEvent: XICOConnectionEventConnect];
    }});
    return self.fsm.state;
}

-(XICOConnectionState) onDisconnect: (id) object {
    
    [self.log info: @"disconnect"];
    
    [self.session setDelegate: nil];
    [self.session close];
    self.session = nil;
    
    self.disconnectReason = XICODisconnectReasonDisconnect;
    
    [self stopTimers];
    
    return XICOConnectionStateInit;
}

-(XICOConnectionState) onConnected: (id) object {
    
    [self.log info: @"connected"];
    
    [self stopTimers];
    self.reconnectCounter = self.config.mqttRetryAttempt;
    
    __weak XICOConnection* weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^() { @autoreleasepool {
        for (id<XICOConnectionListener> listener in [weakSelf.listeners copy]) {
            if ([listener respondsToSelector: @selector(connection:didConnectedToBroker:)])
                [listener connection: weakSelf didConnectedToBroker: weakSelf.brokerUrl];
        }
    }});
    
    return XICOConnectionStateConnected;
}

-(XICOConnectionState) onConnectionError: (id) object {
    
    [self.log info: @"connection error"];
    
    [self startReconnectTimer];
    
    for (id<XICOConnectionListener> listener in [self.listeners copy]) {
        if ([listener respondsToSelector: @selector(connection:willReconnectToBroker:)])
            [listener connection: self willReconnectToBroker: self.brokerUrl];
    }
    
    return XICOConnectionStateReconnecting;
}

-(XICOConnectionState) onConnectionNotAuthorized: (id) object {
    
    [self.log info: @"not authorized"];
    
    [self stopTimers];
    
    self.disconnectReason = XICODisconnectReasonNotAuthorized;
    
    return [self returnWithError: XIErrorUnauthorized];
}

-(XICOConnectionState) onConnectionTimeout: (id) object {
    
    [self.log info: @"connection timeout"];
    
    self.disconnectReason = XICODisconnectReasonNetworkError;
    
    [self stopTimers];
    
    return [self returnWithError: XIErrorTimeout];
}

-(XICOConnectionState) onSubscribe: (NSDictionary*) parameters {
    
    if (!parameters[@"topic"] ||
        !parameters[@"qos"]) {
        
        [self.log warning: @"subscribe: invalid parameters"];
        return self.fsm.state;
    }
    
    NSString* topic = parameters[@"topic"];
    XICOQOS qos =  [parameters[@"qos"] integerValue];
    
    [self.log info: @"subscribe to: '%@' with qos level: %d", topic, qos];
    
    __weak XICOConnection* weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^() { @autoreleasepool {
        @autoreleasepool {
            for (id<XICOConnectionListener> listener in [weakSelf.listeners copy]) {
                if ([listener respondsToSelector: @selector(connection:willSubscribeToTopic:)])
                    [listener connection: weakSelf willSubscribeToTopic: topic];
            }
        }
    }});
    
    [self.session subscribeToTopic: topic atLevel: qos];
    
    return self.fsm.state;
}

- (XICOQOS)qosFromUInt:(NSUInteger)val {
    switch (val) {
        case 0:
            return XICOQOSAtMostOnce;
            
        case 1:
            return XICOQOSAtLeastOnce;
            
        case 2:
            return XICOQOSExactlyOnce;
            
        default:
            return XICOQOSAtMostOnce;
    }
}

-(XICOConnectionState) onSubscribeAckReceived: (NSDictionary*)dict {
    NSString *topic = dict[@"topic"];
    NSUInteger qos = [dict[@"qos"] unsignedIntegerValue];
    
    [self.log info: @"subscribe ack: '%@'", topic];
    
    __weak XICOConnection* weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^() { @autoreleasepool {
        @autoreleasepool {
            for (id<XICOConnectionListener> listener in [weakSelf.listeners copy]) {
                if ([listener respondsToSelector: @selector(connection:didSubscribeToTopic:qos:)])
                    [listener connection: weakSelf didSubscribeToTopic: topic qos:(XICOQOS)qos];
            }
        }
    }});
    
    return self.fsm.state;
}

-(XICOConnectionState) onSubscribeFailed: (NSString*)topic {
    [self.log info: @"subscribe failed: '%@'", topic];
    
    __weak XICOConnection* weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^() {
        @autoreleasepool {
            for (id<XICOConnectionListener> listener in [weakSelf.listeners copy]) {
                if ([listener respondsToSelector: @selector(connection:didFailToSubscribeToTopic:)])
                    [listener connection: weakSelf didFailToSubscribeToTopic:topic];
            }
        }
    });
    
    return self.fsm.state;
}

-(XICOConnectionState) onUnsubscribe: (NSString*) topic {
    
    if (!topic) {
        
        [self.log error: @"unsubscribe: invalid parameters"];
        return self.fsm.state;
    }
    
    [self.log info: @"unsubscribe from: '%@'", topic];
    
    __weak XICOConnection* weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^() {
        @autoreleasepool {
            for (id<XICOConnectionListener> listener in [weakSelf.listeners copy]) {
                if ([listener respondsToSelector: @selector(connection:willUnsubscribeFromTopic:)])
                    [listener connection: weakSelf willUnsubscribeFromTopic: topic];
            }
        }
    });
    
    [self.session unsubscribeTopic: topic];
    
    return self.fsm.state;
}

-(XICOConnectionState) onUnsubscribeAckReceived: (NSString*) topic {
    
    [self.log info: @"unsubscribe ack: '%@'", topic];
    
    __weak XICOConnection* weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^() {
        @autoreleasepool {
            for (id<XICOConnectionListener> listener in [weakSelf.listeners copy]) {
                if ([listener respondsToSelector: @selector(connection:didUnsubscribeFromTopic:)])
                    [listener connection: weakSelf didUnsubscribeFromTopic: topic];
            }
        }
    });
    
    return self.fsm.state;
}

-(XICOConnectionState) onPublish: (NSMutableDictionary*) parameters {
    
    NSString* topic = parameters[@"topic"];
    NSData* data = parameters[@"data"];
    NSNumber* qos = parameters[@"qos"];
    NSNumber* retained = parameters[@"retain"];
    
    if (!topic || !data || !qos) {
        
        [self.log error: @"publish: invalid parameters"];
        return self.fsm.state;
    }
    
    UInt16 messageId = 0;
    switch ((XICOQOS)[qos integerValue]) {
        case XICOQOSAtMostOnce:
        {
            [self.session publishDataAtMostOnce: data onTopic: topic];
            messageId = XIQoS0MessageId;
        }
            break;
            
        case XICOQOSAtLeastOnce:
            messageId = [self.session publishDataAtLeastOnce: data onTopic: topic retain:retained ? [retained boolValue] : NO];
            break;
        case XICOQOSExactlyOnce:
            messageId = [self.session publishDataExactlyOnce: data onTopic: topic retain:retained ? [retained boolValue] : NO];
            break;
    }
    
    parameters[@"messageId"] = @(messageId);
    
    return self.fsm.state;
}

-(XICOConnectionState) onPublishAckReceived: (NSDictionary*) parameters {
    NSData* data = parameters[@"data"];
    NSString* topic = parameters[@"topic"];
    NSNumber* messageId = parameters[@"messageId"];
    
    if (!data || !topic || !messageId) {
        
        [self.log error: @"publish ack: invalid parameters"];
        return self.fsm.state;
    }
    
    [self.log info: @"publish ack received from topic '%@'", topic];
    
    __weak XICOConnection* weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^() {
        @autoreleasepool {
            for (id<XICOConnectionListener> listener in [weakSelf.listeners copy]) {
                if ([listener respondsToSelector: @selector(connection:didReceivePublishAckFromTopic:withData:messageId:)])
                    [listener connection: weakSelf
           didReceivePublishAckFromTopic: topic
                                withData: data
                               messageId: [messageId unsignedIntegerValue]];
            }
        }
    });
    
    return self.fsm.state;
}

-(XICOConnectionState) onMessageReceived: (NSDictionary*) parameters {
    NSData* data = parameters[@"data"];
    NSString* topic = parameters[@"topic"];
    
    if (!data || !topic) {
        [self.log error: @"message received: invalid parameters"];
        return self.fsm.state;
    }
    
    [self.log debug: @"receive message from topic: '%@'", topic];
    
    __weak XICOConnection* weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^(){
        @autoreleasepool {
            for (id<XICOConnectionListener> listener in [weakSelf.listeners copy]) {
                if ([listener respondsToSelector: @selector(connection:didReceiveData:fromTopic:)])
                    [listener connection: weakSelf didReceiveData: data fromTopic: topic];
            }
        }
    });
    return self.fsm.state;
}

-(XICOConnectionState) onSuspend: (id) object {
    self.reconnectCounter = self.config.mqttRetryAttempt;
    [self.session close];
    [self stopTimers];
    
    __weak XICOConnection* weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^(){
        @autoreleasepool {
            for (id<XICOConnectionListener> listener in [weakSelf.listeners copy]) {
                if ([listener respondsToSelector: @selector(connectionWasSuspended:)])
                    [listener connectionWasSuspended:weakSelf];
            }
        }
    });

    return XICOConnectionStateSuspended;
}

-(XICOConnectionState) onResume: (id) object {
    self.reconnectCounter = self.config.mqttRetryAttempt;
    __weak XICOConnection* weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^() { @autoreleasepool {
        [weakSelf.fsm doEvent: XICOConnectionEventConnect];
    }});
    
    return _fsm.state;
}

#pragma mark -
#pragma mark XICOConnecting
-(void) addListener: (id<XICOConnectionListener>) listener {
    [self addListener: listener requestUpdate: NO];
}

-(void) addListener: (id<XICOConnectionListener>) listener requestUpdate: (BOOL) requestUpdate {
    [self.listeners addObject: listener];
    if (requestUpdate) {
        
        __weak XICOConnection* weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^() { @autoreleasepool {
            for (id<XICOConnectionListener> listener in [weakSelf.listeners copy]) {
                switch (self.fsm.state) {
                    case XICOConnectionStateInit:
                        break;
                        
                    case XICOConnectionStateConnecting:
                        if ([listener respondsToSelector: @selector(connection:willConnectToBroker:)])
                            [listener connection: weakSelf willConnectToBroker: weakSelf.brokerUrl];
                        break;
                        
                    case XICOConnectionStateConnected:
                        if ([listener respondsToSelector: @selector(connection:didConnectedToBroker:)])
                            [listener connection: weakSelf didConnectedToBroker: weakSelf.brokerUrl];
                        break;
                        
                    case XICOConnectionStateSuspended:
                        // TODO:
                        break;
                        
                    case XICOConnectionStateReconnecting:
                        if ([listener respondsToSelector: @selector(connection:willReconnectToBroker:)])
                            [listener connection: weakSelf willReconnectToBroker: weakSelf.brokerUrl];
                        break;
                        
                    case XICOConnectionStateError:
                        if ([listener respondsToSelector: @selector(connection:didFailToConnect:)])
                            [listener connection: weakSelf didFailToConnect: weakSelf.error];
                        break;
                }
            }
        }});
    }
}

-(void) removeListener: (id<XICOConnectionListener>) listener {
    [self.listeners removeObject: listener];
}

-(void) connectWithUrl: (NSURL*) brokerUrl
              username: (NSString*) username
              password: (NSString*) password
          cleanSession: (BOOL) cleanSession
              lastWill: (XILastWill*) lastWill {
    
    NSMutableDictionary* params = [[NSMutableDictionary alloc] initWithDictionary: @{@"brokerUrl": brokerUrl,
                                                                                     @"username": username,
                                                                                     @"password": password,
                                                                                     @"cleanSession": @(cleanSession)}];
    if (lastWill) {
        params[@"lastWill"] = lastWill;
    }
    
    [self.fsm doEvent: XICOConnectionEventConnect withObject: params];
}

-(void) disconnect {
    [self.fsm doEvent: XICOConnectionEventDisconnect];
}

-(void) subscribeToTopic: (NSString*) topic qos: (XICOQOS) qos {
    [self.fsm doEvent: XICOConnectionEventSubscribe
           withObject: @{@"topic": topic,
                         @"qos": @(qos)}];
}

-(void) unsubscribeFromTopic: (NSString*) topic {
    [self.fsm doEvent: XICOConnectionEventUnsubscribe withObject: topic];
}

-(NSUInteger) publishData: (NSData*) data toTopic: (NSString*) topic withQos: (XICOQOS) qos retain: (BOOL) retain {
    
    NSMutableDictionary* parameters = [[NSMutableDictionary alloc] initWithDictionary: @{@"topic": topic,
                                                                                         @"data": data,
                                                                                         @"qos": @(qos),
                                                                                         @"retain": @(retain)}];
    
    [self.fsm doEvent: XICOConnectionEventPublish
           withObject: parameters];
    
    NSNumber* messageId = parameters[@"messageId"];
    if (!messageId)
        return 0;
    
    return [messageId unsignedIntegerValue];
}

-(void) releaseConnection {
    
    [self.connectionPool releaseConnection: self];
}

#pragma mark -
#pragma mark MQTTSession delegate
- (void)session:(MQTTSession*)session handleEvent:(MQTTSessionEvent)eventCode {
    switch (eventCode) {
        case MQTTSessionEventConnected:
            [self.fsm doEvent: XICOConnectionEventConnected];
            break;
        case MQTTSessionEventConnectionRefused:
            [self.fsm doEvent: XICOConnectionEventConnectionNotAuthorized];
            break;
        case MQTTSessionEventConnectionClosed:
            // ???
            break;
        case MQTTSessionEventConnectionError:
            [self.fsm doEvent: XICOConnectionEventConnectionError];
            break;
        case MQTTSessionEventProtocolError:
            // ???
            break;
    }
}
- (void)session:(MQTTSession*)session newMessage:(NSData*)data onTopic:(NSString*)topic {
    [self.fsm doEvent: XICOConnectionEventMessageReceived
           withObject: @{@"data" : data,
                         @"topic" : topic}];
}
- (void)session:(MQTTSession*)session handlePublishAck: (NSData*)data onTopic: (NSString*) topic withMessageId: (UInt16) messageId {
    [self.fsm doEvent: XICOConnectionEventPublishAckReceived
           withObject: @{@"data": data,
                         @"topic": topic,
                         @"messageId": @(messageId)}];
}

- (void)session:(MQTTSession*)session handleSubscribeAck:(NSString*)topic qos:(UInt8)qos {
    [self.fsm doEvent: XICOConnectionEventSubscribeAckReceived
           withObject: @{@"topic": topic,
                         @"qos": @(qos)}];
}

- (void)session:(MQTTSession *)session subscribeFailedAtTopic:(NSString *)topic {
    [self.fsm doEvent: XICOConnectionEventSubscribeFailed
           withObject: topic];
}

- (void)session:(MQTTSession*)session handleUnsubscribeAck: (NSString*) topic {
    [self.fsm doEvent: XICOConnectionEventUnsubscribeAckReceived
           withObject: topic];
}

#pragma mark -
#pragma mark XITimerDelegate
- (void) fireConnectionTimeout {
    
    [self.fsm doEvent: XICOConnectionEventConnectionTimeout];
}

- (void) fireReconnect {
    
    [self.fsm doEvent: XICOConnectionEventReconnect];
}

- (void)XITimerDidTick:(id<XITimer>)timer {
    
    if (timer == self.connectionTimeoutTimer) {
        
        [self fireConnectionTimeout];
        
    } else if (timer == self.reconnectTimer) {
        
        [self fireReconnect];
    }
}

#pragma mark -
#pragma mark Private methods
-(XICOConnectionState) returnWithError: (NSInteger) errorCode {
    
    __weak XICOConnection* weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^() { @autoreleasepool {
        
        weakSelf.error = [[NSError alloc] initWithDomain: @"XIConnection"
                                                    code: errorCode
                                                userInfo: nil];
        
        for (id<XICOConnectionListener> listener in [weakSelf.listeners copy]) {
            if ([listener respondsToSelector: @selector(connection:didFailToConnect:)])
                [listener connection: weakSelf didFailToConnect: weakSelf.error];
        }
    }});
    
    return XICOConnectionStateError;
}

-(void) startConnectionTimeoutTimer {
    
    if (self.connectionTimeoutTimer)
        [self.connectionTimeoutTimer cancel];
    
    self.connectionTimeoutTimer = [self.timerProvider getTimer];
    [self.connectionTimeoutTimer setDelegate: self];
    [self.connectionTimeoutTimer startWithTimeout: self.config.mqttConnectTimeout periodic: NO];
}

-(void) stopConnectionTimeoutTimer {
    
    [self.connectionTimeoutTimer cancel];
    self.connectionTimeoutTimer = nil;
}

-(void) startReconnectTimer {
    
    if (self.reconnectTimer)
        [self.reconnectTimer cancel];
    
    self.reconnectTimer = [self.timerProvider getTimer];
    [self.reconnectTimer setDelegate: self];
    [self.reconnectTimer startWithTimeout: self.config.mqttWaitOnReconnect periodic: NO];
}

-(void) stopReconnectTimer {
    
    [self.reconnectTimer cancel];
    self.reconnectTimer = nil;
}

-(void) stopTimers {
    
    [self stopReconnectTimer];
    [self stopConnectionTimeoutTimer];
}
@end
