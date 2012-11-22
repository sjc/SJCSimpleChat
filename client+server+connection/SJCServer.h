//
//  SJCServer.h
//  SimpleChat
//
//  Created by Stuart Crook on 17/06/2012.
//  Copyright (c) 2012 JAMl. All rights reserved.
//

/*  Server which creates a bonjour service and listens for a connection
 */

#import <Foundation/Foundation.h>
#import "SJCConnection.h"

@class SJCServer;
@protocol SJCConnectionHolderDelegate;

@protocol SJCServerDelegate <NSObject>
@optional
-(void)serverEnabledBonjour:(SJCServer *)server;
-(void)server:(SJCServer *)server willOpenNewConnection:(SJCConnection *)connection;
-(void)server:(SJCServer *)server didOpenNewConnection:(SJCConnection *)connection;
-(void)serverDidRefuseNewConnection:(SJCServer *)server;
-(void)server:(SJCServer *)server willCloseConnection:(SJCConnection *)connection;
-(void)server:(SJCServer *)server didCloseConnection:(SJCConnection *)connection;
@end

@interface SJCServer : NSObject <SJCConnectionHolderDelegate>

@property (nonatomic,assign) NSObject <SJCServerDelegate> *delegate;
@property (nonatomic,readonly) NSString *serverName;
@property (nonatomic) NSUInteger maxConnections;
@property (nonatomic,readonly) NSUInteger currentConnections;

-(id)initWithServiceName:(NSString *)name;

-(void)closeConnection:(SJCConnection *)connection;

-(void)connectionClosed:(SJCConnection *)connection; // SJCConnectionHolderDelegate

@end
