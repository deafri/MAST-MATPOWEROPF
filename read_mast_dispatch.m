function [tDisp, tCommit] = read_mast_dispatch(fileName)
%
%   [tDisp, tCommit] = READ_MAST_DISPATCH('solution.csv')
%
%   • tDisp    – timetable with  *_Pg  (and *_Qg if present)
%   • tCommit  – timetable with  *_On  (integer unit counts)
%
%   Recognised columns
%       Commitment : Status_var_<Gen>   or   <Gen>_On
%       Dispatch   : Pwr_Gen_var_<Gen>  or   <Gen>_Pg
%       Reactive   : Qg_Gen_var_<Gen>   or   <Gen>_Qg    
%       Storage    : P_chrg_, P_dischrg_, U_bin_          

% -------------------------------------------------------------------
raw = readtable(fileName, 'VariableNamingRule','preserve');
hdr = raw.Properties.VariableNames;

%% --- TIME ----------------------------------------------------------
tCol = find(strcmpi(hdr,'Time'),1);
assert(~isempty(tCol),'Column "Time" not found.');
tHour = raw{:,tCol};
assert(all(tHour==round(tHour)),'“Time” must be integer hours.');
times = hours(tHour - 1);                 % Solution file starts from 0
Nt    = numel(times);

%% --- helpers -------------------------------------------------------
isCommit = @(h) endsWith(h,'_On','IgnoreCase',true) ...
            |  startsWith(h,'Status_var_','IgnoreCase',true);
isPg   = @(h) endsWith(h,'_Pg','IgnoreCase',true) ...
            |  startsWith(h,'Pwr_Gen_var_','IgnoreCase',true);
isQg   = @(h) endsWith(h,'_Qg','IgnoreCase',true) ...
            |  startsWith(h,'Qg_Gen_var_','IgnoreCase',true);

cCols  = find(cellfun(isCommit, hdr));
pgCols = find(cellfun(isPg,      hdr));
qgCols = find(cellfun(isQg,      hdr));

% canonical generator ID
clean = @(h) matlab.lang.makeValidName(lower( ...
            regexprep(h,{'^Status_var_','^Pwr_Gen_var_','^Qg_Gen_var_', ...
                          '_On$','_Pg$','_Qg$'},'')));

ids_c  = cellfun(clean, hdr(cCols),  'uni',0);
ids_pg = cellfun(clean, hdr(pgCols), 'uni',0);
ids_qg = cellfun(clean, hdr(qgCols), 'uni',0);

ids  = unique([ids_c ids_pg ids_qg], 'stable');
Ng   = numel(ids);

% allocate
commit  = zeros(Nt,Ng);      % unit counts
Pg_mat  = zeros(Nt,Ng);
hasQg   = ~isempty(qgCols);
if hasQg, Qg_mat = zeros(Nt,Ng); end

for g = 1:Ng
    id = ids{g};
    % commitment
    c = cCols(strcmp(ids_c,id)); if ~isempty(c), commit(:,g) = raw{:,c}; end
    % dispatch Pg
    c = pgCols(strcmp(ids_pg,id)); if ~isempty(c), Pg_mat(:,g) = raw{:,c}; end
    % Qg (optional)
    if hasQg
        c = qgCols(strcmp(ids_qg,id));
        if ~isempty(c), Qg_mat(:,g) = raw{:,c}; end
    end
end

%% --- build output timetables ---------------------------------------
varsC = strcat(ids, "_On");
varsP = strcat(ids, "_Pg");

tCommit      = array2timetable(commit, 'RowTimes',times, 'VariableNames',varsC);
tDisp        = array2timetable(Pg_mat, 'RowTimes',times, 'VariableNames',varsP);

if hasQg
    varsQ  = strcat(ids, "_Qg");
    tDisp  = addvars(tDisp, Qg_mat, 'NewVariableNames', varsQ);
end
end
