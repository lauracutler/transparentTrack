function [ output_args ] = processVideoPipeline( pathParams, varargin )

%% Parse input and define variables
p = inputParser; p.KeepUnmatched = true;

% required input
p.addRequired('pathParams',@isstruct);

% parse
p.parse(pathParams, varargin{:})
pathParams=p.Results.pathParams;


%% Create output directories if needed
if ~exist(pathParams.dataOutputDirFull,'dir')
    mkdir(pathParams.dataOutputDirFull)
end
if ~exist(pathParams.controlFileDirFull,'dir')
    mkdir(pathParams.controlFileDirFull)
end


%% Determine if the suffix of the raw file is "_raw.mov" or ".mov"
if exist(fullfile(pathParams.dataSourceDirFull,[pathParams.runName '_raw.mov']),'file')
    rawVideoName = fullfile(pathParams.dataSourceDirFull,[pathParams.runName '_raw.mov']);
else
    rawVideoName = fullfile(pathParams.dataSourceDirFull,[pathParams.runName '.mov']);
end


%% Conduct the analysis

% Convert raw video to cropped, resized, 60Hz gray
grayVideoName = fullfile(pathParams.dataOutputDirFull, [pathParams.runName '_gray.avi']);
raw2gray(rawVideoName,grayVideoName, varargin{:});

% track the glint
glintFileName = fullfile(pathParams.dataOutputDirFull, [pathParams.runName '_glint.mat']);
trackGlint(grayVideoName, glintFileName, varargin{:});

% extract pupil perimeter
perimeterFileName = fullfile(pathParams.dataOutputDirFull, [pathParams.runName '_perimeter.mat']);
extractPupilPerimeter(grayVideoName, perimeterFileName, varargin{:});

% generate preliminary control file
controlFileName = fullfile(pathParams.controlFileDirFull, [pathParams.runName '_controlFile.csv']);
makePreliminaryControlFile(controlFileName, perimeterFileName, glintFileName, varargin{:});

% correct the perimeter video
correctedPerimeterFileName = fullfile(pathParams.dataOutputDirFull, [pathParams.runName '_correctedPerimeter.mat']);
correctPupilPerimeter(perimeterFileName,controlFileName,correctedPerimeterFileName, varargin{:});

% bayesian fit of the pupil on the corrected perimeter video
ellipseFitFileName = fullfile(pathParams.dataOutputDirFull, [pathParams.runName '_pupil.mat']);
bayesFitPupilPerimeter(correctedPerimeterFileName, ellipseFitFileName, varargin{:});

% create a video of the final fit
finalFitVideoName = fullfile(pathParams.dataOutputDirFull, [pathParams.runName '_finalFit.mat']);
makePupilFitVideo(grayVideoName, finalFitVideoName, ...
    'glintFileName', glintFileName, 'perimeterFileName', correctedPerimeterFileName,...
    'ellipseFitFileName', ellipseFitFileName, 'whichFieldToPlot', 'pPosteriorMeanTransparent', ...
    'controlFileName',controlFileName,varargin{:});

end % function

