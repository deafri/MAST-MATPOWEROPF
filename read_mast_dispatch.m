function [tDisp, tCommit] = read_mast_dispatch(fileName)
%
%   [tDisp, tCommit] = READ_MAST_DISPATCH('solution.csv')
%
%   • tDisp    – timetable with:
%                   *_Pg
%                   *_Qg        (if present)
%                   *_P_chrg    (storage)
%                   *_P_dischrg (storage)
%                   *_SOC       (storage)
%                   *_U_bin     (storage)
%
%   • tCommit  – timetable with:
%                   *_On        (integer unit counts)
%
%   Recognised columns
%       Commitment : Status_var_<Gen>   or   <Gen>_On
%       Dispatch   : Pwr_Gen_var_<Gen>  or   <Gen>_Pg
%       Reactive   : Qg_Gen_var_<Gen>   or   <Gen>_Qg
%       Storage    : P_chrg_<Bat>, P_dischrg_<Bat>, SOC_<Bat>, U_bin_<Bat>
%

% -------------------------------------------------------------------
raw = readtable(fileName, 'VariableNamingRule','preserve');
hdr = raw.Properties.VariableNames;

%% --- TIME ----------------------------------------------------------
tCol = find(strcmpi(hdr,'Time'),1);
assert(~isempty(tCol),'Column "Time" not found.');
tHour = raw{:,tCol};
assert(all(tHour==round(tHour)),'“Time” must be integer hours.');
times = hours(tHour - 1);                 % solution file starts from 1/0 offset convention
Nt    = numel(times);

%% --- helpers -------------------------------------------------------
isCommit = @(h) endsWith(h,'_On','IgnoreCase',true) ...
            || startsWith(h,'Status_var_','IgnoreCase',true);

isPg = @(h) endsWith(h,'_Pg','IgnoreCase',true) ...
        || startsWith(h,'Pwr_Gen_var_','IgnoreCase',true);

isQg = @(h) endsWith(h,'_Qg','IgnoreCase',true) ...
        || startsWith(h,'Qg_Gen_var_','IgnoreCase',true);

isPch  = @(h) startsWith(h,'P_chrg_','IgnoreCase',true);
isPdis = @(h) startsWith(h,'P_dischrg_','IgnoreCase',true);
isSOC  = @(h) startsWith(h,'SOC_','IgnoreCase',true);
isUbin = @(h) startsWith(h,'U_bin_','IgnoreCase',true);

cCols    = find(cellfun(isCommit, hdr));
pgCols   = find(cellfun(isPg, hdr));
qgCols   = find(cellfun(isQg, hdr));
pchCols  = find(cellfun(isPch, hdr));
pdisCols = find(cellfun(isPdis, hdr));
socCols  = find(cellfun(isSOC, hdr));
ubinCols = find(cellfun(isUbin, hdr));

%% --- canonical generator IDs --------------------------------------
cleanGen = @(h) matlab.lang.makeValidName(lower( ...
    regexprep(h, {'^Status_var_','^Pwr_Gen_var_','^Qg_Gen_var_','_On$','_Pg$','_Qg$'}, '') ));

ids_c  = cellfun(cleanGen, hdr(cCols),  'uni',0);
ids_pg = cellfun(cleanGen, hdr(pgCols), 'uni',0);
ids_qg = cellfun(cleanGen, hdr(qgCols), 'uni',0);

genIDs = unique([ids_c ids_pg ids_qg], 'stable');
Ng     = numel(genIDs);

%% --- canonical storage IDs ----------------------------------------
cleanBat = @(h) matlab.lang.makeValidName(lower( ...
    regexprep(h, {'^P_chrg_','^P_dischrg_','^SOC_','^U_bin_'}, '') ));

