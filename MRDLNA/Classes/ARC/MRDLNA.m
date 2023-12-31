//
//  MRDLNA.m
//  MRDLNA
//
//  Created by MccRee on 2018/5/4.
//

#import "MRDLNA.h"
#import "StopAction.h"

@interface MRDLNA()<CLUPnPServerDelegate, CLUPnPResponseDelegate>

@property(nonatomic, strong) CLUPnPServer *upd;              //MDS服务器
@property(nonatomic, strong) NSMutableArray *dataArray;

@property(nonatomic, strong) CLUPnPRenderer *render;         //MDR渲染器
@property(nonatomic, copy) NSString *volume;
@property(nonatomic, assign) NSInteger seekTime;
@property(nonatomic, assign) BOOL isPlaying;


@property (nonatomic, strong) NSTimer *timer;

@end

@implementation MRDLNA

+ (MRDLNA *)sharedMRDLNAManager
{
    static MRDLNA *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.upd = [CLUPnPServer shareServer];
        self.upd.searchTime = 5;
        self.upd.delegate = self;
        self.dataArray = [NSMutableArray array];
    }
    return self;
}

- (void)startSearch
{
    CLLog(@"airPlay-startSearch");
    [self.upd start];
}

- (void)refresSearch
{
    CLLog(@"airPlay-refresSearch");
    [self.upd refresh];
}

- (void)stopSearch
{
    CLLog(@"airPlay-stopSearch");
    [self.upd stop];
}


/**
 ** DLNA投屏
 */
- (void)startDLNA
{
    CLLog(@"airPlay-startDLNA");
    [self initCLUPnPRendererAndDlnaPlay];
}
/**
 ** DLNA投屏
 ** 【流程: 停止 ->设置代理 ->设置Url -> 播放】
 */
- (void)startDLNAAfterStop
{
    CLLog(@"airPlay-startDLNAAfterStop");
    StopAction *action = [[StopAction alloc]initWithDevice:self.device Success:^{
        [self initCLUPnPRendererAndDlnaPlay];
        
    } failure:^{
        [self initCLUPnPRendererAndDlnaPlay];
    }];
    [action executeAction];
}

- (void)timerEvent:(NSTimer *)timer
{
    [self.render getPositionInfo];
}

- (void)removeTimer
{
    [_timer invalidate];
    _timer = nil;
}

/**
 初始化CLUPnPRenderer
 */
- (void)initCLUPnPRendererAndDlnaPlay
{
    CLLog(@"airPlay-initCLUPnPRendererAndDlnaPlay:%@",self.device.friendlyName);
    self.render = [[CLUPnPRenderer alloc] initWithModel:self.device];
    self.render.delegate = self;
    self.render.userAgent = self.userAgent;
    self.render.referer = self.referer;
    
//    [self.render stop];
    [self playTheURL:self.playUrl];
    
    [self.render getVolume];
}
/**
 退出DLNA
 */
- (void)endDLNA
{
    CLLog(@"airPlay-endDLNA");
    self.isConnected = NO;//主动置为NO，不然stop指令可能是失败的
    [self.render stop];
    [self removeTimer];
}

/**
 播放
 */
- (void)dlnaPlay
{
    CLLog(@"airPlay-dlnaPlay");
    [self.render play];
}


/**
 暂停
 */
- (void)dlnaPause
{
    CLLog(@"airPlay-dlnaPause");
    [self.render pause];
}

/**
 设置音量 volume建议传0-100之间字符串
 */
- (void)volumeChanged:(NSString *)volume
{
    self.volume = volume;
    [self.render setVolumeWith:volume];
}

- (void)addVolume
{
    NSString *volume = [NSString stringWithFormat:@"%zd",MIN(self.volume.integerValue+5, 100)];
    CLLog(@"airPlay-addVolume :%@",volume);
    [self volumeChanged:volume];
}

- (void)reduceVolume
{
    NSString *volume = [NSString stringWithFormat:@"%zd",MAX(self.volume.integerValue-5, 0)];
    CLLog(@"airPlay-reduceVolume :%@",volume);
    [self volumeChanged:volume];
}

/**
 播放进度条
 */
- (void)seekChanged:(NSInteger)seek
{
    CLLog(@"airPlay-seekChanged :%zd",seek);
    self.seekTime = seek;
    NSString *seekStr = [self timeFormatted:seek];
    [self.render seekToTarget:seekStr Unit:unitREL_TIME];
}


/**
 播放进度单位转换成string
 */
- (NSString *)timeFormatted:(NSInteger)totalSeconds
{
    NSInteger seconds = totalSeconds % 60;
    NSInteger minutes = (totalSeconds / 60) % 60;
    NSInteger hours = totalSeconds / 3600;
    return [NSString stringWithFormat:@"%02ld:%02ld:%02ld",(long)hours, (long)minutes, (long)seconds];
}

/**
 播放切集
 */
