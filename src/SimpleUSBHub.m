//
//  SimpleUSBHub.m
//
//  Created by rexq57 on 2018/1/6.
//

#import "SimpleUSBHub.h"
#import <PeerTalk/Peertalk.h>

#if TARGET_OS_IPHONE
#import <UIKit/UIApplication.h>
#endif

NSString* const ReconnectNotification = @"ReconnectNotification";

@interface SimpleUSBHubClient() <PTChannelDelegate>
{
    PTUSBHub *_usbHub; // 不使用 [PTUSBHub sharedHub]，因为它的实现里只调用了一次启动，中途回调链断掉，就无法再次启动
    
    dispatch_queue_t _notConnectedQueue;
    NSNumber* _connectingToDeviceID;
    NSNumber* _connectedDeviceID;
}

@property (nonatomic) PTChannel* connectedChannel;
@property (nonatomic, copy) void(^stateCallback)(SimpleUSBHubState);
@property (nonatomic, copy) void(^receiveCallback)(uint32_t, PTData*);

- (void) startListeningForDevice;
- (void) connectToUSBDevice;

@end

@implementation SimpleUSBHubClient

- (instancetype) initWithPort:(uint32_t) port
{
    if ((self = [self init]))
    {
        _port = port;
        _connectInterval = 1.0;
        
        _notConnectedQueue = dispatch_queue_create("SimpleUSBHub.notConnectedQueue", DISPATCH_QUEUE_SERIAL);
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_process_ReconnectNotification:) name:ReconnectNotification object:nil];
        
        _usbHub = [PTUSBHub new];
    }
    return self;
}

- (void) startWithStateCallback:(void(^)(SimpleUSBHubState state)) stateCallback receiveCallback:(void(^)(uint32_t type, PTData* payload)) receiveCallback
{
    self.stateCallback = stateCallback;
    self.receiveCallback = receiveCallback;
    
    [self startListeningForDevice];
}

- (void) dealloc
{
}

- (void) stop
{
    id object = _usbHub;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:PTUSBDeviceDidAttachNotification object:object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:PTUSBDeviceDidDetachNotification object:object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ReconnectNotification object:nil];
}

- (void) sendFrameOfType:(uint32_t) type withPalload:(dispatch_data_t) payload
{
    if (_connectedChannel) {
        PTChannel* channel = self.connectedChannel;
        if (channel)
        {
            [channel sendFrameOfType:type tag:channel.protocol.newTag withPayload:payload callback:^(NSError *error) {
                if (error)
                    NSLog(@"发送失败: %@", error);
            }];
        }
    }
    else {
        NSLog(@"send fail: 没有建立连接");
    }
}

#pragma mark - Private

- (void) _process_ReconnectNotification:(NSNotification * _Nonnull) note
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_connectInterval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        dispatch_async(self->_notConnectedQueue, ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                self.stateCallback(SimpleUSBHubStateClientConnecting); // 连接中
                [self connectToUSBDevice];
            });
        });
    });
}

- (void) _process_PTUSBDeviceDidAttachNotification:(NSNotification * _Nonnull) note
{
    NSDictionary* userInfo = note.userInfo;
    NSNumber* deviceID = [userInfo objectForKey:@"DeviceID"];
    //        NSNumber* deviceID = userInfo[@"DeviceID"];
    if (deviceID)
    {
        self->_connectingToDeviceID = deviceID;
        [self connectToUSBDevice];
    }
}

- (void) _process_PTUSBDeviceDidDetachNotification:(NSNotification * _Nonnull) note
{
    NSDictionary* userInfo = note.userInfo;
    NSNumber* deviceID = [userInfo objectForKey:@"DeviceID"];
    //        NSNumber* deviceID = userInfo[@"DeviceID"];
    if ([self->_connectingToDeviceID isEqual:deviceID])
    {
        self->_connectingToDeviceID = nil;
        [self.connectedChannel close];
    }
}

