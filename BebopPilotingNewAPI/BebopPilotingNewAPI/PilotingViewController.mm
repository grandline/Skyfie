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
//  PilotingViewController.m
//  BebopPiloting
//
//  Created on 19/01/2015.
//  Copyright (c) 2015 Parrot. All rights reserved.
//

// CV used
#import "Object.h"
#import <vector>

#import "PilotingViewController.h"
extern "C" {
#include <libARDiscovery/ARDiscovery.h>
#include <libARController/ARController.h>
#import <uthash/uthash.h>
}

// CV used
#define CIRCLE_COLOR CV_RGB(255,0,0)
#define CIRCLE_SIZE 1
//default capture width and height[]
CGRect  screenRect = [[UIScreen mainScreen] bounds];
const int FRAME_WIDTH = screenRect.size.width;
const int FRAME_HEIGHT = screenRect.size.height;
//max number of objects to be detected in frame
const int MAX_NUM_OBJECTS=10;
//minimum and maximum object area
const int MIN_OBJECT_AREA = 3*3;
const int MAX_OBJECT_AREA = FRAME_HEIGHT*FRAME_WIDTH/1.5;
const double SIZE_DIFF=0.05;
const int centerRange=20;
bool orangeFlag=false,blueFlag=false;

// Video used
#define ALLOWANCE_THRESHOLD 7.5
#define DEVICE_PORT     21
#define MEDIA_FOLDER    "internal_000"

@interface PilotingViewController ()
@property (nonatomic) ARCONTROLLER_Device_t *deviceController;
@property (nonatomic, strong) UIAlertView *alertView;
@property (nonatomic) dispatch_semaphore_t stateSem;
@property (nonatomic) dispatch_semaphore_t resolveSemaphore;

@end

@implementation PilotingViewController
@synthesize videoCamera;

- (void)viewDidLoad
{
    [super viewDidLoad];
    // CV used
    // Do any additional setup after loading the view, typically from a nib.
    self.videoCamera =[[CvVideoCamera alloc]initWithParentView:imageView];
    self.videoCamera.defaultAVCaptureDevicePosition = AVCaptureDevicePositionBack;
    self.videoCamera.defaultAVCaptureSessionPreset = AVCaptureSessionPreset1280x720;
    self.videoCamera.defaultAVCaptureVideoOrientation = AVCaptureVideoOrientationPortrait;
    self.videoCamera.defaultFPS = 30;
    self.videoCamera.grayscaleMode = NO;
    self.videoCamera.delegate = self;
    
    [_batteryLabel setText:@"?%"];
    
    _alertView = [[UIAlertView alloc] initWithTitle:[_service name] message:@"Connecting ..."
                                           delegate:self cancelButtonTitle:nil otherButtonTitles:nil, nil];
    
    _deviceController = NULL;
    _stateSem = dispatch_semaphore_create(0);
    
    _locationManager = [[CLLocationManager alloc] init];
    _locationManager.delegate = self;
    
    _phoneHeading = 0;
    _droneHeading = 0;
    _isCalibrationOK = false;
    _isTouch = false;
    _isFirstCalibration = false;
    
    _takeoffView.hidden = false;
    [self.view bringSubviewToFront:_takeoffView];
    
    // setting pan gestrues to imageView & videoView
    UIPanGestureRecognizer *imagePan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panonImageView:)];
    UIPanGestureRecognizer *videoPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panonVideoView:)];
    [imageView addGestureRecognizer:imagePan];
    [_videoView addGestureRecognizer:videoPan];
    _pictureView.hidden = true;
//    _videoView.hidden = true;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(orientationChanged:) name:UIApplicationDidChangeStatusBarOrientationNotification object:nil];
}

- (void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    [_alertView show];
    
    // call createDeviceControllerWithService in background
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // create the device controller
        [self createDeviceControllerWithService:_service];
    });
}

#pragma mark
- (void)createDeviceControllerWithService:(ARService*)service
{
    // first get a discovery device
    ARDISCOVERY_Device_t *discoveryDevice = [self createDiscoveryDeviceWithService:service];
    
    if (discoveryDevice != NULL)
    {
        eARCONTROLLER_ERROR error = ARCONTROLLER_OK;
        
        // create the device controller
        NSLog(@"- ARCONTROLLER_Device_New ... ");
        _deviceController = ARCONTROLLER_Device_New (discoveryDevice, &error);
        
        if ((error != ARCONTROLLER_OK) || (_deviceController == NULL))
        {
            NSLog(@"- error :%s", ARCONTROLLER_Error_ToString(error));
        }
        
        // add the state change callback to be informed when the device controller starts, stops...
        if (error == ARCONTROLLER_OK)
        {
            NSLog(@"- ARCONTROLLER_Device_AddStateChangedCallback ... ");
            error = ARCONTROLLER_Device_AddStateChangedCallback(_deviceController, stateChanged, (__bridge void *)(self));
            
            if (error != ARCONTROLLER_OK)
            {
                NSLog(@"- error :%s", ARCONTROLLER_Error_ToString(error));
            }
        }
        
        // add the command received callback to be informed when a command has been received from the device
        if (error == ARCONTROLLER_OK)
        {
            NSLog(@"- ARCONTROLLER_Device_AddCommandRecievedCallback ... ");
            error = ARCONTROLLER_Device_AddCommandReceivedCallback(_deviceController, onCommandReceived, (__bridge void *)(self));
            
            if (error != ARCONTROLLER_OK)
            {
                NSLog(@"- error :%s", ARCONTROLLER_Error_ToString(error));
            }
        }
        
        // add the received frame callback to be informed when a frame should be displayed
        if (error == ARCONTROLLER_OK)
        {
            NSLog(@"- ARCONTROLLER_Device_SetVideoReceiveCallback ... ");
            error = ARCONTROLLER_Device_SetVideoReceiveCallback (_deviceController, didReceiveFrameCallback, NULL , (__bridge void *)(self));
            
            if (error != ARCONTROLLER_OK)
            {
                NSLog(@"- error :%s", ARCONTROLLER_Error_ToString(error));
            }
        }
        
        // start the device controller (the callback stateChanged should be called soon)
        if (error == ARCONTROLLER_OK)
        {
            NSLog(@"- ARCONTROLLER_Device_Start ... ");
            error = ARCONTROLLER_Device_Start (_deviceController);
            
            if (error != ARCONTROLLER_OK)
            {
                NSLog(@"- error :%s", ARCONTROLLER_Error_ToString(error));
            }
        }
        
        // we don't need the discovery device anymore
        ARDISCOVERY_Device_Delete (&discoveryDevice);
        
        // if an error occured, go back
        if (error != ARCONTROLLER_OK)
        {
            [self goBack];
        }
    }
    else
    {
        [self goBack];
    }
}

