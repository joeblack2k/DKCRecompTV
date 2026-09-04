#import <Foundation/Foundation.h>
#import <AVFAudio/AVFAudio.h>
#import <GameController/GameController.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>

#include <cmath>
#include <cstdint>
#include <cstring>
#include <limits>
#include <memory>
#include <string>
#include <vector>

#include "audio_ring.hpp"
#include "dkc_game_core.h"
#include "input_mapper.hpp"

#ifndef DKC_CORE_FUNCTION
#define DKC_CORE_FUNCTION dkc2_game_core
#endif

extern "C" const DKCGameCoreV1 *DKC_CORE_FUNCTION(void);

namespace {

constexpr double kSnesPixelAspect = 7.0 / 6.0;
constexpr uint32_t kMaxGameFramesPerDisplay = 4;

static NSString *DkcCoreString(const char *value) {
  if (!value)
    return nil;
  return [NSString stringWithUTF8String:value];
}

static bool DkcSafeCoreID(NSString *coreID) {
  if (!coreID.length || [coreID isEqualToString:@"."] ||
      [coreID isEqualToString:@".."])
    return false;
  return ![coreID containsString:@"/"] &&
         ![coreID containsString:@"\\"];
}

static size_t DkcFramebufferBytes(const DKCGameCoreInfo *info) {
  if (!info || info->framebuffer_width == 0 ||
      info->framebuffer_height == 0 || info->framebuffer_bytes_per_pixel == 0 ||
      info->framebuffer_pitch_bytes < info->framebuffer_width *
                                          info->framebuffer_bytes_per_pixel)
    return 0;
  if (info->framebuffer_height >
      std::numeric_limits<size_t>::max() / info->framebuffer_pitch_bytes)
    return 0;
  return static_cast<size_t>(info->framebuffer_height) *
         info->framebuffer_pitch_bytes;
}

static MTLViewport DkcViewportForSize(CGSize drawableSize,
                                      const DKCGameCoreInfo *info) {
  const NSUInteger drawableWidth =
      drawableSize.width > 0.0 ? static_cast<NSUInteger>(drawableSize.width)
                               : 0;
  const NSUInteger drawableHeight =
      drawableSize.height > 0.0
          ? static_cast<NSUInteger>(drawableSize.height)
          : 0;
  if (!info || drawableWidth == 0 || drawableHeight == 0)
    return MTLViewport{0.0, 0.0, 0.0, 0.0, 0.0, 1.0};

  const double sourceAspect =
      static_cast<double>(info->framebuffer_width) /
      static_cast<double>(info->framebuffer_height);
  const double displayAspect = sourceAspect * kSnesPixelAspect;
  NSUInteger viewportWidth = drawableWidth;
  NSUInteger viewportHeight = static_cast<NSUInteger>(
      std::floor(static_cast<double>(viewportWidth) / displayAspect));
  if (viewportHeight > drawableHeight) {
    viewportHeight = drawableHeight;
    viewportWidth = static_cast<NSUInteger>(
        std::floor(static_cast<double>(viewportHeight) * displayAspect));
  }

  const double originX =
      static_cast<double>(drawableWidth - viewportWidth) / 2.0;
  const double originY =
      static_cast<double>(drawableHeight - viewportHeight) / 2.0;
  return MTLViewport{originX,
                     originY,
                     static_cast<double>(viewportWidth),
                     static_cast<double>(viewportHeight),
                     0.0,
                     1.0};
}

static NSString *DkcResultDescription(DKCGameCoreResult result) {
  switch (result) {
  case DKC_GAME_CORE_INVALID_ARGUMENT:
    return @"invalid argument";
  case DKC_GAME_CORE_ALREADY_BOOTED:
    return @"already booted";
  case DKC_GAME_CORE_ROM_REJECTED:
    return @"ROM rejected";
  case DKC_GAME_CORE_NOT_BOOTED:
    return @"not booted";
  case DKC_GAME_CORE_BUFFER_TOO_SMALL:
    return @"framebuffer too small";
  case DKC_GAME_CORE_RUNTIME_ERROR:
    return @"runtime error";
  case DKC_GAME_CORE_OK:
    return @"ok";
  }
  return @"unknown error";
}

static bool DkcButtonPressed(GCControllerButtonInput *button) {
  return button && button.isPressed;
}

static DKCControllerSample DkcSampleForGamepad(
    GCExtendedGamepad *gamepad) {
  DKCControllerSample sample;
  if (!gamepad)
    return sample;

  sample.connected = true;
  sample.apple_a = DkcButtonPressed(gamepad.buttonA);
  sample.apple_b = DkcButtonPressed(gamepad.buttonB);
  sample.apple_x = DkcButtonPressed(gamepad.buttonX);
  sample.apple_y = DkcButtonPressed(gamepad.buttonY);
  sample.left_shoulder = DkcButtonPressed(gamepad.leftShoulder);
  sample.right_shoulder = DkcButtonPressed(gamepad.rightShoulder);
  sample.options = DkcButtonPressed(gamepad.buttonOptions);
  sample.menu = DkcButtonPressed(gamepad.buttonMenu);
  sample.up = DkcButtonPressed(gamepad.dpad.up);
  sample.down = DkcButtonPressed(gamepad.dpad.down);
  sample.left = DkcButtonPressed(gamepad.dpad.left);
  sample.right = DkcButtonPressed(gamepad.dpad.right);
  sample.stick_x = gamepad.leftThumbstick.xAxis.value;
  sample.stick_y = gamepad.leftThumbstick.yAxis.value;
  return sample;
}

} // namespace

