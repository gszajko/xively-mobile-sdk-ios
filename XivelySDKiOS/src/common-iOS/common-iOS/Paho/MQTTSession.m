//
// MQTTSession.m
// MQtt Client
// 
// Copyright (c) 2011, 2013, 2lemetry LLC
// 
// All rights reserved. This program and the accompanying materials
// are made available under the terms of the Eclipse Public License v1.0
// and Eclipse Distribution License v. 1.0 which accompanies this distribution.
// The Eclipse Public License is available at http://www.eclipse.org/legal/epl-v10.html
// and the Eclipse Distribution License is available at
// http://www.eclipse.org/org/documents/edl-v10.php.
// 
// Contributors:
//    Kyle Roche - initial API and implementation and/or initial documentation
// 

#import "MQTTSession.h"
#import "MQttTxFlow.h"

@implementation MQTTSession

- (id)initWithClientId:(NSString*)theClientId {
    return [self initWithClientId:theClientId userName:@"" password:@""];
}

- (id)initWithClientId:(NSString*)theClientId
              userName:(NSString*)theUserName
              password:(NSString*)thePassword {
    return [self initWithClientId:theClientId
                         userName:theUserName
                         password:thePassword
                        keepAlive:60
                     cleanSession:YES];
}

- (id)initWithClientId:(NSString*)theClientId runLoop:(NSRunLoop*)theRunLoop
               forMode:(NSString*)theRunLoopMode {
    return [self initWithClientId:theClientId userName:@"" password:@"" runLoop:theRunLoop forMode:theRunLoopMode];
}

- (id)initWithClientId:(NSString*)theClientId
              userName:(NSString*)theUserName
              password:(NSString*)thePassword
               runLoop:(NSRunLoop*)theRunLoop
               forMode:(NSString*)theRunLoopMode {
    return [self initWithClientId:theClientId
                         userName:theUserName
                         password:thePassword
                        keepAlive:60
                     cleanSession:YES
                          runLoop:theRunLoop
                          forMode:theRunLoopMode];
}


- (id)initWithClientId:(NSString*)theClientId
              userName:(NSString*)theUserName
              password:(NSString*)thePassword
             keepAlive:(UInt16)theKeepAliveInterval
          cleanSession:(BOOL)theCleanSessionFlag {
    return [self initWithClientId:theClientId
                         userName:theUserName
                         password:thePassword
                        keepAlive:theKeepAliveInterval
                     cleanSession:theCleanSessionFlag
                          runLoop:[NSRunLoop currentRunLoop]
                          forMode:NSDefaultRunLoopMode];
}

- (id)initWithClientId:(NSString*)theClientId
              userName:(NSString*)theUserName
              password:(NSString*)thePassword
             keepAlive:(UInt16)theKeepAliveInterval
          cleanSession:(BOOL)theCleanSessionFlag
               runLoop:(NSRunLoop*)theRunLoop
               forMode:(NSString*)theRunLoopMode {
    MQTTMessage *msg = [MQTTMessage connectMessageWithClientId:theClientId
                                                      userName:theUserName
                                                      password:thePassword
                                                     keepAlive:theKeepAliveInterval
                                                  cleanSession:theCleanSessionFlag];
    return [self initWithClientId:theClientId
                        keepAlive:theKeepAliveInterval
                   connectMessage:msg
                          runLoop:theRunLoop
                          forMode:theRunLoopMode];
}

- (id)initWithClientId:(NSString*)theClientId
              userName:(NSString*)theUserName
              password:(NSString*)thePassword
             keepAlive:(UInt16)theKeepAliveInterval
          cleanSession:(BOOL)theCleanSessionFlag
             willTopic:(NSString*)willTopic
               willMsg:(NSData*)willMsg
               willQoS:(UInt8)willQoS
        willRetainFlag:(BOOL)willRetainFlag {
    return [self initWithClientId:theClientId
                         userName:theUserName
                         password:thePassword
                        keepAlive:theKeepAliveInterval
                     cleanSession:theCleanSessionFlag
                        willTopic:willTopic
                          willMsg:willMsg
                          willQoS:willQoS
                   willRetainFlag:willRetainFlag
                          runLoop:[NSRunLoop currentRunLoop]
                          forMode:NSDefaultRunLoopMode];
}

