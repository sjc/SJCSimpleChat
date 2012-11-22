//
//  SJCServer.m
//  SimpleChat
//
//  Created by Stuart Crook on 17/06/2012.
//  Copyright (c) 2012 JAMl. All rights reserved.
//

#import "SJCServer.h"
#import "TCPServer.h"
#import "SJCConnection.h"

@interface SJCServer () <TCPServerDelegate>

@end

@implementation SJCServer {
    NSString *_name;
    TCPServer *_server;
    NSMutableSet *_connections;
}

@synthesize delegate=_delegate;
@synthesize serverName=_serverName;
@synthesize maxConnections=_maxConnections;
@synthesize currentConnections=_currectConnections;

// should the server create its own runloop for doing this stuff???

-(id)initWithServiceName:(NSString *)name {
    if((self = [super init])) {
        _maxConnections = 1;
        _currectConnections = 0; // yeah, i know...
        _connections = [NSMutableSet new];
        
        _name = name;
        
        _server = [TCPServer new];
        [_server setDelegate:self];
        NSError *error = nil;
        if(_server == nil || ![_server start:&error]) {
            if (error == nil) {
                NSLog(@"Failed creating server: Server instance is nil");
            } else {
                NSLog(@"Failed creating server: %@", error);
            }
            //[self _showAlert:@"Failed creating server"];
            NSLog(@"failed to create server");
            return nil;
        }
        
        //Start advertising to clients, passing nil for the name to tell Bonjour to pick use default name
        if(![_server enableBonjourWithDomain:@"local" applicationProtocol:[TCPServer bonjourTypeFromIdentifier: name] name:nil]) {
            //[self _showAlert:@"Failed advertising server"];
            NSLog(@"failed to advertise server");
            return nil;
        }

    }
    return self;
}

-(void)closeConnection:(SJCConnection *)connection {
    if(YES == [_connections containsObject: connection]) {
        if([_delegate respondsToSelector: @selector(server:willCloseConnection:)]) {
            [_delegate server: self willCloseConnection: connection];
        }
        [self connectionClosed: connection];
        if([_delegate respondsToSelector: @selector(server:didCloseConnection:)]) {
            [_delegate server: self didCloseConnection: connection];
        }
    }
}

#pragma mark - SJCConnectionHolderDelegate

-(void)connectionClosed:(SJCConnection *)connection {
    [_connections removeObject: connection];
    _currectConnections = [_connections count];
}

#pragma mark -
//@implementation AppController (TCPServerDelegate)

-(void)serverDidEnableBonjour:(TCPServer *)server withName:(NSString *)string {
    NSLog(@"service published with name '%@'", string);
    _serverName = string;
    if([_delegate respondsToSelector: @selector(serverEnabledBonjour:)]) {
        [_delegate serverEnabledBonjour: self];
    }
}

-(void)didAcceptConnectionForServer:(TCPServer *)server inputStream:(NSInputStream *)istr outputStream:(NSOutputStream *)ostr {
	if(server != _server) { return; }

    // check whether we've maxed-out our connections
    if((0 != _maxConnections) && (_currectConnections >= _maxConnections)) {
        if([_delegate respondsToSelector: @selector(serverDidRefuseNewConnection:)]) {
            [_delegate serverDidRefuseNewConnection: self];
        }
        NSLog(@"SJCServer '%@' did refuse a connection (%d/%d)", _name, (int)_currectConnections, (int)_maxConnections);
        [istr close];
        [ostr close];
        return;
    }
    SJCConnection *conn = [[SJCConnection alloc] initWithHolder: self input: istr output: ostr];
    if([_delegate respondsToSelector: @selector(server:willOpenNewConnection:)]) {
        [_delegate server: self willOpenNewConnection: conn];
    }
    [conn open];
    _currectConnections = [_connections count];
    if([_delegate respondsToSelector: @selector(server:didOpenNewConnection:)]) {
        [_delegate server: self didOpenNewConnection: conn];
    }
    [_connections addObject: conn];
}

@end