@interface DKCGameViewController : UIViewController <MTKViewDelegate> {
  const DKCGameCoreV1 *core_;
  const DKCGameCoreInfo *info_;
  DKCGameCoreInstance *instance_;

  MTKView *metalView_;
  UILabel *errorLabel_;
  id<MTLDevice> device_;
  id<MTLCommandQueue> commandQueue_;
  id<MTLRenderPipelineState> pipelineState_;
  id<MTLTexture> framebufferTexture_;
  AVAudioEngine *audioEngine_;
  AVAudioSourceNode *audioSourceNode_;

  NSData *romData_;
  NSString *romPath_;
  NSString *saveDirectoryPath_;
  std::string saveDirectoryUTF8_;
  std::vector<uint8_t> framebuffer_;
  std::shared_ptr<DKCAudioRing> audioRing_;
  std::vector<int16_t> audioPcm_;
  std::vector<DKCFloatStereoFrame> audioFloatPcm_;

  double framePeriod_;
  double nextFrameTime_;
  double audioFramesPerVideoFrame_;
  double audioFrameAccumulator_;
  bool booted_;
  bool suspended_;
  bool loggedFirstVideo_;
  bool loggedFirstAudio_;
  bool loggedAudioOverrun_;
}

- (void)pauseForLifecycle;
- (void)resumeForLifecycle;
- (BOOL)configureAudio;
- (BOOL)startAudio;
- (void)stopAudio;
- (void)teardownAudio;
- (BOOL)renderAudioForFrame;
- (uint32_t)controllerMaskForFrame;
- (void)controllerDidConnect:(NSNotification *)notification;
- (void)controllerDidDisconnect:(NSNotification *)notification;
@end

@implementation DKCGameViewController

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = UIColor.blackColor;
  NSNotificationCenter *notificationCenter =
      [NSNotificationCenter defaultCenter];
  [notificationCenter addObserver:self
                         selector:@selector(controllerDidConnect:)
                             name:GCControllerDidConnectNotification
                           object:nil];
  [notificationCenter addObserver:self
                         selector:@selector(controllerDidDisconnect:)
                             name:GCControllerDidDisconnectNotification
                           object:nil];
  [self boot];
}

- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  metalView_.frame = self.view.bounds;
}

