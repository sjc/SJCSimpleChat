/*
 *  SJCChatClient.m
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

#import "SJCChatClient.h"
#import "SJCClient.h"
#import "SJCConnection.h"
#import "FMDatabase.h"

NSString *const SJCChatOnLineStatusNotification = @"SJCChatOnLineStatusNotification";
NSString *const SJCChatNewMessagesNotificaiton = @"SJCChatNewMessagesNotificaiton";

@interface SJCChatClient () <SJCClientDelegate, SJCConnectionDelegate>
-(void)setup;
-(void)storeMessages:(NSArray *)messages;
//-(void)didEnterBackgroundNotification:(NSNotification *)note;
//-(void)willEnterForegroundNotification:(NSNotification *)note;
@end

@implementation SJCChatClient {
    NSString *_serverName;
    NSString *_userID;
    SJCClient *_client;
    SJCConnection *_conn;
    dispatch_queue_t _queue;
    FMDatabase *_db;
}

-(id)initWithServerName:(NSString *)serverName userID:(NSString *)userID {
    if((self = [super init])) {
        _serverName = serverName;
        _userID = userID;
        _queue = dispatch_queue_create([[@"uk.co.jaml.simple-chat." stringByAppendingString: _userID] UTF8String], DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(_queue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
        dispatch_async(_queue, ^{
            [self setup];
        });
        
        //UIApplicationDidEnterBackgroundNotification
        //UIApplicationWillEnterForegroundNotification
    }
    return self;
}

-(void)dealloc {
    NSLog(@"----> chat client dealloced: %@", _userID);
    [_conn setDelegate: nil];
    [_conn close];
}

-(void)setup {
    NSString *path = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
    path = [path stringByAppendingPathComponent: [_userID stringByAppendingPathExtension: @"sqlite"]];
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath: path];
    _db = [FMDatabase databaseWithPath: path];
    if(NO == [_db open]) {
        NSLog(@"couldn't open database for %@!", _userID);
        return;
    }
    //NSLog(@"opened DB for %@", _userID);
    if(NO == exists) {
        [_db executeUpdate: @"CREATE TABLE messages (mid integer UNIQUE, type INTEGER, time integer, fromName text, toName text, subject text, msg text, read integer DEFAULT 0)"];
        if([_db hadError]) {
            NSLog(@"Error creating messages table %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
        }
        [_db executeUpdate: @"CREATE INDEX typeIndex ON messages (type)"];
        if([_db hadError]) {
            NSLog(@"Error creating from type %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
        }
        [_db executeUpdate: @"CREATE INDEX fromIndex ON messages (fromName)"];
        if([_db hadError]) {
            NSLog(@"Error creating from index %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
        }
        [_db executeUpdate: @"CREATE INDEX toIndex ON messages (toName)"];
        if([_db hadError]) {
            NSLog(@"Error creating to index %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
        }
        [_db executeUpdate: @"CREATE INDEX subjectIndex ON messages (subject)"];
        if([_db hadError]) {
            NSLog(@"Error creating subject index %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
        }
    }
}

-(void)start {
    _client = [[SJCClient alloc] initWithServiceName: _serverName];
    [_client setDelegate: self];
    [_client startSearch];
}

-(void)stop {
    [_client setDelegate: nil];
    [_client stopSearch];
    _client = nil;
    [_conn setDelegate: nil];
    [_conn close];
    _conn = nil;
}


-(void)sendMessages:(NSString *)text toUser:(NSString *)userID {
    if((0 == [text length]) || (0 == [userID length])) {
        return;
    }
    NSDictionary *msg = @{ @"kind" : @"msg", @"from" : _userID, @"to" : userID, @"msg" : text };
    [_conn sendMessage: msg];
}

-(void)postMessage:(NSString *)text withSubject:(NSString *)subject {
    if((0 == [text length]) || (0 == [subject length])) {
        return;
    }
    NSDictionary *msg = @{ @"kind" : @"msg", @"from" : _userID, @"subject" : subject, @"msg" : text };
    [_conn sendMessage: msg];
}

-(void)postMessage:(NSString *)text withSubject:(NSString *)subject toUser:(NSString *)userID {
    if((0 == [text length]) || (0 == [subject length]) || (0 == [userID length])) {
        return;
    }
    NSDictionary *msg = @{ @"kind" : @"msg", @"from" : _userID, @"subject" : subject, @"msg" : text, @"to" : userID };
    [_conn sendMessage: msg];
}

-(void)markMessageAsRead:(NSNumber *)messageID {
    dispatch_async(_queue, ^{
        [_db executeUpdate: @"UPDATE messages SET read = 1 WHERE mid = ?", messageID];
        if([_db hadError]) {
            NSLog(@"Error %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
        }
    });
}

// returns an array of dictionaries, each containing the 'subject' of the conversation
// and a count of read and unread messages. also retains the latest message in each under
// the 'latest' key...
-(void)fetchConversations:(void (^)(NSArray *conversations))block {
    if(NULL == block) { return; }
    dispatch_async(_queue, ^{
        FMResultSet *rs = [_db executeQuery: @"SELECT COUNT(*),subject,read FROM messages WHERE type = 1 GROUP BY subject,read ORDER BY subject"];
        if([_db hadError]) {
            NSLog(@"Error fetching conversations %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
            dispatch_async(dispatch_get_main_queue(), ^{
                block(nil);
            });
            return;
        }
        NSMutableArray *conversations = [NSMutableArray array];
        NSString *subject = nil;
        NSMutableDictionary *dict = nil;
        while([rs next]) {
            NSString *thisSubject = [rs stringForColumnIndex: 1];
            if(NO == [subject isEqualToString: thisSubject]) {
                [dict setObject: @([[dict objectForKey: @"readCount"] intValue] + [[dict objectForKey: @"unreadCount"] intValue]) forKey: @"count"];
                subject = thisSubject;
                dict = [NSMutableDictionary new];
                [conversations addObject: dict];
                [dict setObject: subject forKey: @"subject"];
            }
            NSInteger count = [rs intForColumnIndex: 0];
            if(0 != count) { // store nothing as a shortcut
                [dict setObject: @(count) forKey: ((0 == [rs intForColumnIndex: 2]) ? @"unreadCount" : @"readCount")];
            }
            FMResultSet *rs2 = [_db executeQuery: @"SELECT mid,time,fromName,msg,read FROM messages WHERE type = 1 AND subject = ? ORDER BY mid DESC LIMIT 1"];
            if([_db hadError]) {
                NSLog(@"Error fetching latest conversation %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
            } else if([rs2 next]) {
                NSDictionary *msg = @{
                    @"mid" : [rs2 objectForColumnIndex: 0],
                    @"time" : [rs2 objectForColumnIndex: 1],
                    @"from" : [rs2 objectForColumnIndex: 2],
                    @"msg" : [rs objectForColumnIndex: 3],
                    @"read" : [rs objectForColumnIndex: 4]  };
                [dict setObject: msg forKey: @"latest"];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            block(conversations);
        });
    });
}

// returns an array of dictionaries containing all of the messages in a public conversation
// with the given subject line
-(void)fetchConversation:(NSString *)subject block:(void (^)(NSArray *conversation))block {
    if((NULL == block) || (0 == [subject length])) { return; }
    dispatch_async(_queue, ^{
        FMResultSet *rs = [_db executeQuery: @"SELECT mid,time,fromName,msg,read FROM messages WHERE type = 1 AND subject = ? ORDER BY mid", subject];
        if([_db hadError]) {
            NSLog(@"Error %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
            if(NULL != block) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    block(nil);
                });
            }
            return;
        }
        NSMutableArray *messages = [NSMutableArray array];
        while([rs next]) {
            [messages addObject: @{ @"mid" : [rs objectForColumnIndex: 0],
                                    @"time" : [rs objectForColumnIndex: 1],
                                    @"from" : [rs objectForColumnIndex: 2],
                                    @"msg" : [rs objectForColumnIndex: 3],
                                    @"read" : [rs objectForColumnIndex: 4]  } ];
        }
        if(NULL != block) {
            dispatch_async(dispatch_get_main_queue(), ^{
                block(messages);
            });
        }
    });
}

// returns an array of dictionaries representing conversations with other users. these
// will be conversations where one of the 'to' or 'from' is the current user, and the
// other is another user. the dictionary contains unread and readCounts and the other
// user's name under 'name'
-(void)fetchDirectMessages:(void (^)(NSArray *senders))block {
    if(NULL == block) { return; }
    dispatch_async(_queue, ^{
        // find unique users we recieved messages from, building unread counts
        FMResultSet *rs = [_db executeQuery: @"SELECT COUNT(*),fromName,read FROM messages WHERE type = 2 AND toName = ? GROUP BY fromName,read", _userID];
        if([_db hadError]) {
            NSLog(@"Error fetching messages to user %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
            dispatch_async(dispatch_get_main_queue(), ^{
                block(nil);
            });
            return;
        }
        NSMutableDictionary *senders = [NSMutableDictionary new];
        NSString *sender = nil;
        NSMutableDictionary *dict = nil;
        while([rs next]) {
            NSString *thisSender = [rs stringForColumnIndex: 1];
            if(NO == [sender isEqualToString: thisSender]) {
                //[dict setObject: @([[dict objectForKey: @"readCount"] intValue] + [[dict objectForKey: @"unreadCount"] intValue]) forKey: @"count"];
                sender = thisSender;
                dict = [NSMutableDictionary new];
                [senders setObject: dict forKey: sender];
                [dict setObject: sender forKey: @"name"];
            }
            NSInteger count = [rs intForColumnIndex: 0];
            if(0 != count) { // store nothing as a shortcut
                [dict setObject: @(count) forKey: ((0 == [rs intForColumnIndex: 2]) ? @"unreadCount" : @"readCount")];
            }
        }
        // also find those cases where we may not have a reply yet to a message we've sent
        rs = [_db executeQuery: @"SELECT COUNT(*),toName FROM messages WHERE type = 2 AND fromName = ? GROUP BY toName", _userID];
        if([_db hadError]) {
            NSLog(@"Error fetching messages from user %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
        } else {
            while([rs next]) {
                sender = [rs stringForColumnIndex: 1];
                dict = [senders objectForKey: sender];
                NSUInteger count = [rs intForColumnIndex: 0];
                if(nil == dict) {
                    dict = [NSMutableDictionary new];
                    [senders setObject: dict forKey: sender];
                    [dict setObject: sender forKey: @"name"];
                } else {
                    count += [[dict objectForKey: @"readCount"] integerValue];
                }
                if(0 != count) { [dict setObject: @(count) forKey: @"readCount"]; }
            }
        }
        NSMutableArray *recipients = [NSMutableArray new];
        NSArray *froms = [[senders allKeys] sortedArrayUsingSelector: @selector(localizedCaseInsensitiveCompare:)];
        for(NSString *key in froms) {
            [recipients addObject: [senders objectForKey: key]];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            block(recipients);
        });
    });
}

// return an ordered array of a particular private conversation with given user
-(void)fetchDirectMessagesFrom:(NSString *)userID block:(void (^)(NSArray *messages))block {
    if((NULL == block) || (0 == [userID length])) { return; }
    dispatch_async(_queue, ^{
        FMResultSet *rs = [_db executeQuery: @"SELECT mid,time,fromName,msg,read FROM messages WHERE type = 2 AND (fromName = ? OR toName = ?) ORDER BY mid", userID, userID];
        if([_db hadError]) {
            NSLog(@"Error %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
            dispatch_async(dispatch_get_main_queue(), ^{
                block(nil);
            });
            return;
        }
        NSMutableArray *messages = [NSMutableArray new];
        while([rs next]) {
            [messages addObject: @{ @"mid" : [rs objectForColumnIndex: 0],
                                    @"time" : [rs objectForColumnIndex: 1],
                                    @"from" : [rs objectForColumnIndex: 2],
                                    @"msg" : [rs objectForColumnIndex: 3],
                                    @"read" : [rs objectForColumnIndex: 4]  } ];
        }
        if(NULL != block) {
            dispatch_async(dispatch_get_main_queue(), ^{
                block(messages);
            });
        }
    });
}

// return an array of dictionaries representing private message threads with subjects, ordered by
// subject title. assume that we can be carrying out multiple conversations with the same subject
// with different users.
// not even sure what this should do
//-(void)fetchDirectMessagesWithSubjects:(void (^)(NSArray *subjects))block {
//}

// return an array of messages from a given private-with-subject conversation. this assumes that
// you know the name of the user and the subject you're discussing (until I work out what the
// correct method of returning the available options are...)
-(void)fetchDirectMessagesWith:(NSString *)userID subject:(NSString *)subject block:(void (^)(NSArray *messages))block {
    if((NULL == block) || (0 == [userID length]) || (0 == [subject length])) { return; }
    dispatch_async(_queue, ^{
        FMResultSet *rs = [_db executeQuery: @"SELECT mid,time,fromName,msg,read FROM messages WHERE type = 3 AND subject = ? AND (fromName = ? OR toName = ?) ORDER BY mid", subject, userID, userID];
        if([_db hadError]) {
            NSLog(@"Error %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
            dispatch_async(dispatch_get_main_queue(), ^{
                block(nil);
            });
            return;
        }
        NSMutableArray *messages = [NSMutableArray new];
        while([rs next]) {
            [messages addObject: @{
                @"mid" : [rs objectForColumnIndex: 0],
                @"time" : [rs objectForColumnIndex: 1],
                @"from" : [rs objectForColumnIndex: 2],
                @"msg" : [rs objectForColumnIndex: 3],
                @"read" : [rs objectForColumnIndex: 4]  } ];
        }
        if(NULL != block) {
            dispatch_async(dispatch_get_main_queue(), ^{
                block(messages);
            });
        }
    });
}

#pragma mark - internal

// store messages into the database. this also now is responsible for notifying of new
// messages. messages are grouped in the notification's userInfo under their types. this
// should alieviate the need for the UI to call one of the expensive -fetch... methods
-(void)storeMessages:(NSArray *)messages {
    NSMutableArray *public = [NSMutableArray new];
    NSMutableArray *private = [NSMutableArray new];
    NSMutableArray *privateWithSubject = [NSMutableArray new];
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    NSUInteger count = 0;
    for(NSDictionary *message in messages) {
        NSNumber *type = [message objectForKey: @"type"];
        switch([type intValue]) {
            case 1: [public addObject: message]; break;
            case 2: [private addObject: message]; break;
            case 3: [privateWithSubject addObject: message]; break;
            default: continue;
        }
        count++;
        NSNumber *mid = [message objectForKey: @"mid"];
        NSNumber *time = [message objectForKey: @"time"];
        NSString *from = [message objectForKey: @"from"];
        NSString *to = [message objectForKey: @"to"] ?: [NSNull null];
        NSString *subject = [message objectForKey: @"subject"] ?: [NSNull null];
        NSString *msg = [message objectForKey: @"msg"];
        [_db executeUpdate: @"INSERT OR REPLACE INTO messages (mid,type,time,fromName,toName,subject,msg) VALUES (?,?,?,?,?,?,?)", mid, type, time, from, to, subject, msg];
        if([_db hadError]) {
            NSLog(@"Error %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
        }
    }
    //NSLog(@"storeMessages took %f", CFAbsoluteTimeGetCurrent() - start);
    if(0 == count) { return; }
    NSDictionary *info = @{ @"public" : public, @"private" : private, @"privateWithSubject" : privateWithSubject };
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName: SJCChatNewMessagesNotificaiton
                                                            object: self
                                                          userInfo: info];
    });
}

#pragma mark - SJCClientDelegate

-(void)client:(SJCClient *)client didFindServers:(NSArray *)servers {
    //NSLog(@"ooh! found servers: %@", servers);
    // randomly choose the last service listed. assume that there will be only one.
    if(nil == _conn) {
        [client connectToServer: [servers lastObject]];
    }
}

-(void)client:(SJCClient *)client didOpenConnection:(SJCConnection *)connection {
    //NSLog(@"ooh! made a connection!");
    if(nil == _conn) {
        _conn = connection;
        [_conn setDelegate: self];
    }
}

#pragma mark - SJCConnectionDelegate

-(void)connectionReady:(SJCConnection *)connection {
    dispatch_async(_queue, ^{
        FMResultSet *rs = [_db executeQuery: @"SELECT MAX(mid) FROM messages"];
        if([_db hadError]) {
            NSLog(@"Error %d: %@", [_db lastErrorCode], [_db lastErrorMessage]);
        }
        NSNumber *since = @(0);
        while([rs next]) {
            since = @([rs intForColumnIndex: 0]);
        }
        NSDictionary *msg = @{ @"kind" : @"request", @"from" : _userID, @"since" : since };
        //NSLog(@"going to send %@ to %@", msg, _conn);
        [_conn sendMessage: msg];
    });
}

// write the messages we get into the database and then
-(void)connection:(SJCConnection *)connection didReceiveMessage:(NSDictionary *)message {
    //NSLog(@"got message here");
    dispatch_async(_queue, ^{
        //NSLog(@"processing message here");
        NSString *kind = [message objectForKey: @"kind"];
        if(0 == [kind length]) { return; }
        NSArray *messages = [message objectForKey: @"messages"]; // digest or broadcast
        NSNumber *lastMID = nil;
        if([kind isEqualToString: @"msg"]) {
            messages = @[ message ];
        } else if([kind isEqualToString: @"digest"]) {
            //NSLog(@"recieved a message digest");
            lastMID = [[messages lastObject] objectForKey: @"mid"];
        }
        if(0 != [messages count]) {
            [self storeMessages: messages];
            if(nil != lastMID) {
                NSDictionary *msg = @{ @"kind" : @"request", @"from" : _userID, @"since" : lastMID };
                //NSLog(@"going to send another request %@ to %@", msg, _conn);
                [_conn sendMessage: msg];
            }
        }
    });
}

-(void)connectionDidClose:(SJCConnection *)connection {
    [_conn setDelegate: nil];
    _conn = nil;
    [_client startSearch];
}

@end
