function [pupilEllipseOnImagePlane, imagePoints, sceneWorldPoints, eyeWorldPoints, pointLabels] = pupilProjection_fwd(eyeParams, sceneGeometry, rayTraceFuncs, varargin)
% Project the pupil circle to an ellipse on the image plane
%
% Description:
%	Given the sceneGeometry--and optionaly ray tracing functions through
%   the cornea--this routine simulates a circular pupil on a spherical eye
%   and then measures the parameters of the ellipse (in transparent format)
%   of the projection of the pupil to the image plane.
%
%   The forward model is a perspective projection of an anatomically
%   accurate eye, with points positioned behind the cornea subject
%   to refractive displacement. The projection incorporates the intrinsic
%   properties of the camera, including any radial lens distortion.
%
% Notes:
%   Rotations - Eye rotation is given as azimuth, elevation, and torsion in
%   degrees. These values correspond to degrees of rotation of the eye
%   relative to a head-fixed (extrinsic) coordinate frame. Note that this
%   is different from an eye-fixed (intrinsic) coordinate frame (such as
%   the Fick coordinate sysem). Azimuth, Elevation of [0,0] corresponds
%   to the position of the eye when a line that connects the center of
%   rotation of the eye with the center of the pupil is normal to the image
%   plane. Positive rotations correspond to rightward, upward, translation
%   of the pupil center in the image. Torsion of zero corresponds to the
%   torsion of the eye when it is in primary position.
%
%   Units - Eye rotations are in units of degrees. However, the units of
%   theta in the transparent ellipse parameters are radians. This is in
%   part to help us keep the two units separate conceptually.
%
% Inputs:
%   eyeParams             - A 1x4 vector provides values for [eyeAzimuth,
%                           eyeElevation, eyeTorsion, pupilRadius].
%                           Azimuth, elevation, and torsion are in units of
%                           head-centered (extrinsic) degrees, and pupil
%                           radius is in mm.
%   sceneGeometry         - A structure; described in estimateSceneGeometry
%   rayTraceFuncs         - A structure that contains handles to the ray
%                           tracing functions created by
%                           assembleRayTraceFuncs()
%
% Optional key/value pairs:
%  'fullEyeModelFlag'     - Logical. Determines if the full posterior and
%                           anterior chamber eye model will be created.
%  'nPupilPerimPoints'    - The number of points that are distributed
%                           around the pupil circle. A minimum of 5 is
%                           required to uniquely specify the image ellipse.
%  'nIrisPerimPoints'     - The number of points that are distributed
%                           around the iris circle. A minimum of 5 is
%                           required to uniquely specify the image ellipse.
%  'posteriorChamberEllipsoidPoints' - The number of points that are on
%                           each latitude line of the posterior chamber
%                           ellipsoid. About 30 makes a nice image.
%  'anteriorChamberEllipsoidPoints' - The number of points that are on
%                           each longitude line of the anterior chamber
%                           ellipsoid. About 30 makes a nice image.
%
% Outputs:
%   pupilEllipseOnImagePlane - A 1x5 vector that contains the parameters of
%                           pupil ellipse on the image plane cast in
%                           transparent form.
%   imagePoints           - An nx2 matrix that specifies the x, y location
%                           on the image plane for each of the eyeWorld
%                           points.
%   sceneWorldPoints      - An nx3 matrix of the coordinates of the
%                           points of the eye model in the sceneWorld
%                           coordinate frame. If fullEyeModel is set to
%                           false, then there will only be points for the
%                           pupil perimeter. If fullEyeModel is true, then
%                           the entire model of ~1000 points will be
%                           returned.
%   eyeWorldPoints        - An nx3 matrix of the coordinates of the
%                           points of the eye model in the eyeWorld
%                           coordinate frame.
%   pointsLabels          - An nx1 cell array that identifies each of the
%                           points, from the set {'pupilCenter',
%                           'irisCenter', 'rotationCenter',
%                           'posteriorChamber', 'irisPerimeter',
%                           'pupilPerimeter',
%                           'anteriorChamber','cornealApex'}.
%

%% input parser
p = inputParser; p.KeepUnmatched = true;

% Required
p.addRequired('eyeParams',@isnumeric);
p.addRequired('sceneGeometry',@(x)(isempty(x) || isstruct(x)));
p.addRequired('rayTraceFuncs',@(x)(isempty(x) || isstruct(x)));

