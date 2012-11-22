/*
 *  SJCConnection.m
 *
 *  Created by Stuart Crook on 17/06/2012.
 *  Copyright (c) 2012 JAMl. All rights reserved.
 *
 *  Copyright (c) 2012, Stuart Crook, Just About Managing ltd
 *  All rights reserved.
 *
 *  Redistribution and use in source and binary forms, with or without
 *  modification, are permitted provided that the following conditions are met:
 *  * Redistributions of source code must retain the above copyright
 *  notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *  notice, this list of conditions and the following disclaimer in the
 *  documentation and/or other materials provided with the distribution.
 *  * Neither the name of the <organization> nor the
 *  names of its contributors may be used to endorse or promote products
 *  derived from this software without specific prior written permission.
 *
 *  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 *  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 *  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 *  DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
 *  DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 *  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 *  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 *  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 *  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 *  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 */

#import "SJCConnection.h"
#import "SJCServer.h"
#import "SJCClient.h"

#define READ_BUFFER_SIZE    4096

@class SJCConnectionThread;

static NSRunLoop *streamRunLoop = nil;
static SJCConnectionThread *streamThread = nil;

@interface SJCConnectionThread : NSThread
@end
@implementation SJCConnectionThread
-(void)main {
    streamRunLoop = [NSRunLoop currentRunLoop];
    //NSLog(@"this is the stream thread, priority == %f", [self threadPriority]);
    [self setThreadPriority: 1.0];
    do {
        [[NSRunLoop currentRunLoop] runUntilDate: [NSDate distantFuture]];
    } while(YES);
    NSLog(@"---> REALLY SHOULD NEVER GET HERE");
}
@end

@interface SJCConnection ()
-(id)initWithInput:(NSInputStream *)input output:(NSOutputStream *)output;
-(void)doOpen;
-(void)doClose;
-(void)doSendData:(NSData *)data;
-(void)recievedData:(NSData *)data;
@end


@implementation SJCConnection {
    NSObject <SJCConnectionHolderDelegate> *_holder;
    NSInputStream *_input;
    NSOutputStream *_output;
    uint8_t *_buffer;
    NSMutableData *_data;
    uint32_t _expected;
    BOOL _inReady, _outReady;
}

-(id)initWithInput:(NSInputStream *)input output:(NSOutputStream *)output {
    if((self = [super init])) {
        _input = input;
        _output = output;
        _buffer = malloc(READ_BUFFER_SIZE); // not at all sure about this
        
        if(nil == streamRunLoop) {
            streamThread = [SJCConnectionThread new];
            [streamThread start];
            // sorry. so very very sorry
            while(nil == streamRunLoop) {
                sleep(1);
            }
        }
    }
    return self;
}

-(id)initWithHolder:(NSObject<SJCConnectionHolderDelegate> *)holder input:(NSInputStream *)input output:(NSOutputStream *)output {
    if((self = [self initWithInput: input output: output])) {
        _holder = holder;
    }
    return self;
}

-(void)dealloc {
    //NSLog(@"~~~> connection dealloced");
    free(_buffer);
}

-(void)open {
    [self performSelector: @selector(doOpen) onThread: streamThread withObject: nil waitUntilDone: YES];
}

// this will be performed on the background streamThread
-(void)doOpen {
    //NSLog(@"streamRunloop == %@", streamRunLoop);
    [_input setDelegate: self];
    [_input scheduleInRunLoop: streamRunLoop forMode:NSDefaultRunLoopMode];
    [_input open];
    [_output setDelegate: self];
    [_output scheduleInRunLoop: streamRunLoop forMode:NSDefaultRunLoopMode];
    [_output open];
}

-(void)close {
    [self performSelector: @selector(doClose) onThread: streamThread withObject: nil waitUntilDone: YES];
    dispatch_async(dispatch_get_main_queue(), ^{
        if([_delegate respondsToSelector: @selector(connectionDidClose:)]) {
            [_delegate connectionDidClose: self];
        }
        [_holder connectionClosed: self];
    });
}

