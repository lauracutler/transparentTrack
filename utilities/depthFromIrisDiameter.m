function [cameraDepthMean, cameraDepthSD] = depthFromIrisDiameter( sceneGeometry, observedIrisDiamPixels )
% Estimate camera depth given sceneGeometry and iris diameter in pixels
%
% Syntax:
%  [cameraDepthMean, cameraDepthSD] = depthFromIrisDiameter( sceneGeometry, observedIrisDiamPixels )
%
% Description:
%   There is limited individual variation in the horizontal visible
%   diameter of the human iris. The maximum observed diameter of the border
%   of the iris in a set of images of the eye will correspond to the
%   diameter of the iris when the eye is posed so a line that connects the
%   center of rotation of the eye and the center of the iris is aligned
%   with the optical axis of the camera. Given an observed iris diameter in
%   pixels in the image and a candidate sceneGeometry structure, we can
%   calculate the distance of the camera from the corneal surface of the
%   eye.
%
% Inputs:
%   sceneGeometry         - A sceneGeometry file for which we wish to
%                           refine the camera depth value.
%   observedIrisDiamPixels - Scalar. The maximum observed diameter of the
%                           iris across image frames, in units of pixels.
%
% Outputs;
%   cameraDepthMean       - Scalar. The distance, in mm, of the camera
%                           from the corneal apex at pose angle [0, 0, 0],
%                           calculated assuming the average horizontal
%                           visible iris diameter.
%   cameraDepthSD         - Scalar. The 1SD variation in distance, in mm, 
%                           of the camera from the corneal apex at pose
%                           angle [0, 0, 0], given the variation in iris
%                           diameters observed in a population.
%
% Examples:
%{
    %% Recover a veridical camera distance
    % Calculate what the observed iris diameter should be at 100 mm
    sceneGeometry_100depth = createSceneGeometry('cameraTranslation',[0; 0; 100],'aqueousRefractiveIndex',1.225);
    [~, imagePoints, ~, ~, pointLabels] = ...
    	pupilProjection_fwd([0 0 0 1], sceneGeometry_100depth, 'fullEyeModelFlag', true, 'nIrisPerimPoints', 20);
    idx = find(strcmp(pointLabels,'irisPerimeter'));
    observedIrisDiamPixels = max(imagePoints(idx,1))-min(imagePoints(idx,1));
    % Now call the estimation function, supplied with a sceneGeometry that
    % a different value for the camera depth (which is used for the x0).
    sceneGeometry_65depth = createSceneGeometry('cameraTranslation',[0; 0; 65],'aqueousRefractiveIndex',1.225);
    [cameraDepthMean, cameraDepthSD] = ...
        depthFromIrisDiameter( sceneGeometry_65depth, observedIrisDiamPixels );
    % Report the results
    fprintf('Veridical camera depth: %4.0f, recovered camera depth: %4.0f \n',sceneGeometry_100depth.cameraPosition.translation(3),cameraDepthMean);
    assert( abs( sceneGeometry_100depth.cameraPosition.translation(3) - cameraDepthMean) < 1);
%}

%% input parser
p = inputParser; p.KeepUnmatched = true;

% Required
p.addRequired('sceneGeometry', @isstruct);
p.addRequired('maxIrisDiameterPixels',@isnumeric);

% parse
p.parse(sceneGeometry, observedIrisDiamPixels)


