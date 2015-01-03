  //
  //  NMPostMeatViewController.m
  //  MeatChat
  //
  //  Created by Marcus Ramberg on 17.01.14.
  //  Copyright (c) 2014 Nordaaker AS. All rights reserved.
  //

#import "MCPostViewController.h"
#import "MCPostListViewController.h"
#import <ImageIO/ImageIO.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import "UIImage+Extras.h"
#import "MCPostListViewController.h"

@interface MCPostViewController ()
@property (retain,nonatomic) AVCaptureSession *session;
@property (weak, nonatomic) IBOutlet UIButton *imageButton;
@property (weak, nonatomic) IBOutlet UIButton *flashButton;
@property (weak, nonatomic) IBOutlet UILabel *countLabel;
@property (strong, atomic) NSMutableArray *frames;
@property (atomic) BOOL capturing;
@property (strong, nonatomic) NSDictionary *frameProperties;
@property (nonatomic) int skipFrames;
@property (nonatomic) AVCaptureVideoPreviewLayer *captureLayer;

- (void)updateCount;
@end


@implementation MCPostViewController

#define MAXLENGTH 250

const int CAPTURE_FRAMES_PER_SECOND=5;

- (void)viewDidLoad
{
  [super viewDidLoad];
  self.frames=[NSMutableArray array];
  self.capturing=NO;
  self.skipFrames=0;
      // Do any additional setup after loading the view.
  [self setupCaptureSession];
  [self orientationChanged];
}

+ (NSArray*)placeholders
  {
  static NSArray *_titles;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    _titles = @[@"What's up?",
                @"What do you say?",
                @"Anything on your mind?",
                @"Hello?",
                @"A field you can type in.",
                @"I take letters.",
                @"Tap and meat!",
                @"250 chars or less."
                ];
  });
  return _titles;
}

- (void)setRandomPlaceholder
{
  NSUInteger randomIndex = arc4random() % [[[self class]placeholders] count];
  [self setPlaceholder: [[[self class] placeholders] objectAtIndex: randomIndex]];
}

- (void)setPlaceholder: (NSString*)placeholder
{
  UIColor *color = [UIColor darkGrayColor];
  self.textfield.attributedPlaceholder = [[NSAttributedString alloc] initWithString:placeholder attributes:@{NSForegroundColorAttributeName: color}];
}


- (void)didReceiveMemoryWarning
{
  [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


- (void)setupCaptureSession
{
  NSError *error = nil;
  
    // Create the session
  AVCaptureSession *session = [[AVCaptureSession alloc] init];
  
    // Configure the session to produce lower resolution video frames, if your
    // processing algorithm can cope. We'll specify medium quality for the
    // chosen device.
  session.sessionPreset = AVCaptureSessionPresetMedium;
  
    // Find a suitable AVCaptureDevice
  AVCaptureDevice *device = [self cameraWithPosition:AVCaptureDevicePositionFront];

  [device lockForConfiguration: &error];
  device.activeVideoMinFrameDuration = CMTimeMake(1, CAPTURE_FRAMES_PER_SECOND);
  device.activeVideoMaxFrameDuration = CMTimeMake(1, CAPTURE_FRAMES_PER_SECOND);
  [device unlockForConfiguration];
    // Create a device input with the device and add it to the session.
  AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device
                                                                      error:&error];
  if (!input) {
      // Handling the error appropriately.
    return;
  }
  [session addInput:input];
  
    // Create a VideoDataOutput and add it to the session
  AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];

  [session addOutput:output];
  [self switchCameraTapped: self];
  AVCaptureVideoPreviewLayer *captureLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:session];
  captureLayer.frame = self.imageButton.bounds;
  captureLayer.videoGravity=AVLayerVideoGravityResizeAspectFill;
  
  [self.imageButton.layer addSublayer:captureLayer];
  self.captureLayer=captureLayer;

    // Configure your output.
  dispatch_queue_t queue = dispatch_queue_create("myQueue", NULL);
  [output setSampleBufferDelegate:self queue:queue];
  
    // Specify the pixel format
  output.videoSettings =
  [NSDictionary dictionaryWithObject:
   [NSNumber numberWithInt:kCVPixelFormatType_32BGRA]
                              forKey:(id)kCVPixelBufferPixelFormatTypeKey];
  
  
    // Assign session to an ivar.
  [self setSession:session];
}

  // Delegate routine that is called when a sample buffer was written
- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection
{
  if(self.capturing) {
      // FIXME: This is a dirty hack, because CAPTURE_FRAMES_PER_SECOND above doesn't seem to work.
    if(self.skipFrames) {
      self.skipFrames--;
      return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{ [self updateCount]; });
    self.skipFrames=5;
    [self.frames addObject: [self imageFromSampleBuffer:sampleBuffer]];
    if([self.frames count] == 10) {
      NSMutableArray *encodedImages=[NSMutableArray array];
      for(int i=0;i<[self.frames count];i++) {
        UIImage *image=[(UIImage*)[self.frames objectAtIndex:i] imageByScalingAndCroppingForSize: CGSizeMake(200, 150)];
        
        
        NSData *imageData = UIImageJPEGRepresentation(image, 0.6);
        NSString *encodedString = [imageData base64EncodedStringWithOptions: 0];
        [encodedImages addObject: [NSString stringWithFormat: @"data:image/jpeg;base64,%@", encodedString]];
      }
      self.capturing=NO;
      [self.frames removeAllObjects];
      MCPostListViewController *parentViewController=(MCPostListViewController*)self.parentViewController;
      
   NSDictionary *message=@{
        @"message": self.textfield.text,
        @"media": encodedImages,
        @"fingerprint": [[[UIDevice currentDevice] identifierForVendor].UUIDString substringToIndex:9]
        };
    dispatch_async(dispatch_get_main_queue(), ^{
      [parentViewController.socket emit: @"message" args: @[ message ]];
      [self closePostWithPosted: YES];
    });
    }
  }
}

- (IBAction)toggleFlashlight:(id)sender {
  [self.session beginConfiguration];
  AVCaptureDevice *camera=[self cameraWithPosition:AVCaptureDevicePositionBack];
  if(![camera isTorchModeSupported: AVCaptureTorchModeOff]) {
    [self.session commitConfiguration];
    return;
  }
  [camera lockForConfiguration:nil];
  if (camera.torchMode == AVCaptureTorchModeOff) {
    camera.torchMode=AVCaptureTorchModeOn;
    _flashButton.selected=YES;
    AVCaptureInput* currentCameraInput = [_session.inputs objectAtIndex:0];
    if(((AVCaptureDeviceInput*)currentCameraInput).device.position == AVCaptureDevicePositionFront) {
      [_session removeInput:currentCameraInput];
      AVCaptureDeviceInput *newVideoInput = [[AVCaptureDeviceInput alloc] initWithDevice:camera error:nil];
      [_session addInput:newVideoInput];
    }
  }
  else {
    camera.torchMode=AVCaptureTorchModeOff;
    _flashButton.selected=NO;
  }
  [camera unlockForConfiguration];
  [_session commitConfiguration];
  
}

-(IBAction)switchCameraTapped:(id)sender
{
    //Change camera source
  if(_session) {
      //Indicate that some changes will be made to the session
    [_session beginConfiguration];
    
      //Remove existing input
    AVCaptureDeviceInput* currentCameraInput = [_session.inputs objectAtIndex:0];
    [_session removeInput:currentCameraInput];
    
      //Get new input
    AVCaptureDevice *newCamera = nil;
    if(((AVCaptureDeviceInput*)currentCameraInput).device.position == AVCaptureDevicePositionBack)
      {
      _flashButton.selected=NO;
      NSError *err;
      [currentCameraInput.device lockForConfiguration:&err];
      if(!err) {
        if([currentCameraInput.device isTorchModeSupported: AVCaptureTorchModeOff]) {
          currentCameraInput.device.torchMode=AVCaptureTorchModeOff;
        }
        [currentCameraInput.device unlockForConfiguration];
      }
      newCamera = [self cameraWithPosition:AVCaptureDevicePositionFront];
      }
    else
      {
      newCamera = [self cameraWithPosition:AVCaptureDevicePositionBack];
      }
    
      //Add input to session
    AVCaptureDeviceInput *newVideoInput = [[AVCaptureDeviceInput alloc] initWithDevice:newCamera error:nil];
    [_session addInput:newVideoInput];
    
      //Commit all the configuration changes at once
    [_session commitConfiguration];
    }
}

- (void)updateCount
{
    self.countLabel.text=[NSString stringWithFormat: @"%u",9-(int)[self.frames count]];
}

- (void)closePostWithPosted: (BOOL)posted
{
  [ self.textfield resignFirstResponder];
  if(posted) {
    self.textfield.text=@"";
    self.characterCount.text=@"250 left";
    [self setRandomPlaceholder];
  }
  self.countLabel.hidden=YES;
  self.countLabel.text=@"9";
  self.characterCount.hidden=YES;
  [UIView animateWithDuration:0.5f animations:^{
    self.imageButton.alpha=0;
  }];
  [_session stopRunning];
}


  // Find a camera with the specified AVCaptureDevicePosition, returning nil if one is not found
- (AVCaptureDevice *) cameraWithPosition:(AVCaptureDevicePosition) position
{
  NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
  for (AVCaptureDevice *device in devices)
    {
    if ([device position] == position) return device;
    }
  return nil;
}

  // Create a UIImage from sample buffer data