// this should be called in background
- (ARDISCOVERY_Device_t *)createDiscoveryDeviceWithService:(ARService*)service
{
    ARDISCOVERY_Device_t *device = NULL;
    
    eARDISCOVERY_ERROR errorDiscovery = ARDISCOVERY_OK;
    
    NSLog(@"- init discovery device  ... ");
    
    device = ARDISCOVERY_Device_New (&errorDiscovery);
    if ((errorDiscovery != ARDISCOVERY_OK) || (device == NULL))
    {
        NSLog(@"device : %p", device);
        NSLog(@"Discovery error :%s", ARDISCOVERY_Error_ToString(errorDiscovery));
    }
    
    if (errorDiscovery == ARDISCOVERY_OK)
    {
        // init the discovery device
        if (service.product == ARDISCOVERY_PRODUCT_ARDRONE)
        {
            // need to resolve service to get the IP
            BOOL resolveSucceeded = [self resolveService:service];
            
            if (resolveSucceeded)
            {
                NSString *ip = [[ARDiscovery sharedInstance] convertNSNetServiceToIp:service];
                int port = (int)[(NSNetService *)service.service port];
                
                if (ip)
                {
                    // create a Wifi discovery device
                    errorDiscovery = ARDISCOVERY_Device_InitWifi (device, service.product, [service.name UTF8String], [ip UTF8String], port);
                }
                else
                {
                    NSLog(@"ip is null");
                    errorDiscovery = ARDISCOVERY_ERROR;
                }
            }
            else
            {
                NSLog(@"Resolve error");
                errorDiscovery = ARDISCOVERY_ERROR;
            }
        }
        
        if (errorDiscovery != ARDISCOVERY_OK)
        {
            NSLog(@"Discovery error :%s", ARDISCOVERY_Error_ToString(errorDiscovery));
            ARDISCOVERY_Device_Delete(&device);
        }
    }
    
    return device;
}

- (void) viewDidDisappear:(BOOL)animated
{
    if (_alertView && !_alertView.isHidden)
    {
        [_alertView dismissWithClickedButtonIndex:0 animated:NO];
    }
    _alertView = [[UIAlertView alloc] initWithTitle:[_service name] message:@"Disconnecting ..."
                                           delegate:self cancelButtonTitle:nil otherButtonTitles:nil, nil];
    [_alertView show];
    
    // in background
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        eARCONTROLLER_ERROR error = ARCONTROLLER_OK;
        
        // if the device controller is not stopped, stop it
        eARCONTROLLER_DEVICE_STATE state = ARCONTROLLER_Device_GetState(_deviceController, &error);
        if ((error == ARCONTROLLER_OK) && (state != ARCONTROLLER_DEVICE_STATE_STOPPED))
        {
            // after that, stateChanged should be called soon
            error = ARCONTROLLER_Device_Stop (_deviceController);
            
            if (error != ARCONTROLLER_OK)
            {
                NSLog(@"- error :%s", ARCONTROLLER_Error_ToString(error));
            }
            else
            {
                // wait for the state to change to stopped
                NSLog(@"- wait new state ... ");
                dispatch_semaphore_wait(_stateSem, DISPATCH_TIME_FOREVER);
            }
        }
        
        // once the device controller is stopped, we can delete it
        if (_deviceController != NULL)
        {
            ARCONTROLLER_Device_Delete(&_deviceController);
        }
        
        // dismiss the alert view in main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            [_alertView dismissWithClickedButtonIndex:0 animated:TRUE];
        });
    });
}

- (void)goBack
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.navigationController popViewControllerAnimated:YES];
    });
}

#pragma mark Device controller callbacks
// called when the state of the device controller has changed
void stateChanged (eARCONTROLLER_DEVICE_STATE newState, eARCONTROLLER_ERROR error, void *customData)
{
    PilotingViewController *pilotingViewController = (__bridge PilotingViewController *)customData;
    
    NSLog (@"newState: %d",newState);
    
    if (pilotingViewController != nil)
    {
        switch (newState)
        {
            case ARCONTROLLER_DEVICE_STATE_RUNNING:
            {
                // dismiss the alert view in main thread
                dispatch_async(dispatch_get_main_queue(), ^{
                    [pilotingViewController.alertView dismissWithClickedButtonIndex:0 animated:TRUE];
                });
                break;
            }
            case ARCONTROLLER_DEVICE_STATE_STOPPED:
            {
                dispatch_semaphore_signal(pilotingViewController.stateSem);
                
                // Go back
                dispatch_async(dispatch_get_main_queue(), ^{
                    [pilotingViewController goBack];
                });
                
                break;
            }
                
            case ARCONTROLLER_DEVICE_STATE_STARTING:
                break;
                
            case ARCONTROLLER_DEVICE_STATE_STOPPING:
                break;
                
            default:
                NSLog(@"new State : %d not known", newState);
                break;
        }
    }
}

