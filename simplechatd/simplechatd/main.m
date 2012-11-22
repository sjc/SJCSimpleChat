/*
 *  main.m
 *  simplechatd
 *
 *  Created by Stuart Crook on 17/11/2012.
 *  Copyright (c) 2012 Stuart Crook. All rights reserved.
 *
 *  A simple chat daemon using the SJCChatServer classes.
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

/*  NOTE: The SJCChatServer class uses FMDB for message storage. By default, this
 *  Xcode project expects to find the FMDB source in a directory name 'src'
 *  parallel to the enclosing folder (eg. ../../../src)
 */

#import <Foundation/Foundation.h>
#import "SJCChatServer.h"

#define VERSION_MAJOR   0
#define VERSION_MINOR   1

#define DEFAULT_SERVER_NAME     "sjc-simple-chat"
#define DEFAULT_DATABASE_PATH   "/Library/Application Support/simplechatd/"

// print the about message
void PrintVersion( void ) {
    printf("simplechatd by Stuart Crook, Just About Managing ltd -- v%d.%d\n", VERSION_MAJOR, VERSION_MINOR);
}

// print the help instructions
void PrintHelp( void ) {
    printf("The following options are recognised:\n");
    printf("  --version             display version information and exit\n");
    printf("  --help                display this help message and exit\n");
    printf("  --verbose             turn on verbose logging to stdout\n");
    printf("  --name <server-name>  set the name the chat server will be advertised under\n");
    printf("                        (default is '%s')\n", DEFAULT_SERVER_NAME);
    printf("  --mem                 use a volatile, in-memory SQLite database for messages\n");
    printf("  --dbpath <path>       store the SQLite message database at the given path\n");
    printf("                        (default is '%s')\n", DEFAULT_DATABASE_PATH);
    printf("  --dbname <name>       store the SQLite message database with this filename\n");
    printf("                        (default is <server-name>.sqlite)\n");
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSString *serverName = nil;
        NSString *dbPath = nil;
        NSString *dbName = nil;
        BOOL useInMemoryDatabase = NO;
        BOOL verbose = NO;
        
        // have we got anything to work with?
        //if(argc <= 1) {
        //    PrintHelp();
        //    return 0;
        //}
        
        for(int i = 1; i < argc; i++) {
            const char *arg = argv[i];
            if(0 == strcmp(arg, "--version")) {
                PrintVersion();
                return 0;

            } else if(0 == strcmp(arg, "--help")) {
                PrintHelp();
                return 0;
            
            } else if(0 == strcmp(arg, "--verbose")) {
                verbose = YES;
                printf("verbose logging enabled\n");
                
            } else if(0 == strcmp(arg, "--name")) {
                if(++i == argc) {
                    printf("no name parameter supplied\n");
                    return 0;
                }
                serverName = [NSString stringWithCString: argv[i] encoding: NSASCIIStringEncoding];
                if(0 == [serverName length]) {
                    printf("no name parameter supplied\n");
                    return 0;
                }

            } else if(0 == strcmp(arg, "--mem")) {
                useInMemoryDatabase = YES;
                
            } else if(0 == strcmp(arg, "--dbpath")) {
                if(++i == argc) {
                    printf("no database path parameter supplied\n");
                    return 0;
                }
                dbPath = [NSString stringWithCString: argv[i] encoding: NSASCIIStringEncoding];
                if(0 == [dbPath length]) {
                    printf("no database path parameter supplied\n");
                    return 0;
                }

            } else if(0 == strcmp(arg, "--dbname")) {
                if(++i == argc) {
                    printf("no database name parameter supplied\n");
                    return 0;
                }
                dbName = [NSString stringWithCString: argv[i] encoding: NSASCIIStringEncoding];
                if(0 == [dbName length]) {
                    printf("no database name parameter supplied\n");
                    return 0;
                }
            
            } else {
                printf("met unrecognised option '%s'. fleeing\n", arg);
                return 0;
            }
        }

        // check server name (or use the default)
        if(0 == [serverName length]) {
            // fall back to default name (hardcoded above)
            serverName = [NSString stringWithCString: DEFAULT_SERVER_NAME encoding: NSASCIIStringEncoding];
            if(verbose) { printf("no server name supplied, using default '%s'\n", DEFAULT_SERVER_NAME); }
        } else if(verbose) {
            printf("setting server name to '%s'\n", [serverName UTF8String]);
        }

        // check that we have a valid database file path
        NSString *path = nil;
        if(YES == useInMemoryDatabase) {
            if(0 != [dbPath length]) {
                printf("cannot use --dbpath option with --mem\n");
                return 0;
            }
            if(0 != [dbName length]) {
                printf("cannot use --dbname option with --mem\n");
                return 0;
            }
            path = @":memory:";
            if(verbose) { printf("using an in-memory message database\n"); }
            
        } else {
            // build the path to the on-disk SQLite database
            if(0 == [dbPath length]) {
                dbPath = [NSString stringWithCString: DEFAULT_DATABASE_PATH encoding: NSASCIIStringEncoding];
                if(verbose) { printf("using default database path '%s'\n", DEFAULT_DATABASE_PATH); }
            }
            dbPath = [dbPath stringByExpandingTildeInPath];
            if(0 == [dbName length]) {
                dbName = [serverName stringByAppendingPathExtension: @"sqlite"];
                if(verbose) { printf("built database filename '%s'\n", [dbName UTF8String]); }
            }
            // check that the path is valid, creating it if not
            NSError *error;
            if(NO == [[NSFileManager defaultManager] createDirectoryAtPath: dbPath
                                               withIntermediateDirectories: YES
                                                                attributes: @{ NSFilePosixPermissions : @(0777) }
                                                                     error: &error])
            {
                NSLog(@"unable to create path '%@': %@", dbPath, error);
                return 0;
            }
            path = [dbPath stringByAppendingPathComponent: dbName];
            if(verbose) { printf("database path will be '%s'\n", [path UTF8String]); }
        }

        if(0 == [path length]) {
            printf("no database path built\n");
            return 0;
        }

        // create chat server with serverName and path
        SJCChatServer *server = [[SJCChatServer alloc] initWithServerName: serverName dbPath: path];
/*        id token = [[NSNotificationCenter defaultCenter] addObserverForName: SJCChatServerStatusNotification
                                                                     object: nil
                                                                      queue: nil
                                                                 usingBlock: ^(NSNotification *note)
        {
            printf("got a notification thingy");
        }];*/
        [server start];
        
        do {
            @autoreleasepool {
                [[NSRunLoop mainRunLoop] runUntilDate: [NSDate distantFuture]];
            }
        } while(YES);

/*        [[NSNotificationCenter defaultCenter] removeObserver: token]; */
    }
    return 0;
}