p.addParameter('fullEyeModelFlag',false,@islogical);
p.addParameter('nPupilPerimPoints',5,@(x)(isnumeric(x) && x>=4));
p.addParameter('nIrisPerimPoints',5,@(x)(isnumeric(x) && x>=4));
p.addParameter('posteriorChamberEllipsoidPoints',30,@isnumeric);
p.addParameter('anteriorChamberEllipsoidPoints',30,@isnumeric);

% parse
p.parse(eyeParams, sceneGeometry, rayTraceFuncs, varargin{:})


%% Check the input

if isempty(sceneGeometry)
    % No sceneGeometry was provided. Use the default settings
    sceneGeometry = estimateSceneGeometry('','');
end


%% Prepare variables
% Separate the eyeParams into individual variables
eyeAzimuth = eyeParams(1);
eyeElevation = eyeParams(2);
eyeTorsion = eyeParams(3);
pupilRadius = eyeParams(4);
nPupilPerimPoints = p.Results.nPupilPerimPoints;

%% Define an eye in eyeWorld coordinates
% This coordinate frame is in mm units and has the dimensions (p1,p2,p3).
% The diagram is of a cartoon pupil, being viewed directly from the front.
%
% Coordinate [0,0,0] corresponds to the apex (front surface) of the cornea.
% The first dimension is depth, and has a negative value towards the
% back of the eye.
%
%                 |
%     ^         __|__
%  -  |        /     \
% p3  -  -----(   +   )-----
%  +  |        \_____/
%     v           |
%                 |
%
%           - <--p2--> +
%
% For the right eye, negative values on the p2 dimension are more temporal,
% and positive values are more nasal. Positive values of p3 are downward,
% and negative values are upward

% Define points around the pupil circle
perimeterPointAngles = 0:2*pi/nPupilPerimPoints:2*pi-(2*pi/nPupilPerimPoints);
eyeWorldPoints(1:nPupilPerimPoints,3) = ...
    sin(perimeterPointAngles)*pupilRadius + sceneGeometry.eye.pupilCenter(3);
eyeWorldPoints(1:nPupilPerimPoints,2) = ...
    cos(perimeterPointAngles)*pupilRadius + sceneGeometry.eye.pupilCenter(2);
eyeWorldPoints(1:nPupilPerimPoints,1) = ...
    0 + sceneGeometry.eye.pupilCenter(1);

% Create labels for the pupilPerimeter points
tmpLabels = cell(nPupilPerimPoints, 1);
tmpLabels(:) = {'pupilPerimeter'};
pointLabels = tmpLabels;

