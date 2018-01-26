function [pupilData] = fitPupilPerimeter(perimeterFileName, pupilFileName, varargin)
% Perform non-linear, constrained ellipse fitting to pupil perimeters
%
% Description:
%   This routine fits an ellipse to each frame of a video that contains the
%   perimeter of the pupil. A non-linear search routine is used, with
%   optional, non-linear constraints on the eccentricity and theta of the
%   ellipse that are informed by scene geometry. An estimate of the
%   standard deviation of the parameters of the best fitting ellipse are
%   calculated and stored as well.
%
% Notes:
%   Image coordinates -  MATLAB uses an "intrinsic" coordinate system such
%   that the center of each pixel in an image corresponds to its integer
%   indexed position. Thus a 3x3 pixel image in intrisic coordinates is
%   represented on a grid with xlim = [0.5 3.5] and ylim = [0.5 3.5], with
%   the origin being the top left corner of the image. This is done to
%   facilitate the handling of images in many of the built-in image
%   processing functions. This routine outputs results in intrinsic
%   coordinates. Additinal information regarding the MATLAB image
%   coordinate system may be found here:
%       https://blogs.mathworks.com/steve/2013/08/28/introduction-to-spatial-referencing/
%
%   Parallel pool - Controlled by the key/value pair 'useParallel'. The
%   routine should gracefully fall-back on serial processing if the
%   parallel pool is unavailable. Each worker requires ~8 GB of memory to
%   operate. It is important to keep total RAM usage below the physical
%   memory limit to prevent swapping and a dramatic slow down in
%   processing. To use the parallel pool with TbTb, provide the identity of
%   the repo name in the 'tbtbRepoName', which is then used to configure
%   the workers.
%
% Inputs:
%   perimeterFileName     - Full path to a .mat file that contains the
%                           pupil perimeter data.
%   pupilFileName         - Full path to the .mat file in which to save
%                           the results of the ellipse fitting.
%
% Optional key/value pairs (display and I/O):
%  'verbosity'            - Level of verbosity. [none, full]
%
% Optional key/value pairs (flow control)
%  'nFrames'              - Analyze fewer than the total number of frames.
%  'useParallel'          - If set to true, use the Matlab parallel pool
%  'nWorkers'             - Specify the number of workers in the parallel
%                           pool. If undefined the default number will be
%                           used.
%  'tbtbProjectName'      - The workers in the parallel pool are configured
%                           by issuing a tbUseProject command for the
%                           project specified here.
%
% Optional key/value pairs (environment)
%  'tbSnapshot'           - This should contain the output of the
%                           tbDeploymentSnapshot performed upon the result
%                           of the tbUse command. This documents the state
%                           of the system at the time of analysis.
%  'timestamp'            - AUTOMATIC; The current time and date
%  'username'             - AUTOMATIC; The user
%  'hostname'             - AUTOMATIC; The host
%
% Optional key/value pairs (fitting)
%  'ellipseTransparentLB/UB' - Define the hard upper and lower boundaries
%                           for the ellipse fit, in units of pixels of the
%                           video. The default values selected here
%                           represent the physical and mathematical limits,
%                           as the constraint for the fit will be provided
%                           by the scene geometry. A mild constraint (0.6)
%                           is placed upon the eccentricity, corresponding
%                           to an aspect ration of 4:5.
%  'eyeParamsLB/UB'       - Upper and lower bounds on the eyeParams
%                           [azimuth, elevation, pupil radius]. Biological
%                           limits in eye rotation and pupil size would
%                           suggest boundaries of [�35, �25, 0.5-5]. Note,
%                           however, that these angles are relative to the
%                           center of projection, not the primary position
%                           of the eye. Therefore, in circumstances in
%                           which the camera is viewing the eye from an
%                           off-center angle, the bounds will need to be
%                           shifted accordingly.
%  'nSplits'              - The number of tests upon the spatial split-
%                           halves of the pupil boundary values to examine
%                           to estimate the SD of the fitting parameters.
%  'sceneGeometryFileName' - Full path to a sceneGeometry file. When the
%                           sceneGeometry is available, fitting is
%                           performed in terms of eye parameters instead of
%                           ellipse parameters
%
% Outputs:
%	pupilData             - A structure with multiple fields corresponding
%                           to the parameters, SDs, and errors of the
%                           fit. Different field names are used
%                           depending upon if a sceneGeometry constraint
%                           was or was not used.
%

%% Parse vargin for options passed here
p = inputParser; p.KeepUnmatched = true;

% Required
p.addRequired('perimeterFileName',@ischar);
p.addRequired('pupilFileName',@ischar);

% Optional display and I/O params
p.addParameter('verbosity','none',@ischar);

