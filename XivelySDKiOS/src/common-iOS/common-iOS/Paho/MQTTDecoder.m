//
// MQTTDecoder.m
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

#import "MQTTDecoder.h"

@implementation MQTTDecoder

- (id)initWithStream:(NSInputStream*)aStream
             runLoop:(NSRunLoop*)aRunLoop
         runLoopMode:(NSString*)aMode {
    self = [super init];
    if (self) {
        status = MQTTDecoderStatusInitializing;
        stream = aStream;
        [stream setDelegate:self];
        runLoop = aRunLoop;
        runLoopMode = aMode;
    }
    return self;
}

- (void)setDelegate:(id)aDelegate {
    delegate = aDelegate;
}

- (void)open {
    [stream setDelegate:self];
    [stream scheduleInRunLoop:runLoop forMode:runLoopMode];
    [stream open];
}

- (void)close {
    [stream setDelegate:nil];
    [stream close];
    [stream removeFromRunLoop:runLoop forMode:runLoopMode];
    stream = nil;
}

- (void)stream:(NSStream*)sender handleEvent:(NSStreamEvent)eventCode {
    if(stream == nil)
        return;
    switch (eventCode) {
        case NSStreamEventOpenCompleted:
            status = MQTTDecoderStatusDecodingHeader;
            break;
        case NSStreamEventHasBytesAvailable:
            if (status == MQTTDecoderStatusDecodingHeader) {
                
                NSInteger n = [stream read:&header maxLength:sizeof(UInt8)];
                if (n  < 0) {
                    status = MQTTDecoderStatusConnectionError;
                    [delegate decoder:self handleEvent:MQTTDecoderEventConnectionError];
                    return;
                }
                else if (n == 1) {
                    length = 0;
                    lengthMultiplier = 1;
                    status = MQTTDecoderStatusDecodingLength;
                } else {
                    assert(0);
                }
            }
            while (status == MQTTDecoderStatusDecodingLength) {
                UInt8 digit = 0;
                NSInteger n = [stream read:&digit maxLength:sizeof(UInt8)];
                if (n  < 0) {
                    status = MQTTDecoderStatusConnectionError;
                    [delegate decoder:self handleEvent:MQTTDecoderEventConnectionError];
                    return;
                }
                else if (n == 0) {
                    break;
                }
                length += (digit & 0x7f) * lengthMultiplier;
                if ((digit & 0x80) == 0x00) {
                    dataBuffer = [NSMutableData dataWithCapacity:length];
                    status = MQTTDecoderStatusDecodingData;
                }
                else {
                    lengthMultiplier *= 128;
                }
            }
            if (status == MQTTDecoderStatusDecodingData) {
                if (length > 0) {
                    NSInteger n, toRead;
                    UInt8 buffer[768];
                    toRead = length - [dataBuffer length];
                    if (toRead > sizeof buffer) {
                        toRead = sizeof buffer;
                    }
                    n = [stream read:buffer maxLength:toRead];
                    if (n  < 0) {
                        status = MQTTDecoderStatusConnectionError;
                        [delegate decoder:self handleEvent:MQTTDecoderEventConnectionError];
                        return;
                    }
                    else {
                        [dataBuffer appendBytes:buffer length:n];
                    }
                }
                if ([dataBuffer length] == length) {
                    MQTTMessage* msg;
                    UInt8 type, qos;
                    BOOL isDuplicate, retainFlag;
                    type = (header >> 4) & 0x0f;
                    isDuplicate = NO;
                    if ((header & 0x08) == 0x08) {
                        isDuplicate = YES;
                    }
                    // XXX qos > 2
                    qos = (header >> 1) & 0x03;
                    retainFlag = NO;
                    if ((header & 0x01) == 0x01) {
                        retainFlag = YES;
                    }
                    msg = [[MQTTMessage alloc] initWithType:type
                                                        qos:qos
                                                 retainFlag:retainFlag
                                                    dupFlag:isDuplicate
                                                       data:dataBuffer];
                    dataBuffer = NULL;
                    status = MQTTDecoderStatusDecodingHeader;
                    [delegate decoder:self newMessage:msg];
                    
                }
            }
            break;
        case NSStreamEventEndEncountered:
            status = MQTTDecoderStatusConnectionClosed;
            [delegate decoder:self handleEvent:MQTTDecoderEventConnectionClosed];
            break;
        case NSStreamEventErrorOccurred:
            status = MQTTDecoderStatusConnectionError;
            [delegate decoder:self handleEvent:MQTTDecoderEventConnectionError];
            break;
        default:
            NSLog(@"unhandled event code");
            break;
    }
}

- (void)dealloc {
    [self close];
}

@end
