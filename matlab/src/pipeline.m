function pipeline(varargin)


% TODO 
% PDF to show filtered design matrix to verify ok hpf
% PDF to show activation map similar to NDW_WM_v2
% Verify csv read works for all tasks


%% Parse inputs
P = inputParser;
P.addOptional('deffwd_niigz','');         % Forward warpfrom cat12
P.addOptional('meanfmri_niigz','');       % Mean fMRI from FSL preproc
P.addOptional('fmri_niigz','');           % Time series from FSL preproc
P.addOptional('eprime_summary_csv','');   % Eprime summary from gf-edat
P.addOptional('motion_par','');           % Motion params from FSL preproc
P.addOptional('fwhm','');                 % Filter kernel in mm for smoothing
P.addOptional('hpf','');                  % High pass filter length in sec
P.addOptional('task','');                 % Task (Oddball, SPT, WM)
P.addOptional('out_dir','');              % Where outputs will be stored

% Parse and show
P.parse(varargin{:});
inp = P.Results;
disp(inp)

% Fix some numbers etc
out_dir = inp.out_dir;
inp.fwhm = str2double(inp.fwhm);
inp.hpf = str2double(inp.hpf);


%% Copy inputs to out_dir and unzip
% Use hardcoded filenames hereafter for convenience
copyfile(inp.deffwd_niigz,[out_dir '/y_deffwd.nii.gz'])
copyfile(inp.meanfmri_niigz,[out_dir '/meanfmri.nii.gz'])
copyfile(inp.fmri_niigz,[out_dir '/fmri.nii.gz'])
copyfile(inp.eprime_summary_csv,[out_dir '/eprime_summary.csv']);
system([' gunzip -f ' out_dir '/*.nii.gz']);


%% Warp
disp('Warp')
clear matlabbatch
matlabbatch{1}.spm.util.defs.comp{1}.def = {[out_dir '/y_deffwd.nii']};
matlabbatch{1}.spm.util.defs.out{1}.pull.fnames = {
	[out_dir '/meanfmri.nii']
	[out_dir '/fmri.nii']
	};
matlabbatch{1}.spm.util.defs.out{1}.pull.savedir.savesrc = 1;
matlabbatch{1}.spm.util.defs.out{1}.pull.interp = 1;
matlabbatch{1}.spm.util.defs.out{1}.pull.mask = 1;
matlabbatch{1}.spm.util.defs.out{1}.pull.fwhm = [0 0 0];
matlabbatch{1}.spm.util.defs.out{1}.pull.prefix = 'w';
spm_jobman('run',matlabbatch);


%% Smooth
disp('Smoothing')
clear matlabbatch
matlabbatch{1}.spm.spatial.smooth.data = {[out_dir '/wfmri.nii']};
matlabbatch{1}.spm.spatial.smooth.fwhm = [inp.fwhm inp.fwhm inp.fwhm];
matlabbatch{1}.spm.spatial.smooth.dtype = 0;
matlabbatch{1}.spm.spatial.smooth.im = 0;
matlabbatch{1}.spm.spatial.smooth.prefix = 's';
spm_jobman('run',matlabbatch);


%% Save condition info into SPM-style .mat
% Read the csv once to get the size, then again to specify field format.
% Matlab is still not clever enough to suss this out on its own. Also there
% are some task-specific things here, e.g. skipping the "Tone" (Foil) event
% for the Oddball task.
names = {}; onsets = {}; durations = {};
ep = readtable([out_dir '/eprime_summary.csv'],'Delimiter','comma');
ep = readtable([out_dir '/eprime_summary.csv'], ...
	'Format',repmat('%q',1,size(ep,2)));
for c = 1:height(ep)
	if strcmp(inp.task,'Oddball') && strcmp(ep.Condition{c},'Tone')
		% Skip this condition
	else
		names{end+1,1} = ep.Condition{c};
		onsets{end+1,1} = eval(ep.OnsetsSec{c});
		durations{end+1,1} = eval(ep.DurationsSec{c});
	end
end
conds_mat = [out_dir '/conds.mat'];
save(conds_mat,'names','onsets','durations');


%% Rename and rescale motion params so SPM can work with it
motion_txt = [out_dir '/motion_params.txt'];
mot = load(inp.motion_par);
mot = zscore(mot);
save(motion_txt,'mot','-ascii');


%% First level stats
disp('First level stats')
first_level_stats( ...
	inp.hpf, ...
	[out_dir '/spm_unsmoothed'], ...
	inp.task, ...
	conds_mat, ...
	motion_txt, ...
	[out_dir '/wfmri.nii'], ...
	out_dir ...
	);

first_level_stats( ...
	inp.hpf, ...
	[out_dir '/spm'], ...
	inp.task, ...
	conds_mat, ...
	motion_txt, ...
	[out_dir '/swfmri.nii'], ...
	out_dir ...
	);


%% Exit
if isdeployed
	exit
end