ids_pch  = cellfun(cleanBat, hdr(pchCols),  'uni',0);
ids_pdis = cellfun(cleanBat, hdr(pdisCols), 'uni',0);
ids_soc  = cellfun(cleanBat, hdr(socCols),  'uni',0);
ids_ubin = cellfun(cleanBat, hdr(ubinCols), 'uni',0);

batIDs = unique([ids_pch ids_pdis ids_soc ids_ubin], 'stable');
Nbatt  = numel(batIDs);

%% --- allocate generator arrays ------------------------------------
commit = zeros(Nt, Ng);
Pg_mat = zeros(Nt, Ng);

hasQg = ~isempty(qgCols);
if hasQg
    Qg_mat = zeros(Nt, Ng);
end

for g = 1:Ng
    id = genIDs{g};

    c = cCols(strcmp(ids_c, id));
    if ~isempty(c)
        commit(:,g) = raw{:, c};
    end

    c = pgCols(strcmp(ids_pg, id));
    if ~isempty(c)
        Pg_mat(:,g) = raw{:, c};
    end

    if hasQg
        c = qgCols(strcmp(ids_qg, id));
        if ~isempty(c)
            Qg_mat(:,g) = raw{:, c};
        end
    end
end

%% --- allocate storage arrays --------------------------------------
hasPch  = ~isempty(pchCols);
hasPdis = ~isempty(pdisCols);
hasSOC  = ~isempty(socCols);
hasUbin = ~isempty(ubinCols);

if Nbatt > 0
    Pch_mat  = zeros(Nt, Nbatt);
    Pdis_mat = zeros(Nt, Nbatt);
    SOC_mat  = zeros(Nt, Nbatt);
    Ubin_mat = zeros(Nt, Nbatt);

    for b = 1:Nbatt
        id = batIDs{b};

        c = pchCols(strcmp(ids_pch, id));
        if ~isempty(c)
            Pch_mat(:,b) = raw{:, c};
        end

        c = pdisCols(strcmp(ids_pdis, id));
        if ~isempty(c)
            Pdis_mat(:,b) = raw{:, c};
        end

        c = socCols(strcmp(ids_soc, id));
        if ~isempty(c)
            SOC_mat(:,b) = raw{:, c};
        end

        c = ubinCols(strcmp(ids_ubin, id));
        if ~isempty(c)
            Ubin_mat(:,b) = raw{:, c};
        end
    end
end

%% --- build output timetables ---------------------------------------
varsC = strcat(genIDs, "_On");
varsP = strcat(genIDs, "_Pg");

tCommit = array2timetable(commit, 'RowTimes', times, 'VariableNames', varsC);
tDisp   = array2timetable(Pg_mat,   'RowTimes', times, 'VariableNames', varsP);

if hasQg
    varsQ = strcat(genIDs, "_Qg");
    Tq    = array2timetable(Qg_mat, 'RowTimes', times, 'VariableNames', varsQ);
    tDisp = synchronize(tDisp, Tq);
end

if Nbatt > 0
    if hasPch
        varsPch = strcat(batIDs, "_P_chrg");
        Tpch    = array2timetable(Pch_mat, 'RowTimes', times, 'VariableNames', varsPch);
        tDisp   = synchronize(tDisp, Tpch);
    end

    if hasPdis
        varsPdis = strcat(batIDs, "_P_dischrg");
        Tpdis    = array2timetable(Pdis_mat, 'RowTimes', times, 'VariableNames', varsPdis);
        tDisp    = synchronize(tDisp, Tpdis);
    end

    if hasSOC
        varsSOC = strcat(batIDs, "_SOC");
        Tsoc    = array2timetable(SOC_mat, 'RowTimes', times, 'VariableNames', varsSOC);
        tDisp   = synchronize(tDisp, Tsoc);
    end

    if hasUbin
        varsUbin = strcat(batIDs, "_U_bin");
        Tubin    = array2timetable(Ubin_mat, 'RowTimes', times, 'VariableNames', varsUbin);
        tDisp    = synchronize(tDisp, Tubin);
    end
end
end