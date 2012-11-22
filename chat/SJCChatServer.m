/*
 *  SJCChatServer.m
 *  SimpleChat
 *
 *  Created by Stuart Crook on 17/06/2012.
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

#import "SJCChatServer.h"
#import "SJCServer.h"
#import "SJCConnection.h"
#import <objc/runtime.h>

#include <time.h>

#import "FMDatabase.h"

NSString *const SJCChatServerStatusNotification = @"SJCChatServerStatusNotification";

enum {
    kMessageTypePublic = 1,
    kMessageTypePrivate,
    kMessageTypePrivateWithSubject,
};

@interface SJCChatServer () <SJCServerDelegate, SJCConnectionDelegate>
-(void)setup;
-(void)processMessage:(NSDictionary *)msg forConnection:(SJCConnection *)conn from:(NSString *)from;
-(void)processRequest:(NSDictionary *)req forConnection:(SJCConnection *)conn from:(NSString *)from;
-(void)postStatusNotification;
@end

@implementation SJCChatServer {
    NSString *_serverName;
    NSString *_dbPath;
    dispatch_queue_t _queue;
    dispatch_source_t _timer;
    NSMutableDictionary *_clients; // email : connection object
    NSMutableArray *_messages; // queue of broadcast public messages
    SJCServer *_server;
    FMDatabase *_db;
    NSUInteger _lastMID;
}

-(id)initWithServerName:(NSString *)serverName {
    return [self initWithServerName: serverName dbPath: nil];
}

-(id)initWithServerName:(NSString *)serverName dbPath:(NSString *)dbPath {
    if((self = [super init])) {
        _serverName = serverName;
        _dbPath = dbPath;
        
        _clients = [NSMutableDictionary new];
        _messages = [NSMutableArray new];
        
        // serial queue for all database operations
        _queue = dispatch_queue_create([[@"uk.co.jaml.simple-chat." stringByAppendingString: _serverName] UTF8String], DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(_queue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
        dispatch_async(_queue, ^{
            [self setup];
        });
        
        // the server which advertises over bonjour and collects client connections
        _server = [[SJCServer alloc] initWithServiceName: _serverName];
        [_server setMaxConnections: 0]; // infinite
        [_server setDelegate: self];
    }
    return self;
}

-(void)setup {
    if(nil == _dbPath) {
        _dbPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
        _dbPath = [_dbPath stringByAppendingPathComponent: [_serverName stringByAppendingPathExtension: @"sqlite"]];
    } else {
        _dbPath = [_dbPath stringByExpandingTildeInPath];
    }
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath: _dbPath];
    _db = [FMDatabase databaseWithPath: _dbPath];
    if(NO == [_db open]) {
        NSLog(@"couldn't open database!");
        return;
    }
    if(NO == exists) {
        [_db executeUpdate: @"CREATE TABLE messages (type integer, time integer, fromName text, toName text, subject text, msg text)"];
        if([_db hadError]) {
            NSLog(@"Error creating database %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
        }
        [_db executeUpdate: @"CREATE INDEX typeIndex ON messages (type)"];
        if([_db hadError]) {
            NSLog(@"Error creating index 'typeIndex' %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
        }
        [_db executeUpdate: @"CREATE INDEX fromIndex ON messages (fromName)"];
        if([_db hadError]) {
            NSLog(@"Error creating index 'fromIndex' %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
        }
        [_db executeUpdate: @"CREATE INDEX toIndex ON messages (toName)"];
        if([_db hadError]) {
            NSLog(@"Error creating index 'toIndex' %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
        }
    }
    // and we should be ready to go
    
    // timer which periodically sends all buffered public messages
    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
    dispatch_source_set_timer(_timer, dispatch_walltime(NULL, 0), 3ull * NSEC_PER_SEC, 1ull * NSEC_PER_SEC);
    dispatch_source_set_event_handler(_timer, ^{
        if(0 != [_messages count]) {
            //NSLog(@"going to broadcast %d messages", (int)[_messages count]);
            NSDictionary *msg = @{ @"kind" : @"broadcast", @"messages" : [_messages copy] };
            NSError *error = nil;
            NSData *data = [NSPropertyListSerialization dataWithPropertyList: msg format: NSPropertyListBinaryFormat_v1_0 options: 0 error: &error];
            if(nil == data) {
                NSLog(@"error encoding message: %@", error);
                return;
            }
            [_messages removeAllObjects];
            for(SJCConnection *conn in [_clients allValues]) {
                [conn sendData: data];
            }
        }
    });
    dispatch_resume(_timer);
}

-(void)start {
    
}

-(void)stop {
    
}

#pragma mark - handling messages and requests

// these will be run on the dispatch queue

-(void)processMessage:(NSDictionary *)msg forConnection:(SJCConnection *)conn from:(NSString *)from {
    NSString *body = [msg objectForKey: @"msg"];
    //NSString *to = [[[msg objectForKey: @"to"] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    NSString *to = [msg objectForKey: @"to"];
    NSString *subject = [[msg objectForKey: @"subject"] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSInteger toLength = [to length];
    NSInteger subjectLength = [subject length];
    if(((0 == toLength) && (0 == subjectLength)) || (0 == [body length])) {
        // not a valid message for our purpose
        return;
    }

    NSNumber *now = @( time(NULL) );
    
    NSUInteger t;
    if(0 == toLength) {
        t = kMessageTypePublic;
    } else if(0 == subjectLength) {
        t = kMessageTypePrivate;
    } else {
        t = kMessageTypePrivateWithSubject;
    }
    NSNumber *type = @(t);
    
    [_db executeUpdate: @"insert into messages (type, time, msg, fromName, toName, subject) values (?,?,?,?,?,?)", type, now, body, from, (to ?: [NSNull null]), (subject ?: [NSNull null])];
    if([_db hadError]) {
        NSLog(@"Error inserting new message %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
    }
    _lastMID = [_db lastInsertRowId];

    NSMutableDictionary *reply = [msg mutableCopy];
    [reply setObject: now forKey: @"time"];
    [reply setObject: @(_lastMID) forKey: @"mid"];
    [reply setObject: type forKey: @"type"];

    // encode it now and send the data, rather than re-encoding every time via sendMessage:

    if(kMessageTypePublic == t) {
        // enqueue message to be broadcast later
        [_messages addObject: reply];

    } else {
        NSError *error = nil;
        NSData *data = [NSPropertyListSerialization dataWithPropertyList: reply format: NSPropertyListBinaryFormat_v1_0 options: 0 error: &error];
        if(nil == data) {
            NSLog(@"error encoding message: %@", error);
            return;
        }
        SJCConnection *recipient = [_clients objectForKey: to];
        [conn sendData: data];
        [recipient sendData: data];
    }
    
    [self postStatusNotification]; // watch this kill performance further
}

-(void)processRequest:(NSDictionary *)req forConnection:(SJCConnection *)conn from:(NSString *)from {
    NSNumber *then = [req objectForKey: @"since"] ?: @(0);
    FMResultSet *rs = [_db executeQuery: @"SELECT rowid,type,time,msg,fromName,toName,subject FROM messages WHERE rowid > ? AND ((type == 1) OR (type in (2,3) AND ((fromName == ?) OR (toName == ?)))) ORDER BY rowid LIMIT 50", then, from, from]; // <-- increase this over time...
    if([_db hadError]) {
        NSLog(@"Error fetching digest of messages %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
    }
    NSMutableArray *messages = [NSMutableArray new];
    while([rs next]) {
        NSMutableDictionary *msg = [NSMutableDictionary new];
        [msg setObject: [rs objectForColumnIndex: 0] forKey: @"mid"];
        [msg setObject: [rs objectForColumnIndex: 1] forKey: @"type"];
        [msg setObject: [rs objectForColumnIndex: 2] forKey: @"time"];
        [msg setObject: [rs objectForColumnIndex: 3] forKey: @"msg"];
        [msg setObject: [rs objectForColumnIndex: 4] forKey: @"from"];
        id to = [rs objectForColumnIndex: 5];
        if(to != [NSNull null]) {
            [msg setObject: to forKey: @"to"];
        }
        id subject = [rs objectForColumnIndex: 6];
        if(subject != [NSNull null]) {
            [msg setObject: subject forKey: @"subject"];
        }
        [messages addObject: msg];
    }
    NSDictionary *msg = @{ @"kind" : @"digest", @"messages" : messages };
    [conn sendMessage: msg];
    
    [self postStatusNotification];
}

-(void)postStatusNotification {
    NSDictionary *info = @{ @"clients" : @([_clients count]), @"messages" : @(_lastMID) };
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName: SJCChatServerStatusNotification
                                                            object: self
                                                          userInfo: info];
    });
}

#pragma mark - SJCServerDelegate

-(void)server:(SJCServer *)server willOpenNewConnection:(SJCConnection *)connection {
    //NSLog(@"ooh! told about a new connection!");
    [connection setDelegate: self];
}

-(void)serverDidRefuseNewConnection:(SJCServer *)server {
    NSLog(@"server refusing connections!");
}

#pragma mark - SJCConnectionDelegate

// process the message, which should be either "msg" or "request"
-(void)connection:(SJCConnection *)connection didReceiveMessage:(NSDictionary *)message {
    //NSLog(@"got message: %@", message);
    //NSString *from = [[[message objectForKey: @"from"] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    NSString *from = [message objectForKey: @"from"];
    if(0 == [from length]) {
        // nothing we can do because we don't know who this is from
        return;
    }
    dispatch_async(_queue, ^{
        // find the connection associated with this from name and check it's the same connection
        SJCConnection *conn = [_clients objectForKey: from];
        if(conn != connection) {
            // this connection has been replaced by a new one -- yeah, absolutely no security here
            if(nil != conn) {
                objc_removeAssociatedObjects(conn);
                [conn close];
            }
            // update to link the from email address to this new connection (or set for first time)
            [_clients setObject: connection forKey: from];
            objc_setAssociatedObject(connection, (__bridge const void *)(self), from, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [self postStatusNotification];
        }
        // what kind of message are we processing?
        NSString *kind = [message objectForKey: @"kind"];
        if([kind isEqualToString: @"request"]) {
            [self processRequest: message forConnection: connection from: from];
        } else if([kind isEqualToString: @"msg"]) {
            [self processMessage: message forConnection: connection from: from];
        }
    });
}

// remove the connection from our _clients map
-(void)connectionDidClose:(SJCConnection *)connection {
    dispatch_async(_queue, ^{
        NSString *email = objc_getAssociatedObject(connection, (__bridge const void *)(self));
        if(0 == [email length]) {
            NSLog(@"unable to remove closed connection -- name tag unknown");
            return;
        }
        objc_removeAssociatedObjects(connection);
        [_clients removeObjectForKey: email];
        [self postStatusNotification];
    });
}

@end