// called when a command has been received from the drone
void onCommandReceived (eARCONTROLLER_DICTIONARY_KEY commandKey, ARCONTROLLER_DICTIONARY_ELEMENT_t *elementDictionary, void *customData)
{
    PilotingViewController *pilotingViewController = (__bridge PilotingViewController *)customData;
    
    if (elementDictionary != NULL) {
        ARCONTROLLER_DICTIONARY_ARG_t *arg = NULL;
        ARCONTROLLER_DICTIONARY_ELEMENT_t *element = NULL;
        
        // get the command received in the device controller
        HASH_FIND_STR (elementDictionary, ARCONTROLLER_DICTIONARY_SINGLE_KEY, element);
        if (element != NULL) {
            switch (commandKey) {
                case // if the command received is a battery state changed
        ARCONTROLLER_DICTIONARY_KEY_COMMON_COMMONSTATE_BATTERYSTATECHANGED:
                {
                    // get the value
                    HASH_FIND_STR (element->arguments, ARCONTROLLER_DICTIONARY_KEY_COMMON_COMMONSTATE_BATTERYSTATECHANGED_PERCENT, arg);
                    if (arg != NULL) {
                        // update UI
                        [pilotingViewController onUpdateBatteryLevel:arg->value.U8];
                    }
                    break;
                }
                    
                case // if the command received is a attitude changed
        ARCONTROLLER_DICTIONARY_KEY_ARDRONE3_PILOTINGSTATE_ATTITUDECHANGED:
                {
                    HASH_FIND_STR(element->arguments, ARCONTROLLER_DICTIONARY_KEY_ARDRONE3_PILOTINGSTATE_ATTITUDECHANGED_YAW, arg);
                    if (arg != NULL) {
                        float fheading = (arg->value.Float * 180 / M_PI);
                        // convert to [0, 360]
                        if (fheading < 0) {
                            fheading = fheading + 360;
                        }
                        // update value of _droneHeading
                        pilotingViewController.droneHeading = fheading;
                        if (pilotingViewController.isTouch || pilotingViewController.isFirstCalibration) {
                            [pilotingViewController checkHeading];
                        }
                    }
                    break;
                }
                    
                case // if the command received is a flying state changed
        ARCONTROLLER_DICTIONARY_KEY_ARDRONE3_PILOTINGSTATE_FLYINGSTATECHANGED:
                {
                    HASH_FIND_STR(element->arguments, ARCONTROLLER_DICTIONARY_KEY_ARDRONE3_PILOTINGSTATE_FLYINGSTATECHANGED_STATE, arg);
                    if (arg != NULL) {
                        int32_t lastState = pilotingViewController.flyingState;
                        pilotingViewController.flyingState = (eARCOMMANDS_ARDRONE3_PILOTINGSTATE_FLYINGSTATECHANGED_STATE)(arg->value.I32);
                        if (lastState == ARCOMMANDS_ARDRONE3_PILOTINGSTATE_FLYINGSTATECHANGED_STATE_TAKINGOFF) {
                            // it means that takingoff is just completed
                            // set isFirstCallbration to TRUE to do first calibration
                            [pilotingViewController.locationManager startUpdatingHeading];
                            pilotingViewController.isFirstCalibration = true;
                        }
                        else if (lastState == ARCOMMANDS_ARDRONE3_PILOTINGSTATE_FLYINGSTATECHANGED_STATE_LANDING) {
                            [pilotingViewController.videoCamera stop];
                            pilotingViewController.takeoffView.hidden = false;
                            [pilotingViewController.view bringSubviewToFront: pilotingViewController.takeoffView];
                        }
                    }
                    break;
                }
                    
                default:
                    break;
            }
        }
    }
}

void didReceiveFrameCallback (ARCONTROLLER_Frame_t *frame, void *customData)
{
    PilotingViewController *pilotingViewController = (__bridge PilotingViewController *)customData;
    
    [pilotingViewController.previewVideo displayFrame:frame];
    [pilotingViewController.videoView displayFrame:frame];
}

#pragma mark CV method
cv::String intToString(int number){
    std::stringstream ss;
    ss << number;
    return ss.str();
}

void drawObject(std::vector<Object> theObjects,cv::Mat &frame, cv::Mat &temp, std::vector< std::vector<cv::Point> > contours, std::vector<cv::Vec4i> hierarchy) {
    for(int i =0; i<theObjects.size(); i++){
        cv::drawContours(frame,contours,i,theObjects.at(i).getColor(),3,8,hierarchy);
    }
}

void morphOps(cv::Mat &thresh) {
    cv::Mat erodeElement=getStructuringElement(cv::MORPH_RECT, cv::Size(3,3));
    cv::Mat dilateElement = getStructuringElement( cv::MORPH_RECT,cv::Size(8,8));
    
    erode(thresh,thresh,erodeElement);
    erode(thresh,thresh,erodeElement);
    
    dilate(thresh,thresh,dilateElement);
    dilate(thresh,thresh,dilateElement);
}