- (id)initWithClientId:(NSString*)theClientId
              userName:(NSString*)theUserName
              password:(NSString*)thePassword
             keepAlive:(UInt16)theKeepAliveInterval
          cleanSession:(BOOL)theCleanSessionFlag
             willTopic:(NSString*)willTopic
               willMsg:(NSData*)willMsg
               willQoS:(UInt8)willQoS
        willRetainFlag:(BOOL)willRetainFlag
               runLoop:(NSRunLoop*)theRunLoop
               forMode:(NSString*)theRunLoopMode {
    MQTTMessage *msg = [MQTTMessage connectMessageWithClientId:theClientId
                                                      userName:theUserName
                                                      password:thePassword
                                                     keepAlive:theKeepAliveInterval
                                                  cleanSession:theCleanSessionFlag
                                                     willTopic:willTopic
                                                       willMsg:willMsg
                                                       willQoS:willQoS
                                                    willRetain:willRetainFlag];
    return [self initWithClientId:theClientId
                        keepAlive:theKeepAliveInterval
                   connectMessage:msg
                          runLoop:theRunLoop
                          forMode:theRunLoopMode];
}

- (id)initWithClientId:(NSString*)theClientId
             keepAlive:(UInt16)theKeepAliveInterval
        connectMessage:(MQTTMessage*)theConnectMessage
               runLoop:(NSRunLoop*)theRunLoop
               forMode:(NSString*)theRunLoopMode {
    self = [super init];
    if (self) {
        clientId = theClientId;
        keepAliveInterval = theKeepAliveInterval;
        connectMessage = theConnectMessage;
        runLoop = theRunLoop;
        runLoopMode = theRunLoopMode;
        
        self.queue = [NSMutableArray array];
        txMsgId = 1;
        txFlows = [[NSMutableDictionary alloc] init];
        rxFlows = [[NSMutableDictionary alloc] init];
        self.timerRing = [[NSMutableArray alloc] initWithCapacity:60];
        int i;
        for (i = 0; i < 60; i++) {
            [self.timerRing addObject:[NSMutableSet set]];
        }
        ticks = 0;
    }
    return self;
}

- (void)dealloc {
    [encoder close];
    encoder = nil;
    [decoder close];
    decoder = nil;
    if (timer != nil) {
        [timer invalidate];
        timer = nil;
    }
}

- (void)close {
    [encoder close];
    [decoder close];
    encoder = nil;
    decoder = nil;
     if (timer != nil) {
        [timer invalidate];
        timer = nil;
        }
    [self error:MQTTSessionEventConnectionClosed];
}

- (void)setDelegate:(id)aDelegate {
    delegate = aDelegate;
}

- (void)connectToHost:(NSString*)ip port:(UInt32)port {
    [self connectToHost:ip port:port usingSSL:false];
}

- (void)connectToHost:(NSString*)ip port:(UInt32)port usingSSL:(BOOL)usingSSL {

    status = MQTTSessionStatusCreated;

    CFReadStreamRef readStream;
    CFWriteStreamRef writeStream;

    CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)ip, port, &readStream, &writeStream);

    if (usingSSL) {
        const void *keys[] = { kCFStreamSSLLevel,
                               kCFStreamSSLPeerName };

        const void *vals[] = { kCFStreamSocketSecurityLevelNegotiatedSSL,
                               kCFNull };

        CFDictionaryRef sslSettings = CFDictionaryCreate(kCFAllocatorDefault, keys, vals, 2,
                                                         &kCFTypeDictionaryKeyCallBacks,
                                                         &kCFTypeDictionaryValueCallBacks);

        CFReadStreamSetProperty(readStream, kCFStreamPropertySSLSettings, sslSettings);
        CFWriteStreamSetProperty(writeStream, kCFStreamPropertySSLSettings, sslSettings);

        CFRelease(sslSettings);
    }

    encoder = [[MQTTEncoder alloc] initWithStream:(__bridge_transfer NSOutputStream*)writeStream
                                          runLoop:runLoop
                                      runLoopMode:runLoopMode];

    decoder = [[MQTTDecoder alloc] initWithStream:(__bridge_transfer NSInputStream*)readStream
                                          runLoop:runLoop
                                      runLoopMode:runLoopMode];

    [encoder setDelegate:self];
    [decoder setDelegate:self];
    
    [encoder open];
    [decoder open];
}

