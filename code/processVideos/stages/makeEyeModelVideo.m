function makeEyeModelVideo(videoOutFileName,pupilFileName, sceneGeometryFileName, varargin)
% Create and store a video that displays the eye model fit to the data
%
% Syntax:
%  makeEyeModelVideo(videoOutFileName,pupilFileName, sceneGeometryFileName)
%
% Description:
%   This routine creates a video that illustrates for each frame the
%   appearance of the model eye in the image plane.
%
% Inputs:
%   videoOutFileName      - Full path to the output .avi file
%   pupilFileName         - Full path to a pupil data file. The file must
%                           have an eyePoses field.
%   sceneGeometryFileName - Full path to the sceneGeometry file
%
% Optional key/value pairs (display and I/O):
%  'verbosity'            - Level of verbosity. [none, full]
%  'videoOutFrameRate'    - Frame rate (in Hz) of saved video [default 60]
%  'saveCompressedVideo'  - Default value is true, resulting in a
%                           a video with a 10x reduction in file size
%  'videoSizeX'           - Size of the video in the X dimension
%  'videoSizeY'           - Size of the video in the Y dimension
%  'modelEyeLabelNames'   - A cell array of the classes of eye model points
%                           to be displayed.
%  'modelEyePlotColors'   - The colors to be used for the plotting of each
%                           of the model eye label names.
%  'fitLabel'             - The field of the pupilData file to use
%
% Outputs:
%   None
%

%% Parse vargin for options passed here
p = inputParser; p.KeepUnmatched = true;

% Required
p.addRequired('videoOutFileName', @ischar);
p.addRequired('pupilFileName', @ischar);
p.addRequired('sceneGeometryFileName', @ischar);

% Optional display and I/O params
p.addParameter('verbosity','none', @ischar);
p.addParameter('videoOutFrameRate', 60, @isnumeric);
p.addParameter('saveCompressedVideo', true, @islogical);
p.addParameter('videoSizeX', 640, @isnumeric);
p.addParameter('videoSizeY', 480, @isnumeric);
p.addParameter('modelEyeLabelNames', {'aziRotationCenter', 'eleRotationCenter', 'posteriorChamber' 'irisPerimeter' 'pupilPerimeter' 'anteriorChamber' 'cornealApex'}, @iscell);
p.addParameter('modelEyePlotColors', {'>r' '^m' '.w' 'ob' '*g' '.y' '*y'}, @iscell);
p.addParameter('fitLabel', 'radiusSmoothed', @ischar);

% parse
p.parse(videoOutFileName, pupilFileName, sceneGeometryFileName, varargin{:})


%% Alert the user and prepare variables
if strcmp(p.Results.verbosity,'full')
    tic
    fprintf(['Creating and saving model video. Started ' char(datetime('now')) '\n']);
    fprintf('| 0                      50                   100%% |\n');
    fprintf('.\n');
end

% Read in the pupilData file
dataLoad = load(p.Results.pupilFileName);
pupilData = dataLoad.pupilData;
clear dataLoad
eyePoses = pupilData.(p.Results.fitLabel).eyePoses.values;

% Read in the sceneGeometry file
dataLoad = load(p.Results.sceneGeometryFileName);
sceneGeometry = dataLoad.sceneGeometry;
clear dataLoad

% Assemble the ray tracing functions
[rayTraceFuncs] = assembleRayTraceFuncs( sceneGeometry );

% Open a video object for writing
if p.Results.saveCompressedVideo
    videoOutObj = VideoWriter(videoOutFileName);
    videoOutObj.FrameRate = p.Results.videoOutFrameRate;
    open(videoOutObj);
else
    % Create a color map
    cmap = [linspace(0,1,256)' linspace(0,1,256)' linspace(0,1,256)'];
    cmap(1,:)=[1 0 0];
    cmap(2,:)=[0 1 0];
    cmap(3,:)=[0 0 1];
    cmap(4,:)=[1 1 0];
    cmap(5,:)=[0 1 1];
    cmap(6,:)=[1 0 1];
    
    videoOutObj = VideoWriter(videoOutFileName,'Indexed AVI');
    videoOutObj.FrameRate = p.Results.videoOutFrameRate;
    videoOutObj.Colormap = cmap;
    open(videoOutObj);
end

% A blank frame to initialize each frame
blankFrame = zeros(p.Results.videoSizeY,p.Results.videoSizeX)+0.5;

% Obtain the number of frames
nFrames = size(eyePoses,1);

% Open a figure
frameFig = figure( 'Visible', 'off');

%% Loop through the frames
for ii = 1:nFrames
    
    % Update the progress display
    if strcmp(p.Results.verbosity,'full') && mod(ii,round(nFrames/50))==0
        fprintf('\b.\n');
    end
    
    % Plot the blank frame
    imshow(blankFrame, 'Border', 'tight');
    hold on
    axis off
    axis equal
    xlim([0 p.Results.videoSizeX]);
    ylim([0 p.Results.videoSizeY]);
    
    if ~any(isnan(eyePoses(ii,:)))
        
        % Obtain the pupilProjection of the model eye to the image plane
        [pupilEllipseParams, imagePoints, ~, ~, pointLabels] = pupilProjection_fwd(eyePoses(ii,:), sceneGeometry, rayTraceFuncs, 'fullEyeModelFlag', true);
        
        % Loop through the point labels present in the eye model
        for pp = 1:length(p.Results.modelEyeLabelNames)
            idx = strcmp(pointLabels,p.Results.modelEyeLabelNames{pp});
            if strcmp(p.Results.modelEyeLabelNames{pp},'pupilPerimeter')
                % Just before we plot the pupil perimeter points, add the
                % pupil fit ellipse
                pFitImplicit = ellipse_ex2im(ellipse_transparent2ex(pupilEllipseParams));
                fh=@(x,y) pFitImplicit(1).*x.^2 +pFitImplicit(2).*x.*y +pFitImplicit(3).*y.^2 +pFitImplicit(4).*x +pFitImplicit(5).*y +pFitImplicit(6);
                % superimpose the ellipse using fimplicit or ezplot (ezplot
                % is the fallback option for older Matlab versions)
                if exist('fimplicit','file')==2
                    fimplicit(fh,[1, p.Results.videoSizeX, 1, p.Results.videoSizeY],'Color', 'g','LineWidth',1);
                    set(gca,'position',[0 0 1 1],'units','normalized')
                    axis off;
                else
                    plotHandle=ezplot(fh,[1, videoSizeX, 1, videoSizeY]);
                    set(plotHandle, 'Color', p.Results.pupilColor)
                    set(plotHandle,'LineWidth',1);
                end
            end
            plot(imagePoints(idx,1), imagePoints(idx,2), p.Results.modelEyePlotColors{pp})
        end
        
    end
    
    % Clean up the plot
    hold off
    
    % Get the frame and close the figure
    thisFrame=getframe(frameFig);
    
    % Write out this frame
    if p.Results.saveCompressedVideo
        thisFrame = squeeze(thisFrame);
        writeVideo(videoOutObj,thisFrame);
    else
        indexedFrame = rgb2ind(thisFrame, cmap, 'nodither');
        writeVideo(videoOutObj,indexedFrame);
    end
    
end % Loop over frames


%% Save and cleanup

% Close the figure
close(frameFig);

% close the video objects
clear videoOutObj videoInObj

% report completion of fit video generation
if strcmp(p.Results.verbosity,'full')
    toc
    fprintf('\n');
end


end % function
