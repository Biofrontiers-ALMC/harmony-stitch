folder = 'D:\Documents\2019Dec Stitching Opera Phenix\20191219_DataFromAlysa\R14\R14.1__2019-08-09T12_39_29-Measurement 2b';

%Read the background profile
xmlDoc = dir(fullfile(folder, 'FFC_Profile', '*.xml'));

xmlfile = xmlread(fullfile(xmlDoc.folder, xmlDoc.name));

docNode = xmlfile.getDocumentElement;
docChildNodes = docNode.getChildNodes;

%Get "Entry" tags
entryNodes = docNode.getElementsByTagName('Entry');

%For each "Entry" tag, get the channel name and the flatfield correction
%data
chCorrection = struct('ID', {});
for ii = 1:entryNodes.getLength
    
    entryAttr = entryNodes.item(ii - 1).getAttributes;
    
    R = regexp(char(entryAttr.getNamedItem('ChannelID')),...
        'ChannelID="(?<chID>[\d]*)+', 'names');
    
    chCorrection(ii).ID = str2double(R.chID);
        
    corrText = strtrim(char(entryNodes.item(0).getTextContent));
    
    %Add quotation marks around strings
    [S, E] = regexp(corrText, '[A-Za-z]*');
    
    for jj = 1:(numel(S) - 1)
        
        corrText = insertAfter(corrText, S(jj) - 1, '"');        
        corrText = insertAfter(corrText, E(jj)+1, '"');
        
        S = S + 2;
        E = E + 2;
        
    end
    
    %Hack for the "Version" (MATLAB doesn't like the colon after "Acapella")
    corrText = insertAfter(corrText, S(end) - 1, '"');    
    corrText = insertAfter(corrText, numel(corrText)-1, '"');    
   
    %Decode the data into a struct
    corrStruct = jsondecode(corrText);
    
    %Merge with output struct
    fields = fieldnames(corrStruct);
    for iP = 1:numel(fields)
        chCorrection(ii).(fields{iP}) = corrStruct.(fields{iP});
    end
    
end


%The correction appears to be listed according to polynomial order
% So order 2: x^2 xy y^2, Order 3: x^3 X^2y xy^2 y^3
%We can iterate over the powers
%
%  x^(M-N) * y^(N) where M = order and N is the iteration variable (which
%  starts at 0)

%Create correction image
bgProfile = getProfile(chCorrection(1).Background);
fgProfile = getProfile(chCorrection(1).Foreground);

I = double(imread('r01c02f01p01-ch1sk1fk1fl1.tiff'));

%Apply approximate background correction
I_corr = I - (chCorrection(1).Background.Mean .* (bgProfile - 1));
I_corr(I_corr < 0) = 0;


%Apply foreground correction
I_corr = I_corr ./ fgProfile;




function profile = getProfile(sIn)

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