- (void)showError:(NSString *)reason {
  [self teardownAudio];
  booted_ = false;
  suspended_ = false;
  nextFrameTime_ = 0.0;
  if (metalView_) {
    metalView_.paused = YES;
    metalView_.delegate = nil;
    [metalView_ removeFromSuperview];
    metalView_ = nil;
  }

  NSLog(@"DKCRecompTV boot failure: %@", reason ?: @"unknown error");
  errorLabel_ = [[UILabel alloc] initWithFrame:CGRectZero];
  errorLabel_.text = @"Unable to start game.";
  errorLabel_.textAlignment = NSTextAlignmentCenter;
  errorLabel_.textColor = UIColor.whiteColor;
  errorLabel_.numberOfLines = 1;
  errorLabel_.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
  errorLabel_.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:errorLabel_];
  [NSLayoutConstraint activateConstraints:@[
    [errorLabel_.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
    [errorLabel_.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    [errorLabel_.leadingAnchor
        constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor
                                    constant:32.0],
    [errorLabel_.trailingAnchor
        constraintLessThanOrEqualToAnchor:self.view.trailingAnchor
                                   constant:-32.0],
  ]];
}

- (void)failWithReason:(NSString *)reason {
  [self showError:reason];
}

- (void)boot {
  core_ = DKC_CORE_FUNCTION();
  if (!core_ || !core_->info || !core_->boot || !core_->run_frame ||
      !core_->draw_frame || !core_->render_audio || !core_->suspend ||
      !core_->resume) {
    [self failWithReason:@"core ABI is incomplete"];
    return;
  }

  info_ = core_->info;
  if (info_->abi_version != DKC_GAME_CORE_ABI_VERSION ||
      info_->framebuffer_format != DKC_GAME_CORE_PIXEL_FORMAT_BGRA8 ||
      info_->framebuffer_bytes_per_pixel != 4 ||
      info_->framebuffer_width == 0 || info_->framebuffer_height == 0 ||
      info_->framebuffer_pitch_bytes == 0 ||
      !std::isfinite(info_->video_cadence_hz) ||
      info_->video_cadence_hz <= 0.0 ||
      info_->audio_format != DKC_GAME_CORE_AUDIO_FORMAT_S16_INTERLEAVED ||
      info_->audio_channels != 2 || info_->audio_sample_rate_hz == 0 ||
      DkcFramebufferBytes(info_) == 0) {
    [self failWithReason:@"unsupported core format"];
    return;
  }

  audioFramesPerVideoFrame_ =
      static_cast<double>(info_->audio_sample_rate_hz) /
      info_->video_cadence_hz;
  const double audioPcmFrames =
      std::ceil(audioFramesPerVideoFrame_) + 1.0;
  if (!std::isfinite(audioFramesPerVideoFrame_) ||
      audioFramesPerVideoFrame_ <= 0.0 || !std::isfinite(audioPcmFrames) ||
      audioPcmFrames >
          static_cast<double>(std::numeric_limits<size_t>::max() / 2)) {
    [self failWithReason:@"unsupported core audio cadence"];
    return;
  }

  NSString *coreID = DkcCoreString(info_->id);
  if (!DkcSafeCoreID(coreID)) {
    [self failWithReason:@"invalid core id"];
    return;
  }

  NSString *applicationSupport =
      NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                          NSUserDomainMask, YES)
          .firstObject;
  if (!applicationSupport.length) {
    [self failWithReason:@"application support is unavailable"];
    return;
  }

  NSString *coreDirectory =
      [[applicationSupport stringByAppendingPathComponent:@"DKCRecompTV"]
          stringByAppendingPathComponent:coreID];
  romPath_ = [coreDirectory stringByAppendingPathComponent:@"Game.sfc"];
  saveDirectoryPath_ = [coreDirectory stringByAppendingPathComponent:@"Saves"];

  NSError *fileError = nil;
  if (![[NSFileManager defaultManager]
          createDirectoryAtPath:saveDirectoryPath_
     withIntermediateDirectories:YES
                      attributes:nil
                           error:&fileError]) {
    [self failWithReason:fileError.localizedDescription ?: @"save directory failed"];
    return;
  }

  romData_ = [NSData dataWithContentsOfFile:romPath_ options:0 error:&fileError];
  if (!romData_ || romData_.length == 0) {
    [self failWithReason:fileError.localizedDescription ?: @"Game.sfc is missing"];
    return;
  }

  const char *saveDirectoryCString = saveDirectoryPath_.UTF8String;
  if (!saveDirectoryCString) {
    [self failWithReason:@"save path is not UTF-8"];
    return;
  }
  saveDirectoryUTF8_ = saveDirectoryCString;

  char coreError[256] = {};
  DKCGameCoreBootConfig bootConfig = {};
  bootConfig.rom_bytes =
      static_cast<const uint8_t *>(romData_.bytes);
  bootConfig.rom_size = static_cast<size_t>(romData_.length);
  bootConfig.save_directory = saveDirectoryUTF8_.c_str();
  bootConfig.error_message = coreError;
  bootConfig.error_message_capacity = sizeof(coreError);

  const DKCGameCoreResult bootResult =
      core_->boot(&bootConfig, &instance_);
  if (bootResult != DKC_GAME_CORE_OK || !instance_) {
    NSString *detail = DkcCoreString(coreError);
    [self failWithReason:detail ?: DkcResultDescription(bootResult)];
    return;
  }

  try {
    framebuffer_.resize(DkcFramebufferBytes(info_));
    const size_t pcmFrames = static_cast<size_t>(audioPcmFrames);
    audioPcm_.resize(pcmFrames * 2);
    audioFloatPcm_.resize(pcmFrames);
  } catch (...) {
    [self failWithReason:@"host buffer allocation failed"];
    return;
  }

  device_ = MTLCreateSystemDefaultDevice();
  if (!device_) {
    [self failWithReason:@"Metal is unavailable"];
    return;
  }
  commandQueue_ = [device_ newCommandQueue];
  id<MTLLibrary> library = [device_ newDefaultLibrary];
  id<MTLFunction> vertexFunction =
      [library newFunctionWithName:@"dkc_vertex_main"];
  id<MTLFunction> fragmentFunction =
      [library newFunctionWithName:@"dkc_fragment_main"];
  if (!commandQueue_ || !library || !vertexFunction || !fragmentFunction) {
    [self failWithReason:@"Metal functions are unavailable"];
    return;
  }

  MTLRenderPipelineDescriptor *pipelineDescriptor =
      [[MTLRenderPipelineDescriptor alloc] init];
  pipelineDescriptor.vertexFunction = vertexFunction;
  pipelineDescriptor.fragmentFunction = fragmentFunction;
  pipelineDescriptor.colorAttachments[0].pixelFormat =
      MTLPixelFormatBGRA8Unorm;
  NSError *pipelineError = nil;
  pipelineState_ =
      [device_ newRenderPipelineStateWithDescriptor:pipelineDescriptor
                                              error:&pipelineError];
  if (!pipelineState_) {
    [self failWithReason:pipelineError.localizedDescription
                         ?: @"Metal pipeline creation failed"];
    return;
  }

  MTLTextureDescriptor *textureDescriptor =
      [MTLTextureDescriptor
          texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                      width:info_->framebuffer_width
                                     height:info_->framebuffer_height
                                  mipmapped:NO];
  textureDescriptor.usage = MTLTextureUsageShaderRead;
  textureDescriptor.storageMode = MTLStorageModeShared;
  framebufferTexture_ = [device_ newTextureWithDescriptor:textureDescriptor];
  if (!framebufferTexture_) {
    [self failWithReason:@"framebuffer texture creation failed"];
    return;
  }

  if (![self configureAudio] || ![self startAudio]) {
    [self failWithReason:@"audio start failed"];
    return;
  }

  metalView_ = [[MTKView alloc] initWithFrame:self.view.bounds device:device_];
  metalView_.delegate = self;
  metalView_.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
  metalView_.framebufferOnly = YES;
  metalView_.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
  metalView_.enableSetNeedsDisplay = NO;
  metalView_.preferredFramesPerSecond =
      static_cast<NSInteger>(std::lround(info_->video_cadence_hz));
  if (metalView_.preferredFramesPerSecond < 1)
    metalView_.preferredFramesPerSecond = 1;
  metalView_.paused = NO;
  metalView_.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [self.view addSubview:metalView_];

  framePeriod_ = 1.0 / info_->video_cadence_hz;
  nextFrameTime_ = 0.0;
  audioFrameAccumulator_ = 0.0;
  booted_ = true;
  suspended_ = false;
  NSLog(@"DKCRecompTV boot core=%s rom=Game.sfc saves=Saves",
        info_->id ?: "unknown");
}

