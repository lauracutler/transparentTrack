function prepareVideo(inputVideoName, outputVideoName, varargin)

%  This fuction converts the video to a "gray frames array" that is stored
%  in the memory and ready to be tracked or written to file. With the
%  default options the routine will scale and crop the video to livetrack
%  standard size.

% Output
% ======
%       a gray video is saved out
%
% Input
% =====
%       inputVideoName
%       outputVideoName
%
% Options
% =======
%       numberOfFrames : number of frames to process. If not specified or
%           Inf will process the full video.
%       resizeVideo : [Y X] desired output video resolution. (recommended: keep default)
%       cropVideo : [firstX firstY lastX lastY] position of first and last
%           pixels to include in the crop. (recommended: keep default)
%       keepOriginalSize : option to skip video resizing.
%
%  NOTE: if processing videos acquired with the LiveTrack+V.TOP hardware
%  setup, do not alter the default resizing and cropping video options
%
%
% Usage examples
% ==============
%  prepareVideo(inputVideoName,outputVideoName);
%  prepareVideo(inputVideoName,outputVideoName, 'numberOfFrames', 1000) % this will
%       process just the first 1000 frames of the video


%% parse input and define variables

p = inputParser;
% required input
p.addRequired('inputVideoName',@isstr);
p.addRequired('outputVideoName',@isstr);
% optional inputs
p.addParameter('resizeVideo',[486 720]/2, @isnumeric);
p.addParameter('cropVideo', [1 1 319 239], @isnumeric);
p.addParameter('numberOfFrames', Inf, @isnumeric);
p.addParameter('keepOriginalSize', false, @islogic);
%parse
p.parse(inputVideoName,outputVideoName,varargin{:})

% define variables
resizeVideo = p.Results.resizeVideo;
cropVideo = p.Results.cropVideo;
numberOfFrames = p.Results.numberOfFrames;
keepOriginalSize = p.Results.keepOriginalSize;

%% Prepare Video

% load video
disp('Loading video file...');
inObj = VideoReader(inputVideoName);

% create outputVideo object
outObj = VideoWriter(outputVideoName);
outObj.FrameRate = inObj.FrameRate;
open(outObj);

% option to manually set numFrames
if numberOfFrames ~= Inf
    numFrames = numberOfFrames;
else
    numFrames = floor(inObj.Duration*inObj.FrameRate);
end

% Convert to gray, resize, crop, save
progBar = ProgressBar(numFrames,'Converting video to LiveTrack format...');
for ff = 1:numFrames
    thisFrame = readFrame(inObj);
    tmp = rgb2gray(thisFrame);
    if keepOriginalSize == 0
        tmp2 = imresize(tmp,resizeVideo);
        tmp = imcrop(tmp2,cropVideo);
    end
    writeVideo(outObj,tmp);
    % increment progress bar
    if ~mod(ff,10);progBar(ff);end;
end

clear inObj outObj