std::vector<Object> trackFilteredObject(Object theObject,cv::Mat threshold,cv::Mat HSV, cv::Mat &cameraFeed) {
    std::vector <Object> objects;
    cv::Mat temp;
    threshold.copyTo(temp);
    //these two vectors needed for output of findContours
    std::vector< std::vector<cv::Point> > contours;
    std::vector<cv::Vec4i> hierarchy;
    //find contours of filtered image using openCV findContours function
    findContours(temp,contours,hierarchy,CV_RETR_CCOMP,CV_CHAIN_APPROX_SIMPLE );
    //use moments method to find our filtered object
    double refArea = 0;
    bool objectFound = false;
    if (hierarchy.size() > 0) {
        int numObjects = hierarchy.size();
        //if number of objects greater than MAX_NUM_OBJECTS we have a noisy filter
        if(numObjects<MAX_NUM_OBJECTS){
            for (int index = 0; index >= 0; index = hierarchy[index][0]) {
                
                cv::Moments moment = moments((cv::Mat)contours[index]);
                double area = moment.m00;
                
                //if the area is less than 3 px by 3px then it is probably just noise
                //if the area is the same as the 3/2 of the image size, probably just a bad filter
                //we only want the object with the largest area so we safe a reference area each
                //iteration and compare it to the area in the next iteration.
                if(area>MIN_OBJECT_AREA){
                    
                    Object object;
                    
                    object.setXPos(moment.m10/area);
                    object.setYPos(moment.m01/area);
                    object.setArea(area);
                    object.setType(theObject.getType());
                    object.setColor(theObject.getColor());
                    
                    objects.push_back(object);
                    
                    objectFound = true;
                    
                }else objectFound = false;
            }
            //let user know you found an object
            if(objectFound ==true){
                //draw object location on screen
                //drawObject(objects,cameraFeed,temp,contours,hierarchy);
            }
            
        }else putText(cameraFeed,"TOO MUCH NOISE! ADJUST FILTER",cv::Point(0,50),1,2,cv::Scalar(0,0,255),2);
    }
    return objects;
}
#ifdef __cplusplus
- (void)processImage:(cv::Mat&)image;
{
    if ([UIDevice currentDevice].orientation == UIDeviceOrientationPortrait || [UIDevice currentDevice].orientation == UIDeviceOrientationPortraitUpsideDown) {
        std::vector<Object> orangeObjects,blueObjects;
        cv::Mat threshold;
        cv::Mat threshold2;
        cv::Mat HSV;
        cv::cvtColor(image,HSV,cv::COLOR_BGR2HSV);
        Object orange("orange"),blue("blue");
        int row=image.rows,
        col=image.cols;
        orangeFlag=false;
        blueFlag=false;
    
        cvtColor(image,HSV,cv::COLOR_BGR2HSV);
        inRange(HSV,cv::Scalar(0, 130, 160),orange.getHSVmax(),threshold);
        morphOps(threshold);
        inRange(HSV,blue.getHSVmin(),blue.getHSVmax(),threshold2);
        morphOps(threshold2);
    
        orangeObjects=trackFilteredObject(orange,threshold,HSV,image);
        if (orangeObjects.size()>1) {
            orangeFlag=true;
            log(1);
            for (int i=0; i<orangeObjects.size()-1; i++) {
                for (int j=i+1; j<orangeObjects.size(); j++) {
                    int posX=(orangeObjects.at(i).getXPos()+orangeObjects.at(j).getXPos())/2;
                    int posY=(orangeObjects.at(i).getYPos()+orangeObjects.at(j).getYPos())/2;
                
                    if (threshold2.at<uchar>(posY, posX)==255) {
                        blueFlag=true;
                        //兩個橘色面積差小於0.05
                        int area1=orangeObjects.at(i).getArea(),
                        area2=orangeObjects.at(j).getArea();
                        if(abs((area1-area2)/area2)<SIZE_DIFF){
                            //距離與大小比小於5
                            if ((pow(orangeObjects.at(i).getXPos()-orangeObjects.at(j).getXPos(),2)+pow(orangeObjects.at(i).getYPos()-orangeObjects.at(j).getYPos(),2))/(area1+area2)<5) {
                                cv::circle(image,cv::Point(posX,posY),10,cv::Scalar(0,0,255));
                                cv::putText(image,intToString(posX)+ " , " + intToString(posY),cv::Point(posX,posY+20),1,1,cv::Scalar(0,0,255));
                                cv::putText(image,"center",cv::Point(posX,posY-20),1,4,cv::Scalar(0,0,255));
                                if (_isTouch && _isCalibrationOK) {
                                    if (posX<col/2-centerRange) {
                                        // 飛機應向右
                                        NSLog(@"RIGHT");
                                        _deviceController->aRDrone3->setPilotingPCMDFlag(_deviceController->aRDrone3, 1);
                                        _deviceController->aRDrone3->setPilotingPCMDRoll(_deviceController->aRDrone3, -15);
                                    }
                                    else if (posX>col/2+centerRange){
                                        // 飛機應向左
                                        NSLog(@"LEFT");
                                        _deviceController->aRDrone3->setPilotingPCMDFlag(_deviceController->aRDrone3, 1);
                                        _deviceController->aRDrone3->setPilotingPCMDRoll(_deviceController->aRDrone3, 15);
                                    }
                                    else {
                                        // 飛機左右到達定點
                                        NSLog(@"左右STOP");
                                        _deviceController->aRDrone3->setPilotingPCMDFlag(_deviceController->aRDrone3, 0);
                                        _deviceController->aRDrone3->setPilotingPCMDRoll(_deviceController->aRDrone3, 0);
                                    }
                                    if (posY<row/2-centerRange) {
                                        // 飛機應向下
                                        NSLog(@"DOWN");
                                        _deviceController->aRDrone3->setPilotingPCMDGaz(_deviceController->aRDrone3, -15);
                                    }
                                    else if (posY>row/2+centerRange+20){
                                        // 飛機應向上
                                        NSLog(@"UP");
                                        _deviceController->aRDrone3->setPilotingPCMDGaz(_deviceController->aRDrone3, 15);
                                    }
                                    else{
                                        // 飛機上下到達定點
                                        NSLog(@"上下STOP");
                                        _deviceController->aRDrone3->setPilotingPCMDGaz(_deviceController->aRDrone3, 0);
                                    }
                                }
                                else {
                                    [self stopDroneMoving];
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
#endif

#pragma mark events

- (IBAction)takeoffClick:(id)sender
{
    _deviceController->aRDrone3->sendPilotingTakeOff(_deviceController->aRDrone3);
    _takeoffView.hidden = true;
    [self.view sendSubviewToBack:_takeoffView];
    [self.videoCamera start];
}

- (IBAction)landingClick:(id)sender
{
    _deviceController->aRDrone3->sendPilotingLanding(_deviceController->aRDrone3);
    [self.videoCamera stop];
    self.takeoffView.hidden = false;
    [self.view bringSubviewToFront: _takeoffView];
}

////events for gaz:
//- (IBAction)gazUpTouchDown:(id)sender
//{
//    // set the gaz value of the piloting command
//    _deviceController->aRDrone3->setPilotingPCMDGaz(_deviceController->aRDrone3, 50);
//}
//- (IBAction)gazDownTouchDown:(id)sender
//{
//    _deviceController->aRDrone3->setPilotingPCMDGaz(_deviceController->aRDrone3, -50);
//}
//
//- (IBAction)gazUpTouchUp:(id)sender
//{
//    _deviceController->aRDrone3->setPilotingPCMDGaz(_deviceController->aRDrone3, 0);
//}
//- (IBAction)gazDownTouchUp:(id)sender
//{
//    _deviceController->aRDrone3->setPilotingPCMDGaz(_deviceController->aRDrone3, 0);
//}
//
////events for yaw:
//- (IBAction)yawLeftTouchDown:(id)sender
//{
//    _deviceController->aRDrone3->setPilotingPCMDYaw(_deviceController->aRDrone3, -50);
//}
//- (IBAction)yawRightTouchDown:(id)sender
//{
//    _deviceController->aRDrone3->setPilotingPCMDYaw(_deviceController->aRDrone3, 50);
//}
//
//- (IBAction)yawLeftTouchUp:(id)sender
//{
//    _deviceController->aRDrone3->setPilotingPCMDYaw(_deviceController->aRDrone3, 0);
//}
//
//- (IBAction)yawRightTouchUp:(id)sender
//{
//    _deviceController->aRDrone3->setPilotingPCMDYaw(_deviceController->aRDrone3, 0);
//}
//
////events for yaw:
//- (IBAction)rollLeftTouchDown:(id)sender
//{
//    _deviceController->aRDrone3->setPilotingPCMDFlag(_deviceController->aRDrone3, 1);
//    _deviceController->aRDrone3->setPilotingPCMDRoll(_deviceController->aRDrone3, -30);
//}
//- (IBAction)rollRightTouchDown:(id)sender
//{
//    _deviceController->aRDrone3->setPilotingPCMDFlag(_deviceController->aRDrone3, 1);
//    _deviceController->aRDrone3->setPilotingPCMDRoll(_deviceController->aRDrone3, 30);
//}
//
//- (IBAction)rollLeftTouchUp:(id)sender
//{
//    _deviceController->aRDrone3->setPilotingPCMDFlag(_deviceController->aRDrone3, 0);
//    _deviceController->aRDrone3->setPilotingPCMDRoll(_deviceController->aRDrone3, 0);
//}
//- (IBAction)rollRightTouchUp:(id)sender
//{
//    _deviceController->aRDrone3->setPilotingPCMDFlag(_deviceController->aRDrone3, 0);
//    _deviceController->aRDrone3->setPilotingPCMDRoll(_deviceController->aRDrone3, 0);
//}
//
////events for pitch:
//- (IBAction)pitchForwardTouchDown:(id)sender
//{
//    _deviceController->aRDrone3->setPilotingPCMDFlag(_deviceController->aRDrone3, 1);
//    _deviceController->aRDrone3->setPilotingPCMDPitch(_deviceController->aRDrone3, 50);
//}
//- (IBAction)pitchBackTouchDown:(id)sender
//{
//    _deviceController->aRDrone3->setPilotingPCMDFlag(_deviceController->aRDrone3, 1);
//    _deviceController->aRDrone3->setPilotingPCMDPitch(_deviceController->aRDrone3, -50);
//}
//
//- (IBAction)pitchForwardTouchUp:(id)sender
//{
//    _deviceController->aRDrone3->setPilotingPCMDFlag(_deviceController->aRDrone3, 0);
//    _deviceController->aRDrone3->setPilotingPCMDPitch(_deviceController->aRDrone3, 0);
//}
//- (IBAction)pitchBackTouchUp:(id)sender
//{
//    _deviceController->aRDrone3->setPilotingPCMDFlag(_deviceController->aRDrone3, 0);
//    _deviceController->aRDrone3->setPilotingPCMDPitch(_deviceController->aRDrone3, 0);
//}

- (IBAction)stillClicked:(id)sender {
    _deviceController->aRDrone3->sendMediaRecordPictureV2(_deviceController->aRDrone3);
    [self createDataTransferManager];
    [self startMediaListThread];
}

- (void) savePhotoToAlbum:(UIImage *) image {
    UIImageWriteToSavedPhotosAlbum(image, self, @selector(image:didFinishSavingWithError:contextInfo:), nil);
}

//自行建立判斷儲存成功與否的函式
- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo {
    UIAlertView *alert;
    
    //以error參數判斷是否成功儲存影像
    if (error) {
        alert = [[UIAlertView alloc] initWithTitle:@"錯誤"
                                           message:[error description]
                                          delegate:self
                                 cancelButtonTitle:@"確定"
                                 otherButtonTitles:nil];
    } else {
        alert = [[UIAlertView alloc] initWithTitle:@"成功"
                                           message:@"影像已存入相簿中"
                                          delegate:self
                                 cancelButtonTitle:@"確定"
                                 otherButtonTitles:nil];
    }
    [alert show];
    // clean media transfer thread
    [self clean];
}

// method will be called when device's orientation has changed
- (void) orientationChanged: (NSNotification *) note {
    UIDevice *device = [UIDevice currentDevice];
    
    if (device.orientation == UIDeviceOrientationPortrait || device.orientation == UIDeviceOrientationPortraitUpsideDown) {
        // display pilotingView
        _pictureView.hidden = true;
        [self.view sendSubviewToBack:_pictureView];
        // set drone's camera tilt and pan face to forward
        _deviceController->aRDrone3->sendCameraOrientation(_deviceController->aRDrone3,0,0);
    }
    else if (device.orientation == UIDeviceOrientationLandscapeLeft || device.orientation == UIDeviceOrientationLandscapeRight) {
        // display VideoView
        _pictureView.hidden = false;
        [self.view bringSubviewToFront:_pictureView];
    }
}

#pragma mark UI updates from commands
- (void)onUpdateBatteryLevel:(uint8_t)percent;
{
    NSLog(@"onUpdateBattery ...");
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *text = [[NSString alloc] initWithFormat:@"%d%%", percent];
        [_batteryLabel setText:text];
    });
}

#pragma mark resolveService
- (BOOL)resolveService:(ARService*)service
{
    BOOL retval = NO;
    _resolveSemaphore = dispatch_semaphore_create(0);
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(discoveryDidResolve:) name:kARDiscoveryNotificationServiceResolved object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(discoveryDidNotResolve:) name:kARDiscoveryNotificationServiceNotResolved object:nil];
    
    [[ARDiscovery sharedInstance] resolveService:service];
    
    // this semaphore will be signaled in discoveryDidResolve and discoveryDidNotResolve
    dispatch_semaphore_wait(_resolveSemaphore, DISPATCH_TIME_FOREVER);
    
    NSString *ip = [[ARDiscovery sharedInstance] convertNSNetServiceToIp:service];
    if (ip != nil)
    {
        retval = YES;
    }
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kARDiscoveryNotificationServiceResolved object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kARDiscoveryNotificationServiceNotResolved object:nil];
    _resolveSemaphore = nil;
    return retval;
}

- (void)discoveryDidResolve:(NSNotification *)notification
{
    dispatch_semaphore_signal(_resolveSemaphore);
}

- (void)discoveryDidNotResolve:(NSNotification *)notification
{
    NSLog(@"Resolve failed");
    dispatch_semaphore_signal(_resolveSemaphore);
}

#pragma mark CLLocationManagerDelegate protocol method
- (void) locationManager:(CLLocationManager *)manager didUpdateHeading:(CLHeading *)newHeading {
    _phoneHeading = newHeading.magneticHeading;
}

#pragma mark touch events handle
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    UIDevice *device = [UIDevice currentDevice];
    if (device.orientation == UIDeviceOrientationPortrait || device.orientation == UIDeviceOrientationPortraitUpsideDown) {
        _isTouch = true;
        [_locationManager startUpdatingHeading];
    }
}

//// stop update phone heading and calibration when touch is end
//// no matter whether calibration is completed or not
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    if (_isTouch) {
        _isTouch = false;
        [self stopHeadingCalibration];
        [self stopDroneMoving];
        [_locationManager stopUpdatingHeading];
    }
}
#pragma mark pan gestures events handle
// pan gesture on imageView to control the drone forward and backward
- (IBAction) panonImageView:(UIPanGestureRecognizer *)sender {
    CGPoint vel = [sender velocityInView:imageView];
    if (vel.y > 200) { // backward
        NSLog(@"PAN DOWN");
        _deviceController->aRDrone3->setPilotingPCMDFlag(_deviceController->aRDrone3, 1);
        _deviceController->aRDrone3->setPilotingPCMDPitch(_deviceController->aRDrone3, -15);
    }
    else if (vel.y < -200) { // forward
        NSLog(@"PAN TOP");
        _deviceController->aRDrone3->setPilotingPCMDFlag(_deviceController->aRDrone3, 1);
        _deviceController->aRDrone3->setPilotingPCMDPitch(_deviceController->aRDrone3, 15);
    }
    if (sender.state == UIGestureRecognizerStateEnded) {
        NSLog(@"PAN STOP");
        _deviceController->aRDrone3->setPilotingPCMDFlag(_deviceController->aRDrone3, 0);
        _deviceController->aRDrone3->setPilotingPCMDPitch(_deviceController->aRDrone3, 0);
        if (_isTouch) {
            _isTouch = false;
            [self stopHeadingCalibration];
            [self stopDroneMoving];
            [_locationManager stopUpdatingHeading];
        }
    }
}
// pan gesture on VideoView to control drone's camera tilt and pan
- (IBAction) panonVideoView:(UIPanGestureRecognizer *)sender {
    CGPoint vel = [sender velocityInView:_videoView];
    int8_t tiltValue = 0;
    int8_t panValue = 0;
    if (vel.x > 50) { // right
        NSLog(@"PAN RIGHT");
        panValue += 5;
        _deviceController->aRDrone3->sendCameraOrientation(_deviceController->aRDrone3,tiltValue,panValue);
    }
    else if (vel.x < -50){ // left
        NSLog(@"PAN LEFT");
        panValue -= 5;
        _deviceController->aRDrone3->sendCameraOrientation(_deviceController->aRDrone3,tiltValue,panValue);
    }
    if (vel.y > 50) { // down
        NSLog(@"PAN DOWN");
        tiltValue -= 5;
        _deviceController->aRDrone3->sendCameraOrientation(_deviceController->aRDrone3,tiltValue,panValue);
    }
    else if (vel.y < -50) { // top
        NSLog(@"PAN TOP");
        tiltValue += 5;
        _deviceController->aRDrone3->sendCameraOrientation(_deviceController->aRDrone3,tiltValue,panValue);
    }
}
#pragma mark heading calibration method
- (void) checkHeading {
    // check whether the heading of drone need to calibration
    float expectedHeading;
    if (_phoneHeading >= 180) {
        expectedHeading = _phoneHeading - 180;
    }
    else {
        expectedHeading = _phoneHeading + 180;
    }

    float diff = expectedHeading - _droneHeading;
    if ( diff < -ALLOWANCE_THRESHOLD || diff > ALLOWANCE_THRESHOLD ) {
        _isCalibrationOK = false;
        [self headingCalibration:expectedHeading];
    }
    else {
        // if heading is ok, stop the rotation of yaw
        _isCalibrationOK = true;
        [self stopHeadingCalibration];
        if (_isFirstCalibration) {
            // first calibration completed, stop phoneHeading update and hide takeoffView
            NSLog(@"First calibration completed");
            _isFirstCalibration = false;
            [self.locationManager stopUpdatingHeading];
            _takeoffView.hidden = true;
            [self.view sendSubviewToBack:_takeoffView];
            [self.videoCamera start];
        }
    }
}

- (void) headingCalibration: (float) expectedHeading {
    if (expectedHeading <= 180) {
        if ( (_droneHeading < expectedHeading) || (_droneHeading > _phoneHeading) ) {
            // Clockwise
            _deviceController->aRDrone3->setPilotingPCMDYaw(_deviceController->aRDrone3, 50);
        }
        else {
            // Counterclockwise
            _deviceController->aRDrone3->setPilotingPCMDYaw(_deviceController->aRDrone3, -50);
        }
    }
    else {
        if ( (_droneHeading < expectedHeading) && (_droneHeading > _phoneHeading) ) {
            // Clockwise
            _deviceController->aRDrone3->setPilotingPCMDYaw(_deviceController->aRDrone3, 50);
        }
        else {
            // Counterclockwise
            _deviceController->aRDrone3->setPilotingPCMDYaw(_deviceController->aRDrone3, -50);
        }
    }
}

- (void) stopHeadingCalibration {
    _deviceController->aRDrone3->setPilotingPCMDYaw(_deviceController->aRDrone3, 0);
}

- (void) stopDroneMoving {
    _deviceController->aRDrone3->setPilotingPCMDFlag(_deviceController->aRDrone3, 0);
    _deviceController->aRDrone3->setPilotingPCMDRoll(_deviceController->aRDrone3, 0);
    _deviceController->aRDrone3->setPilotingPCMDGaz(_deviceController->aRDrone3, 0);
}

#pragma mark dataTransfer
// Create the data transfer manager
- (void)createDataTransferManager
{
    NSString *productIP = @"192.168.42.1";

    eARDATATRANSFER_ERROR result = ARDATATRANSFER_OK;
    _manager = ARDATATRANSFER_Manager_New(&result);
    
    if (result == ARDATATRANSFER_OK)
    {
        eARUTILS_ERROR ftpError = ARUTILS_OK;
        _ftpListManager = ARUTILS_Manager_New(&ftpError);
        if(ftpError == ARUTILS_OK)
        {
            _ftpQueueManager = ARUTILS_Manager_New(&ftpError);
        }
        
        if(ftpError == ARUTILS_OK)
        {
            ftpError = ARUTILS_Manager_InitWifiFtp(_ftpListManager, [productIP UTF8String], DEVICE_PORT, ARUTILS_FTP_ANONYMOUS, "");
        }
        
        if(ftpError == ARUTILS_OK)
        {
            ftpError = ARUTILS_Manager_InitWifiFtp(_ftpQueueManager, [productIP UTF8String], DEVICE_PORT, ARUTILS_FTP_ANONYMOUS, "");
        }
        
        if(ftpError != ARUTILS_OK)
        {
            result = ARDATATRANSFER_ERROR_FTP;
        }
    }
    // NO ELSE
    
    if (result == ARDATATRANSFER_OK)
    {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *path = [paths lastObject];
        
        result = ARDATATRANSFER_MediasDownloader_New(_manager, _ftpListManager, _ftpQueueManager, MEDIA_FOLDER, [path UTF8String]);
    }
}

- (void)startMediaListThread
{
    // first retrieve Medias without their thumbnails
    ARSAL_Thread_Create(&_threadRetreiveAllMedias, ARMediaStorage_retreiveAllMediasAsync, (__bridge void *)self);
}

static void* ARMediaStorage_retreiveAllMediasAsync(void* arg)
{
    PilotingViewController *self = (__bridge PilotingViewController *)(arg);
    [self getAllMediaAsync];
    return NULL;
}

- (void)getAllMediaAsync
{
    eARDATATRANSFER_ERROR result = ARDATATRANSFER_OK;
    int mediaListCount = 0;
    ARDATATRANSFER_Media_t * mediaObject;
    
    if (result == ARDATATRANSFER_OK)
    {
        mediaListCount = ARDATATRANSFER_MediasDownloader_GetAvailableMediasSync(_manager,0,&result);
        if (result == ARDATATRANSFER_OK)
        {
            for (int i = 0 ; i < mediaListCount && result == ARDATATRANSFER_OK; i++)
            {
                mediaObject = ARDATATRANSFER_MediasDownloader_GetAvailableMediaAtIndex(_manager, i, &result);
                NSLog(@"Media %i : %s", i, mediaObject->name);
                // Do what you want with this mediaObject
            }
        }
//        [self downloadMedias:mediaObject withCount:1];
//        NSLog(@"Call download thumbnails");
        [self startMediaThumbnailDownloadThread];
    }
}

#pragma mark Download methods
- (void)startMediaThumbnailDownloadThread
{
    // first retrieve Medias without their thumbnails
    ARSAL_Thread_Create(&_threadGetThumbnails, ARMediaStorage_retreiveMediaThumbnailsSync, (__bridge void *)self);
}

static void* ARMediaStorage_retreiveMediaThumbnailsSync(void* arg)
{
    PilotingViewController *self = (__bridge PilotingViewController *)(arg);
    [self downloadThumbnails];
    return NULL;
}

- (void)downloadThumbnails
{
    ARDATATRANSFER_MediasDownloader_GetAvailableMediasAsync(_manager, availableMediaCallback, (__bridge void *)self);
}

void availableMediaCallback (void* arg, ARDATATRANSFER_Media_t *media, int index)
{
    if (NULL != arg)
    {
        PilotingViewController *self = (__bridge PilotingViewController *)(arg);
        // you can alternatively call updateThumbnailWithARDATATRANSFER_Media_t if you use the ARMediaObjectDelegate
        UIImage *newThumbnail = [UIImage imageWithData:[NSData dataWithBytes:media->thumbnail length:media->thumbnailSize]];
        // Do what you want with the image
        [self savePhotoToAlbum:newThumbnail];
    }
}

//- (void)downloadMedias:(ARDATATRANSFER_Media_t *)medias withCount:(int)count
//{
//    eARDATATRANSFER_ERROR result = ARDATATRANSFER_OK;
//    for (int i = 0 ; i < count && result == ARDATATRANSFER_OK; i++)
//    {
//        ARDATATRANSFER_Media_t *media = &medias[i];
//        
//        result = ARDATATRANSFER_MediasDownloader_AddMediaToQueue(_manager, media, medias_downloader_progress_callback, (__bridge void *)(self), medias_downloader_completion_callback,(__bridge void*)self);
//    }
//    
//    if (result == ARDATATRANSFER_OK)
//    {
//        if (_threadMediasDownloader == NULL)
//        {
//            // if not already started, start download thread in background
//            ARSAL_Thread_Create(&_threadMediasDownloader, ARDATATRANSFER_MediasDownloader_QueueThreadRun, _manager);
//        }
//    }
//}
//void medias_downloader_progress_callback(void* arg, ARDATATRANSFER_Media_t *media, float percent)
//{
//    // the media is downloading
//}
//
//void medias_downloader_completion_callback(void* arg, ARDATATRANSFER_Media_t *media, eARDATATRANSFER_ERROR error)
//{
//    PilotingViewController *self = (__bridge PilotingViewController *)(arg);
//    // the media is downloaded
//    NSLog(@"Media downloaded: %s",media->name);
//    UIImage *img = [UIImage imageWithData:[NSData dataWithBytes:media->thumbnail length:media->thumbnailSize]];
//    NSLog(@"Media save to album");
//    [self savePhotoToAlbum:img];
//}
//
//- (void)cancelCurrentDownload {
//    if (_threadMediasDownloader != NULL)
//    {
//        ARDATATRANSFER_MediasDownloader_CancelQueueThread(_manager);
//        
//        ARSAL_Thread_Join(_threadMediasDownloader, NULL);
//        ARSAL_Thread_Destroy(&_threadMediasDownloader);
//        _threadMediasDownloader = NULL;
//    }
//}

- (void)clean
{
    if (_threadRetreiveAllMedias != NULL)
    {
        ARDATATRANSFER_MediasDownloader_CancelGetAvailableMedias(_manager);
        
        ARSAL_Thread_Join(_threadRetreiveAllMedias, NULL);
        ARSAL_Thread_Destroy(&_threadRetreiveAllMedias);
        _threadRetreiveAllMedias = NULL;
    }
    
    if (_threadGetThumbnails != NULL)
    {
        ARDATATRANSFER_MediasDownloader_CancelGetAvailableMedias(_manager);
        
        ARSAL_Thread_Join(_threadGetThumbnails, NULL);
        ARSAL_Thread_Destroy(&_threadGetThumbnails);
        _threadGetThumbnails = NULL;
    }
    
    if (_threadMediasDownloader != NULL)
    {
        ARDATATRANSFER_MediasDownloader_CancelQueueThread(_manager);
        
        ARSAL_Thread_Join(_threadMediasDownloader, NULL);
        ARSAL_Thread_Destroy(&_threadMediasDownloader);
        _threadMediasDownloader = NULL;
    }
    
    ARDATATRANSFER_MediasDownloader_Delete(_manager);
    
    ARUTILS_Manager_CloseWifiFtp(_ftpListManager);
    ARUTILS_Manager_CloseWifiFtp(_ftpQueueManager);
    
    ARUTILS_Manager_Delete(&_ftpListManager);
    ARUTILS_Manager_Delete(&_ftpQueueManager);
    ARDATATRANSFER_Manager_Delete(&_manager);
}

@end