- (BOOL)configureAudio {
  AVAudioFormat *sourceFormat =
      [[AVAudioFormat alloc]
          initWithCommonFormat:AVAudioPCMFormatFloat32
                    sampleRate:static_cast<double>(info_->audio_sample_rate_hz)
                      channels:2
                   interleaved:NO];
  if (!sourceFormat) {
    NSLog(@"DKCRecompTV audio format creation failed");
    return NO;
  }

  try {
    audioRing_ = std::make_shared<DKCAudioRing>();
  } catch (...) {
    NSLog(@"DKCRecompTV audio ring allocation failed");
    return NO;
  }
  const std::shared_ptr<DKCAudioRing> renderRing = audioRing_;
  audioEngine_ = [[AVAudioEngine alloc] init];
  audioSourceNode_ =
      [[AVAudioSourceNode alloc]
          initWithFormat:sourceFormat
             renderBlock:^OSStatus(BOOL *isSilence,
                                   const AudioTimeStamp *timestamp,
                                   AVAudioFrameCount frameCount,
                                   AudioBufferList *outputData) {
               (void)timestamp;
               if (isSilence)
                 *isSilence = YES;
               if (!outputData)
                 return noErr;

               const size_t outputBytes =
                   static_cast<size_t>(frameCount) * sizeof(float);
               for (UInt32 bufferIndex = 0;
                    bufferIndex < outputData->mNumberBuffers; ++bufferIndex) {
                 AudioBuffer &buffer = outputData->mBuffers[bufferIndex];
                 if (buffer.mData && outputBytes)
                   std::memset(buffer.mData, 0, outputBytes);
               }
               if (outputData->mNumberBuffers < 2 ||
                   !outputData->mBuffers[0].mData ||
                   !outputData->mBuffers[1].mData)
                 return noErr;

               float *left =
                   static_cast<float *>(outputData->mBuffers[0].mData);
               float *right =
                   static_cast<float *>(outputData->mBuffers[1].mData);
               for (AVAudioFrameCount frame = 0; frame < frameCount; ++frame) {
                 DKCFloatStereoFrame sample;
                 if (!renderRing->pop(&sample))
                   continue;
                 left[frame] = sample.left;
                 right[frame] = sample.right;
                 if (isSilence && (sample.left != 0.0f ||
                                   sample.right != 0.0f))
                   *isSilence = NO;
               }
               return noErr;
             }];
  if (!audioEngine_ || !audioSourceNode_) {
    NSLog(@"DKCRecompTV audio node creation failed");
    return NO;
  }

  [audioEngine_ attachNode:audioSourceNode_];
  [audioEngine_ connect:audioSourceNode_
                     to:audioEngine_.mainMixerNode
                 format:sourceFormat];
  return YES;
}