- (void)subscribeTopic:(NSString*)theTopic {
    [self subscribeToTopic:theTopic atLevel:0];
}

- (void) subscribeToTopic:(NSString*)topic
                  atLevel:(UInt8)qosLevel {
    
    UInt16 msgId = [self nextMsgId];
    MQTTMessage* msg = [MQTTMessage subscribeMessageWithMessageId:msgId
                                                            topic:topic
                                                              qos:qosLevel];
    
    MQttTxFlow *flow = [MQttTxFlow flowWithMsg:msg deadline:(ticks + 60)];
    [txFlows setObject:flow forKey:[NSNumber numberWithUnsignedInt:msgId]];
    
    [self send: msg];
}

- (void)unsubscribeTopic:(NSString*)theTopic {
    
    UInt16 msgId = [self nextMsgId];
    MQTTMessage* msg = [MQTTMessage unsubscribeMessageWithMessageId: msgId
                                                              topic: theTopic];
    MQttTxFlow* flow = [MQttTxFlow flowWithMsg: msg deadline: (ticks + 60)];
    [txFlows setObject: flow forKey: [NSNumber numberWithUnsignedInt: msgId]];
    [self send: msg];
}

- (void)publishData:(NSData*)data onTopic:(NSString*)topic {
    [self publishDataAtMostOnce:data onTopic:topic];
}

- (void)publishDataAtMostOnce:(NSData*)data
                      onTopic:(NSString*)topic {
  [self publishDataAtMostOnce:data onTopic:topic retain:false];
}

- (void)publishDataAtMostOnce:(NSData*)data
                      onTopic:(NSString*)topic
                     retain:(BOOL)retainFlag {
    [self send:[MQTTMessage publishMessageWithData:data
                                           onTopic:topic
                                        retainFlag:retainFlag]];
}

- (uint16_t)publishDataAtLeastOnce:(NSData*)data
                       onTopic:(NSString*)topic {
    return [self publishDataAtLeastOnce:data onTopic:topic retain:false];
}

- (uint16_t)publishDataAtLeastOnce:(NSData*)data
                       onTopic:(NSString*)topic
                        retain:(BOOL)retainFlag {
    UInt16 msgId = [self nextMsgId];
    MQTTMessage *msg = [MQTTMessage publishMessageWithData:data
                                                   onTopic:topic
                                                       qos:1
                                                     msgId:msgId
                                                retainFlag:retainFlag
                                                   dupFlag:false];
    MQttTxFlow *flow = [MQttTxFlow flowWithMsg:msg
                                      deadline:(ticks + 60)];
    [txFlows setObject:flow forKey:[NSNumber numberWithUnsignedInt:msgId]];
    [[self.timerRing objectAtIndex:([flow deadline] % 60)] addObject:[NSNumber numberWithUnsignedInt:msgId]];
    [self send:msg];
    return msgId;
}

- (uint16_t)publishDataExactlyOnce:(NSData*)data
                       onTopic:(NSString*)topic {
    return [self publishDataExactlyOnce:data onTopic:topic retain:false];
}

- (uint16_t)publishDataExactlyOnce:(NSData*)data
                       onTopic:(NSString*)topic
                        retain:(BOOL)retainFlag {
    UInt16 msgId = [self nextMsgId];
    MQTTMessage *msg = [MQTTMessage publishMessageWithData:data
                                                   onTopic:topic
                                                       qos:2
                                                     msgId:msgId
                                                retainFlag:retainFlag
                                                   dupFlag:false];
    MQttTxFlow *flow = [MQttTxFlow flowWithMsg:msg
                                      deadline:(ticks + 60)];
    [txFlows setObject:flow forKey:[NSNumber numberWithUnsignedInt:msgId]];
    [[self.timerRing objectAtIndex:([flow deadline] % 60)] addObject:[NSNumber numberWithUnsignedInt:msgId]];
    [self send:msg];
    
    return msgId;
}

