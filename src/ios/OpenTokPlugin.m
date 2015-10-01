//
//  OpentokPlugin.m
//
//  Copyright (c) 2012 TokBox. All rights reserved.
//  Please see the LICENSE included with this distribution for details.
//

#import "OpentokPlugin.h"

@implementation OpenTokPlugin{
    OTSession* _session;
    OTPublisher* _publisher;
    OTSubscriber* _subscriber;
    NSMutableDictionary *subscriberDictionary;
    NSMutableDictionary *connectionDictionary;
    NSMutableDictionary *streamDictionary;
    NSMutableDictionary *callbackList;
    NSMutableDictionary *publisherPosition;
    int spaceTop;
    int spaceLeft;
    int spaceWidth;
    int spaceHeight;
}

@synthesize exceptionId;

#pragma mark -
#pragma mark Cordova Methods
-(void) pluginInitialize{
    callbackList = [[NSMutableDictionary alloc] init];
    publisherPosition = [[NSMutableDictionary alloc] init];


    spaceTop = 64;
    spaceLeft = 0;
    spaceWidth = 375;
    spaceHeight = 525;
}
- (void)addEvent:(CDVInvokedUrlCommand*)command{
    NSString* event = [command.arguments objectAtIndex:0];
    [callbackList setObject:command.callbackId forKey: event];
}


#pragma mark -
#pragma mark Cordova JS - iOS bindings
#pragma mark TB Methods
/*** TB Methods
 ****/
// Called by TB.addEventListener('exception', fun...)
-(void)exceptionHandler:(CDVInvokedUrlCommand*)command{
    self.exceptionId = command.callbackId;
}