- (BOOL)startAudio {
  if (!audioEngine_)
    return NO;

  AVAudioSession *session = [AVAudioSession sharedInstance];
  NSError *audioError = nil;
  if (![session setCategory:AVAudioSessionCategoryPlayback
                        error:&audioError]) {
    NSLog(@"DKCRecompTV audio session category failed: %@",
          audioError.localizedDescription ?: @"unknown error");
    return NO;
  }
  audioError = nil;
  if (![session setActive:YES error:&audioError]) {
    NSLog(@"DKCRecompTV audio session activation failed: %@",
          audioError.localizedDescription ?: @"unknown error");
    return NO;
  }

  [audioEngine_ prepare];
  audioError = nil;
  if (![audioEngine_ startAndReturnError:&audioError]) {
    NSLog(@"DKCRecompTV audio engine start failed: %@",
          audioError.localizedDescription ?: @"unknown error");
    return NO;
  }
  NSLog(@"DKCRecompTV audio started rate=%u channels=2",
        info_->audio_sample_rate_hz);
  return YES;
}

- (void)stopAudio {
  if (audioEngine_.isRunning)
    [audioEngine_ stop];
  if (!audioRing_)
    return;
  DKCFloatStereoFrame discarded;
  while (audioRing_->pop(&discarded)) {
  }
}

- (void)teardownAudio {
  [self stopAudio];
  if (audioEngine_ && audioSourceNode_) {
    [audioEngine_ disconnectNodeOutput:audioSourceNode_];
    [audioEngine_ detachNode:audioSourceNode_];
  }
  audioSourceNode_ = nil;
  audioEngine_ = nil;
  audioRing_.reset();
}

