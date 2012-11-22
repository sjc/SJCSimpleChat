/*
 *  SJCClient.h
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
#import "SJCConnection.h"

@class SJCClient;

@protocol SJCClientDelegate <NSObject>
@optional
-(void)client:(SJCClient *)client didFindServers:(NSArray *)servers;
-(void)client:(SJCClient *)client didOpenConnection:(SJCConnection *)connection;
-(void)client:(SJCClient *)client failedToOpenConnection:(NSDictionary *)errorDictionary;
@end

@interface SJCClient : NSObject <SJCConnectionHolderDelegate>

@property (nonatomic,assign) NSObject <SJCClientDelegate> *delegate;

-(id)initWithServiceName:(NSString *)name;

-(void)setServerName:(NSString *)serverName;

-(void)startSearch;
-(void)stopSearch;

-(void)connectToServer:(NSNetService *)server;

-(void)connectionClosed:(SJCConnection *)connection; // SJCConnectionHolderDelegate

@end