-(void)doClose {
    [_input close]; _input = nil;
    [_output close]; _output = nil;
}

-(void)sendData:(NSData *)data {
    if(0 == [data length]) { return; }
    [self performSelector: @selector(doSendData:) onThread: streamThread withObject: data waitUntilDone: NO];
}

-(void)doSendData:(NSData *)data {
    uint32_t length = (uint32_t)[data length];
    if((nil != _output) && (YES == [_output hasSpaceAvailable])) {
        if(-1 == [_output write: (const void *)&length maxLength: sizeof(uint32_t)]) {
            NSLog(@"Failed sending data length to peer");
        }
        if(-1 == [_output write: [data bytes] maxLength: [data length]]) {
            NSLog(@"Failed sending data to peer");
        }
    }
}

-(void)sendMessage:(NSDictionary *)message {
    NSError *error;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList: message format: NSPropertyListBinaryFormat_v1_0 options: 0 error: &error];
    if(nil == data) {
        NSLog(@"error: %@", error);
        return;
    }
    [self sendData: data];
}

-(void)recievedData:(NSData *)data {
    //NSLog(@"recieved something! %@", data);
    NSDictionary *message = nil;
    if([_delegate respondsToSelector: @selector(connection:didReceiveMessage:)]) {
        NSError *error = nil;
        //message = [NSJSONSerialization JSONObjectWithData: data options: 0 error: &error];
        message = [NSPropertyListSerialization propertyListWithData: data options: 0 format: NULL error: &error];
        if(nil == message) {
            //NSLog(@"couldn't decode to PLIST: %@", error);
            //NSLog(@"%@", [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding]);
        }
    }
    if(nil != message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [_delegate connection: self didReceiveMessage: message];
        });
    } else if([_delegate respondsToSelector: @selector(connection:didReceiveData:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [_delegate connection: self didReceiveData: data];
        });
    }
}

#pragma mark - NSStreamDelegate

-(void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode {
	switch(eventCode) {
		case NSStreamEventOpenCompleted:
		{
			if (stream == _input) {
				_inReady = YES;
			} else {
				_outReady = YES;
			}
			if(_inReady && _outReady) {
                //NSLog(@"connection made!");
                if([_delegate respondsToSelector: @selector(connectionReady:)]) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [_delegate connectionReady: self];
                    });
                }
			}
			break;
		}

		case NSStreamEventHasBytesAvailable:
		{
			if(stream == _input) {
				NSInteger len = 0;

                do {
                    // because we were getting messages clumped together...
                    if(0 == _expected) {
                        // need to check that there are sizeof(uint32_t) bytes available... which doesn't seem possible...
                        len = [_input read: (uint8_t *)&_expected maxLength: sizeof(uint32_t)];
                        if(len != sizeof(uint32_t)) {
                            //NSLog(@"this is something really messed up... didn't get all of the message size header");
                            return;
                        }
                        _data = [NSMutableData new];
                    }
                    
                    // do the reading and stuff -- only read up to the next message header
                    len = [_input read: _buffer maxLength: (READ_BUFFER_SIZE > _expected ? _expected : READ_BUFFER_SIZE)];
                    if(len > 0) {
                        _expected -= len;
                        [_data appendBytes: _buffer length: len];
                    } else {
                        // bugger
                        break;
                    }
                    
                    // have we read everything?
                    if(0 == _expected) {
                        [self recievedData: _data];
                        _data = nil;
                    }
                    
                } while([_input hasBytesAvailable]);
                
                if((len <= 0) && ([stream streamStatus] != NSStreamStatusAtEnd)) {
                    NSLog(@"failed reading data from peer");
                    return;
                }
			}
			break;
		}
		case NSStreamEventErrorOccurred:
		{
            //NSLog(@"error on stream");
            [self close];
			break;
		}
			
		case NSStreamEventEndEncountered:
		{
            //NSLog(@"peer disconnected!");
            [self close];
			break;
		}
            
        case NSStreamEventHasSpaceAvailable:
        case NSStreamEventNone:
            break;
	}
}

@end