// Called by TB.initsession()
-(void)initSession:(CDVInvokedUrlCommand*)command{
    // Get Parameters
    NSString* apiKey = [command.arguments objectAtIndex:0];
    NSString* sessionId = [command.arguments objectAtIndex:1];
    
    // Create Session
    _session = [[OTSession alloc] initWithApiKey: apiKey sessionId:sessionId delegate:self];
    
    // Initialize Dictionary, contains DOM info for every stream
    subscriberDictionary = [[NSMutableDictionary alloc] init];
    streamDictionary = [[NSMutableDictionary alloc] init];
    connectionDictionary = [[NSMutableDictionary alloc] init];
    
    // Return Result
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

// Called by TB.initPublisher()
- (void)initPublisher:(CDVInvokedUrlCommand *)command{
    NSLog(@"iOS creating Publisher");
    BOOL bpubAudio = YES;
    BOOL bpubVideo = YES;
    
    // Get Parameters
    NSString* name = [command.arguments objectAtIndex:0];
    int top = [[command.arguments objectAtIndex:1] intValue];
    int left = [[command.arguments objectAtIndex:2] intValue];
    int width = [[command.arguments objectAtIndex:3] intValue];
    int height = [[command.arguments objectAtIndex:4] intValue];
    int zIndex = [[command.arguments objectAtIndex:5] intValue];
    
    [publisherPosition setObject:[NSNumber numberWithInt:left] forKey:@"left"];
    [publisherPosition setObject:[NSNumber numberWithInt:top] forKey:@"top"];
    [publisherPosition setObject:[NSNumber numberWithInt:width] forKey:@"width"];
    [publisherPosition setObject:[NSNumber numberWithInt:height] forKey:@"height"];
    [publisherPosition setObject:[NSNumber numberWithInt:0] forKey:@"expanded"];
    
    NSString* publishAudio = [command.arguments objectAtIndex:6];
    if ([publishAudio isEqualToString:@"false"]) {
        bpubAudio = NO;
    }
    NSString* publishVideo = [command.arguments objectAtIndex:7];
    if ([publishVideo isEqualToString:@"false"]) {
        bpubVideo = NO;
    }
    
    // Publish and set View
    if( ! _publisher ){
        _publisher = [[OTPublisher alloc] initWithDelegate:self name:name];
    }
    [_publisher setPublishAudio:bpubAudio];
    [_publisher setPublishVideo:bpubVideo];
    
    if (width < 80) {
        _publisher.view.userInteractionEnabled = NO;
    } else {
        _publisher.view.userInteractionEnabled = YES;
    }
        
    UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget: self action:@selector(handleSingleTap:)];
    singleTap.numberOfTapsRequired = 1;
    [_publisher.view addGestureRecognizer:singleTap];
    
    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget: self action:@selector(handleDoubleTap:)];
    doubleTap.numberOfTapsRequired = 2;
    [_publisher.view addGestureRecognizer:doubleTap];
    
    [singleTap requireGestureRecognizerToFail:doubleTap];
    
    UIPanGestureRecognizer *panner = [[UIPanGestureRecognizer alloc]
                                      initWithTarget:self action:@selector(handlePan:)];
    [_publisher.view addGestureRecognizer:panner];
    
    _publisher.view.layer.cornerRadius = round(width / 2);
    _publisher.view.layer.masksToBounds = YES;
    
    [self.webView.superview addSubview:_publisher.view];
    [_publisher.view setFrame:CGRectMake(left, top, width, height)];
    _publisher.view.layer.zPosition = zIndex;
    
    NSString* cameraPosition = [command.arguments objectAtIndex:8];
    if ([cameraPosition isEqualToString:@"back"]) {
        _publisher.cameraPosition = AVCaptureDevicePositionBack;
    }

    NSMutableDictionary* payload = [[NSMutableDictionary alloc] init];
    
    // Return to Javascript
    [callbackList setObject:command.callbackId forKey:@"publishViewChangeCallbackId"];
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary: payload];
    [pluginResult setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

// Called by TB.setViewSpace()
- (void)setViewSpace:(CDVInvokedUrlCommand*)command {
    NSLog(@"iOS setting view space");

    // Get Parameters
    spaceTop = [[command.arguments objectAtIndex:0] intValue];
    spaceLeft = [[command.arguments objectAtIndex:1] intValue];
    spaceWidth = [[command.arguments objectAtIndex:2] intValue];
    spaceHeight = [[command.arguments objectAtIndex:3] intValue];
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

// Helper function to update Views
- (void)updateView:(CDVInvokedUrlCommand*)command{
    NSString* sid = [command.arguments objectAtIndex:0];
    int top = [[command.arguments objectAtIndex:1] intValue];
    int left = [[command.arguments objectAtIndex:2] intValue];
    int width = [[command.arguments objectAtIndex:3] intValue];
    int height = [[command.arguments objectAtIndex:4] intValue];
    int zIndex = [[command.arguments objectAtIndex:5] intValue];
    int visible = [[command.arguments objectAtIndex:6] intValue];

    
    if ([sid isEqualToString:@"TBPublisher"]) {
        NSLog(@"The Width is: %d", width);
        if (visible) {
            _publisher.view.alpha = 1;
            if (width < 100) {
                if (width == 0) {
                    top = [[publisherPosition objectForKey:@"top"] intValue];
                    left = [[publisherPosition objectForKey:@"left"] intValue];
                    width = [[publisherPosition objectForKey:@"width"] intValue];
                    height = [[publisherPosition objectForKey:@"height"] intValue];
                    [publisherPosition setObject:[NSNumber numberWithInt:0] forKey:@"expanded"];
                }
                
                _publisher.view.layer.cornerRadius = round(width / 2);
                
                [_publisher.view  setUserInteractionEnabled:YES];
            }
            if (width < 80) {
                _publisher.view.userInteractionEnabled = NO;
            } else {
                _publisher.view.userInteractionEnabled = YES;
            }

            _publisher.view.frame = CGRectMake(left, top, width, height);
            /*
            [UIView animateWithDuration:0.5 animations:^{
                _publisher.view.frame = CGRectMake(_publisher.view.frame.origin.x, _publisher.view.frame.origin.y, 0,0);
                } completion:^(BOOL finished){
                    _publisher.view.frame = CGRectMake(left, top, 0,0);
                    [UIView animateWithDuration:0.5 animations:^{
                        _publisher.view.frame = CGRectMake(left, top, width, height);
                    }];
                }
            ];
            */
            _publisher.view.layer.zPosition = zIndex;
        } else {
            _publisher.view.alpha = 0;
        }
    }
    
    // Pulls the subscriber object from dictionary to prepare it for update
    OTSubscriber* streamInfo = [subscriberDictionary objectForKey:sid];
    
    if (streamInfo) {
        streamInfo.view.frame = CGRectMake(left, top, width, height);
        if (visible) {
            // Reposition the video feeds!
            [UIView animateWithDuration:0.5
                             animations:^{                                             _publisher.view.alpha = 1;
                             }];
            if (width == 86) {
                streamInfo.view.layer.cornerRadius = round(width / 2);
            } else {
                streamInfo.view.layer.cornerRadius = 0;
            }
            streamInfo.view.layer.zPosition = zIndex;
        } else {
            [UIView animateWithDuration:0.5
                             animations:^{                                             _publisher.view.alpha = 0;
                             }];
        }
    }
    
    CDVPluginResult* callbackResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [callbackResult setKeepCallbackAsBool:YES];
    //[self.commandDelegate sendPluginResult:callbackResult toSuccessCallbackString:command.callbackId];
    [self.commandDelegate sendPluginResult:callbackResult callbackId:command.callbackId];
}

- (void)handleSingleTap:(UITapGestureRecognizer *)recognizer {
    CGRect frame;
    if ([[publisherPosition objectForKey:@"expanded"] intValue] == 1) {
        int top = [[publisherPosition objectForKey:@"top"] intValue];
        int left = [[publisherPosition objectForKey:@"left"] intValue];
        int width = [[publisherPosition objectForKey:@"width"] intValue];
        int height = [[publisherPosition objectForKey:@"height"] intValue];
        [publisherPosition setObject:[NSNumber numberWithInt:0] forKey:@"expanded"];
        
        _publisher.view.layer.cornerRadius = round(width / 2);
        
        frame = CGRectMake(left, top, width, height);

        //[_publisher.view  setUserInteractionEnabled:YES];
    } else {
        [publisherPosition setObject:[NSNumber numberWithInt:_publisher.view.frame.origin.x] forKey:@"left"];
        [publisherPosition setObject:[NSNumber numberWithInt:_publisher.view.frame.origin.y] forKey:@"top"];
        [publisherPosition setObject:[NSNumber numberWithInt:_publisher.view.frame.size.width] forKey:@"width"];
        [publisherPosition setObject:[NSNumber numberWithInt:_publisher.view.frame.size.height] forKey:@"height"];
        [publisherPosition setObject:[NSNumber numberWithInt:1] forKey:@"expanded"];
        
        _publisher.view.layer.cornerRadius = 0;

        frame = CGRectMake(spaceLeft, spaceTop, spaceWidth, spaceHeight);
        
        //[_publisher.view  setUserInteractionEnabled:NO];
    }
    [_publisher.view setFrame:frame];

    NSMutableDictionary* payload = [[NSMutableDictionary alloc] init];
    [payload setObject:[NSNumber numberWithInt:_publisher.view.frame.origin.x] forKey:@"left"];
    [payload setObject:[NSNumber numberWithInt:_publisher.view.frame.origin.y] forKey:@"top"];
    [payload setObject:[NSNumber numberWithInt:_publisher.view.frame.size.width] forKey:@"width"];
    [payload setObject:[NSNumber numberWithInt:_publisher.view.frame.size.height] forKey:@"height"];
    
    // Return to Javascript
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary: payload];
    [pluginResult setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:[callbackList objectForKey:@"publishViewChangeCallbackId"]];
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)recognizer {
    if (_publisher.cameraPosition == AVCaptureDevicePositionBack) {
        [_publisher setCameraPosition:AVCaptureDevicePositionFront];
    } else {
        [_publisher setCameraPosition:AVCaptureDevicePositionBack];
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)panner {
    UIView *draggedView = panner.view;
    if ([[publisherPosition objectForKey:@"expanded"] intValue] == 0) {
        CGPoint offset = [panner translationInView:draggedView.superview];
        CGPoint center = draggedView.center;
        int left = center.x + offset.x;
        int top = center.y + offset.y;
        
        int width = _publisher.view.frame.size.width / 2;
        int height = _publisher.view.frame.size.height / 2;
        
        if (left < width + spaceLeft) {
            left = width + spaceLeft;
        }
        if (top < width + spaceTop) {
            top = width + spaceTop;
        }
        if (left > (spaceLeft + spaceWidth - height)) {
            left = (spaceLeft + spaceWidth - height);
        }
        if (top > (spaceTop + spaceHeight - height)) {
            top = (spaceTop + spaceHeight - height);
        }
        
        draggedView.center = CGPointMake(left, top);
        
        // Reset translation to zero so on the next `panWasRecognized:` message, the
        // translation will just be the additional movement of the touch since now.
        [panner setTranslation:CGPointZero inView:draggedView.superview];
        if(panner.state == UIGestureRecognizerStateBegan) {
            //All fingers are lifted.
            draggedView.alpha = 0.3;
            NSLog(@"Pan started");
        }
    }
    if(panner.state == UIGestureRecognizerStateEnded) {
        //All fingers are lifted.
        draggedView.alpha = 1;
        NSLog(@"Pan ended");

        NSMutableDictionary* payload = [[NSMutableDictionary alloc] init];
        [payload setObject:[NSNumber numberWithInt:_publisher.view.frame.origin.x] forKey:@"left"];
        [payload setObject:[NSNumber numberWithInt:_publisher.view.frame.origin.y] forKey:@"top"];
        [payload setObject:[NSNumber numberWithInt:_publisher.view.frame.size.width] forKey:@"width"];
        [payload setObject:[NSNumber numberWithInt:_publisher.view.frame.size.height] forKey:@"height"];
        CDVPluginResult* callbackResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary: payload];
        [callbackResult setKeepCallbackAsBool:YES];
        [self.commandDelegate sendPluginResult:callbackResult callbackId:[callbackList objectForKey:@"publishViewChangeCallbackId"]];
    }
}

#pragma mark Publisher Methods
- (void)publishAudio:(CDVInvokedUrlCommand*)command{
    NSString* publishAudio = [command.arguments objectAtIndex:0];
    NSLog(@"iOS Altering Audio publishing state, %@", publishAudio);
    BOOL pubAudio = YES;
    if ([publishAudio isEqualToString:@"false"]) {
        pubAudio = NO;
    }
    [_publisher setPublishAudio:pubAudio];
}
- (void)publishVideo:(CDVInvokedUrlCommand*)command{
    NSString* publishVideo = [command.arguments objectAtIndex:0];
    NSLog(@"iOS Altering Video publishing state, %@", publishVideo);
    BOOL pubVideo = YES;
    if ([publishVideo isEqualToString:@"false"]) {
        pubVideo = NO;
    }
    [_publisher setPublishVideo:pubVideo];
}
- (void)visible:(CDVInvokedUrlCommand*)command{
    NSString* visibleString = [command.arguments objectAtIndex:0];
    NSLog(@"iOS Altering Video visiblility, %@", visibleString);
    BOOL visible = YES;
    if ([visibleString isEqualToString:@"false"]) {
        visible = NO;
    }
    [_publisher.view setHidden:!visible];
}
- (void)destroyPublisher:(CDVInvokedUrlCommand *)command{
    NSLog(@"iOS Destroying Publisher");
    // Unpublish publisher
    [_session unpublish:_publisher error:nil];
    
    // Remove publisher view
    if (_publisher) {
        [_publisher.view removeFromSuperview];
    }
    
    // Return to Javascript
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}


#pragma mark Session Methods
- (void)connect:(CDVInvokedUrlCommand *)command{
    NSLog(@"iOS Connecting to Session");
    
    // Get Parameters
    NSString* tbToken = [command.arguments objectAtIndex:0];
    [_session connectWithToken:tbToken error:nil];
}

// Called by session.disconnect()
- (void)disconnect:(CDVInvokedUrlCommand*)command{
    [_session disconnect:nil];
}

// Called by session.publish(top, left)
- (void)publish:(CDVInvokedUrlCommand*)command{
    NSLog(@"iOS Publish stream to session");
    [_session publish:_publisher error:nil];
    
    // Return to Javascript
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

// Called by session.unpublish(...)
- (void)unpublish:(CDVInvokedUrlCommand*)command{
    NSLog(@"iOS Unpublishing publisher");
    [_session unpublish:_publisher error:nil];
}

// Called by session.subscribe(streamId, top, left)
- (void)subscribe:(CDVInvokedUrlCommand*)command{
    NSLog(@"iOS subscribing to stream");
    
    // Get Parameters
    NSString* sid = [command.arguments objectAtIndex:0];
    
    int top = [[command.arguments objectAtIndex:1] intValue];
    int left = [[command.arguments objectAtIndex:2] intValue];
    //int width = [[command.arguments objectAtIndex:3] intValue];
    //int height = [[command.arguments objectAtIndex:4] intValue];
    //int zIndex = [[command.arguments objectAtIndex:5] intValue];

    int width = 86;
    int height = 86;
    
    // Acquire Stream, then create a subscriber object and put it into dictionary
    OTStream* myStream = [streamDictionary objectForKey:sid];
    OTSubscriber* sub = [[OTSubscriber alloc] initWithStream:myStream delegate:self];
    [_session subscribe:sub error:nil];
    
    if ([[command.arguments objectAtIndex:6] isEqualToString:@"false"]) {
        [sub setSubscribeToAudio: NO];
    }
    if ([[command.arguments objectAtIndex:7] isEqualToString:@"false"]) {
        [sub setSubscribeToVideo: NO];
    }
    [subscriberDictionary setObject:sub forKey:myStream.streamId];
    
    [sub.view setFrame:CGRectMake(left, top, width, height)];
    
    [self.webView.superview addSubview:sub.view];

    sub.view.layer.zPosition = 3;
    sub.view.layer.cornerRadius = round(width / 2);
    sub.view.layer.masksToBounds = YES;
    

    // Return to JS event handler
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

// Called by session.unsubscribe(streamId, top, left)
- (void)unsubscribe:(CDVInvokedUrlCommand*)command{
    NSLog(@"iOS unSubscribing to stream");
    //Get Parameters
    NSString* sid = [command.arguments objectAtIndex:0];
    OTSubscriber * subscriber = [subscriberDictionary objectForKey:sid];
    [_session unsubscribe:subscriber error:nil];
    [subscriber.view removeFromSuperview];
    [subscriberDictionary removeObjectForKey:sid];
}

// Called by session.unsubscribe(streamId, top, left)
- (void)signal:(CDVInvokedUrlCommand*)command{
    NSLog(@"iOS signaling to connectionId %@", [command.arguments objectAtIndex:2]);
    OTConnection* c = [connectionDictionary objectForKey: [command.arguments objectAtIndex:2]];
    NSLog(@"iOS signaling to connection %@", c);
    [_session signalWithType:[command.arguments objectAtIndex:0] string:[command.arguments objectAtIndex:1] connection:c error:nil];
}


#pragma mark -
#pragma mark Delegates
#pragma mark Subscriber Delegates
/*** Subscriber Methods
 ****/
- (void)subscriberDidConnectToStream:(OTSubscriberKit*)sub{
    NSLog(@"iOS Connected To Stream");
    NSMutableDictionary* eventData = [[NSMutableDictionary alloc] init];
    NSString* streamId = sub.stream.streamId;
    [eventData setObject:streamId forKey:@"streamId"];
    [self triggerJSEvent: @"sessionEvents" withType: @"subscribedToStream" withData: eventData];
    
}
- (void)subscriber:(OTSubscriber*)subscrib didFailWithError:(OTError*)error{
    NSLog(@"subscriber didFailWithError %@", error);
    NSMutableDictionary* eventData = [[NSMutableDictionary alloc] init];
    NSString* streamId = subscrib.stream.streamId;
    NSNumber* errorCode = [NSNumber numberWithInt:1600];
    [eventData setObject: errorCode forKey:@"errorCode"];
    [eventData setObject:streamId forKey:@"streamId"];
    [self triggerJSEvent: @"sessionEvents" withType: @"subscribedToStream" withData: eventData];
}


#pragma mark Session Delegates
- (void)sessionDidConnect:(OTSession*)session{
    NSLog(@"iOS Connected to Session");
    
    NSMutableDictionary* sessionDict = [[NSMutableDictionary alloc] init];
    
    // SessionConnectionStatus
    NSString* connectionStatus = @"";
    if (session.sessionConnectionStatus==OTSessionConnectionStatusConnected) {
        connectionStatus = @"OTSessionConnectionStatusConnected";
    }else if (session.sessionConnectionStatus==OTSessionConnectionStatusConnecting) {
        connectionStatus = @"OTSessionConnectionStatusConnecting";
    }else if (session.sessionConnectionStatus==OTSessionConnectionStatusDisconnecting) {
        connectionStatus = @"OTSessionConnectionStatusDisconnected";
    }else{
        connectionStatus = @"OTSessionConnectionStatusFailed";
    }
    [sessionDict setObject:connectionStatus forKey:@"sessionConnectionStatus"];
    
    // SessionId
    [sessionDict setObject:session.sessionId forKey:@"sessionId"];
    
    [connectionDictionary setObject: session.connection forKey: session.connection.connectionId];
    
    
    // After session is successfully connected, the connection property is available
    NSMutableDictionary* eventData = [[NSMutableDictionary alloc] init];
    [eventData setObject:@"status" forKey:@"connected"];
    NSMutableDictionary* connectionData = [self createDataFromConnection: session.connection];
    [eventData setObject: connectionData forKey: @"connection"];
    
    
    NSLog(@"object for session is %@", sessionDict);
    
    // After session dictionary is constructed, return the result!
    //    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:sessionDict];
    //    NSString* sessionConnectCallback = [callbackList objectForKey:@"sessSessionConnected"];
    //    [self.commandDelegate sendPluginResult:pluginResult callbackId:sessionConnectCallback];
    
    
    [self triggerJSEvent: @"sessionEvents" withType: @"sessionConnected" withData: eventData];
}


- (void)session:(OTSession *)session connectionCreated:(OTConnection *)connection
{
    [connectionDictionary setObject: connection forKey: connection.connectionId];
    NSMutableDictionary* data = [[NSMutableDictionary alloc] init];
    NSMutableDictionary* connectionData = [self createDataFromConnection: connection];
    [data setObject: connectionData forKey: @"connection"];
    [self triggerJSEvent: @"sessionEvents" withType: @"connectionCreated" withData: data];
}

- (void)session:(OTSession *)session connectionDestroyed:(OTConnection *)connection
{
    [connectionDictionary removeObjectForKey: connection.connectionId];
    NSMutableDictionary* data = [[NSMutableDictionary alloc] init];
    NSMutableDictionary* connectionData = [self createDataFromConnection: connection];
    [data setObject: connectionData forKey: @"connection"];
    [self triggerJSEvent: @"sessionEvents" withType: @"connectionDestroyed" withData: data];
}
- (void)session:(OTSession*)mySession streamCreated:(OTStream*)stream{
    NSLog(@"iOS Received Stream");
    [streamDictionary setObject:stream forKey:stream.streamId];
    [self triggerStreamCreated: stream withEventType: @"sessionEvents"];
}
- (void)session:(OTSession*)session streamDestroyed:(OTStream *)stream{
    NSLog(@"iOS Drop Stream");
    
    OTSubscriber * subscriber = [subscriberDictionary objectForKey:stream.streamId];
    if (subscriber) {
        NSLog(@"subscriber found, unsubscribing");
        [_session unsubscribe:subscriber error:nil];
        [subscriber.view removeFromSuperview];
        [subscriberDictionary removeObjectForKey:stream.streamId];
    }
    [self triggerStreamDestroyed: stream withEventType: @"sessionEvents"];
}
- (void)session:(OTSession*)session didFailWithError:(OTError*)error {
    NSLog(@"Error: Session did not Connect");
    NSLog(@"Error: %@", error);
    NSNumber* code = [NSNumber numberWithInt:[error code]];
    NSMutableDictionary* err = [[NSMutableDictionary alloc] init];
    [err setObject:error.localizedDescription forKey:@"message"];
    [err setObject:code forKey:@"code"];
    
    if (self.exceptionId) {
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary: err];
        [pluginResult setKeepCallbackAsBool:YES];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.exceptionId];
    }
}
- (void)sessionDidDisconnect:(OTSession*)session{
    NSString* alertMessage = [NSString stringWithFormat:@"Session disconnected: (%@)", session.sessionId];
    NSLog(@"sessionDidDisconnect (%@)", alertMessage);
    
    // Setting up event object
    for ( id key in subscriberDictionary ) {
        OTSubscriber* aStream = [subscriberDictionary objectForKey:key];
        [aStream.view removeFromSuperview];
    }
    [subscriberDictionary removeAllObjects];
    if( _publisher ){
        [_publisher.view removeFromSuperview];
    }
    
    // Setting up event object
    NSMutableDictionary* eventData = [[NSMutableDictionary alloc] init];
    [eventData setObject:@"clientDisconnected" forKey:@"reason"];
    [self triggerJSEvent: @"sessionEvents" withType: @"sessionDisconnected" withData: eventData];
}
-(void) session:(OTSession *)session receivedSignalType:(NSString *)type fromConnection:(OTConnection *)connection withString:(NSString *)string{
    
    NSLog(@"iOS Session Received signal from Connection: %@ with id %@", connection, [connection connectionId]);
    NSMutableDictionary* data = [[NSMutableDictionary alloc] init];
    [data setObject: type forKey: @"type"];
    [data setObject: string forKey: @"data"];
    if (connection.connectionId) {
        [data setObject: connection.connectionId forKey: @"connectionId"];
        [self triggerJSEvent: @"sessionEvents" withType: @"signalReceived" withData: data];
    }
}


#pragma mark Publisher Delegates
- (void)publisher:(OTPublisherKit *)publisher streamCreated:(OTStream *)stream{
    [streamDictionary setObject:stream forKey:stream.streamId];
    [self triggerStreamCreated: stream withEventType: @"publisherEvents"];
}
- (void)publisher:(OTPublisherKit*)publisher streamDestroyed:(OTStream *)stream{
    if (_publisher) {
        [_publisher.view removeFromSuperview];
    }
    
    [self triggerStreamDestroyed: stream withEventType: @"publisherEvents"];
}
- (void)publisher:(OTPublisher*)publisher didFailWithError:(NSError*) error {
    NSLog(@"iOS Publisher didFailWithError");
    NSMutableDictionary* err = [[NSMutableDictionary alloc] init];
    [err setObject:error.localizedDescription forKey:@"message"];
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary: err];
    [pluginResult setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.exceptionId];
}