- (BOOL)renderAudioForFrame {
  audioFrameAccumulator_ += audioFramesPerVideoFrame_;
  const double requestedFramesDouble = std::floor(audioFrameAccumulator_);
  if (requestedFramesDouble <= 0.0)
    return YES;

  const size_t requestedFrames =
      static_cast<size_t>(requestedFramesDouble);
  audioFrameAccumulator_ -= static_cast<double>(requestedFrames);
  if (requestedFrames > audioPcm_.size() / 2) {
    [self failWithReason:@"audio buffer sizing failed"];
    return NO;
  }

  const size_t renderedFrames =
      core_->render_audio(instance_, audioPcm_.data(), requestedFrames);
  if (renderedFrames > requestedFrames) {
    [self failWithReason:@"audio render failed"];
    return NO;
  }

  for (size_t frame = 0; frame < renderedFrames; ++frame) {
    audioFloatPcm_[frame].left =
        static_cast<float>(audioPcm_[frame * 2]) / 32768.0f;
    audioFloatPcm_[frame].right =
        static_cast<float>(audioPcm_[frame * 2 + 1]) / 32768.0f;
  }
  const size_t pushedFrames =
      audioRing_->push(audioFloatPcm_.data(), renderedFrames);
  if (pushedFrames < renderedFrames && !loggedAudioOverrun_) {
    loggedAudioOverrun_ = true;
    NSLog(@"DKCRecompTV audio ring overrun; dropping frames");
  }
  if (!loggedFirstAudio_) {
    for (size_t frame = 0; frame < pushedFrames; ++frame) {
      if (audioFloatPcm_[frame].left != 0.0f ||
          audioFloatPcm_[frame].right != 0.0f) {
        loggedFirstAudio_ = true;
        NSLog(@"DKCRecompTV first nonzero audio core=%s",
              info_->id ?: "unknown");
        break;
      }
    }
  }
  return YES;
}

- (uint32_t)controllerMaskForFrame {
  NSArray<GCController *> *controllers = [GCController controllers];
  GCController *selected[2] = {nil, nil};

  /*
   * Honor Apple's explicit player assignment first. Unassigned extended
   * gamepads fill the remaining SNES ports in GCController's connection order.
   */
  for (GCController *controller in controllers) {
    if (!controller.extendedGamepad)
      continue;
    if (controller.playerIndex == GCControllerPlayerIndex1 &&
        !selected[0]) {
      selected[0] = controller;
    } else if (controller.playerIndex == GCControllerPlayerIndex2 &&
               !selected[1]) {
      selected[1] = controller;
    }
  }
  for (GCController *controller in controllers) {
    if (!controller.extendedGamepad ||
        selected[0] == controller || selected[1] == controller)
      continue;
    if (!selected[0])
      selected[0] = controller;
    else if (!selected[1])
      selected[1] = controller;
  }

  DKCControllerSample samples[2] = {
      DkcSampleForGamepad(selected[0] ? selected[0].extendedGamepad : nil),
      DkcSampleForGamepad(selected[1] ? selected[1].extendedGamepad : nil),
  };
  return dkc_pack_controllers(samples, 2);
}

- (void)controllerDidConnect:(NSNotification *)notification {
  GCController *controller = (GCController *)notification.object;
  NSLog(@"DKCRecompTV controller connected profile=%s",
        controller.extendedGamepad ? "ExtendedGamepad" : "unsupported");
}

- (void)controllerDidDisconnect:(NSNotification *)notification {
  GCController *controller = (GCController *)notification.object;
  NSLog(@"DKCRecompTV controller disconnected profile=%s",
        controller.extendedGamepad ? "ExtendedGamepad" : "unsupported");
}

- (void)uploadFramebuffer {
  if (!framebufferTexture_ || framebuffer_.empty())
    return;
  const MTLRegion region =
      MTLRegionMake2D(0, 0, info_->framebuffer_width, info_->framebuffer_height);
  [framebufferTexture_ replaceRegion:region
                         mipmapLevel:0
                           withBytes:framebuffer_.data()
                         bytesPerRow:info_->framebuffer_pitch_bytes];
}