% If the fullEyeModel flag is set, then we will create a model of the
% posterior and anterior chambers of the eye.
if p.Results.fullEyeModelFlag
    
    % Add points for the center of the pupil, iris, and rotation
    eyeWorldPoints = [eyeWorldPoints; sceneGeometry.eye.pupilCenter];
    pointLabels = [pointLabels; 'pupilCenter'];
    eyeWorldPoints = [eyeWorldPoints; sceneGeometry.eye.irisCenter];
    pointLabels = [pointLabels; 'irisCenter'];
    eyeWorldPoints = [eyeWorldPoints; sceneGeometry.eye.rotationCenter];
    pointLabels = [pointLabels; 'rotationCenter'];
    
    % Create the posterior chamber ellipsoid. We switch dimensions here so
    % that the ellipsoid points have their poles at corneal apex and
    % posterior apex of the eye
    [p3tmp, p2tmp, p1tmp] = ellipsoid( ...
        sceneGeometry.eye.posteriorChamberCenter(3), ...
        sceneGeometry.eye.posteriorChamberCenter(2), ...
        sceneGeometry.eye.posteriorChamberCenter(1), ...
        sceneGeometry.eye.posteriorChamberRadii(3), ...
        sceneGeometry.eye.posteriorChamberRadii(2), ...
        sceneGeometry.eye.posteriorChamberRadii(1), ...
        p.Results.posteriorChamberEllipsoidPoints);
    % Convert the surface matrices to a vector of points and switch the
    % axes back
    ansTmp = surf2patch(p1tmp, p2tmp, p3tmp);
    posteriorChamberPoints=ansTmp.vertices;
    
    % Retain those points that are anterior to the center of the posterior
    % chamber and are posterior to the iris plane
    retainIdx = logical(...
        (posteriorChamberPoints(:,1) > sceneGeometry.eye.posteriorChamberCenter(1)) .* ...
        (posteriorChamberPoints(:,1) < sceneGeometry.eye.irisCenter(1)) ...
        );
    if all(~retainIdx)
        error('The iris center is behind the center of the posterior chamber');
    end
    posteriorChamberPoints = posteriorChamberPoints(retainIdx,:);
    
    % Add the points and labels
    eyeWorldPoints = [eyeWorldPoints; posteriorChamberPoints];
    tmpLabels = cell(size(posteriorChamberPoints,1), 1);
    tmpLabels(:) = {'posteriorChamber'};
    pointLabels = [pointLabels; tmpLabels];
    
    % Define points around the perimeter of the iris
    nIrisPerimPoints = p.Results.nIrisPerimPoints;
    perimeterPointAngles = 0:2*pi/nIrisPerimPoints:2*pi-(2*pi/nIrisPerimPoints);
    irisPoints(1:nIrisPerimPoints,3) = ...
        sin(perimeterPointAngles)*sceneGeometry.eye.irisRadius + sceneGeometry.eye.irisCenter(3);
    irisPoints(1:nIrisPerimPoints,2) = ...
        cos(perimeterPointAngles)*sceneGeometry.eye.irisRadius + sceneGeometry.eye.irisCenter(2);
    irisPoints(1:nIrisPerimPoints,1) = ...
        0 + sceneGeometry.eye.irisCenter(1);
    
    % Add the points and labels
    eyeWorldPoints = [eyeWorldPoints; irisPoints];
    tmpLabels = cell(size(irisPoints,1), 1);
    tmpLabels(:) = {'irisPerimeter'};
    pointLabels = [pointLabels; tmpLabels];
    
    % Create the anterior chamber ellipsoid.
    [p1tmp, p2tmp, p3tmp] = ellipsoid( ...
        sceneGeometry.eye.corneaFrontSurfaceCenter(1), ...
        sceneGeometry.eye.corneaFrontSurfaceCenter(2), ...
        sceneGeometry.eye.corneaFrontSurfaceCenter(3), ...
        sceneGeometry.eye.corneaFrontSurfaceRadius, ...
        sceneGeometry.eye.corneaFrontSurfaceRadius, ...
        sceneGeometry.eye.corneaFrontSurfaceRadius, ...
        p.Results.anteriorChamberEllipsoidPoints);
    % Convert the surface matrices to a vector of points and switch the
    % axes back
    ansTmp = surf2patch(p1tmp, p2tmp, p3tmp);
    anteriorChamberPoints=ansTmp.vertices;
    
    % Retain those points that are anterior to the iris plane
    retainIdx = logical(...
        (anteriorChamberPoints(:,1) > sceneGeometry.eye.irisCenter(1)));
    if all(~retainIdx)
        error('The pupil plane is set in front of the corneal apea');
    end
    anteriorChamberPoints = anteriorChamberPoints(retainIdx,:);
    
    % Add the points and labels
    eyeWorldPoints = [eyeWorldPoints; anteriorChamberPoints];
    tmpLabels = cell(size(anteriorChamberPoints,1), 1);
    tmpLabels(:) = {'anteriorChamber'};
    pointLabels = [pointLabels; tmpLabels];
    
    % Add a point for the corneal apex
    cornealApex=[0 0 0];
    eyeWorldPoints = [eyeWorldPoints; cornealApex];
    pointLabels = [pointLabels; 'cornealApex'];    
end


%% Project the pupil circle points to headWorld coordinates.
% This coordinate frame is in mm units and has the dimensions (h1,h2,h3).
% The diagram is of a cartoon eye, being viewed directly from the front.
%
%  h1 values negative --> towards the head, positive towards the camera
%
%         h2
%    0,0 ---->
%     |
%  h3 |
%     v
%
%               |
%             __|__
%            /  _  \
%    -------(  (_)  )-------  h2 (horizontal axis of the head)
%            \_____/          rotation about h2 causes pure vertical
%               |             eye movement
%               |
%
%               h3
%   (vertical axis of the head)
%  rotation about h3 causes pure
%     horizontal eye movement
%
%
%
% Position [0,-,-] indicates the front surface of the eye.
% Position [-,0,0] indicates the h2 / h3 position of the optical axis of
% the eye when it is normal to the image plane.
%
% We will convert from this coordinate frame to that of the camera scene
% later.


