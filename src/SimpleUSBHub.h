//
//  SimpleUSBHub.h
//
//  Created by rexq57 on 2018/1/6.
//

#import <Foundation/Foundation.h>
#import <PeerTalk/PTChannel.h>

typedef enum {
    SimpleUSBHubStateServerReady,       // 服务端: 已准备好
    SimpleUSBHubStateClientConnecting,  // 客户端: 连接中
    SimpleUSBHubStateConnected,         // 已连接
    SimpleUSBHubStateDisconnected,      // 失去连接
}SimpleUSBHubState;

@interface SimpleUSBHubClient : NSObject

@property (nonatomic, readonly) uint32_t port;
@property (nonatomic) float connectInterval;    // 尝试连接间歇秒数

- (instancetype) initWithPort:(uint32_t) port;

// 开始监听
- (void) startWithStateCallback:(void(^)(SimpleUSBHubState state)) stateCallback receiveCallback:(void(^)(uint32_t type, PTData* payload)) receiveCallback;

// 停止监听，必须调用stop，否则对象无法释放
- (void) stop;

// 发送数据
- (void) sendFrameOfType:(uint32_t) type withPalload:(dispatch_data_t) payload;

@end

@interface SimpleUSBHubServer : NSObject

@property (nonatomic, readonly) uint32_t port;

- (instancetype) initWithPort:(uint32_t) port;

// 开始监听
- (void) startWithStateCallback:(void(^)(SimpleUSBHubState state)) stateCallback receiveCallback:(void(^)(uint32_t type, PTData* payload)) receiveCallback;

// 停止监听，必须调用stop，否则对象无法释放
- (void) stop;

// 发送数据
- (void) sendFrameOfType:(uint32_t) type withPalload:(dispatch_data_t) payload;

@end
