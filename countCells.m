%First pass at counting cells in an image
clearvars
clc

%Open dialog box to set base folder. This folder should contain images to
%process (i.e. the \Images subfolder)
baseFolder = uigetdir('', 'Set base folder');

%Get filenames
files = dir(fullfile(baseFolder, 'Images', 'r01*-ch1*.tiff'));

if ~exist(fullfile(baseFolder, 'masks'), 'dir')
    
    mkdir(fullfile(baseFolder, 'masks'))    
    
end

for iFile = 1:100%numel(files)
    
    %Read in the images. Ch1 = EGFP, Ch3 = mCherry
    I_ch1 = imread(fullfile(files(iFile).folder, files(iFile).name));
    
    %Segment the cells
    mask_ch1 = segmentCells(I_ch1, 30);
    
    %Count number of cells
    cc = bwconncomp(mask_ch1);
    
    files(iFile).NumCells = cc.NumObjects;    
    
    %Save the mask
    I_ch1 = uint8( double(I_ch1)./double(max(I_ch1(:))) * 255);
    Iout = showoverlay(I_ch1, bwperim(mask_ch1));
    
    imwrite(Iout, fullfile(baseFolder, 'masks', [files(iFile).name(1:end - 5), '.jpg']))
        
end

%Print the number of cells
fid = fopen(fullfile(baseFolder, 'cellcounts.txt'), 'w');

for ii = 1:100%numel(files)
    
    fprintf(fid, '%s\t%.0f\r\n', files(ii).name, files(ii).NumCells);
    
end

fclose(fid);



% I_ch3 = imread(fullfile(folder, files(3).name));

function mask = segmentCells(imgIn, thFactor)

%Estimate the background?
bg = imerode(imgIn, strel('disk', 40));
bg = median(bg);

mask = imgIn > thFactor * bg;
mask = imopen(mask, strel('disk', 5));

dd = -bwdist(~mask);
dd = imhmin(dd, 1);

LL = watershed(dd);

mask(LL == 0) = 0;

end


