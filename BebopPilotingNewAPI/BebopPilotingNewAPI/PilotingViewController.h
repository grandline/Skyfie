/*
    Copyright (C) 2014 Parrot SA

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions
    are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in
      the documentation and/or other materials provided with the 
      distribution.
    * Neither the name of Parrot nor the names
      of its contributors may be used to endorse or promote products
      derived from this software without specific prior written
      permission.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
    FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
    COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
    BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS
    OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED 
    AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
    OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT
    OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
    SUCH DAMAGE.
*/
//
//  PilotingViewController.h
//  BebopPiloting
//
//  Created on 19/01/2015.
//  Copyright (c) 2015 Parrot. All rights reserved.
//

// CV used
//#ifdef __cplusplus
#import <opencv2/opencv.hpp>
#import <opencv2/videoio/cap_ios.h>
#import <opencv2/objdetect/objdetect.hpp>
#import <opencv2/imgproc/imgproc.hpp>

//#endif

#import <UIKit/UIKit.h>
extern "C" {
#import <libARController/ARController.h>
#import <libARDiscovery/ARDISCOVERY_BonjourDiscovery.h>
#import <libARDataTransfer/ARDataTransfer.h>
}
#import "VideoView.h"
#import <CoreLocation/CoreLocation.h>

@interface PilotingViewController : UIViewController <CLLocationManagerDelegate,  CvVideoCameraDelegate>
{
    // CV used
    __weak IBOutlet UIImageView *imageView;
    CvVideoCamera* videoCamera;
}
// the service we want to connect with (in this sample, this is a service.service is a NSNetService)
@property (nonatomic, strong) ARService* service;

@property (nonatomic,retain) CvVideoCamera* videoCamera;
@property (strong, nonatomic) IBOutlet UIView *pictureView;
@property (strong, nonatomic) IBOutlet UIView *takeoffView;
@property (strong, nonatomic) IBOutlet VideoView *previewVideo;
@property (nonatomic, strong) IBOutlet VideoView *videoView;

@property (nonatomic, strong) IBOutlet UILabel *batteryLabel;

@property (nonatomic, strong) CLLocationManager *locationManager;
@property eARCOMMANDS_ARDRONE3_PILOTINGSTATE_FLYINGSTATECHANGED_STATE flyingState;
@property float droneHeading;
@property float phoneHeading;
@property BOOL isCalibrationOK;
@property BOOL isTouch;
@property BOOL isFirstCalibration;

@property (nonatomic, assign) ARSAL_Thread_t threadRetreiveAllMedias;   // the thread that will do the media retrieving
@property (nonatomic, assign) ARSAL_Thread_t threadGetThumbnails;       // the thread that will download the thumbnails
@property (nonatomic, assign) ARSAL_Thread_t threadMediasDownloader;    // the thread that will download medias

@property (nonatomic, assign) ARDATATRANSFER_Manager_t *manager;        // the data transfer manager

@property (nonatomic, assign) ARUTILS_Manager_t *ftpListManager;        // an ftp that will do the list
@property (nonatomic, assign) ARUTILS_Manager_t *ftpQueueManager;       // an ftp that will do the download

- (IBAction)takeoffClick:(id)sender;
- (IBAction)landingClick:(id)sender;

//- (IBAction)gazUpTouchDown:(id)sender;
//- (IBAction)gazDownTouchDown:(id)sender;
//
//- (IBAction)gazUpTouchUp:(id)sender;
//- (IBAction)gazDownTouchUp:(id)sender;
//
//
//- (IBAction)yawLeftTouchDown:(id)sender;
//- (IBAction)yawRightTouchDown:(id)sender;
//
//- (IBAction)yawLeftTouchUp:(id)sender;
//- (IBAction)yawRightTouchUp:(id)sender;
//
//
//- (IBAction)rollLeftTouchDown:(id)sender;
//- (IBAction)rollRightTouchDown:(id)sender;
//
//- (IBAction)rollLeftTouchUp:(id)sender;
//- (IBAction)rollRightTouchUp:(id)sender;
//
//
//- (IBAction)pitchForwardTouchDown:(id)sender;
//- (IBAction)pitchBackTouchDown:(id)sender;
//
//- (IBAction)pitchForwardTouchUp:(id)sender;
//- (IBAction)pitchBackTouchUp:(id)sender;

- (IBAction)stillClicked:(id)sender;


@end

