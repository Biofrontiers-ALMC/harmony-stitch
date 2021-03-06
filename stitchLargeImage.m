clearvars
clc

%Open dialog box to set base folder. This folder should contain the
%AssayLayout, FFC_Profile, and Images sub-folders
baseFolder = uigetdir('', 'Set base folder');

%Set the image numbers to export. These numbers are obtained from the image
%map generated by the Harmony software. You can specify multiple images as
%elements in a cell. For example, to specify two different images:
%  imageRange = {872:958, 1371:1418};
%
%To specify a single image, you can omit the curly brackets:
%  imageRange = 872:958;
%
%Note: Make sure the range goes from low:high otherwise the code will throw
%an error.
imageRange = {872:958, 1371:1418};

%Specify the range of channels to export (e.g. channels = 1:3)
channels = 1;

%Set to true if you want a single multipage TIFF file, set to false if you
%want individual TIFF files per channel.
makeMultipage = false;

%The code will create a new sub-folder called 'ExportedImages' within the
%base sub-folder. The filenames will be created based on the settings
%specified above. 
%
%For example, for the stitched image consisting of images 872-958, channel
%1, the output file name will be:
%  f872-958_ch1.tiff

%% Processing code

if isequal(baseFolder, 0)
    %Cancelled
    return;    
end

%Read data from Index.idx.xml file including image position, resolution and
%the orientation matrix
indexFile = xmlread(fullfile(baseFolder, 'Images', 'Index.idx.xml'));

imagesNode = indexFile.getDocumentElement.getElementsByTagName('Images');
imageNodes = imagesNode.item(0).getElementsByTagName('Image');

%Create a struct to hold image metadata
imgMetadata = struct('Filename', {}, ...
    'PositionXum', {}, ...
    'PositionYum', {}, ...
    'PositionXpx', {}, ...
    'PositionYpx', {}, ...    
    'ImageResolutionX', {}, ...
    'ImageResolutionY', {}, ...
    'OrientationMatrix', {});

for idx = 1:imageNodes.getLength
    
    imageNode = imageNodes.item(idx - 1);
    
    imgMetadata(idx).Filename = ...
        char(imageNode.getElementsByTagName('URL').item(0).getTextContent);
    imgMetadata(idx).ImageResolutionX = ...
        str2double(imageNode.getElementsByTagName('ImageResolutionX').item(0).getTextContent);
    imgMetadata(idx).ImageResolutionY = ...
        str2double(imageNode.getElementsByTagName('ImageResolutionY').item(0).getTextContent);
    imgMetadata(idx).OrientationMatrix = ...
        jsondecode(char(imageNode.getElementsByTagName('OrientationMatrix').item(0).getTextContent));
    imgMetadata(idx).PositionXum = ...
        str2double(imageNode.getElementsByTagName('PositionX').item(0).getTextContent);
    imgMetadata(idx).PositionYum = ...
        str2double(imageNode.getElementsByTagName('PositionY').item(0).getTextContent);
    
    %Rotate the center positions according to the Harmony stitching
    %document
    imgMetadata(idx).PositionXpx = imgMetadata(idx).PositionXum / imgMetadata(idx).ImageResolutionX;
    imgMetadata(idx).PositionYpx = imgMetadata(idx).PositionYum / imgMetadata(idx).ImageResolutionY;
    
    %Rotate center positions using inverted 2x2 portion of OrientationMatrix
    rotCoords = imgMetadata(idx).OrientationMatrix(1:2,1:2) \ ...
        [imgMetadata(idx).PositionXpx; imgMetadata(idx).PositionYpx];
    
    imgMetadata(idx).PositionXcorr = rotCoords(1);
    imgMetadata(idx).PositionYcorr = rotCoords(2);
    
end

%Read data from the FFC_Profile XML file which contains the background
%and foreground correction profiles. The XML file seems to be named after
%the measurement.

%Get the profile XML file name
xmlDoc = dir(fullfile(baseFolder, 'FFC_Profile', '*.xml'));

%Read the profile XML
xmlfile = xmlread(fullfile(xmlDoc.folder, xmlDoc.name));

%Get "Entry" tags under the "Map" node
mapNode = xmlfile.getDocumentElement.getElementsByTagName('Map');
entryNodes = mapNode.item(0).getElementsByTagName('Entry');

%For each "Entry" tag, get the channel name and the flatfield correction
%(FFC) data
FFCdata = struct('ID', {});

for ii = 1:entryNodes.getLength
    
    %Get channel ID
    entryAttr = entryNodes.item(ii - 1).getAttributes;
    R = regexp(char(entryAttr.getNamedItem('ChannelID')),...
        'ChannelID="(?<chID>[\d]*)+', 'names');
    FFCdata(ii).ID = str2double(R.chID);
        
    %Get the FlatfieldProfile content
    corrText = strtrim(char(entryNodes.item(ii - 1).getTextContent));
    
    %Add quotation marks around text to allow MATLAB to properly decode the
    %JSON string
    [startIdx, endIdx] = regexp(corrText, '[A-Za-z]*');
    
    for jj = 1:(numel(startIdx) - 1)
        corrText = insertAfter(corrText, startIdx(jj) - 1, '"');        
        corrText = insertAfter(corrText, endIdx(jj)+1, '"');
        
        startIdx = startIdx + 2;
        endIdx = endIdx + 2;
    end
    
    %Hack for the "Version" (MATLAB doesn't like the colon after
    %"Acapella")
    corrText = insertAfter(corrText, startIdx(end) - 1, '"');    
    corrText = insertAfter(corrText, numel(corrText)-1, '"');    
   
    %Decode the data into a struct
    corrStruct = jsondecode(corrText);
    
    %Merge with output struct
    fields = fieldnames(corrStruct);
    for iP = 1:numel(fields)
        FFCdata(ii).(fields{iP}) = corrStruct.(fields{iP});
    end
    