- (void)publishJson:(id)payload onTopic:(NSString*)theTopic {
    NSError * error = nil;
    NSData * data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&error];
    if(error!=nil){
        //NSLog(@"Error creating JSON: %@",error.description);
        return;
    }
    [self publishData:data onTopic:theTopic];
}

- (void)timerHandler:(NSTimer*)theTimer {
    idleTimer++;
    if (idleTimer >= keepAliveInterval) {
        if ([encoder status] == MQTTEncoderStatusReady) {
            //NSLog(@"sending PINGREQ");
            [encoder encodeMessage:[MQTTMessage pingreqMessage]];
            idleTimer = 0;
        }
    }
    ticks++;
    NSEnumerator *e = [[self.timerRing objectAtIndex:(ticks % 60)] objectEnumerator];
    id msgId;

    while ((msgId = [e nextObject])) {
        MQttTxFlow *flow = [txFlows objectForKey:msgId];
        MQTTMessage *msg = [flow msg];
        [flow setDeadline:(ticks + 60)];
        [msg setDupFlag];
        [self send:msg];
    }
}

- (void)encoder:(MQTTEncoder*)sender handleEvent:(MQTTEncoderEvent) eventCode {
   // NSLog(@"encoder:(MQTTEncoder*)sender handleEvent:(MQTTEncoderEvent) eventCode ");
    if(sender == encoder) {
        switch (eventCode) {
            case MQTTEncoderEventReady:
                switch (status) {
                    case MQTTSessionStatusCreated:
                        //NSLog(@"Encoder has been created. Sending Auth Message");
                        [sender encodeMessage:connectMessage];
                        status = MQTTSessionStatusConnecting;
                        break;
                    case MQTTSessionStatusConnecting:
                        break;
                    case MQTTSessionStatusConnected:
                        if ([self.queue count] > 0) {
                            MQTTMessage *msg = [self.queue objectAtIndex:0];
                            [self.queue removeObjectAtIndex:0];
                            [encoder encodeMessage:msg];
                        }
                        break;
                    case MQTTSessionStatusError:
                        break;
                }
                break;
            case MQTTEncoderEventErrorOccurred:
                [self error:MQTTSessionEventConnectionError];
                break;
        }
    }
}

- (void)decoder:(MQTTDecoder*)sender handleEvent:(MQTTDecoderEvent)eventCode {
    //NSLog(@"decoder:(MQTTDecoder*)sender handleEvent:(MQTTDecoderEvent)eventCode");
    if(sender == decoder) {
        MQTTSessionEvent event;
        switch (eventCode) {
            case MQTTDecoderEventConnectionClosed:
                event = MQTTSessionEventConnectionError;
                break;
            case MQTTDecoderEventConnectionError:
                event = MQTTSessionEventConnectionError;
                break;
            case MQTTDecoderEventProtocolError:
                event = MQTTSessionEventProtocolError;
                break;
        }
        [self error:event];
    }
}