%% Iris width values
% Define the iris radius. One study measured the horizontal visible
% iris diameter (HVID) in 200 people, and found a mean of 11.8 with
% a range of 10.2 - 13.0.
%    PJ Caroline & MP Andrew. "The Effect of Corneal Diameter on
%    Soft Lens Fitting, Part 1" Contact Lens Spectrum, Issue: April
%    2002
%    https://www.clspectrum.com/issues/2002/april-2002/contact-lens-case-reports
%
% Bernd Bruckner of the company Appenzeller Kontaktlinsen AG
% supplied me with a tech report from his company (HVID & SimK
% study) that measured HVID in 461 people. These data yield a mean
% iris radius of 5.92 mm, 0.28 SD. The values from the histogram
% are represented here, along with a Gaussian fit to the
% distribution
%{
	counts = [0 2 2 0 0 4 5 12 19 23 36 44 52 41 39 37 43 30 28 12 15 10 4 1 0 2 0];
	HVIDRadiusmm = (10.5:0.1:13.1)/2;
	hvidGaussFit = fit(HVIDRadiusmm', counts', 'gauss1');
	hvidRadiusMean = hvidGaussFit.b1;
    hvidRadiusSD =  hvidGaussFit.c1;
    figure
    plot(HVIDRadiusmm, hvidGaussFit(HVIDRadiusmm), '-r')
    hold on
    plot(HVIDRadiusmm, counts, '*k')
    xlabel('HVID radius in mm')
    ylabel('counts')
%}
% The HVID is the refracted iris size. We can use the forward model
% to find the size of the true iris for the mean and mean+1SD observed
% refracted iris sizes
%{
 	sceneGeometry = createSceneGeometry('aqueousRefractiveIndex',1.225);
	% Get the area in pixels of a "pupil" that is the same radius
	sceneGeometry.refraction = [];
	% as the HVID when there is no ray tracing
	hvidP=pupilProjection_fwd([0 0 0 hvidRadiusMean],sceneGeometry);
	% Restore ray tracing
 	sceneGeometry = createSceneGeometry('aqueousRefractiveIndex',1.225);
	% Set up the objective function
	myArea = @(p) p(3);
	myObj = @(r) (hvidP(3) - myArea(pupilProjection_fwd([0 0 0 r],sceneGeometry)))^2;
	[r,pixelError] = fminsearch(myObj,5.5);
	fprintf('An unrefracted iris radius of %4.2f yields a refracted HVID of %4.2f \n',r,hvidRadiusMean)
	% Now handle the +1SD case
	sceneGeometry.refraction = [];
	% as the HVID when there is no ray tracing
	hvidP=pupilProjection_fwd([0 0 0 hvidRadiusMean+hvidRadiusSD],sceneGeometry);
	% Restore ray tracing
 	sceneGeometry = createSceneGeometry('aqueousRefractiveIndex',1.225);
	% Set up the objective function
	myArea = @(p) p(3);
	myObj = @(r) (hvidP(3) - myArea(pupilProjection_fwd([0 0 0 r],sceneGeometry)))^2;
	[r,pixelError] = fminsearch(myObj,5.5);
	fprintf('An unrefracted iris radius of %4.2f yields a refracted HVID of %4.2f \n',r,hvidRadiusMean+hvidRadiusSD)
%}
trueIrisSizeMean = 5.54;
trueIrisSizeSD = 0.30;

% We now identify the camera distances corresponding the mean, and then to
% the +1SD iris sizes

% Set the x0 position for the search to be the passed scene geometry
x0 = sceneGeometry.cameraPosition.translation(3);

searchSDvals = [0, 1];
for tt = 1:2
    assumedIrisRadius = trueIrisSizeMean + trueIrisSizeSD*searchSDvals(tt);
    cameraTranslationValues(tt) = fminsearch(@objfun, x0);
end
    function fVal = objfun(x)
        candidateSceneGeometry = sceneGeometry;
        candidateSceneGeometry.eye.iris.radius = assumedIrisRadius;
        candidateSceneGeometry.cameraPosition.translation(3) = x;
        [~, imagePoints, ~, ~, pointLabels] = ...
            pupilProjection_fwd([0 0 0 1], candidateSceneGeometry, 'fullEyeModelFlag', true, 'nIrisPerimPoints', 20);
        idx = find(strcmp(pointLabels,'irisPerimeter'));
        predictedIrisDiamPixels = max(imagePoints(idx,1))-min(imagePoints(idx,1));
        fVal = (predictedIrisDiamPixels - observedIrisDiamPixels)^2;
    end

cameraDepthMean = cameraTranslationValues(1);
cameraDepthSD = cameraTranslationValues(2)-cameraTranslationValues(1);

end