%% Define the eye rotation matrix
% Assemble a rotation matrix from the head-fixed Euler angle rotations. In
% the head-centered world coordinate frame, positive azimuth, elevation and
% torsion values correspond to leftward, downward and clockwise (as seen
% from the perspective of the subject) eye movements
R3 = [cosd(eyeAzimuth) -sind(eyeAzimuth) 0; sind(eyeAzimuth) cosd(eyeAzimuth) 0; 0 0 1];
R2 = [cosd(eyeElevation) 0 sind(eyeElevation); 0 1 0; -sind(eyeElevation) 0 cosd(eyeElevation)];
R1 = [1 0 0; 0 cosd(eyeTorsion) -sind(eyeTorsion); 0 sind(eyeTorsion) cosd(eyeTorsion)];

% This order (1-2-3) corresponds to a head-fixed, extrinsic, rotation
% matrix. The reverse order (3-2-1) would be an eye-fixed, intrinsic
% rotation matrix and would corresponds to the "Fick coordinate" scheme.
eyeRotation = R1*R2*R3;


%% Obtain the virtual image for the eyeWorld points
% This steps accounts for the effect of corneal refraction upon the
% appearance of points from the iris and pupil
if ~isempty(rayTraceFuncs)
    % Identify the eyeWorldPoints that are subject to refraction by the cornea
    refractPointsIdx = find(strcmp(pointLabels,'pupilPerimeter')+...
        strcmp(pointLabels,'irisPerimeter')+...
        strcmp(pointLabels,'pupilCenter')+...
        strcmp(pointLabels,'irisCenter'));
    % Loop through the eyeWorldPoints that are to be refracted
    for ii=1:length(refractPointsIdx)
        % Grab this eyeWorld point
        eyeWorldPoint=eyeWorldPoints(refractPointsIdx(ii),:);
        % Define an error function which is the distance between the nodal
        % point of the camera and a the point at which a ray impacts the
        % plane that contains the camera, with the ray departing from the
        % eyeWorld point at angle theta in the p1p2 plane.
        errorFunc = @(theta) rayTraceFuncs.cameraNodeDistanceError2D.p1p2(...
            sceneGeometry.extrinsicTranslationVector(1),...
            sceneGeometry.extrinsicTranslationVector(2),...
            sceneGeometry.extrinsicTranslationVector(3),...
            deg2rad(eyeAzimuth), deg2rad(eyeElevation), deg2rad(eyeTorsion),...
            eyeWorldPoint(1),eyeWorldPoint(2),eyeWorldPoint(3),...
            sceneGeometry.eye.rotationCenter(1),...
            theta);
        % Conduct an fminsearch to find the p1p2 theta that results in a
        % ray that strikes as close as possible to the camera nodal point
        theta_p1p2=fminsearch(errorFunc,0);
        % Now repeat this process for a ray that varies in theta in the
        % p1p3 plane
        errorFunc = @(theta) rayTraceFuncs.cameraNodeDistanceError2D.p1p3(...
            sceneGeometry.extrinsicTranslationVector(1),...
            sceneGeometry.extrinsicTranslationVector(2),...
            sceneGeometry.extrinsicTranslationVector(3),...
            deg2rad(eyeAzimuth), deg2rad(eyeElevation), deg2rad(eyeTorsion),...
            eyeWorldPoint(1),eyeWorldPoint(2),eyeWorldPoint(3),...
            sceneGeometry.eye.rotationCenter(1),...
            theta);
        theta_p1p3=fminsearch(errorFunc,0);
        % With both theta values calculated, now obtain the virtual image
        % ray arising from the pupil plane that reflects the corneal optics
        virtualImageRay = rayTraceFuncs.virtualImageRay(eyeWorldPoint(1), eyeWorldPoint(2), eyeWorldPoint(3), theta_p1p2, theta_p1p3);
        % Replace the original eyeWorld point with the virtual image 
        % eyeWorld point
        eyeWorldPoints(refractPointsIdx(ii),:) = virtualImageRay(1,:);
    end
end

