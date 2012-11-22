/*
 *  SJCConnection.h
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

#import <Foundation/Foundation.h>

@class SJCServer;
@class SJCClient;
@class SJCConnection;

@protocol SJCConnectionDelegate <NSObject>
@optional
-(void)connectionReady:(SJCConnection *)connection;
-(void)connectionDidClose:(SJCConnection *)connection;
-(void)connection:(SJCConnection *)connection didReceiveData:(NSData *)data;
-(void)connection:(SJCConnection *)connection didReceiveMessage:(NSDictionary *)message;
@end

@protocol SJCConnectionHolderDelegate <NSObject>
-(void)connectionClosed:(SJCConnection *)connection;
@end

@interface SJCConnection : NSObject <NSStreamDelegate>

@property (nonatomic,assign) NSObject <SJCConnectionDelegate> *delegate;

-(id)initWithHolder:(NSObject <SJCConnectionHolderDelegate> *)holder input:(NSInputStream *)input output:(NSOutputStream *)output;

-(void)open;
-(void)close;

-(void)sendData:(NSData *)data;
-(void)sendMessage:(NSDictionary *)message;

@end
