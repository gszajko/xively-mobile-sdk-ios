//
//  XICOMqttSessionFactory.m
//  common-iOS
//
//  Created by gszajko on 10/07/15.
//  Copyright (c) 2015 LogMeIn Inc. All rights reserved.
//

#import "XICOMqttSessionFactory.h"
#import "MQTTSession.h"
#import "XIMessaging.h"

@implementation XICOMqttSessionFactory
-(instancetype) init {
    if ((self = [super init])) {
        
    }
    return self;
}

-(MQTTSession*)createMqttSessionWithClientId: (NSString*) clientId
                                    username: (NSString*) username
                                    password: (NSString*) password
                                   keepalive: (NSUInteger) keepalive
                                cleanSession: (BOOL) cleanSession
                                    lastWill: (XILastWill*) lastWill {
    if (lastWill) {
        
        return [[MQTTSession alloc] initWithClientId: clientId
                                            userName: username
                                            password: password
                                           keepAlive: keepalive
                                        cleanSession: cleanSession
                                           willTopic: lastWill.channel
                                             willMsg: lastWill.message
                                             willQoS: (UInt8)lastWill.qos
                                      willRetainFlag: lastWill.retained];
    }
    
    return [[MQTTSession alloc] initWithClientId: clientId
                                        userName: username
                                        password: password
                                       keepAlive: keepalive
                                    cleanSession: cleanSession];
}
@end
