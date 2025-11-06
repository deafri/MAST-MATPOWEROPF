function R = extract_re_gen(mpc, mastCsv)
% EXTRACT_RE_GEN  Retrieve Pg of *removed* renewables from a MAST CSV.
%
%   R = EXTRACT_RE_GEN(mpc,'solution.csv')
%
%   Requires: mpc.RE_info with variables
%               • tag  – generator tag (as in Generator sheet)
%               • bus  – numeric bus index (row in mpc.bus)
%
%   Output
%   ------
%     R.time     (Nt×1 datetime)   hour vector from the CSV
%     R.tag      (1×Nr string)     removed tag names  
%     R.busNames (1×Nb string)     names from mpc.bus_name
%     R.Pg_tag   (Nt×Nr double)    MW of each removed tag 
%     R.Pg_bus   (Nt×Nb double)    MW summed on each bus 


%% read MAST dispatch into timetable  
tt = readtable(mastCsv, 'VariableNamingRule','preserve');
assert(any(strcmpi(tt.Properties.VariableNames,'Time')), ...
       'CSV must have a "Time" column.');

tHour     = tt.Time(:);
R.time    = hours(tHour - 1);            % Nt×1  datetime durations
Nt        = numel(tHour);
Nb        = size(mpc.bus,1);

%% varsity of CSV variable names to lower-case for robust matching
varsLC = lower(string(tt.Properties.VariableNames));

%% tags & bus indices from RE_info
tags = string(mpc.RE_info.tag).';
bIdx = mpc.RE_info.bus.';
Nr   = numel(tags);

Pg_tag = zeros(Nt,Nr);       
Pg_bus = zeros(Nt,Nb);     

for k = 1:Nr
    pat = "pwr_gen_var_" + lower(tags(k));      
    col = find(varsLC == pat, 1);               
    if isempty(col)
        warning('Column "%s" not found in %s – tag skipped.', pat, mastCsv);
        continue
    end

    Pg                 = tt{:,col};
    Pg_tag(:,k)        = Pg;                     % store raw column
    Pg_bus(:,bIdx(k))  = Pg_bus(:,bIdx(k)) + Pg; % add to bus aggregate
end

R.tag      = tags;
R.busNames = string(mpc.bus_name).';
R.Pg_tag   = Pg_tag;
R.Pg_bus   = Pg_bus;
end