- (void)decoder:(MQTTDecoder*)sender newMessage:(MQTTMessage*)msg {
    //NSLog(@"decoder:(MQTTDecoder*)sender newMessage:(MQTTMessage*)msg ");
    if(sender == decoder){
        switch (status) {
            case MQTTSessionStatusConnecting:
                switch ([msg type]) {
                    case MQTTConnack:
                        if ([[msg data] length] != 2) {
                            [self error:MQTTSessionEventProtocolError];
                        }
                        else {
                            const UInt8 *bytes = (const UInt8 *)[[msg data] bytes];
                            if (bytes[1] == 0) {
                                status = MQTTSessionStatusConnected;
                                timer = [[NSTimer alloc] initWithFireDate:[NSDate dateWithTimeIntervalSinceNow:1.0]
                                                                 interval:1.0
                                                                   target:self
                                                                 selector:@selector(timerHandler:)
                                                                 userInfo:nil
                                                                  repeats:YES];
                                [runLoop addTimer:timer forMode:runLoopMode];
                                if ([delegate respondsToSelector:@selector(session:handleEvent:)]) {
                                    [delegate session:self handleEvent:MQTTSessionEventConnected];
                                }
                            }
                            else {
                                
                                //The Server does not support the level of the MQTT protocol requested by the Client
                                if (bytes[1] == 0x01) {
                                    [self error:MQTTSessionEventConnectionError];
                                    
                                //The Client identifier is correct UTF-8 but not allowed by the Server
                                } else if (bytes[1] == 0x02) {
                                    [self error:MQTTSessionEventConnectionError];
                                    
                                //The Network Connection has been made but the MQTT service is unavailable
                                } else if (bytes[1] == 0x03) {
                                    [self error:MQTTSessionEventConnectionError];
                                    
                                //The data in the user name or password is malformed
                                } else if (bytes[1] == 0x04) {
                                    [self error:MQTTSessionEventConnectionError];
                                    
                                //The Client is not authorized to connect
                                } else if (bytes[1] == 0x05) {
                                    [self error:MQTTSessionEventConnectionRefused];
                                } else {
                                    [self error:MQTTSessionEventConnectionError];
                                }
                            }
                        }
                        break;
                    default:
                        [self error:MQTTSessionEventProtocolError];
                        break;
                }
                break;
            case MQTTSessionStatusConnected:
                [self newMessage:msg];
                break;
            default:
                break;
        }
    }
}

- (void)newMessage:(MQTTMessage*)msg {
    switch ([msg type]) {
        case MQTTPublish:
            [self handlePublish:msg];
            break;
        case MQTTPuback:
            [self handlePuback:msg];
            break;
        case MQTTPubrec:
            [self handlePubrec:msg];
            break;
        case MQTTPubrel:
            [self handlePubrel:msg];
            break;
        case MQTTPubcomp:
            [self handlePubcomp:msg];
            break;
        case MQTTSuback:
            [self handleSuback:msg];
            break;
        case MQTTUnsuback:
            [self handleUnsuback:msg];
            break;
    default:
        return;
    }
}

- (void)handlePublish:(MQTTMessage*)msg {
    
    NSData *data = [msg data];
    if ([data length] < 2) {
        return;
    }
    UInt8 const *bytes = (UInt8 const *)[data bytes];
    UInt16 topicLength = 256 * bytes[0] + bytes[1];
    if ([data length] < 2 + topicLength) {
        return;
    }
    NSData *topicData = [data subdataWithRange:NSMakeRange(2, topicLength)];
    NSString *topic = [[NSString alloc] initWithData:topicData
                                            encoding:NSUTF8StringEncoding];
    NSRange range = NSMakeRange(2 + topicLength, [data length] - topicLength - 2);
    data = [data subdataWithRange:range];
    
    if ([msg qos] == 0) {
        if ([delegate respondsToSelector:@selector(session:newMessage:onTopic:)]) {
            [delegate session:self newMessage:data onTopic:topic];
        }
    }
    else {
        if ([data length] < 2) {
            return;
        }
        bytes = (UInt8 const *)[data bytes];
        UInt16 msgId = 256 * bytes[0] + bytes[1];
        if (msgId == 0) {
            return;
        }
        data = [data subdataWithRange:NSMakeRange(2, [data length] - 2)];
        if ([msg qos] == 1) {
            [self send:[MQTTMessage pubackMessageWithMessageId:msgId]];
            if ([delegate respondsToSelector:@selector(session:newMessage:onTopic:)]) {
                [delegate session:self newMessage:data onTopic:topic];
            }
        }
        else {
            NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
                data, @"data", topic, @"topic", nil];
            [rxFlows setObject:dict forKey:[NSNumber numberWithUnsignedInt:msgId]];
            [self send:[MQTTMessage pubrecMessageWithMessageId:msgId]];
        }
    }
}