% Optional flow control params
p.addParameter('nFrames',Inf,@isnumeric);
p.addParameter('useParallel',false,@islogical);
p.addParameter('nWorkers',[],@(x)(isempty(x) | isnumeric(x)));
p.addParameter('tbtbRepoName','transparentTrack',@ischar);

% Optional environment params
p.addParameter('tbSnapshot',[],@(x)(isempty(x) | isstruct(x)));
p.addParameter('timestamp',char(datetime('now')),@ischar);
p.addParameter('hostname',char(java.lang.System.getProperty('user.name')),@ischar);
p.addParameter('username',char(java.net.InetAddress.getLocalHost.getHostName),@ischar);

% Optional analysis params
p.addParameter('ellipseTransparentLB',[0,0,800,0,0],@(x)(isempty(x) | isnumeric(x)));
p.addParameter('ellipseTransparentUB',[640,480,20000,0.6,pi],@(x)(isempty(x) | isnumeric(x)));
p.addParameter('eyeParamsLB',[-35,-25,0,0.25],@(x)(isempty(x) | isnumeric(x)));
p.addParameter('eyeParamsUB',[35,25,0,4],@(x)(isempty(x) | isnumeric(x)));
p.addParameter('nSplits',2,@isnumeric);
p.addParameter('sceneGeometryFileName',[],@(x)(isempty(x) | ischar(x)));
p.addParameter('fitLabel',[],@(x)(isempty(x) | ischar(x)));


%% Parse and check the parameters
p.parse(perimeterFileName, pupilFileName, varargin{:});

nEllipseParams=5; % 5 params in the transparent ellipse form
nEyeParams=4; % 4 values (azimuth, elevation, torsion, pupil radius) for eyeParams


%% Load data
% Load the pupil perimeter data. It will be a structure variable
% "perimeter", with the fields .data and .meta
dataLoad=load(perimeterFileName);
perimeter=dataLoad.perimeter;
clear dataLoad

% Optionally load a sceneGeometry file
if isempty(p.Results.sceneGeometryFileName)
    sceneGeometry=[];
else
    % load the sceneGeometry structure
    dataLoad=load(p.Results.sceneGeometryFileName);
    sceneGeometry=dataLoad.sceneGeometry;
    clear dataLoad
end

% Optionally load the pupilData file
if exist(p.Results.pupilFileName, 'file') == 2
    dataLoad=load(pupilFileName);
    pupilData=dataLoad.pupilData;
    clear dataLoad
else
    pupilData=[];
end

% determine how many frames we will process
if p.Results.nFrames == Inf
    nFrames=size(perimeter.data,1);
else
    nFrames = p.Results.nFrames;
end


%% Prepare some functions
% Create an anonymous function to return a rotation matrix given theta in
% radians
returnRotMat = @(theta) [cos(theta) -sin(theta); sin(theta) cos(theta)];

% If sceneGeometry is defined, prepare the ray tracing functions
if ~isempty(sceneGeometry)
    if strcmp(p.Results.verbosity,'full')
        fprintf('Assembling ray tracing functions.\n');
    end
    [rayTraceFuncs] = assembleRayTraceFuncs( sceneGeometry );
else
    rayTraceFuncs = [];
end


%% Set up the parallel pool
if p.Results.useParallel
    if strcmp(p.Results.verbosity,'full')
        tic
        fprintf(['Opening parallel pool. Started ' char(datetime('now')) '\n']);
    end
    if isempty(p.Results.nWorkers)
        parpool;
    else
        parpool(p.Results.nWorkers);
    end
    poolObj = gcp;
    if isempty(poolObj)
        nWorkers=0;
    else
        nWorkers = poolObj.NumWorkers;
        % Use TbTb to configure the workers.
        if ~isempty(p.Results.tbtbRepoName)
            spmd
                tbUse(p.Results.tbtbRepoName,'reset','full','verbose',false,'online',false);
            end
            if strcmp(p.Results.verbosity,'full')
                fprintf('CAUTION: Any TbTb messages from the workers will not be shown.\n');
            end
        end
    end
    if strcmp(p.Results.verbosity,'full')
        toc
        fprintf('\n');
    end
else
    nWorkers=0;
end


%% Calculate an ellipse fit for each video frame

% Recast perimeter into a sliced cell array to reduce par for
% broadcast overhead
frameCellArray = perimeter.data(1:nFrames);
clear perimeter

% Set-up other variables to be non-broadcast
verbosity = p.Results.verbosity;
ellipseTransparentLB = p.Results.ellipseTransparentLB;
ellipseTransparentUB = p.Results.ellipseTransparentUB;
eyeParamsLB = p.Results.eyeParamsLB;
eyeParamsUB = p.Results.eyeParamsUB;
nSplits = p.Results.nSplits;

