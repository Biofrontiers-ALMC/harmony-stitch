%HARMONYSTITCH  Stitch large images from Opera Phenix
%
%  HARMONYSTITCH will 
%
%  HARMONYSTITCH(folder, frame_range, outputfolder)
%
%  This function expects to find 

clearvars
clc

folder = uigetdir;

%% Read data from XML file
xmlfile = xmlread(fullfile(folder, 'Index.idx.xml'));
doc = xmlfile.getDocumentElement;

docNodes = doc.getChildNodes;

for iChild = 1:docNodes.getLength
    
    currNodeName = docNodes.item(iChild).getNodeName;

    if strcmpi(currNodeName, 'Images')

        imageNode = docNodes.item(iChild).getChildNodes;
        
        %Get imageData
        imgFilename = imageNode.getElementsByTagName('URL');
        imageResX = imageNode.getElementsByTagName('ImageResolutionX');
        imageResY = imageNode.getElementsByTagName('ImageResolutionY');
        orientationMatrix = imageNode.getElementsByTagName('OrientationMatrix');
        posX = imageNode.getElementsByTagName('PositionX');
        posY = imageNode.getElementsByTagName('PositionY');
        
        %Create a struct to hold image data
        imgData = struct('Filename', {}, 'PositionX', {}, ...
            'PositionY', {}, 'ImageResolutionX', {}, 'ImageResolutionY', {}, ...
            'OrientationMatrix', {});
        
        for idx = 1:imgFilename.getLength
                      
            imgData(idx).Filename = char(imgFilename.item(idx - 1).getTextContent);
            imgData(idx).ImageResolutionX = str2double(imageResX.item(idx - 1).getTextContent);
            imgData(idx).ImageResolutionY = str2double(imageResY.item(idx - 1).getTextContent);
            imgData(idx).OrientationMatrix = jsondecode(char(orientationMatrix.item(idx - 1).getTextContent));
            imgData(idx).PositionXum = str2double(posX.item(idx - 1).getTextContent);
            imgData(idx).PositionYum = str2double(posY.item(idx - 1).getTextContent);
            
            imgData(idx).PositionXpx = imgData(idx).PositionXum / imgData(idx).ImageResolutionX;
            imgData(idx).PositionYpx = imgData(idx).PositionYum / imgData(idx).ImageResolutionY;
            
        end
        
        break
        
    end
    
end

%% Perform the correction

% %Get list of images that we want
% imgList = 96:200;
% 
% for ii = 1%:numel(imgList)
%     
%     hh = regexp({imgData.Filename}, sprintf('f%.0fp', imgList(ii)));
%     isCellFound = cellfun(@isempty, hh);
%     fileIdx = find(~isCellFound);
% 
%     %Sort into channels
%     idxList = 
%     
% end

% folder = pwd;

%Get list of TIFF files in current folder
TIFFlist = dir(fullfile(folder, 'r01*.tif*'));

%Find files that match frame range of interest
framerange = 872:958;
ch = 1;

matchingIdxs = false(1, numel(TIFFlist));

for ii = 1:numel(framerange)
    
    if framerange(ii) < 10
        idx = regexp({TIFFlist.name}, sprintf('f%02.0f[\\D]+.*ch%.0f[\\D]', framerange(ii), ch));
    else
        idx = regexp({TIFFlist.name}, sprintf('f%.0f[\\D]+.*ch%.0f[\\D]', framerange(ii), ch));
    end
    matchingIdxs = matchingIdxs | ~cellfun('isempty', idx);
    
end

%Crop to matching TIFFs
TIFFlist = TIFFlist(matchingIdxs);

%Get list of indices matching the filenames
idxFiles = ismember({imgData.Filename}, {TIFFlist.name});

currImgData = imgData(idxFiles);

%Sort by image name
[x, idx] = sort({currImgData.Filename});
currImgData = currImgData(idx);

%Correct the center positions
for ii = 1:numel(currImgData)
    
    CX = currImgData(ii).PositionXpx;
    CY = currImgData(ii).PositionYpx;
    
    %Rotate center positions using inverted 2x2 portion of OrientationMatrix
    rotCoords = currImgData(ii).OrientationMatrix(1:2,1:2) \ [CX; CY];
    
    currImgData(ii).PositionXcorr = rotCoords(1);
    currImgData(ii).PositionYcorr = rotCoords(2);
    
end

minX = min([currImgData.PositionXcorr]);
minY = min([currImgData.PositionYcorr]);

%Compute the output image size
imgOutWidth = ceil(max([currImgData.PositionXcorr]) - min([currImgData.PositionXcorr])) + 1080;
imgOutHeight = ceil(max([currImgData.PositionYcorr]) - min([currImgData.PositionYcorr])) + 1080;

imgOut = zeros(imgOutHeight, imgOutWidth, 'uint16');

%Compile output image
for ii = 1:numel(TIFFlist)
    
    I = imread(currImgData(ii).Filename);
    
    XX = floor(currImgData(ii).PositionXcorr - minX + 1); %+1 because MATLAB indices start at 1
    YY = floor(currImgData(ii).PositionYcorr - minY + 1);
    
    %%Try scaling
    %tform = affine2d([inv(currImgData(ii).OrientationMatrix(1:2,1:2)), [0;0];[0 0 1]]);
    %I = imwarp(I, tform);
    
    imgOut((YY):(YY + size(I,1) - 1), XX:(XX + size(I,2) - 1)) = I;
    
end

imwrite(imgOut, 'test.tiff', 'Compression', 'none');

%T