- (void)handlePuback:(MQTTMessage*)msg {
    if ([[msg data] length] != 2) {
        return;
    }
    UInt8 const *bytes = (UInt8 const *)[[msg data] bytes];
    NSNumber *msgId = [NSNumber numberWithUnsignedInt:(256 * bytes[0] + bytes[1])];
    if ([msgId unsignedIntValue] == 0) {
        return;
    }
    MQttTxFlow *flow = [txFlows objectForKey:msgId];
    if (flow == nil) {
        return;
    }

    if ([[flow msg] type] != MQTTPublish || [[flow msg] qos] != 1) {
        return;
    }

    if ([delegate respondsToSelector:@selector(session:handlePublishAck:onTopic:withMessageId:)]) {

        // get message from tx flow
        MQttTxFlow *flow = [txFlows objectForKey:msgId];
        MQTTMessage* flowMessage = [flow msg];
        NSData *data = [flowMessage data];
        if ([data length] < 4) return;

        UInt8 const *bytes = (UInt8 const *)[data bytes];
        UInt16 topicLength = 256 * bytes[0] + bytes[1];
        if ([data length] < 2 + topicLength) {
            return;
        }
        
        // get topic name
        NSData *topicData = [data subdataWithRange:NSMakeRange(2, topicLength)];
        NSString *topic = [[NSString alloc] initWithData:topicData
                                                encoding:NSUTF8StringEncoding];
        // get message
        NSRange range = NSMakeRange(2 + topicLength, [data length] - topicLength - 2);
        data = [data subdataWithRange:range];
        
        // notify delegate
        [delegate session: self
         handlePublishAck: data
                  onTopic: topic
            withMessageId: [msgId unsignedShortValue]];
    }

    [[self.timerRing objectAtIndex:([flow deadline] % 60)] removeObject:msgId];
    [txFlows removeObjectForKey:msgId];
}

- (void)handlePubrec:(MQTTMessage*)msg {
    if ([[msg data] length] != 2) {
        return;
    }
    UInt8 const *bytes = (UInt8 const *)[[msg data] bytes];
    NSNumber *msgId = [NSNumber numberWithUnsignedInt:(256 * bytes[0] + bytes[1])];
    if ([msgId unsignedIntValue] == 0) {
        return;
    }
    MQttTxFlow *flow = [txFlows objectForKey:msgId];
    if (flow == nil) {
        return;
    }
    msg = [flow msg];
    if ([msg type] != MQTTPublish || [msg qos] != 2) {
        return;
    }
    msg = [MQTTMessage pubrelMessageWithMessageId:[msgId unsignedIntValue]];
    [flow setMsg:msg];
    [[self.timerRing objectAtIndex:([flow deadline] % 60)] removeObject:msgId];
    [flow setDeadline:(ticks + 60)];
    [[self.timerRing objectAtIndex:([flow deadline] % 60)] addObject:msgId];

    [self send:msg];
}

- (void)handlePubrel:(MQTTMessage*)msg {
    if ([[msg data] length] != 2) {
        return;
    }
    UInt8 const *bytes = (UInt8 const *)[[msg data] bytes];
    UInt16 msgIdUint = 256 * bytes[0] + bytes[1];
    NSNumber *msgId = [NSNumber numberWithUnsignedInt:msgIdUint];
    if ([msgId unsignedIntValue] == 0) {
        return;
    }
    NSDictionary *dict = [rxFlows objectForKey:msgId];
    [self send:[MQTTMessage pubcompMessageWithMessageId:[msgId unsignedIntegerValue]]];
    if (dict != nil) {
        [rxFlows removeObjectForKey:msgId];
        [delegate session:self
               newMessage:[dict valueForKey:@"data"]
                  onTopic:[dict valueForKey:@"topic"]];
    }
}

- (void)handlePubcomp:(MQTTMessage*)msg {
    if ([[msg data] length] != 2) {
        return;
    }
    UInt8 const *bytes = (UInt8 const *)[[msg data] bytes];
    NSNumber *msgId = [NSNumber numberWithUnsignedInt:(256 * bytes[0] + bytes[1])];
    if ([msgId unsignedIntValue] == 0) {
        return;
    }
    MQttTxFlow *flow = [txFlows objectForKey:msgId];
    if (flow == nil || [[flow msg] type] != MQTTPubrel) {
        return;
    }

    [[self.timerRing objectAtIndex:([flow deadline] % 60)] removeObject:msgId];
    [txFlows removeObjectForKey:msgId];
}