- (void) startListeningForDevice
{
    id object = _usbHub;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_process_PTUSBDeviceDidAttachNotification:) name:PTUSBDeviceDidAttachNotification object:object];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_process_PTUSBDeviceDidDetachNotification:) name:PTUSBDeviceDidDetachNotification object:object];
    
    // 必须在监听器设置后调用
    [_usbHub listenOnQueue:dispatch_get_main_queue() onStart:^(NSError *error) {
        if (error) {
            NSLog(@"PTUSBHub failed to initialize: %@", error);
        }
    } onEnd:nil];
}

- (void) connectToUSBDevice
{
    @synchronized (self)
    {
        PTChannel* channel = [PTChannel channelWithDelegate:self];
        channel.userInfo = _connectingToDeviceID;
        
        uint32_t port = _port;
        
        [channel connectToPort:port overUSBHub:_usbHub deviceID:_connectingToDeviceID callback:^(NSError *error) {
            
            if (error) {
                if (error.domain == NSPOSIXErrorDomain && (error.code == ECONNREFUSED || error.code == ETIMEDOUT)) {
                    // this is an expected state
                    NSLog(@"error: %@", error);
                } else {
                    NSLog(@"Failed to connect to 127.0.0.1:%d: %@", port, error);
                }
                if (channel.userInfo == self->_connectingToDeviceID) {
                    [self _enqueueConnectToUSBDevice];
                }
            } else {
                self->_connectedDeviceID = self->_connectingToDeviceID;
                self.connectedChannel = channel;
                NSLog(@"Connected device");
                
                self.stateCallback(SimpleUSBHubStateConnected); // 已连接
            }
        }];
    }
}

- (void) _enqueueConnectToUSBDevice {
    
    [[NSNotificationCenter defaultCenter] postNotificationName:ReconnectNotification object:nil];
}


#pragma - PTChannelDelegate

- (void)ioFrameChannel:(PTChannel*)channel didReceiveFrameOfType:(uint32_t)type tag:(uint32_t)tag payload:(PTData*)payload
{
    self.receiveCallback(type, payload);
}

- (void)ioFrameChannel:(PTChannel*)channel didEndWithError:(NSError*)error {
    if (_connectedDeviceID && [_connectedDeviceID isEqualToNumber:channel.userInfo]) {
        //        [self didDisconnectFromDevice:connectedDeviceID_];
        _connectedDeviceID = nil;
    }
    
    if (_connectedChannel == channel) {
        
        self.stateCallback(SimpleUSBHubStateDisconnected); // 连接已断开
        
        NSLog(@"%@", [NSString stringWithFormat:@"Disconnected from %@", channel.userInfo]);
        self.connectedChannel = nil;
        
        // 重新连接
        [self _enqueueConnectToUSBDevice];
    }
}

@end

@interface SimpleUSBHubServer() <PTChannelDelegate>

@property (nonatomic) PTChannel* channel;
@property (nonatomic) PTChannel* peerChannel;

@property (nonatomic, copy) void(^stateCallback)(SimpleUSBHubState);
@property (nonatomic, copy) void(^receiveCallback)(uint32_t, PTData*);

- (void) startListening;

@end

@implementation SimpleUSBHubServer

- (instancetype) initWithPort:(uint32_t) port
{
    if ((self = [self init]))
    {
        _port = port;
    }
    return self;
}

- (void) startWithStateCallback:(void(^)(SimpleUSBHubState state)) stateCallback receiveCallback:(void(^)(uint32_t type, PTData* payload)) receiveCallback
{
    self.stateCallback = stateCallback;
    self.receiveCallback = receiveCallback;
    
    [self startListening];
}

- (void) dealloc
{
}

- (void) stop
{
    [_channel cancel];
    _channel = nil;
}