- (UIImage *) imageFromSampleBuffer:(CMSampleBufferRef) sampleBuffer
{
  
    // Get a CMSampleBuffer's Core Video image buffer for the media data
  CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    // Lock the base address of the pixel buffer
  CVPixelBufferLockBaseAddress(imageBuffer, 0);
  
    // Get the number of bytes per row for the pixel buffer
  void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
  
    // Get the number of bytes per row for the pixel buffer
  size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    // Get the pixel buffer width and height
  size_t width = CVPixelBufferGetWidth(imageBuffer);
  size_t height = CVPixelBufferGetHeight(imageBuffer);
  
    // Create a device-dependent RGB color space
  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  
    // Create a bitmap graphics context with the sample buffer data
  CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8,
                                               bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    // Create a Quartz image from the pixel data in the bitmap graphics context
  CGImageRef quartzImage = CGBitmapContextCreateImage(context);
    // Unlock the pixel buffer
  CVPixelBufferUnlockBaseAddress(imageBuffer,0);
  
    // Free up the context and color space
  CGContextRelease(context);
  CGColorSpaceRelease(colorSpace);
  
    // Create an image object from the Quartz image
  AVCaptureInput* currentCameraInput = [_session.inputs objectAtIndex:0];
  BOOL frontcamera= ((AVCaptureDeviceInput*)currentCameraInput).device.position == AVCaptureDevicePositionFront;
  UIImage *image = [[UIImage alloc] initWithCGImage:quartzImage scale:(CGFloat)1.0 orientation: [self currentImageOrientationWithMirroring: frontcamera]];

    // Release the Quartz image
  CGImageRelease(quartzImage);
  
  return (image);
}



- (BOOL)textField:(UITextField *) textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
  
  NSUInteger oldLength = [textField.text length];
  NSUInteger replacementLength = [string length];
  NSUInteger rangeLength = range.length;
  
  NSUInteger newLength = oldLength - rangeLength + replacementLength;
  
  BOOL returnKey = [string rangeOfString: @"\n"].location != NSNotFound;
  
  if( newLength <= MAXLENGTH) {
    self.characterCount.text=[NSString stringWithFormat: @"%lu left",MAXLENGTH-(unsigned long)newLength];
  }
  return newLength <= MAXLENGTH || returnKey;
}


-(BOOL)textFieldShouldBeginEditing:(UITextField *)textField
{
  [_session startRunning];
  [UIView animateWithDuration:0.5f animations:^{
    self.imageButton.alpha=1;
  } completion:^(BOOL finished) {
    [self.textfield becomeFirstResponder];
  }];
  
  return YES;
}

-(BOOL)textFieldShouldReturn:(UITextField *)textField
{
  
  self.countLabel.hidden=NO;
  self.capturing=YES;
  return YES;
  
}

-(void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
  [self orientationChanged];
}


-(void) orientationChanged
{
  // get the new orientation from device
  AVCaptureVideoOrientation newOrientation = [self videoOrientationFromDeviceOrientation: [UIDevice currentDevice].orientation];
  
  // set the orientation of preview layer :( which will be displayed in the device )
  [self.captureLayer.connection setVideoOrientation:newOrientation];
  
  // set the orientation of the connection: which will take care of capture
  //[pCaptureConnection setVideoOrientation:newOrientation];
  
}

- (AVCaptureVideoOrientation)videoOrientationFromDeviceOrientation:(UIDeviceOrientation)deviceOrientation
{
  AVCaptureVideoOrientation orientation;
  switch (deviceOrientation) {
    case UIDeviceOrientationUnknown:
      orientation = AVCaptureVideoOrientationPortrait;
      break;
    case UIDeviceOrientationPortrait:
      orientation = AVCaptureVideoOrientationPortrait;
      break;
    case UIDeviceOrientationPortraitUpsideDown:
      orientation = AVCaptureVideoOrientationPortraitUpsideDown;
      break;
    case UIDeviceOrientationLandscapeLeft:
      orientation = AVCaptureVideoOrientationLandscapeRight;
      break;
    case UIDeviceOrientationLandscapeRight:
      orientation = AVCaptureVideoOrientationLandscapeLeft;
      break;
    case UIDeviceOrientationFaceUp:
      orientation = AVCaptureVideoOrientationPortrait;
      break;
    case UIDeviceOrientationFaceDown:
      orientation = AVCaptureVideoOrientationPortrait;
      break;
  }
  return orientation;
}

- (UIImageOrientation)currentImageOrientationWithMirroring: (BOOL)isUsingFrontCamera
{
  switch ([UIDevice currentDevice].orientation)
  {
    case UIDeviceOrientationPortrait:
      return isUsingFrontCamera ? UIImageOrientationRight : UIImageOrientationLeftMirrored;
    case UIDeviceOrientationPortraitUpsideDown:
      return isUsingFrontCamera ? UIImageOrientationLeft :UIImageOrientationRightMirrored;
    case UIDeviceOrientationLandscapeLeft:
      return isUsingFrontCamera ? UIImageOrientationDown :  UIImageOrientationUpMirrored;
    case UIDeviceOrientationLandscapeRight:
      return isUsingFrontCamera ? UIImageOrientationUp : UIImageOrientationDownMirrored;
    default:
      return  UIImageOrientationUp;
  }
}



@end