- (void)handleSuback: (MQTTMessage*)msg {

    // get message id
    UInt8 const *bytes = (UInt8 const *)[[msg data] bytes];
    NSNumber *msgId = [NSNumber numberWithUnsignedInt:(256 * bytes[0] + bytes[1])];
    if ([msgId unsignedIntValue] == 0) {
        return;
    }
    
    UInt8 result = bytes[2];
    
    // get message from tx flow
    MQttTxFlow *flow = [txFlows objectForKey:msgId];
    MQTTMessage* flowMessage = [flow msg];
    
    NSData *data = [flowMessage data];
    if ([data length] < 4) {
        return;
    }
    
    bytes = (UInt8 const *)[data bytes];
    // get topic name from message
    UInt16 topicLength = 256 * bytes[2] + bytes[3];
    if ([data length] < 2 + topicLength) {
        return;
    }
    NSData *topicData = [data subdataWithRange:NSMakeRange(4, topicLength)];
    NSString *topic = [[NSString alloc] initWithData:topicData encoding:NSUTF8StringEncoding];
    
    if (result == 0x80) {
        if ([delegate respondsToSelector:@selector(session:subscribeFailedAtTopic:)]) {
            [delegate session:self subscribeFailedAtTopic:topic];
        }
    } else {
        if ([delegate respondsToSelector:@selector(session:handleSubscribeAck:qos:)]) {
            [delegate session:self handleSubscribeAck:topic qos:result];
        }
    }
    
    
    [txFlows removeObjectForKey:msgId];
}

- (void)handleUnsuback: (MQTTMessage*)msg {
    
    // get message id
    UInt8 const *bytes = (UInt8 const *)[[msg data] bytes];
    NSNumber *msgId = [NSNumber numberWithUnsignedInt:(256 * bytes[0] + bytes[1])];
    if ([msgId unsignedIntValue] == 0) {
        return;
    }
    
    // get message from tx flow
    MQttTxFlow *flow = [txFlows objectForKey:msgId];
    MQTTMessage* flowMessage = [flow msg];
    
    NSData *data = [flowMessage data];
    if ([data length] < 4) {
        return;
    }
    
    bytes = (UInt8 const *)[data bytes];
    // get topic name from message
    UInt16 topicLength = 256 * bytes[2] + bytes[3];
    if ([data length] < 2 + topicLength) {
        return;
    }
    NSData *topicData = [data subdataWithRange:NSMakeRange(4, topicLength)];
    NSString *topic = [[NSString alloc] initWithData:topicData encoding:NSUTF8StringEncoding];
    
    if ([delegate respondsToSelector:@selector(session:handleUnsubscribeAck:)]) {
        [delegate session:self handleUnsubscribeAck: topic];
    }
    [txFlows removeObjectForKey:msgId];
}

- (void)error:(MQTTSessionEvent)eventCode {
    
    [encoder close];
    encoder = nil;
    
    [decoder close];
    decoder = nil;
    
    if (timer != nil) {
        [timer invalidate];
        
        timer = nil;
    }
    status = MQTTSessionStatusError;
    
    usleep(1000000); // 1 sec delay
    
    if ([delegate respondsToSelector:@selector(session:handleEvent:)]) {
        [delegate session:self handleEvent:eventCode];
    }

}

- (void)send:(MQTTMessage*)msg {
    if ([encoder status] == MQTTEncoderStatusReady) {
        [encoder encodeMessage:msg];
    }
    else {
        [self.queue addObject:msg];
    }
}

- (UInt16)nextMsgId {
    txMsgId++;
    while (txMsgId == 0 || [txFlows objectForKey:[NSNumber numberWithUnsignedInt:txMsgId]] != nil) {
        txMsgId++;
    }
    return txMsgId;
}

@end