- (void)drawInMTKView:(MTKView *)view {
  if (!booted_ || suspended_ || !instance_)
    return;

  const double now = CACurrentMediaTime();
  if (nextFrameTime_ == 0.0)
    nextFrameTime_ = now;
  uint32_t framesProcessed = 0;
  while (now >= nextFrameTime_ &&
         framesProcessed < kMaxGameFramesPerDisplay) {
    const uint32_t controllerMask = [self controllerMaskForFrame];
    const DKCGameCoreResult runResult =
        core_->run_frame(instance_, controllerMask);
    if (runResult != DKC_GAME_CORE_OK) {
      [self failWithReason:DkcResultDescription(runResult)];
      return;
    }
    if (![self renderAudioForFrame])
      return;
    nextFrameTime_ += framePeriod_;
    ++framesProcessed;
  }

  /*
   * Keep an overdue deadline when the explicit catch-up ceiling is reached.
   * A normal one-frame miss is therefore never silently re-anchored; only a
   * lifecycle transition resets the deadline.
   */
  if (framesProcessed > 0) {
    const DKCGameCoreResult drawResult =
        core_->draw_frame(instance_, framebuffer_.data(),
                          info_->framebuffer_pitch_bytes);
    if (drawResult != DKC_GAME_CORE_OK) {
      [self failWithReason:DkcResultDescription(drawResult)];
      return;
    }
    [self uploadFramebuffer];
    if (!loggedFirstVideo_) {
      loggedFirstVideo_ = true;
      NSLog(@"DKCRecompTV first active video core=%s", info_->id ?: "unknown");
    }
  }

  MTLRenderPassDescriptor *renderPass = view.currentRenderPassDescriptor;
  id<CAMetalDrawable> drawable = view.currentDrawable;
  if (!renderPass || !drawable)
    return;
  renderPass.colorAttachments[0].loadAction = MTLLoadActionClear;
  renderPass.colorAttachments[0].clearColor =
      MTLClearColorMake(0.0, 0.0, 0.0, 1.0);

  id<MTLCommandBuffer> commandBuffer = [commandQueue_ commandBuffer];
  id<MTLRenderCommandEncoder> encoder =
      [commandBuffer renderCommandEncoderWithDescriptor:renderPass];
  [encoder setRenderPipelineState:pipelineState_];
  [encoder setFragmentTexture:framebufferTexture_ atIndex:0];
  [encoder setViewport:DkcViewportForSize(view.drawableSize, info_)];
  [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
              vertexStart:0
              vertexCount:4];
  [encoder endEncoding];
  [commandBuffer presentDrawable:drawable];
  [commandBuffer commit];
}

- (void)mtkView:(MTKView *)view
    drawableSizeWillChange:(CGSize)size {
  (void)view;
  (void)size;
}

- (void)pauseForLifecycle {
  if (!booted_ || suspended_)
    return;
  suspended_ = true;
  metalView_.paused = YES;
  [self stopAudio];
  nextFrameTime_ = 0.0;
  const DKCGameCoreResult result = core_->suspend(instance_);
  NSLog(@"DKCRecompTV suspend core=%s result=%s", info_->id ?: "unknown",
        DkcResultDescription(result).UTF8String);
}

- (void)resumeForLifecycle {
  if (!booted_ || !suspended_)
    return;
  const DKCGameCoreResult result = core_->resume(instance_);
  if (result != DKC_GAME_CORE_OK) {
    [self failWithReason:DkcResultDescription(result)];
    return;
  }
  if (![self startAudio]) {
    [self failWithReason:@"audio restart failed"];
    return;
  }
  suspended_ = false;
  nextFrameTime_ = 0.0;
  metalView_.paused = NO;
  [metalView_ setNeedsDisplay];
  NSLog(@"DKCRecompTV resume core=%s; render cadence restarted",
        info_->id ?: "unknown");
}

- (void)dealloc {
  [self teardownAudio];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end

@interface DKCSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation DKCSceneDelegate

- (void)scene:(UIScene *)scene
    willConnectToSession:(UISceneSession *)session
               options:(UISceneConnectionOptions *)connectionOptions {
  (void)session;
  (void)connectionOptions;
  if (![scene isKindOfClass:[UIWindowScene class]])
    return;
  self.window =
      [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
  self.window.rootViewController = [[DKCGameViewController alloc] init];
  [self.window makeKeyAndVisible];
}

- (DKCGameViewController *)gameViewController {
  if ([self.window.rootViewController isKindOfClass:
          [DKCGameViewController class]])
    return (DKCGameViewController *)self.window.rootViewController;
  return nil;
}

- (void)sceneWillResignActive:(UIScene *)scene {
  (void)scene;
  [[self gameViewController] pauseForLifecycle];
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
  (void)scene;
  [[self gameViewController] pauseForLifecycle];
}

- (void)sceneWillEnterForeground:(UIScene *)scene {
  (void)scene;
  [[self gameViewController] resumeForLifecycle];
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
  (void)scene;
  [[self gameViewController] resumeForLifecycle];
}

@end

@interface DKCAppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation DKCAppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  (void)application;
  (void)launchOptions;
  return YES;
}

@end

int main(int argc, char *argv[]) {
  @autoreleasepool {
    return UIApplicationMain(argc, argv, nil,
                              NSStringFromClass([DKCAppDelegate class]));
  }
}