end

%-- Export images --%

%Make the image range variable a cell
if ~iscell(imageRange)
    imageRange = {imageRange};    
end

msg = '';
for iImg = 1:numel(imageRange)
    
    fprintf(repmat('\b',1, numel(msg)));
    msg = sprintf('Exporting image %.0f of %.0f\n', iImg, numel(imageRange));
    fprintf(msg);
    
    %Stitch the large image for each channel
    for iCh = 1:numel(channels)
        
        %Find image data matching specified set of images
        matchingIdxs = false(1, numel(imgMetadata));
        for ii = 1:numel(imageRange{iImg})
            if imageRange{iImg}(ii) < 10
                %Images with numbers less than zero are saved with a
                %leading zero, e.g. image 1 = f01
                idx = regexp({imgMetadata.Filename}, sprintf('f%02.0f[\\D]+.*ch%.0f[\\D]', imageRange{iImg}(ii), channels(iCh)));
            else
                idx = regexp({imgMetadata.Filename}, sprintf('f%.0f[\\D]+.*ch%.0f[\\D]', imageRange{iImg}(ii), channels(iCh)));
            end
            
            matchingIdxs = matchingIdxs | ~cellfun('isempty', idx);
        end
        
        currImgData = imgMetadata(matchingIdxs);
                
        %Create correction images
        chIdx = [FFCdata.ID] == channels(iCh); %Find index corresponding to the channel
        bgProfile = getProfile(FFCdata(chIdx).Background);
        
        if isfield(FFCdata, 'Foreground')
            fgProfile = getProfile(FFCdata(chIdx).Foreground);
        else
            fgProfile = ones(size(bgProfile));
        end
        
        %Compute the output stitched image size
        imgOutWidth = ceil(max([currImgData.PositionXcorr]) - min([currImgData.PositionXcorr])) + 1080;
        imgOutHeight = ceil(max([currImgData.PositionYcorr]) - min([currImgData.PositionYcorr])) + 1080;
        
        %Initialize a matrix to hold the output stitched image
        imgOut = zeros(imgOutHeight, imgOutWidth, 'uint16');
        
        %Calculate the minimum X and Y coordinate - required to adjust the
        %final tile position to the stitched image position
        minX = min([currImgData.PositionXcorr]);
        minY = min([currImgData.PositionYcorr]);
        
        %Compile stitched image
        for ii = 1:numel(currImgData)
            
            I = double(imread(fullfile(baseFolder, 'Images', currImgData(ii).Filename)));

            %Adjust the image position
            XX = floor(currImgData(ii).PositionXcorr - minX + 1); % +1 because MATLAB indices start at 1
            YY = floor(currImgData(ii).PositionYcorr - minY + 1);
            
            %Apply approximate background correction
            I_corr = I - (FFCdata(1).Background.Mean .* (bgProfile - 1));
            I_corr(I_corr < 0) = 0;
            
            %Apply foreground correction
            I_corr = I_corr ./ fgProfile;
            
            %Convert the image back to uint16
            I_corr = uint16(I_corr);
            
            imgOut((YY):(YY + size(I,1) - 1), XX:(XX + size(I,2) - 1)) = I;
            
        end
        
        %Create the ExportedImages folder if it doesn't already exist
        if ~exist(fullfile(baseFolder, 'ExportedImages'), 'dir')
            mkdir(fullfile(baseFolder, 'ExportedImages'));
        end
        
        %Generate a name for the exported image
        if numel(imageRange{iImg}) == 1
            baseOutputFN = fullfile(baseFolder, 'ExportedImages', sprintf('f%.0f', imageRange{iImg}(1)));
        else
            baseOutputFN = fullfile(baseFolder, 'ExportedImages', sprintf('f%.0f-%.0f', imageRange{iImg}(1), imageRange{iImg}(end)));
        end
        
        %Write the stitched image to file        
        if ~makeMultipage
            imwrite(imgOut, sprintf('%s_ch%.0f.tiff', baseOutputFN, channels(iCh)), 'Compression', 'none');
        else
            if iCh == 1
                imwrite(imgOut, sprintf('%s_composite.tiff', baseOutputFN), 'Compression', 'none');
            else
                imwrite(imgOut, sprintf('%s_composite.tiff', baseOutputFN), 'Compression', 'none', 'writeMode', 'append');
            end
        end
        
    end
    
end

function profile = getProfile(sIn)
%GETPROFILE  Generates the flatfield correction profiles
%
%  According to the Harmony document, the correction is listed according to
%  polynomial order starting with x
%  e.g. coefficients for order 2: x^2 xy y^2, 
%                    for order 3: x^3 x^2y xy^2 y^3. 
%  
%  We can iterate over the powers 
%  x^(M - N) * y^(N - 1) where M = order and N is the iteration variable

coeffs = sIn.Profile.Coefficients;

xx = 1:(sIn.Profile.Dims(1));
yy = 1:(sIn.Profile.Dims(2));

[xx, yy] = meshgrid(xx, yy);

%Convert to microns
xx = (xx - sIn.Profile.Origin(1)) * sIn.Profile.Scale(1);
yy = (yy - sIn.Profile.Origin(2)) * sIn.Profile.Scale(2);

%Create correction image
profile = zeros(size(xx));

for iOrder = 1:numel(coeffs)
    
    if iOrder == 1
        
        profile = profile + coeffs{iOrder}(1);
        
    else
        
        for iCoeff = 1:numel(coeffs{iOrder})
            
            profile = profile + coeffs{iOrder}(iCoeff) .* xx.^(iOrder - iCoeff) .* yy.^(iCoeff - 1);
            
        end
    end
end
end