- (void)playTheURL:(NSString *)url
{
    self.playUrl = url;
    [self removeTimer];
    [self.render setAVTransportURL:url];
    
    
    if (!_timer) {
        _timer = [NSTimer timerWithTimeInterval:3 target:self selector:@selector(timerEvent:) userInfo:nil repeats:YES];
        [_timer fire];
        [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
    }
}

#pragma mark -- 搜索协议CLUPnPDeviceDelegate回调
- (void)upnpSearchChangeWithResults:(NSArray<CLUPnPDevice *> *)devices
{
    CLLog(@"airPlay - 搜索到设备：%zd", devices.count);
    NSMutableArray *deviceMarr = [NSMutableArray array];
    for (CLUPnPDevice *device in devices) {
        CLLog(@"airPlay - 设备: %@, %@ - %@", device.uuid,device.friendlyName, device.modelName);
        // 只返回匹配到视频播放的设备
        if ([device.uuid containsString:serviceType_AVTransport]) {
            [deviceMarr addObject:device];
            CLLog(@"airPlay - 匹配:%@", device.friendlyName);
        }
    }
    if (self.connentDelegate && [self.connentDelegate respondsToSelector:@selector(searchDLNAResult:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.connentDelegate searchDLNAResult:[deviceMarr copy]];
        });
    }
    self.dataArray = deviceMarr;
}

- (void)upnpSearchErrorWithError:(NSError *)error
{
//    CLLog(@"DLNA_Error======>%@", error);
    if (self.connentDelegate && [self.connentDelegate respondsToSelector:@selector(searchDLNAFailue:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.connentDelegate searchDLNAFailue:error];
        });
    }
}

- (void)upnpDidEndSearch
{
    if (self.connentDelegate && [self.connentDelegate respondsToSelector:@selector(searchDLNAFinish)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.connentDelegate searchDLNAFinish];
        });
    }
}

#pragma mark - CLUPnPResponseDelegate
- (void)upnpSetAVTransportURIResponse
{
//    self.isConnected = YES;
    
    [self.render play];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.playDelegate && [self.playDelegate respondsToSelector:@selector(dlnaStartPlay)]) {
            [self.playDelegate dlnaStartPlay];
        }
    });
    
    if (self.isConnected) {
        return;
    }
    self.isConnected = YES;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.playDelegate && [self.playDelegate respondsToSelector:@selector(dlnaPlayDidConnent)]) {
            [self.playDelegate dlnaPlayDidConnent];
        }
    });
}

- (void)upnpGetTransportInfoResponse:(CLUPnPTransportInfo *)info
{
//    CLLog(@"%@ === %@", info.currentTransportState, info.currentTransportStatus);
    if (!([info.currentTransportState isEqualToString:@"PLAYING"] || [info.currentTransportState isEqualToString:@"TRANSITIONING"])) {
        [self.render play];

    }
}

- (void)upnpPlayResponse
{
    [self changePlayState:DLNAPlayStatePlaying];
}

- (void)upnpPauseResponse
{
    [self changePlayState:DLNAPlayStatePause];
}

- (void)upnpStopResponse
{
    self.isConnected = NO;
    
    [self changePlayState:DLNAPlayStateStopped];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.playDelegate && [self.playDelegate respondsToSelector:@selector(dlnaEndPlay)]) {
            [self.playDelegate dlnaEndPlay];
        }
    });
}

- (void)upnpUndefinedResponse:(NSString *)resXML postXML:(NSString *)postXML
{
    CLLog(@"airPlay-DLNA -- upnpUndefinedResponse :%@ - %@", resXML, postXML);
    [self changePlayState:DLNAPlayStateError];
}

- (void)upnpErrorDomain:(NSError *)error
{
    
}

- (void)upnpSeekResponse
{
    
}

- (void)upnpPreviousResponse
{
    
}

- (void)upnpNextResponse
{
    
}

- (void)upnpSetVolumeResponse
{
    CLLog(@"airPlay-upnpSetVolumeResponse : %@",self.volume);
}

- (void)upnpSetNextAVTransportURIResponse
{
    
}

- (void)upnpGetVolumeResponse:(NSString *)volume
{
    CLLog(@"airPlay-upnpGetVolumeResponse : %@",volume);
    _volume = volume;
}

- (void)upnpGetPositionInfoResponse:(CLUPnPAVPositionInfo *)info
{
    if (self.playDelegate && [self.playDelegate respondsToSelector:@selector(dlnaPositionInfo:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.playDelegate dlnaPositionInfo:info];
        });
    }
    
    if (info.trackDuration && info.trackDuration<=(info.relTime+2)) {//超过2s就无能为力了
        [self removeTimer];
        [self changePlayState:DLNAPlayStateCommpleted];
    }
}

- (void)changePlayState:(DLNAPlayState)state
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.playDelegate && [self.playDelegate respondsToSelector:@selector(dlnaDidChangePlayState:)]) {
            [self.playDelegate dlnaDidChangePlayState:state];
        }
    });
    
//    if (state==DLNAPlayStateStopped || state==DLNAPlayStateError || state==DLNAPlayStateCommpleted) {
//        [self removeTimer];
//    }
}

#pragma mark Set&Get
- (void)setSearchTime:(NSInteger)searchTime
{
    _searchTime = searchTime;
    self.upd.searchTime = searchTime;
}
@end