%% Apply the eye rotation
headWorldPoints = (eyeRotation*(eyeWorldPoints-sceneGeometry.eye.rotationCenter)')'+sceneGeometry.eye.rotationCenter;


%% Project the pupil circle points to sceneWorld coordinates.
% This coordinate frame is in mm units and has the dimensions (X,Y,Z).
% The diagram is of a cartoon head (borrowed from Leszek Swirski), being
% viewed from above:
%
%   |
%   |    .-.
%   |   |   | <- Head
%   |   `^u^'
% Z |      :V <- Camera    (As seen from above)
%   |      :
%   |      :
%  \|/     o <- Target
%
%     ----------> X
%
% +X = right
% +Y = up
% +Z = front (towards the camera)
%
% The origin [0,0,0] corresponds to the front surface of the eye and the
% optical center of the eye when the line that connects the center of
% rotation of the eye and the optical axis of the eye are normal to the
% image plane.

% Re-arrange the head world coordinate frame to transform to the scene
% world coordinate frame
sceneWorldPoints = headWorldPoints(:,[2 3 1]);

% We reverse the direction of the Y axis so that positive elevation of the
% eye corresponds to a movement of the pupil upward in the image
sceneWorldPoints(:,2) = sceneWorldPoints(:,2)*(-1);


%% Project the pupil circle points to the image plane
% This coordinate frame is in units of pixels, and has the dimensions
% [x, y]:
%
%      ^
%      |
%   y  |
%      |
%      +------->
% [0,0]    x
%
% With x being left/right and y being down/up
%

% Add a column of ones to support the upcoming matrix multiplication with a
% combined rotation and translation matrix
nEyeWorldPoints = size(eyeWorldPoints,1);
sceneWorldPoints=[sceneWorldPoints, ones(nEyeWorldPoints,1)];

% Create the projectionMatrix
projectionMatrix = ...
    sceneGeometry.intrinsicCameraMatrix * ...
    [sceneGeometry.extrinsicRotationMatrix, ...
    sceneGeometry.extrinsicTranslationVector];

% Project the world points to the image plane and scale
tmpImagePoints=(projectionMatrix*sceneWorldPoints')';
imagePointsPreDistortion=zeros(nEyeWorldPoints,2);
imagePointsPreDistortion(:,1) = ...
    tmpImagePoints(:,1)./tmpImagePoints(:,3);
imagePointsPreDistortion(:,2) = ...
    tmpImagePoints(:,2)./tmpImagePoints(:,3);


%% Apply radial lens distortion
% This step introduces "pincushion" (or "barrel") distortion produced by
% the lens. The x and y distortion equations are in the normalized image
% coordinates. Thus, the origin is at the optical center (aka principal
% point), and the coordinates are in world units. To apply this distortion
% to our image coordinate points, we subtract the optical center, and then
% divide by fx and fy from the intrinsic matrix.
imagePointsNormalized = (imagePointsPreDistortion - [sceneGeometry.intrinsicCameraMatrix(1,3) sceneGeometry.intrinsicCameraMatrix(2,3)]) ./ ...
    [sceneGeometry.intrinsicCameraMatrix(1,1) sceneGeometry.intrinsicCameraMatrix(2,2)];

% Distortion is proportional to distance from the center of the center of
% projection on the camera sensor
radialPosition = sqrt(imagePointsNormalized(:,1).^2 + imagePointsNormalized(:,2).^2);

distortionVector =   1 + ...
    sceneGeometry.radialDistortionVector(1).*radialPosition.^2 + ...
    sceneGeometry.radialDistortionVector(2).*radialPosition.^4;

imagePointsNormalizedDistorted(:,1) = imagePointsNormalized(:,1).*distortionVector;
imagePointsNormalizedDistorted(:,2) = imagePointsNormalized(:,2).*distortionVector;

% Place the distorted points back into the imagePoints vector
imagePoints = (imagePointsNormalizedDistorted .* [sceneGeometry.intrinsicCameraMatrix(1,1) sceneGeometry.intrinsicCameraMatrix(2,2)]) +...
    [sceneGeometry.intrinsicCameraMatrix(1,3) sceneGeometry.intrinsicCameraMatrix(2,3)];


%% Fit the ellipse in the image plane and store values
% Obtain the transparent ellipse params of the projection of the pupil
% circle on the image plane.
pupilPerimIdx = find(strcmp(pointLabels,'pupilPerimeter'));

if eyeParams(4)==0 || ~isreal(imagePoints(pupilPerimIdx,:)) || length(pupilPerimIdx)<5
    pupilEllipseOnImagePlane=nan(1,5);
else
    pupilEllipseOnImagePlane = ellipse_ex2transparent(...
        ellipse_im2ex(...
        ellipsefit_direct( imagePoints(pupilPerimIdx,1), ...
        imagePoints(pupilPerimIdx,2)  ...
        ) ...
        )...
        );
    % place theta within the range of 0 to pi
    if pupilEllipseOnImagePlane(5) < 0
        pupilEllipseOnImagePlane(5) = pupilEllipseOnImagePlane(5)+pi;
    end
end

end % pupilProjection_fwd



