/*
 *  SJCClient.m
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

#import "SJCClient.h"
#import "SJCConnection.h"
#import "TCPServer.h"

@interface SJCClient () <NSNetServiceBrowserDelegate, NSNetServiceDelegate>
-(void)stopCurrentResolve;
-(void)sortAndNotify;
@end

@implementation SJCClient {
    NSString *_name;

    NSString *_serverName;
	NSNetService *_ownEntry;

	NSMutableArray *_services;
    
	NSNetServiceBrowser *_netServiceBrowser;
	NSNetService *_currentResolve;

    NSMutableSet *_connections;
}

@synthesize delegate=_delegate;

-(id)initWithServiceName:(NSString *)name {
    if((self = [super init])) {
        _name = name;
        _services = [NSMutableArray new];
        _connections = [NSMutableSet new];
    }
    return self;
}

// so we don't return ourselves in the list of services, if we're running a server from the same app
-(void)setServerName:(NSString *)serverName {
    _serverName = serverName;
    _ownEntry = nil;
    for(NSNetService *service in _services) {
        if([_serverName isEqualToString: [service name]]) {
            _ownEntry = service;
            break;
        }
    }
    if(nil != _ownEntry) {
        [_services removeObject: _ownEntry];
    }
}

-(void)startSearch {
    [self stopCurrentResolve];
    [_netServiceBrowser stop];
    [_services removeAllObjects];
        
    _netServiceBrowser = [[NSNetServiceBrowser alloc] init];
    if(nil == _netServiceBrowser) {
        NSLog(@"The NSNetServiceBrowser couldn't be allocated and initialized.");
        return;
    }
    
    [_netServiceBrowser setDelegate: self];
    // this call to TCPServer can probably be tidied away so we don't need to include the class
    [_netServiceBrowser searchForServicesOfType: [TCPServer bonjourTypeFromIdentifier: _name] inDomain: @"local"];
}

-(void)stopSearch {
    [_netServiceBrowser setDelegate: nil];
    [_netServiceBrowser stop];
    _netServiceBrowser = nil;
}

-(void)connectToServer:(id)server {
    [self stopCurrentResolve];
    [self stopSearch];
    
    _currentResolve = server;
	[_currentResolve setDelegate: self];
	[_currentResolve resolveWithTimeout: 30.0];
}

-(void)connectionClosed:(SJCConnection *)connection {
    [_connections removeObject: connection];
}

-(void)stopCurrentResolve {
    [_currentResolve setDelegate: nil];
	[_currentResolve stop];
	_currentResolve = nil;
}

-(void)sortAndNotify {
    // alphabetically by name
    [_services sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        return [[obj1 name] localizedCaseInsensitiveCompare: [obj2 name]];
    }];

    if([_delegate respondsToSelector: @selector(client:didFindServers:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [_delegate client: self didFindServers: _services];
        });
    }
}

#pragma mark - NSNetServiceBrowserDelegate

-(void)netServiceBrowser:(NSNetServiceBrowser *)netServiceBrowser didRemoveService:(NSNetService *)service moreComing:(BOOL)moreComing {
	// If a service went away, stop resolving it if it's currently being resolved,
	// remove it from the list and update the table view if no more events are queued.
	
	if((nil != _currentResolve) && (YES == [service isEqual: _currentResolve])) {
		[self stopCurrentResolve];
	}
	[_services removeObject: service];
	if(_ownEntry == service) {
		_ownEntry = nil;
    }
	
	// If moreComing is NO, it means that there are no more messages in the queue from the Bonjour daemon, so we should update the UI.
	// When moreComing is set, we don't update the UI so that it doesn't 'flash'.
	if(NO == moreComing) {
		[self sortAndNotify];
	}
}

-(void)netServiceBrowser:(NSNetServiceBrowser *)netServiceBrowser didFindService:(NSNetService *)service moreComing:(BOOL)moreComing {
    NSLog(@"got service: %@", [service name]);
    
    // if we have a server name (we're running a server alongside the client) check we don't add it
    if ([_serverName isEqual: [service name]]) {
        _ownEntry = service;
    } else {
		[_services addObject: service];
    }
    
	// If moreComing is NO, it means that there are no more messages in the queue from the Bonjour daemon, so we should update the UI.
	// When moreComing is set, we don't update the UI so that it doesn't 'flash'.
	if(NO == moreComing) {
		[self sortAndNotify];
	}
}	

#pragma mark - NSNetServiceDelegate

-(void)netService:(NSNetService *)sender didNotResolve:(NSDictionary *)errorDict {
    NSLog(@"service did not resolve: %@", errorDict);
    if([_delegate respondsToSelector: @selector(client:failedToOpenConnection:)]) {
        [_delegate client: self failedToOpenConnection: errorDict];
    }
	[self stopCurrentResolve];
}

-(void)netServiceDidResolveAddress:(NSNetService *)service {
	assert(service == _currentResolve);
	
	//[service retain];
	[self stopCurrentResolve];
	
	//[self.delegate browserViewController:self didResolveInstance:service];
	//[service release];
    
    // note the following method returns _inStream and _outStream with a retain count that the caller must eventually release
    NSInputStream *input;
    NSOutputStream *output;
	if(NO == [service getInputStream: &input outputStream: &output]) {
		//[self _showAlert:@"Failed connecting to server"];
        NSLog(@"failed to open streams for service");
        // yeah, need to tell the delegate about this
		return;
	}

    SJCConnection *conn = [[SJCConnection alloc] initWithHolder: self input: input output: output];
    // need 'will open' warning?
    [conn open];
    if([_delegate respondsToSelector: @selector(client:didOpenConnection:)]) {
        [_delegate client: self didOpenConnection: conn];
    }
    [_connections addObject: conn];
}

@end