- (void) startListening
{
    uint32_t port = _port;
    
    PTChannel* channel = [PTChannel channelWithDelegate:self];
    [channel listenOnPort:port IPv4Address:INADDR_LOOPBACK callback:^(NSError *error) {
        if (error) {
            NSLog(@"%@", [NSString stringWithFormat:@"Failed to listen on 127.0.0.1:%d: %@", port, error]);
        } else {
            NSLog(@"%@", [NSString stringWithFormat:@"Listening on 127.0.0.1:%d", port]);
            self.channel = channel;
            
            self.stateCallback(SimpleUSBHubStateServerReady);
        }
    }];
}

- (void) sendFrameOfType:(uint32_t) type withPalload:(dispatch_data_t) payload
{
    if (_peerChannel) {
        PTChannel* channel = self.peerChannel;
        if (channel)
        {
            [channel sendFrameOfType:type tag:channel.protocol.newTag withPayload:payload callback:^(NSError *error) {
                if (error)
                    NSLog(@"发送失败: %@", error);
            }];
        }
    }
    else {
        NSLog(@"send fail: 没有建立连接");
    }
}

#pragma mark - PTChannelDelegate

- (void)ioFrameChannel:(PTChannel*)channel didReceiveFrameOfType:(uint32_t)type tag:(uint32_t)tag payload:(PTData*)payload
{
//    if (type == ARDataCollectionFrameTypeARDataMessage) {
//        //        PTExampleTextFrame *textFrame = (PTExampleTextFrame*)payload.data;
//        //        textFrame->length = ntohl(textFrame->length);
//        //        NSString *message = [[NSString alloc] initWithBytes:textFrame->utf8text length:textFrame->length encoding:NSUTF8StringEncoding];
//        //        [self appendOutputMessage:[NSString stringWithFormat:@"[%@]: %@", channel.userInfo, message]];
//    } else if (type == SimpleUSBHubFrameTypePing && _peerChannel) {
//        [_peerChannel sendFrameOfType:SimpleUSBHubFrameTypePong tag:tag withPayload:nil callback:nil];
//    }
    
    self.receiveCallback(type, payload); // 接收数据
}

// Invoked to accept an incoming frame on a channel. Reply NO ignore the
// incoming frame. If not implemented by the delegate, all frames are accepted.
- (BOOL)ioFrameChannel:(PTChannel*)channel shouldAcceptFrameOfType:(uint32_t)type tag:(uint32_t)tag payloadSize:(uint32_t)payloadSize {
    if (channel != _peerChannel) {
        // A previous channel that has been canceled but not yet ended. Ignore.
        return NO;
    }
//    else if (type != ARDataCollectionFrameTypeARDataMessage && type != ARDataCollectionFrameTypePing) {
//        NSLog(@"Unexpected frame of type %u", type);
//        [channel close];
//        return NO;
//    }
    else {
        return YES;
    }
}

- (void)ioFrameChannel:(PTChannel*)channel didEndWithError:(NSError*)error {
    if (error) {
        NSLog(@"%@", [NSString stringWithFormat:@"%@ ended with error: %@", channel, error]);
        
        // 发生错误导致通道关闭，需要重新开启
        [self startListening];
        
    } else {
        NSLog(@"%@", [NSString stringWithFormat:@"Disconnected from %@", channel.userInfo]);
        
        self.stateCallback(SimpleUSBHubStateDisconnected); // 断开连接
    }
}

- (void)ioFrameChannel:(PTChannel*)channel didAcceptConnection:(PTChannel*)otherChannel fromAddress:(PTAddress*)address {
    // Cancel any other connection. We are FIFO, so the last connection
    // established will cancel any previous connection and "take its place".
    if (_peerChannel) {
        [_peerChannel cancel];
    }
    
    // Weak pointer to current connection. Connection objects live by themselves
    // (owned by its parent dispatch queue) until they are closed.
    _peerChannel = otherChannel;
    _peerChannel.userInfo = address;
    NSLog(@"%@", [NSString stringWithFormat:@"Connected to %@", address]);
    
    self.stateCallback(SimpleUSBHubStateConnected); // 连接成功
}

@end
