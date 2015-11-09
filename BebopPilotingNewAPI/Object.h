#pragma once
#include <string>
#include <opencv2/opencv.hpp>
#include <opencv2/highgui/highgui.hpp>

//using namespace cv;

class Object
{
public:
	Object();
	~Object(void);

	Object(cv::String name);

	int getXPos();
	void setXPos(int x);

	int getYPos();
	void setYPos(int y);

    int getArea();
    void setArea(int a);
    
	 cv::Scalar getHSVmin();
	 cv::Scalar getHSVmax();

	void setHSVmin( cv::Scalar min);
	void setHSVmax( cv::Scalar max);

    cv::String getType(){return type;}
	void setType( cv::String t){type = t;}

    cv::Scalar getColor(){
		return Color;
	}
	void setColor( cv::Scalar c){

		Color = c;
	}

private:

	int xPos, yPos,area;
	 cv::String type;
	 cv::Scalar HSVmin, HSVmax;
	 cv::Scalar Color;
};