% Alert the user
if strcmp(p.Results.verbosity,'full')
    tic
    fprintf(['Ellipse fitting to pupil perimeter. Started ' char(datetime('now')) '\n']);
    fprintf('| 0                      50                   100%% |\n');
    fprintf('.\n');
end

% Loop through the frames
parfor (ii = 1:nFrames, nWorkers)
    
    % Update progress
    if strcmp(verbosity,'full')
        if mod(ii,round(nFrames/50))==0
            fprintf('\b.\n');
        end
    end
    
    % Initialize the results variables
    ellipseParamsTransparent=NaN(1,nEllipseParams);
    ellipseParamsSplitsSD=NaN(1,nEllipseParams);
    ellipseParamsObjectiveError=NaN(1);
    eyeParams=NaN(1,nEyeParams);
    eyeParamsSplitsSD=NaN(1,nEyeParams);
    eyeParamsObjectiveError=NaN(1);
    pFitTransparentSplit=NaN(1,nSplits,nEllipseParams);
    pFitEyeParamSplit=NaN(1,nSplits,nEyeParams);
    
    % get the boundary points
    Xp = frameCellArray{ii}.Xp;
    Yp = frameCellArray{ii}.Yp;
    
    % fit an ellipse to the boundary (if any points exist)
    if ~isempty(Xp) && ~isempty(Yp)
        try % this is to have information on which frame caused an error
            
            % Obtain the fit to the veridical data
            if isempty(sceneGeometry)
                [ellipseParamsTransparent, ellipseParamsObjectiveError] = ...
                    constrainedEllipseFit(Xp, Yp, ...
                    ellipseTransparentLB, ...
                    ellipseTransparentUB, ...
                    []);
            else
                % Identify the best fitting eye parameters for the  the
                % pupil perimeter
                eyeParams_x0 = [0 0 0 2];
                [eyeParams, eyeParamsObjectiveError] = ...
                    eyeParamEllipseFit(Xp, Yp, sceneGeometry, rayTraceFuncs, 'x0', eyeParams_x0, 'eyeParamsLB', eyeParamsLB, 'eyeParamsUB', eyeParamsUB);
                % Obtain the parameters of the ellipse
                ellipseParamsTransparent = ...
                    pupilProjection_fwd(eyeParams, sceneGeometry, rayTraceFuncs);
            end
            
            % Re-calculate fit for splits of data points, if requested
            if nSplits == 0
                if isempty(sceneGeometry)
                    ellipseParamsSplitsSD=NaN(1,nEllipseParams);
                else
                    eyeParamsSplitsSD=NaN(1,nEyeParams);
                end
            else
                % Find the center of the pupil boundary points, place the boundary
                % points in a matrix and shift them to the center position
                xCenter=mean(Xp); yCenter=mean(Yp);
                centerMatrix = repmat([xCenter'; yCenter'], 1, length(Xp));
                
                % Prepare a variable to hold the results of the split data
                % fits
                if isempty(sceneGeometry)
                    pFitTransparentSplit=NaN(2,nSplits,nEllipseParams);
                else
                    pFitEyeParamSplit=NaN(2,nSplits,nEyeParams);
                end
                % Loop across the number of requested splits
                for ss=1:nSplits
                    % Rotate the data and split in half through the center
                    theta=((pi/2)/nSplits)*ss;
                    forwardPoints = feval(returnRotMat,theta) * ([Xp,Yp]' - centerMatrix) + centerMatrix;
                    splitIdx1 = find((forwardPoints(1,:) < median(forwardPoints(1,:))))';
                    splitIdx2 = find((forwardPoints(1,:) >= median(forwardPoints(1,:))))';
                    % Fit the split sets of pupil boundary points
                    if isempty(sceneGeometry)
                        % We don't have sceneGeometry defined, so fit an
                        % ellipse to the splits of the pupil perimeter
                        pFitTransparentSplit(1,ss,:) = ...
                            constrainedEllipseFit(Xp(splitIdx1), Yp(splitIdx1), ...
                            ellipseTransparentLB, ...
                            ellipseTransparentUB, ...
                            []);
                        pFitTransparentSplit(2,ss,:) = ...
                            constrainedEllipseFit(Xp(splitIdx2), Yp(splitIdx2), ...
                            ellipseTransparentLB, ...
                            ellipseTransparentUB, ...
                            []);
                    else
                        % We do have sceneGeometry, so search for eyeParams
                        % that best fit the splits of the pupil perimeter.
                        % To speed up the search, we do not use ray tracing
                        % here, as we are not interested in the absolute
                        % values of the fits, but instead just their
                        % variation.
                        pFitEyeParamSplit(1,ss,:) = ...
                            eyeParamEllipseFit(Xp(splitIdx1), Yp(splitIdx1), sceneGeometry, [], 'x0', eyeParams, 'eyeParamsLB', eyeParamsLB, 'eyeParamsUB', eyeParamsUB);
                        pFitEyeParamSplit(2,ss,:) = ...
                            eyeParamEllipseFit(Xp(splitIdx2), Yp(splitIdx2), sceneGeometry, [], 'x0', eyeParams, 'eyeParamsLB', eyeParamsLB, 'eyeParamsUB', eyeParamsUB);
                        % Obtain the ellipse parameeters that correspond
                        % the eyeParams
                        pFitTransparentSplit(1,ss,:) = ...
                            pupilProjection_fwd(pFitEyeParamSplit(1,ss,:), sceneGeometry, []);
                        pFitTransparentSplit(2,ss,:) = ...
                            pupilProjection_fwd(pFitEyeParamSplit(2,ss,:), sceneGeometry, []);
                    end
                end % loop through splits
                
                % Calculate the SD of the parameters across splits
                ellipseParamsSplitsSD=nanstd(reshape(pFitTransparentSplit,ss*2,nEllipseParams));
                if ~isempty(sceneGeometry)
                    eyeParamsSplitsSD=nanstd(reshape(pFitEyeParamSplit,ss*2,nEyeParams));
                end
            end % check if we want to do splits
            
        catch ME
            warning ('Error while processing frame: %d', ii)
        end % try catch
    end % check if there are pupil boundary data to be fit
    
    % store results
    loopVar_ellipseParamsTransparent(ii,:) = ellipseParamsTransparent';
    loopVar_ellipseParamsSplitsSD(ii,:) = ellipseParamsSplitsSD';
    loopVar_ellipseParamsObjectiveError(ii) = ellipseParamsObjectiveError;
    if ~isempty(sceneGeometry)
        loopVar_eyeParams(ii,:) = eyeParams';
        loopVar_eyeParamsSplitsSD(ii,:) = eyeParamsSplitsSD';
        loopVar_eyeParamsObjectiveError(ii) = eyeParamsObjectiveError;
    end
    
end % loop over frames

% alert the user that we are done with the fit loop
if strcmp(p.Results.verbosity,'full')
    toc
    fprintf('\n');
end

%% Clean up and save

% Establish a label to save the fields of the ellipse fit data
if isempty(p.Results.fitLabel)
    if isempty(sceneGeometry)
        fitLabel = 'initial';
    else
        fitLabel = 'sceneConstrained';
    end
else
    fitLabel = p.Results.fitLabel;
end

% Store the ellipse fit data in informative fields
pupilData.(fitLabel).ellipses.values = loopVar_ellipseParamsTransparent;
if isempty(sceneGeometry)
    pupilData.(fitLabel).ellipses.RMSE = loopVar_ellipseParamsObjectiveError';
else
    pupilData.(fitLabel).ellipses.RMSE = loopVar_eyeParamsObjectiveError';
end
if nSplits~=0
    pupilData.(fitLabel).ellipses.splitsSD = loopVar_ellipseParamsSplitsSD;
end
pupilData.(fitLabel).ellipses.meta.ellipseForm = 'transparent';
pupilData.(fitLabel).ellipses.meta.labels = {'x','y','area','eccentricity','theta'};
pupilData.(fitLabel).ellipses.meta.units = {'pixels','pixels','squared pixels','non-linear eccentricity','rads'};
pupilData.(fitLabel).ellipses.meta.coordinateSystem = 'intrinsic image';
if ~isempty(sceneGeometry)
    pupilData.(fitLabel).eyeParams.values = loopVar_eyeParams;
    if nSplits~=0
        pupilData.(fitLabel).eyeParams.splitsSD = loopVar_eyeParamsSplitsSD;
    end
    pupilData.(fitLabel).eyeParams.meta.labels = {'azimuth','elevation','torsion','pupil radius'};
    pupilData.(fitLabel).eyeParams.meta.units = {'deg','deg','deg','mm'};
    pupilData.(fitLabel).eyeParams.meta.coordinateSystem = 'head fixed (extrinsic)';
end

% add meta data
pupilData.(fitLabel).meta = p.Results;

% save the ellipse fit results
save(p.Results.pupilFileName,'pupilData')


%% Delete the parallel pool
if p.Results.useParallel
    if strcmp(p.Results.verbosity,'full')
        tic
        fprintf(['Closing parallel pool. Started ' char(datetime('now')) '\n']);
    end
    poolObj = gcp;
    if ~isempty(poolObj)
        delete(poolObj);
    end
    if strcmp(p.Results.verbosity,'full')
        toc
        fprintf('\n');
    end
end


end % function
