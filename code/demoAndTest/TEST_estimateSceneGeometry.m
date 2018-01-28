%% TEST_estimateSceneGeometry
% Examine the ability of the routines to estimate an unknown scene geometry
%
% Description:

%

close all

% Obtain the default sceneGeometry
defaultSceneGeometry = estimateSceneGeometry([],[],'eyeLaterality','Right');

% Create variations in center of rotation and camera distance
vsg={};
esg={};
resultIdx = 1;
for CoR = -14:0.25:-13
    for cameraDistance = 125:25:175
        veridicalSceneGeometry = defaultSceneGeometry;
        veridicalSceneGeometry.eye.rotationCenter(1) = CoR;
        veridicalSceneGeometry.extrinsicTranslationVector(3) = cameraDistance;
        
        % Assemble the ray tracing functions
        rayTraceFuncs = assembleRayTraceFuncs( veridicalSceneGeometry );
        
        % Create a set of ellipses from the veridial geometry
        ellipseIdx=1;
        for azi=-15:15:15
            for ele=-15:15:15
                pupilRadius = 2*randn()/2;
                eyeParams=[azi, ele, 0, pupilRadius];
                pupilData.initial.ellipses.values(ellipseIdx,:) = pupilProjection_fwd(eyeParams, veridicalSceneGeometry, rayTraceFuncs);
                pupilData.initial.ellipses.RMSE(ellipseIdx) = 1;
                ellipseIdx=ellipseIdx+1;
            end
        end
        
        estimatedSceneGeometry = estimateSceneGeometry(pupilData,'','useParallel',true,'ellipseArrayList',1:1:ellipseIdx-1);
        
        vsg{resultIdx}=veridicalSceneGeometry;
        esg{resultIdx}=estimatedSceneGeometry;
        resultIdx = resultIdx+1;
    end
end

