function deinterlaceVideo (inputVideoName, outputVideoName, varargin)
% deinterlaceVideo (inputVideoName, outputVideoName)

% This function deinterlaces NTSC DV 30Hz videos, saving out
% progressive 60 Hz videos, using a "bob deinterlacing" strategy.
%
% The video is also converted to gray scale.
%
% Four deinterlace strategies are available (bobMode):
% 'Raw'    =  extract 2 fields for every frame. Save progressive video.
%             Final spatial resolution is half the original resolution.
% 'Zero'   =  extract 2 fields for every frame. Alternate every row with a
%             row of zeros to preserve aspect ratio.
% 'Double' =  extract 2 fields for every frame. Duplicate each raw to
%             preserve aspect ratio.
% 'Mean'   =  extract 2 fields for every frame. Add a row with the mean of
%             two consecutive rows to preserve aspect ratio.

% References on bob techniques for deinterlacing and on deinterlacing in
% general:
% https://www.altera.com/content/dam/altera-www/global/en_US/pdfs/literature/wp/wp-01117-hd-video-deinterlacing.pdf
% http://www.100fps.com/
%
% Output
%   an AVI video is saved out.
% 
% Input (required)
%	inputVideoName - full path to the video to deinterlace
%	outputVideoName - full path to the deinterlaced output video
%
% Options (analysis)
%   bobMode - deinterlace strategy convertToGray - if set to true
%   (default), the video will also be converted to grayscale.
%
% Options (verbosity and display)
%   verbosity - controls console status updates
% 
% Options (flow control)
%  nFrames' - analyze fewer than the total number of frames.
%  startFrame - which frame to start on
% 
% Options (environment)
%   tbSnapshot - the passed tbSnapshot output that is to be saved along
%      with the data
%   timestamp / username / hostname - these are automatically derived and
%      saved within the p.Results structure.
% 

%% parse input and define variables

p = inputParser;
% required input
p.addRequired('inputVideoName',@isstr);
p.addRequired('outputVideoName',@isstr);

% optional inputs
p.addParameter('bobMode', 'Mean', @isstr);
p.addParameter('convertToGray',true,@islogical)

% verbosity
p.addParameter('verbosity', 'none', @isstr);

% flow control
p.addParameter('nFrames',Inf,@isnumeric);
p.addParameter('startFrame',1,@isnumeric);

% environment parameters
p.addParameter('tbSnapshot',[],@(x)(isempty(x) | isstruct(x)));
p.addParameter('timestamp',char(datetime('now')),@ischar);
p.addParameter('username',char(java.lang.System.getProperty('user.name')),@ischar);
p.addParameter('hostname',char(java.net.InetAddress.getLocalHost.getHostName),@ischar);

% parse
p.parse(inputVideoName,outputVideoName,varargin{:})

% define variables
bobMode = p.Results.bobMode;

%% Load video to deinterlace and set parameters for output video file.

inObj = VideoReader(inputVideoName);

if p.Results.nFrames == Inf
    nFrames = floor(inObj.Duration*inObj.FrameRate);
else
    nFrames=p.Results.nFrames;
end

Bob = VideoWriter(outputVideoName);
Bob.FrameRate = inObj.FrameRate * 2;
Bob.Quality = 100;

% Alert the user
if strcmp(p.Results.verbosity,'full')
    tic
    fprintf(['Deinterlacing video. Started ' char(datetime('now')) '\n']);
    fprintf('| 0                      50                   100%% |\n');
    fprintf('.');
end

open(Bob)

for ii = p.Results.startFrame:nFrames
    
    % update progressbar
    if strcmp(p.Results.verbosity,'full') && mod(ii,round(nFrames/50))==0
        fprintf('.');
    end
    
    % get the frame
    tmp = readFrame(inObj);
    thisFrame = rgb2gray(tmp);
    
    %get the fields
    oddFields = thisFrame(1:2:end,:);
    evenFields = thisFrame(2:2:end,:);
    
    %deinterlace
    switch bobMode
        case 'Raw'
            % shift the even lines to avoid "jumping" from frame to frame. (i.e
            % align the two fields)
            evenFields = cat(1,zeros(1,size(evenFields,2),'like',evenFields), evenFields(1:end-1,:));
            
        case 'Zero'
            % put zero rows in
            m = 1;
            k = 1;
            n = size(oddFields);
            oddFields = reshape([reshape(oddFields,m,[]);zeros(k,n(1)/m*n(2))],[],n(2));
            evenFields = reshape([reshape(evenFields,m,[]);zeros(k,n(1)/m*n(2))],[],n(2));
            evenFields = cat(1,zeros(1,size(evenFields,2),'like',evenFields), evenFields(1:end-1,:));
            
        case 'Double'
            % duplicate each row
            oddFields = repelem(oddFields, 2, 1);
            evenFields = repelem(evenFields, 2, 1);
            evenFields = cat(1,zeros(1,size(evenFields,2),'like',evenFields), evenFields(1:end-1,:));
            
        case 'Mean'
            % put means in between rows (odd fields)
            tmp = [oddFields(1,:); ((oddFields(1,:)+oddFields(2,:))/2);oddFields(2,:)];
            for jj = 2 : size(oddFields,1)-1
                newLines = [mean([oddFields(jj,:);oddFields(jj+1,:)],1);oddFields(jj+1,:)];
                tmp = cat(1,tmp,newLines);
            end
            oddFields = cat(1,tmp,oddFields(end,:));
            clear tmp
            clear newLines
            % put means in between rows (even fields)
            tmp = [evenFields(1,:); ((evenFields(1,:)+evenFields(2,:))./2);evenFields(2,:)];
            for jj = 2 : size(evenFields,1)-1
                newLines = [mean([evenFields(jj,:);evenFields(jj+1,:)],1);evenFields(jj+1,:)];
                tmp = cat(1,tmp,newLines);
            end
            evenFields = cat(1,evenFields(1,:),tmp);
            clear tmp
            clear newLines
        otherwise
        error('Unknown bobMode. Type help deinterlaceVideo for available deinterlacing methods.')
    end
    
    % if required, convert the fields to gray
    if p.Results.convertToGray
        oddFields = rgb2gray(oddFields);
        evenFields = rgb2gray(evenFields);
    end

    % write the fields as frames
    writeVideo(Bob,oddFields);
    writeVideo(Bob,evenFields);
    
end

clear Bob inObj

% report completion of analysis
if strcmp(p.Results.verbosity,'full')
    fprintf('\n');
    toc
    fprintf('\n');
end


end % function