#pragma mark -
#pragma mark Helper Methods
- (void)triggerStreamCreated: (OTStream*) stream withEventType: (NSString*) eventType{
    NSMutableDictionary* data = [[NSMutableDictionary alloc] init];
    NSMutableDictionary* streamData = [self createDataFromStream: stream withConnectionId:YES];
    [data setObject: streamData forKey: @"stream"];
    [self triggerJSEvent: eventType withType: @"streamCreated" withData: data];
}
- (void)triggerStreamDestroyed: (OTStream*) stream withEventType: (NSString*) eventType{
    [streamDictionary removeObjectForKey: stream.streamId];
    
    NSMutableDictionary* data = [[NSMutableDictionary alloc] init];
    NSMutableDictionary* streamData = [self createDataFromStream: stream withConnectionId:NO];
    [data setObject: streamData forKey: @"stream"];
    [self triggerJSEvent: eventType withType: @"streamDestroyed" withData: data];
}
- (NSMutableDictionary*)createDataFromConnection:(OTConnection*)connection{
    NSLog(@"iOS creating data from stream: %@", connection);
    NSMutableDictionary* connectionData = [[NSMutableDictionary alloc] init];
    [connectionData setObject: connection.connectionId forKey: @"connectionId" ];
    [connectionData setObject: [NSString stringWithFormat:@"%.0f", [connection.creationTime timeIntervalSince1970]] forKey: @"creationTime" ];
    if (connection.data) {
        [connectionData setObject: connection.data forKey: @"data" ];
    }
    return connectionData;
}
- (NSMutableDictionary*)createDataFromStream:(OTStream*)stream withConnectionId:(BOOL)toggle{
    NSMutableDictionary* streamData = [[NSMutableDictionary alloc] init];
    if (toggle && [stream.connection isKindOfClass:[OTConnection class]]) {
        [streamData setObject: stream.connection.connectionId forKey: @"connectionId" ];
    }
    [streamData setObject: [NSString stringWithFormat:@"%.0f", [stream.creationTime timeIntervalSince1970]] forKey: @"creationTime" ];
    [streamData setObject: [NSNumber numberWithInt:-999] forKey: @"fps" ];
    [streamData setObject: [NSNumber numberWithBool: stream.hasAudio] forKey: @"hasAudio" ];
    [streamData setObject: [NSNumber numberWithBool: stream.hasVideo] forKey: @"hasVideo" ];
    [streamData setObject: stream.name forKey: @"name" ];
    [streamData setObject: stream.streamId forKey: @"streamId" ];
    return streamData;
}
- (void)triggerJSEvent:(NSString*)event withType:(NSString*)type withData:(NSMutableDictionary*) data{
    NSMutableDictionary* message = [[NSMutableDictionary alloc] init];
    [message setObject:type forKey:@"eventType"];
    [message setObject:data forKey:@"data"];
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:message];
    [pluginResult setKeepCallbackAsBool:YES];
    
    NSString* callbackId = [callbackList objectForKey:event];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
}



/***** Notes
 
 
 NSString *stringObtainedFromJavascript = [command.arguments objectAtIndex:0];
 CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString: stringObtainedFromJavascript];
 
 if(YES){
 [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackID]];
 }else{
 //Call  the Failure Javascript function
 [self.commandDelegate [pluginResult toErrorCallbackString:self.callbackID]];
 }
 
 ******/


@end

